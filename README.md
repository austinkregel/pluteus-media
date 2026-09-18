# Household Media Platform — Specifications

A self-hosted media system for one household: catalog, preservation, and
consumption in one application. Music, video, documents, photographs, scanned
correspondence, ebooks, and home recordings — anything the household holds.

**Status:** specification, with an implementation of specs 01, 02, 03 and 06 in
this repository.

## The specification series

[spec-01](docs/spec-01-catalog-data-model.md) is normative and has no upstream
dependency. Everything else builds on it.

| Spec | Covers | Status |
|---|---|---|
| [01 — Catalog Data Model](docs/spec-01-catalog-data-model.md) | Identifiers, IFLA LRM entities, assets, nomens, addressing, principals, preservation, deletion. 37 conformance criteria. | Draft, amended |
| [01 Annex A — Worked WEMI Mappings](docs/spec-01-annex-a-wemi-mappings.md) | §5–6 applied to seven media classes. Non-normative. | Draft |
| [02 — Annotations and Derived Data](docs/spec-02-annotations-and-derived-data.md) | Bodies attached to §8 addresses. Provenance, model versioning, supersession. The one abstraction spanning audio segments, video scenes, document chunks, OCR words, face tags. | Draft |
| [03 — Assets, Storage and Preservation](docs/spec-03-assets-storage-and-preservation.md) | Normalization, checksum scheduling, format risk, backup scope, dedupe. | Draft |
| [04 — Ingest and Normalization](docs/spec-04-ingest-and-normalization.md) | Acquisition from an inbox, identification, placement per media class, normalization, analysis by native and sidecar tools. Idempotency and resumability. | Draft |
| 05 — Metadata Acquisition and Matching | External identifier nomens. MusicBrainz, TMDB, AcoustID. Correction beats automatic. | Not started |
| [06 — Principals, Auth and Authorization](docs/spec-06-principals-auth-and-authorization.md) | Principals and roles, identity from a forward-authenticating proxy, household boundary, per-principal scoping, audit. | Draft |
| 07 — Wire Protocol | Native API plus an OpenSubsonic compatibility surface. Change notification. | Not started |
| 08 — Playback and Transcode Negotiation | Sessions, direct play / remux / transcode, track selection. | Not started |
| 09 — Search, Ranking and Recommendation | Feature vectors, taste modelling, playlist generation and sequencing. | Not started |
| 10 — Presentation | Resolution profiles, client contracts. | Not started |

**01, 02, 03 and 06 gate implementation.** Open items are marked **OPEN**
inline.

## Foundations

**Base model.** IFLA LRM (2024-07), adopted whole — no entity omitted. Work,
expression, manifestation, item, plus a `digital item` extension LRM §5.3
anticipates, and an `asset` at the preservation layer beneath it.

**Three layers, never conflated.** Catalog (what exists and what it is called,
from LRM), preservation (custody and integrity, outside LRM), consumption (what
a person did, outside LRM).

**Names are entities.** There is no title column anywhere. A nomen carries its
own language, script, scheme, assigner, and context of use, and resolution to a
preferred form is a pure function evaluated at the render boundary. A null
assigner means the household's shared vocabulary.

**Regions are addressable.** LRM's smallest unit is a whole entity; typed
selectors address a part of one — a time range, a pixel region, a text quote —
in units natural to the medium, on a basis that survives re-encoding.

**Detection over recovery.** Recovery cannot be guaranteed, so integrity work is
scheduled checksum verification and format-risk identification, with the backup
copy carrying recovery.

**One household, several people.** Every playback is attributable to a
principal, and no principal's consumption is visible to another.

## Implementation

**Pluteus** — one Phoenix application, one PostgreSQL database, Ecto as sole
schema owner. Each specification's conformance criteria are its test suite:
spec-01 is met except criterion 33, which waits on spec-08; spec-02, spec-03 and
spec-06 are met in full.

Everything runs in containers; [CLAUDE.md](CLAUDE.md) states the working
constraints and the commands.

## Research notes

[docs/notes/](docs/notes/) — non-normative background: protocol survey, Elixir
package inventory, media pipeline, analysis and playlist research. Each file
names what in it the specifications supersede. The
[Elixir package reference](docs/notes/04-elixir-package-reference.md) remains
current.

[docs/drafts/](docs/drafts/) — the decision log behind spec-01.
