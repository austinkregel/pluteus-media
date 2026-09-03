> **Non-normative.** Where this conflicts with
> [spec-01](../spec-01-catalog-data-model.md), the specification governs.
>
> **Superseded here:** the out-of-scope list — multi-user is in scope — and the architectural questions resolved by the greenfield decision. Every question raised here is now tracked in the reconciliation plan with a named owner, not in this file.

# 09 — Open Questions

Decisions deliberately deferred, plus the interface between these documents and the data-structure
specification being defined separately.

---

## For the data specification

These documents make architectural commitments that constrain the data model. Flagged here so the
spec can decide deliberately rather than inherit by accident.

### 1. Sub-track addressing

The largest gap in the entire protocol landscape, and our differentiator. The spec should decide:

- How a segment is **identified** — positional index, time range, content hash, or a stable
  surrogate key.
- Whether segment identity **survives re-analysis**. Likes reference segments; if boundaries shift
  when `extractor_version` changes, likes need a migration story or they silently drift onto the
  wrong music.
- Whether segments are strictly non-overlapping and exhaustive, or may overlap and leave gaps.
- Whether the same abstraction covers **video scenes** and **document chunks** — all three are
  "an addressable region of a larger asset with its own feature vector and embedding."

That last question is worth answering deliberately. A single `Region` concept across three media
types would be elegant, and would make the shared `core` library substantially more useful. It may
also be a false generalization. Either answer is defensible; drifting into it is not.

### 2. Feature naming

The Elixir↔Python contract is **name-based**, not positional
([05-python-sidecar-contract.md](05-python-sidecar-contract.md)). Names become a public interface.

- Naming convention for scalars vs. array-valued features.
- How array-valued features are addressed for weighting (`mfcc_mean[3]`? a flattened
  `mfcc_mean_3`?). This affects the per-theme weight override design in
  [07-analysis-taste-and-playlists.md](07-analysis-taste-and-playlists.md).
- Whether the 13 semantic groups are data or code.

### 3. Multi-valued fields

Music Assistant documents that Subsonic implementations render badly when a track's contributing
artists don't all have artist IDs. Multi-valued artist, genre, and language should be first-class
from the start rather than retrofitted.

### 4. Versioning and provenance

- `extractor_version` on every derived row (already decided; the spec should formalize the format).
- Whether embeddings carry a separate model-version stamp — they will change independently of the
  engineered features.
- Whether raw and normalized vectors are separate columns, separate tables, or a JSON blob plus a
  pgvector column (current design is the last).

### 5. Identity and dedupe

- MBID as the canonical external identifier; what happens when AcoustID returns multiple or none.
- Relationship between `SongDuplicate`, perceptual/chromaprint hashes, and user-visible merging.
- Whether the same dedupe machinery covers document and video near-duplicates.

---

## Architectural questions still open

### Where CLAP runs

Python sidecar (zero work, already there) or Ortex on the inference node (shares GPU memory with
CLIP and Whisper, drops torch, uses `nx_signal`'s `stft_to_mel` for input). Export to ONNX either
way. Decide after Phase 5, when the cost is visible.

### Whether to use Music Assistant at all

Default plan: implement OpenSubsonic and let MA handle output. Alternative: drive AirPlay and
Snapcast natively with the pure-Elixir packages, and skip MA entirely.

Arguments for native: a playback-session `GenServer` owning the Snapcast clock in-process is
architecturally cleaner; no separate service; no macvlan networking requirement; no Subsonic-layer
format quirks (m4a/opus/VBR).

Arguments against: MA covers ~20 protocols versus 2; the Elixir packages are pre-1.0, GPL-3.0, and
single-maintainer.

Probably both — MA for breadth, native for the paths used daily.

### Umbrella vs. separate apps

Currently: separate apps plus a shared `core` and a shared inference node. Driven by the single GPU
and by `document-sorter` already existing standalone. Revisit if cross-app transactions turn out to
be needed, which would be a surprise.

### Whether the video app is a third app or part of music

They share transcoding, artwork, ingestion, and playback-session machinery. They differ in metadata
model and in resource profile. Leaning separate, mainly so a runaway transcode cannot disturb music
playback — but this is not settled.

### Eliminating Python entirely

Two routes, both real work, neither urgent:

1. **Port onto `nx_signal`** — write DCT-II, spectral contrast, onset detection, tempogram, beat
   tracking, and a CQT. Ordered by tractability. CQT and the Ellis DP beat tracker are each a
   project.
2. **Rustler NIF over `bliss-rs` or aubio** — lower risk, since `bliss-rs` already works and ships
   Python bindings, so the FFI surface is proven. Nothing like it exists on Hex; it would be a
   genuinely useful contribution.

Route 2 is preferred if this is ever attempted. Neither is on the roadmap.

---

## Known unknowns

Things asserted here with less confidence than the rest.

- **Segment count at scale.** Segment tables will be the largest in the database by an order of
  magnitude, with HNSW indexes over them. Memory behaviour at full library size has not been
  measured. This could force IVFFlat, or partitioning, or a smaller segment embedding.
- **Sidecar throughput.** Moving from an in-process thread pool to HTTP adds per-request overhead.
  Probably negligible against minutes of librosa work, but unmeasured.
- **`Nx.Serving` under mixed load.** Documented to be distributed by default and to load-balance by
  partition count, but behaviour with heterogeneous model sizes on one GPU is untested here.
- **Whether LiveView is a good fit for a media player UI.** Playback position, seek, and waveform
  scrubbing are high-frequency client-side interactions. Some of the player will need hooks and
  client-side state regardless; how much is unknown.
- **Android Auto browse-tree design.** The four-tab root limit is documented, but what actually
  makes a *good* car browse tree for a large personal library is a design problem we have not
  solved. This is the original complaint — worth prototyping early rather than assuming.

---

## Explicitly out of scope

Recording these so they are not re-litigated:

- Multi-user, sharing, federation
- Collaborative filtering or anything needing a user population
- Native mobile/TV clients (consume existing OpenSubsonic clients instead)
- Implementing AirPlay/Cast/Sonos protocols from scratch
- CarPlay, unless Apple grants the entitlement (category-locked, months-long approval)
- Matter Casting — genuinely open and royalty-free, but adoption is near-nil and video-first. Track
  it; do not build on it.
- Matching Plex's video metadata scraping breadth
