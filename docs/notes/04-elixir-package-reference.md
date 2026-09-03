> **Non-normative.** Where this conflicts with
> [spec-01](../spec-01-catalog-data-model.md), the specification governs.
>
> **Superseded here:** nothing. These tables remain current and are the most directly reusable material in this directory. They predate the preservation obligations of spec-01 §13.4, for which there are no entries — see the plan's package gaps.

# 04 — Elixir Package Reference

Organized by **capability**, not by package family. Versions and dates are as verified in
September 2026. Licenses are noted where they constrain distribution.

Legend: **Core** = adopt now · **Candidate** = likely, evaluate · **Watch** = know it exists ·
**Stale** = last release >2 years, treat as unmaintained.

---

## 1. Transcoding and remuxing

| Package | Ver / updated | License | Role | Status |
|---|---|---|---|---|
| `ffmpex` | 2026-05 | MIT | Builder API for ffmpeg command lines — options per-file, per-stream, global. Avoids string concatenation. | **Core** |
| `xav` | 0.12.0 · 2026-08 | Apache-2.0 | ffmpeg wrapper for **reading and decoding** audio/video into raw frames. By `elixir-webrtc`. The bridge to Nx tensors. | **Core** |
| `audio_proxy` | 0.7.1 · 2026-08 | Apache-2.0 | On-the-fly transcoding proxy: renders variants from signed URLs, **streams while encoding**, caches for range-capable serving, extracts waveform peaks. | **Candidate** |
| `membrane_transcoder_plugin` | 2026-06 | Apache-2.0 | Membrane-native transcoding element. | **Candidate** |
| `membrane_ffmpeg_transcoder_plugin` | 2026-03 | Apache-2.0 | Transcode audio and video into multiple qualities via FFmpeg. | **Candidate** |
| `membrane_ffmpeg_swresample_plugin` | 2026-08 | Apache-2.0 | Audio conversion, resampling, channel mixing (FFmpeg SWResample). | **Core** |
| `membrane_ffmpeg_swscale_plugin` | 2026-07 | Apache-2.0 | Video scaling (FFmpeg SWScale). | **Core** (video) |
| `thumbnex` | — | MIT | Thumbnails and animated GIF previews from video. | **Candidate** |
| `rockbox_ex_ffi` | 0.7.0 · 2026-07 | **GPL-2.0+** | Bindings to the Rockbox DSP / metadata / codec / playback engine. Mature C codebase covering many formats. | **Watch** |

**Guidance.** The majority of a media server's video work is *direct play* — serving bytes with
HTTP range requests, no transcode at all. Below that: remux (container swap), then on-demand
transcode. For those, driving ffmpeg directly via `ffmpex` is simpler and is what Jellyfin and Plex
do. Reach for Membrane when you need live pipelines, dynamic reconfiguration, WebRTC, or per-frame
processing. See [06-media-pipeline.md](06-media-pipeline.md).

---

## 2. Streaming, packaging, containers

| Package | Ver / updated | Role |
|---|---|---|
| `membrane_core` | 1.3.x | Pipeline framework: elements linked into pipelines. Streams via WebRTC, RTSP, RTMP, HLS, HTTP. Accepts and produces MP4, MKV, FLV. |
| `membrane_hls_plugin` | 2026-08 | Adaptive live HLS for Membrane. |
| `membrane_http_adaptive_stream_plugin` | current | HLS manifest generation and packaging. |
| `ex_hls` | 2026-07 | Handling HLS streams. |
| `kim_hls` | 2025-04 | HLS library bound to RFC 8216. |
| `hls` | 2024-10 | Fast HLS manifest parser. |
| `membrane_h264_ffmpeg_plugin` | 2026-06 | H.264 decoder/encoder (ffmpeg + x264). |
| `membrane_h265_ffmpeg_plugin` | 2025-10 | H.265 encoder/decoder. |
| `membrane_flac_plugin` / `membrane_opus_plugin` / `membrane_aac_*` | current | Codec parsing and coding. |
| `membrane_audio_mix_plugin` | 2026-06 | Raw audio mixing and interleaving. |
| `membrane_realtimer_plugin` | 2026-06 | Limits playback speed to realtime — needed when a pipeline would otherwise run as fast as it can read. |
| `membrane_audiometer_plugin` | 2026-06 | Audio level measurement. |
| `membrane_portaudio_plugin` | 2026-06 | Raw audio playback/capture via PortAudio — local sound-card output. |

---

## 3. Transport and output (Layer 2)

| Package | Ver / updated | License | Role | Status |
|---|---|---|---|---|
| `airplay` | 0.6.0 · 2026-08 | **GPL-3.0+** | **Pure-Elixir AirPlay (RAOP) sender.** Discovers receivers, streams lossless ALAC. No native deps. | **Candidate** |
| `snapcast` | 0.4.7 · 2026-08 | **GPL-3.0+** | **Pure-Elixir Snapcast server.** Speaks the binary protocol directly to snapclients, owns the audio clock, timestamps every chunk, PCM or FLAC transport. No external snapserver. | **Candidate** |
| `bluez` | 2026-08 | — | BlueZ over D-Bus: BLE scanning, GATT, pairing, and `bluez-alsa` audio. | **Watch** |
| `livekit` | 2025-09 | Apache-2.0 | LiveKit server SDK — real-time audio/video, if WebRTC casting is ever wanted. | **Watch** |

**License note.** `airplay` and `snapcast` are GPL-3.0-or-later; `rockbox_ex_ffi` is GPL-2.0-or-later.
Irrelevant for personal use. A copyleft decision if this is ever distributed. Both AirPlay and
Snapcast packages are pre-1.0 from a single maintainer on sourcehut with ~1,000 recent downloads —
usable, but note the bus factor on a long horizon.

**Strategy.** Music Assistant already implements ~20 output protocols and consumes OpenSubsonic.
Default to letting it do Layer 2. These packages are the option for driving AirPlay and a
synchronized multiroom setup natively — attractive because a playback-session `GenServer` owning
the Snapcast clock in-process is architecturally cleaner than shelling out.

---

## 4. Transcribing (speech → text)

| Package | Role |
|---|---|
| `bumblebee` | `Bumblebee.Audio.speech_to_text_whisper/…` — Whisper, accurate multilingual transcription. Runs through `Nx.Serving`, so it lives on the inference node with everything else. |
| `ortex` | If a non-Bumblebee ASR model is preferred (e.g. a distilled Whisper or Silero as ONNX). |
| `xav` | Decodes the audio track to raw PCM to feed either of the above. |

Whisper also performs **translation to English natively** as a task variant, which covers a
meaningful part of the translation need without a second model.

Use cases across the three apps: lyric extraction where no `.lrc` or fetched lyrics exist
(AudioMuse does exactly this), video subtitle generation, and audio-bearing document ingest.

---

## 5. Translating

| Package | Role |
|---|---|
| `bumblebee` | **`Bumblebee.Text.translation/4`**, added in Bumblebee 0.6.0. Supports **M2M100** (100 languages, ~9,900 directions) and **NLLB** (200 languages). Checkpoints at 418M and 1.2B. |
| `bumblebee` (Whisper) | `task: :translate` — speech directly to English text, one model instead of two. |

Use cases: non-English lyrics for the lyric-classification axis, subtitle translation, multilingual
document ingest.

---

## 6. Transforming (DSP, signal, image)

### Signal / DSP

| Package | Ver | Provides |
|---|---|---|
| `nx_signal` | 0.3.0 · 2026-03 | `stft`, `istft`, `stft_to_mel`, `mel_filters`, `fft_frequencies`, `as_windowed`, `overlap_and_add`, `czt`, `zoom_fft`. **Windows:** bartlett, blackman, hamming, hann, kaiser, rectangular, triangular. **Transforms:** `fft_nd`, `ifft_nd`. **Filters:** `firwin`, `wiener`, `median`. **PeakFinding:** `argrelextrema`, `argrelmax`, `argrelmin`. **Convolution:** `correlate`. **Waveforms:** `chirp`, `gaussian_pulse`, `polynomial_sweep`, `sawtooth`, `sinc`. |

**What `nx_signal` does NOT have** — verified absent from the entire Hex ecosystem, not just this
package:

- constant-Q transform / CQT / chroma / chromagram
- MFCC / DCT / cepstral analysis
- beat tracking, tempo detection, onset detection
- chromaprint / AcoustID fingerprinting
- any wrapper for aubio, Essentia, libXtract, or Rubber Band

This is the entire justification for the Python sidecar. See
[05-python-sidecar-contract.md](05-python-sidecar-contract.md).

**Important consequence of `stft_to_mel`:** mel spectrogram is exactly the input format CLAP,
MusiCNN, and AST expect. So the *neural* half of analysis can run in Elixir (NxSignal → Ortex)
even while the engineered-feature half stays in Python. Split on "does this need librosa's specific
feature implementations," not on "is this analysis."

### Image

| Package | Role |
|---|---|
| `image` (wraps `vix` / libvips) | 300+ operations. Thumbnails, EXIF/XMP metadata, **video frame extraction**, blurhash, **perceptual hashing**. ~2–3× faster than Mogrify with ~5× less memory. |
| `vix` | Lower-level libvips bindings if `image`'s API is insufficient. |

Perceptual hashing is quietly useful across all three apps — near-duplicate detection for artwork,
video frames, and scanned documents, the visual analogue of chromaprint.

---

## 7. Analyzing (ML, clustering, vectors)

| Package | Ver | Role | Status |
|---|---|---|---|
| `nx` | 0.9–0.11 | Tensors, `defn`, FFT. Foundation for everything below. | **Core** |
| `exla` | 0.9 | XLA backend — CPU and CUDA compilation. | **Core** |
| `scholar` | 0.4.x | **Traditional ML on Nx.** Clustering: `KMeans`, `DBSCAN`, `GaussianMixture`, `AffinityPropagation`, `Hierarchical`. Plus classification, regression, metrics, preprocessing, dimensionality reduction. GPU-ready, vectorizable, deployable via `Nx.Serving`. | **Core** |
| `bumblebee` | 0.6.x | Pre-trained HF models in Axon: Whisper (ASR), CLIP, translation (M2M100/NLLB), text embedding, zero-shot classification, generation. | **Core** |
| `ortex` | 0.1.x | **ONNX Runtime** via Rustler. CUDA / TensorRT / CoreML backends. Implements `Nx.Serving`. | **Core** |
| `axon` | 0.7 | Neural network definition — only if training something ourselves. | **Candidate** |
| `explorer` | current | Polars-backed dataframes for exploratory work. | **Candidate** |
| `pgvector` | 0.3 | Ecto + Postgrex support. Distances: `l2_distance`, `cosine_distance`, `max_inner_product`, `l1_distance`, `hamming_distance`, `jaccard_distance`. HNSW and IVFFlat index creation. Ships a hybrid-search (RRF) example. | **Core** |
| `edifice` | 2026-02 | 186 neural network architectures for Nx/Axon (transformers, Mamba, diffusion). | **Watch** |

**`scholar` is the highest-value addition not currently in `document-sorter`.** It is the sklearn
replacement, and it is what the *k*-component taste clustering and document clustering both need.

**`ortex` is required** because Bumblebee has Whisper and CLIP but **not CLAP**. Exporting CLAP and
AST to ONNX makes them runnable natively and drops the torch dependency.

---

## 8. Metadata and identity

| Package | Ver / updated | Status | Notes |
|---|---|---|---|
| `son_ex_musicbrainz_client` | 2025-10 | **Candidate** | MusicBrainz API v2 client. |
| `exbrainz` | 2020 | **Stale** | Older MusicBrainz client. |
| `id3vx` | 2022 | **Stale** | Read/write ID3v2.3 with chapter support. |
| `taglib` | 2019 | **Stale** | TagLib bindings. |
| `id3` | 2020 | **Stale** | Rust NIF for ID3. |

**Gap.** Audio tag reading has no actively maintained Elixir package. Options, in order of
preference:

1. Read tags in the Python sidecar (mutagen) — it already opens the file.
2. `ffprobe` via `ffmpex` — returns container metadata as JSON, covers every format, one dependency
   we already have.
3. `rockbox_ex_ffi` — its metadata engine is mature, but GPL-2.0 and an unusual dependency.

**Option 2 is probably right** — the sidecar shouldn't own metadata semantics, and ffprobe is
already needed for video.

**Chromaprint/AcoustID has no Elixir path at all.** Shell out to `fpcalc` or keep it in the sidecar.

---

## 9. Documents and OCR

| Package | Ver / updated | Status | Notes |
|---|---|---|---|
| `kreuzberg` | 4.10.2 · 2026-07 | **Candidate** | Document intelligence **with OCR**. MIT, 74 releases — actively developed. Fills the scanned-PDF gap. |
| `ex_pdf_poppler` | in use | **Core** | PDF text extraction. |
| `bupe` | in use | **Core** | EPUB. |
| `docxelixir` | in use | **Core** | DOCX. |
| `xlsxir` / `exoffice` | in use | **Core** | Spreadsheets. |
| `earmark` | in use | **Core** | Markdown. |
| `html2markdown` | 2026-08 | **Watch** | HTML content extraction to Markdown, strips non-content sections. |
| `tesseract_ocr` | 2020 | **Stale** | Prefer `kreuzberg`. |

---

## 10. Application infrastructure

| Package | Role |
|---|---|
| `phoenix` 1.8.x | Web framework. |
| `phoenix_live_view` 1.1.x | UI — replaces the Vue SPA entirely. |
| `bandit` | HTTP server. |
| `ecto_sql` / `postgrex` | Database. **Sole schema owner.** |
| `oban` 2.19+ | Background jobs: retries with backoff, unique jobs, per-queue concurrency. |
| `oban_web` | Queue observability. **Open sourced and free as of Oban 2.19.** |
| `file_system` | Filesystem watching for library ingest. |
| `req` | HTTP client — sidecar calls, MusicBrainz, ListenBrainz. |
| `libcluster` | Node discovery across the app/inference nodes. |
| `phoenix_live_dashboard` | Runtime introspection. |
| `dns_cluster` | Already in use in `document-sorter`. |

**Oban Pro** ($135/mo) adds cluster-wide global concurrency limits, rate limiting, and
workflows/batches/chunks/chains. Local per-node concurrency is open source and sufficient for a
single-node deployment — revisit only if the inference node moves to separate hardware and queue
coordination becomes a real problem.

---

## 11. Rust escape hatches

Not needed now; relevant if the Python sidecar is ever eliminated.

| Project | Role |
|---|---|
| `bliss-rs` | Song analysis **for making playlists** — tempo, timbre, loudness, and distance between songs. Chroma extraction is a direct port of librosa's. Uses aubio bindings. **Already ships Python bindings**, so the FFI surface is proven and a Rustler NIF would be wrapping a working library rather than porting algorithms. |
| `emo-audio` | Targets rough librosa parity: MFCCs, filterbank energies, spectral subband centroids. |
| `nghe` | Rust OpenSubsonic server — reference implementation. In-memory transcoding via the ffmpeg C API, no ffmpeg binary or preconfigured profiles. |
| `opensubsonic` (crate) | Async OpenSubsonic **client**, all ~80 v1.16.1 endpoints. Useful for integration testing our server. |

A `Rustler` NIF over `bliss-rs` or aubio is the lowest-risk path to zero Python, and nothing like it
exists on Hex — it would be a genuinely useful contribution.
