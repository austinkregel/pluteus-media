> **Non-normative.** Where this conflicts with
> [spec-01](../spec-01-catalog-data-model.md), the specification governs.
>
> **Superseded here:** the read-only media library — ingest now writes normalized copies (spec-01 §13.1–13.3) — and the `transcode-cache` volume as described, since spec-01 §13.6 permits retention only as an evictable derived asset.

# 06 — Media Pipeline

Covers ingest, transcode, packaging, and playback for both audio and video. The data *shapes*
these paths produce are the data spec's concern; this document covers the machinery.

---

## The four playback paths

Ordered by frequency. Most requests take the first path, which is why optimizing the others first
is a common mistake.

| Path | When | Mechanism | Cost |
|---|---|---|---|
| **Direct play** | Client supports the container and codecs | Serve bytes with HTTP range requests | ~zero |
| **Remux** | Codecs fine, container wrong | `ffmpeg -c copy` into a new container | low, no re-encode |
| **Transcode** | Codec unsupported, or bandwidth-constrained | ffmpeg re-encode, packaged as HLS | high, CPU/GPU-bound |
| **Adaptive (ABR)** | Variable network, video | Multiple renditions + HLS manifest | highest |

**Design implication.** Probe capability up front and *decide* the path, rather than transcoding
defensively. OpenSubsonic's `transcoding` extension exists for exactly this negotiation —
`getTranscodeDecision` lets the client participate rather than guess.

---

## Audio ingest

```
file_watcher (FileSystem)
      │
      ▼
:scan       ffprobe via ffmpex  →  container, codec, duration, bitrate, channels,
      │                             embedded tags, embedded cover art
      ▼
:extract    POST → python sidecar  →  named scalars + arrays + segments + fingerprint
      │
      ▼
:embed      Nx.Serving (CLAP)  →  512-dim song + segment embeddings
      │
      ▼
:classify   Nx.Serving (AST)   →  instrument presence
      │
      ▼
:lyrics     fetch, or Whisper transcription, or .lrc sidecar file
      │
      ▼
:derive     assemble vectors, normalize, write pgvector columns   [Elixir]
```

### Metadata reading

No actively maintained Elixir audio-tag package exists (`id3vx` 2022, `taglib` 2019, `id3` 2020 are
all stale). **Use `ffprobe` via `ffmpex`** — it returns container metadata as JSON, covers every
format, and is already a dependency for video. The sidecar should not own metadata semantics.

Sidecar conventions worth supporting because everything else reads them: **ReplayGain** tags,
`.lrc` synchronized lyrics, `.nfo` artist/album metadata, and embedded cover art.

### Multi-artist handling

Music Assistant's documentation warns that Subsonic implementations which don't assign an artist ID
to *every* contributing artist render badly. Treat multi-valued artist as a first-class modelling
requirement, not a later refinement — this is a note for the data spec.

---

## Video ingest

```
:scan       ffprobe  →  container, video/audio/subtitle streams, codecs,
      │                  resolution, framerate, HDR metadata, chapters
      ▼
:artwork    Image (libvips)  →  poster, backdrop, thumbnail, blurhash, perceptual hash
      │
      ▼
:trickplay  ffmpeg  →  sprite sheets for scrub preview
      │
      ▼
:subtitles  extract embedded tracks; optionally Whisper-generate;
      │      optionally translate via Bumblebee M2M100/NLLB
      ▼
:scenes     [optional] Membrane per-frame pipeline → scene boundaries
      │                Xav → frames → Nx → CLIP embeddings
      ▼
:derive     write scene rows + pgvector embeddings
```

**Scene analysis is video's analogue of audio segments** — and it's the case where Membrane
genuinely earns its place, because per-frame pipeline processing is exactly what it's built for.
Treat it as a later phase; the playback path does not depend on it.

---

## Transcoding: which tool when

| Situation | Tool | Why |
|---|---|---|
| One-shot transcode or remux | `ffmpex` → ffmpeg CLI | Simplest. What Jellyfin and Plex do. Easy to supervise as an OS process. |
| Serve a variant while it encodes | `audio_proxy` | Purpose-built: signed URLs, streams during encode, caches for range serving, extracts waveform peaks. |
| Decode to raw frames/samples | `xav` | Gets PCM or video frames into Nx tensors. The analysis on-ramp. |
| Adaptive bitrate ladders | `membrane_ffmpeg_transcoder_plugin` + `membrane_http_adaptive_stream_plugin` | Multiple renditions and HLS packaging as a supervised pipeline. |
| Live restream, WebRTC, per-frame processing | `membrane_core` + codec plugins | Dynamic reconfiguration mid-stream. |
| Local sound-card output | `membrane_portaudio_plugin` | Direct playback on the server itself. |

### Supervising ffmpeg

An ffmpeg transcode is an OS process, so BEAM supervision does not cover it directly. Use a
`GenServer` per transcode session that:

- owns the `Port`, and traps exits
- enforces a wall-clock deadline
- kills the OS process on client disconnect (**important** — an abandoned HLS session otherwise
  transcodes an entire film for nobody)
- reports progress to LiveView via PubSub

Bound `:transcode` queue concurrency to 1–2. A media server that transcodes three things at once on
one box serves none of them well.

---

## Output and playback

### Default: let Music Assistant do Layer 2

Implementing OpenSubsonic makes us an MA music provider, and MA already implements AirPlay, Sonos,
Google Cast, DLNA, Snapcast, MPD, MusicCast, HEOS, Bluesound, SoundTouch, Samsung WAM, WiiM,
Squeezelite, AmpliPi, Roku, and a Home Assistant fallback.

Requirements this imposes on us:

- **Serve formats MA can stream.** It has documented trouble with m4a, opus, and variable-bitrate
  encodes over Subsonic, because those can carry information mid-file rather than in the header.
  Transcode to a stream-friendly format rather than passing those through.
- MA needs layer-2 network access (host or macvlan networking) to discover players.

### Optional: native output

`airplay` (pure-Elixir RAOP sender, lossless ALAC) and `snapcast` (pure-Elixir Snapcast server that
owns the audio clock and timestamps every chunk) allow driving output directly from the BEAM.

Architecturally attractive: a playback-session `GenServer` holding the Snapcast clock in-process is
cleaner than coordinating with an external snapserver. Both are GPL-3.0, pre-1.0, single-maintainer.

### Playback state

Phoenix PubSub for cross-device state — this is the piece nothing open standardizes (see
[02-protocol-landscape.md](02-protocol-landscape.md), gap 5) and the piece OTP makes almost free.

One `GenServer` per playback session holding queue, position, and target device, under a
supervisor. LiveView subscribes for the web UI; OpenSubsonic's `savePlayQueue` /
`getPlayQueue` project the same state for external clients.

---

## Storage layout

| Volume | Mount | Access |
|---|---|---|
| `music` | `/music` | read-only, all services that need it |
| `video` | `/video` | read-only |
| `pgdata` | Postgres data | read-write, db only |
| `model-cache` | `/cache` | `HF_HOME` / `TORCH_HOME` — download weights once |
| `transcode-cache` | `/cache/transcode` | ephemeral variants, size-capped with LRU eviction |
| `artwork` | `/artwork` | derived posters, thumbnails, sprite sheets |

**Keep media paths absolute and the in-container mount point stable.** The existing music app
enforces that `/audio/{song_id}` refuses anything outside `MUSIC_LIBRARY_PATH`; keep that check and
apply the same to video. Repointing storage should be a volume-driver change (NFS, CIFS, bind), not
a path change.
