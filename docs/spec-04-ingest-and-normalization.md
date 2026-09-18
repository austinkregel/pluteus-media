# Ingest and Normalization

**Specification 04**
**Status:** Draft
**Version:** 0.1
**Depends on:** spec-01 (Catalog Data Model), spec-02 (Annotations and Derived
Data), spec-03 (Assets, Storage and Preservation)
**Obsoletes:** nothing

## Abstract

This document specifies how a file becomes a holding: how it is acquired into
primary storage, identified, placed in the catalog, normalized, and analysed.
spec-01 defines what a holding is, spec-02 what may be computed about one, and
spec-03 what custody of its bytes requires. This document is the path between a
file appearing and all three being true of it.

---

## 1. Introduction

### 1.1 Scope

- Acquisition from an inbox into primary storage, and the storage layout
- Identification of format, essence and embedded evidence
- Placement in the catalog per media class
- When normalization runs and what it reads
- Analysis by deriving tools, and the contract every tool meets
- Resumability, idempotency and failure

### 1.2 What this document does not specify

Matching holdings against external metadata sources (spec-05). Transcoding for
playback (spec-08). The feature and body-type vocabularies, which are seed data
(spec-01 §7.5, spec-02 §6.1). How derived measurements are assembled, weighted
or searched (spec-09).

---

## 2. Conventions

BCP 14 key words per spec-01 §2.

---

## 3. The stages

A file passes through five stages. Each is a unit of scheduled work, and each
is idempotent: running a stage over something it has already completed changes
nothing.

| Stage | Reads | Produces |
| --- | --- | --- |
| Acquire | a file in the inbox | an asset in primary storage |
| Identify | the asset's bytes | format, essence, and derived evidence |
| Place | the evidence | the asset's position in the catalog |
| Normalize | the acquired asset | the standardized master (spec-03 §4) |
| Analyse | the normalized master | derived annotations (spec-02) |

**Progress is catalog state, not queue state.** Each stage finds its work by
querying for what lacks its output — an asset with no identified essence, a
digital item with no normalized master, a manifestation with no current
derivation from a given tool. The job queue is a schedule and holds nothing that
cannot be reconstructed. Losing it loses no work; re-running the stages finds
everything unfinished.

Concurrency is set in one place, per stage, in the queue configuration. A stage
MUST NOT run a pool of its own underneath it.

---

## 4. Acquisition

### 4.1 The inbox

Files enter through an inbox: a directory the household writes to and the
deployment watches. A file in the inbox is moved into primary storage, and the
inbox no longer holds it once it is acquired. An existing library is imported
the same way, by moving it into the inbox once.

A file is acquired only once it has stopped changing. A file whose size or
modification time changed within the settle interval is still being written and
MUST NOT be acquired yet. Acquiring a half-copied file records bytes that were
never the file.

### 4.2 Order of operations

Acquisition MUST complete in this order:

1. Place the bytes at their location in primary storage. Within one filesystem
   this is a rename. Across filesystems it is a copy, and the copy is digested
   and compared with the source before anything else happens.
2. Measure and identify the bytes where they now lie (spec-03 §3.2, §6).
3. Record the asset, with the name the file arrived under as its nomen
   (spec-03 §3.2) and the path it arrived at within the inbox as evidence.
4. Remove the file from the inbox.

The file leaves the inbox only after the asset that accounts for it has
committed. An interruption at any step leaves either the inbox file with no
asset, or both. Neither loses anything.

### 4.3 Idempotency

An inbox file whose digest equals that of an asset recorded from the same inbox
path is already acquired. It MUST be removed from the inbox and MUST NOT produce
a second asset. This is the interruption between steps 3 and 4 completing on the
next pass.

A file whose digest equals an asset acquired from a different path is a new
acquisition, and a candidate for spec-03 §8's deduplication. Acquisition does
not decide it is a duplicate; spec-03 §8.3 leaves that to a person.

### 4.4 Layout

An asset's location derives from its identifier and from nothing else: not its
name, not its format, not its place in the catalog. Renaming, re-placing or
re-identifying a holding never moves its bytes. What a file was called is its
nomen; where it sat in the inbox is evidence for placement.

### 4.5 Companion files

A file arriving beside media and describing it — synchronized lyrics, a cover
image, a cue sheet, an `.nfo` — is acquired as an asset of the same digital item,
with a role in the Acquired class naming what it is. It is evidence for
placement and for analysis, and it is kept, since it cannot be regenerated.

---

## 5. Identification

Identification reads the bytes and nothing else.

- **Format** is the PRONOM identifier of spec-03 §6.
- **Stream structure and embedded tags** come from probing the container:
  codecs, duration, channels, dimensions, chapters, embedded tags and embedded
  artwork. They are recorded as derived annotations of the probing tool
  (spec-02 §4), since re-running the probe regenerates them from the asset.
- **Essence** — whether the bytes have already discarded information — follows
  from the codec, through a registry of codecs and their essence (spec-01 §17).

Essence that cannot be determined is treated as lossy. Normalization then adopts
the asset as its own master and never re-encodes it (spec-03 §4.2), which is the
only choice that cannot lose fidelity whatever the essence turns out to be.

---

## 6. Placement

### 6.1 What placement decides

spec-01 §6.2 requires every holding to sit under a manifestation, an expression
and a work. Placement decides which, from the evidence identification produced:
embedded tags, companion files, and the path the file arrived at.

Placement MUST NOT treat each acquired file as a singleton manifestation of its
own work (spec-01 §5.2). Files that are one release are placed as one release.

Every entity placement creates is named (spec-01 §6.1), from embedded titles
where present and from the acquired name otherwise.

### 6.2 Placement is provisional

Placement acts on evidence that is often incomplete and sometimes wrong: a
missing album tag, two releases sharing a folder. What it creates is the
household's catalog and is corrected the way any catalog content is — by a
member, whose correction outranks it (spec-01 §7.5), or by matching against
external sources (spec-05). Re-running placement MUST NOT undo a correction.

### 6.3 Per media class

Placement follows Annex A for each class.

**Music.** Each track is a work (the composition) realized by an expression
(the recording). Each track's recording is embodied in a **track manifestation
of its own**, which is a part of the release manifestation through LRM-R26, and
the track's file is the digital item carrying the track manifestation. The
release is an aggregating work whose expression aggregates the track recordings
through LRM-R25, and track order is arrangement on that relation (spec-01
§12.1). This is the shape external identifiers expect: a MusicBrainz track
identifies a track manifestation and a release identifies the release
manifestation.

Tracks are grouped into one release when their embedded release evidence agrees;
where it is absent, files that arrived in the same inbox directory are one
release. A multi-disc release is one release whose track manifestations carry
their disc in their arrangement.

**Film and television.** Per Annex A §A.2–A.3. A container holding several
audio or subtitle tracks embodies parallel expressions and MUST NOT be
demultiplexed (spec-01 §5.3).

**Photographs and home video.** One work, one expression, one manifestation,
one digital item (Annex A §A.4, §A.7).

**Scans.** A scan of a physical object is a manifestation of the object's
expression (Annex A §A.5). A second scan of an object already catalogued is a
further manifestation of the same expression, not a new work (spec-01 conformance
criterion 10), where the evidence identifies the object; where it does not, the
scan is placed as its own work and the household merges them through spec-03
§8's candidates.

**Documents and ebooks.** Per Annex A §A.6.

### 6.4 Idempotency

Placement records the digital item it placed each asset under. Re-running it
over a placed asset changes nothing.

---

## 7. Normalization

Normalization runs once placement is complete, and is governed by spec-03 §4.

Where the registry names no standard format for a media class (spec-01 §17), the
acquired asset is the class's master: it is adopted in place and nothing is
re-encoded. Naming a format for the class later makes the lossless holdings of
that class due for normalization, which is a query over the catalog.

---

## 8. Analysis

### 8.1 What analysis reads and targets

Analysis reads the **normalized master**, so that every tool reads one format
per media class rather than every format the household ever acquired
(spec-01 §13.3).

A derived annotation over media targets the **manifestation whose bytes were
read**, or an address on it. Two manifestations of one expression — a
remaster, a second scan — differ in timing and in pixels, and a measurement of
one is not a measurement of the other. spec-02 §3.3's association between an
authored annotation on an expression and the derived regions covering it spans
the manifestations embodying that expression.

### 8.2 Tools

Each analysing component is a deriving tool in spec-02's sense: every
annotation it produces names it and its version, and nothing else.

Two families of tool run from the start, side by side:

| Family | Runs | Provides |
| --- | --- | --- |
| **Native** | In the deployment, on the BEAM | What the Elixir ecosystem can compute: short-time Fourier and mel spectra, MFCC through a discrete cosine transform, chroma from the short-time spectrum, loudness |
| **Sidecar** | A separate service | What it cannot: constant-Q chroma and the key, mode and harmony features built on it, beat and onset tracking, acoustic fingerprinting |

They are different tools, so neither supersedes the other (spec-02 §5.2). Where
both compute a measurement of the same name, both results stand, and which one a
vector uses is the assembling component's choice (spec-02 §6.3). A native tool
reaching parity with the sidecar for a measurement is established by comparing
their stored bodies over the same holdings, never by assuming it.

### 8.3 The tool contract

Every tool, whatever it runs on, meets the same contract.

- **One input per request.** A tool analyses one asset per call and holds no
  queue of its own. Concurrency is the stage's (§3).
- **Named values.** A tool returns measurements by name (spec-02 §6.1) and never
  a positional vector. The wire format carries its own schema version, and a
  response whose schema version the deployment does not know is refused.
- **Raw values.** A tool returns values as it computed them (spec-02 §7).
  Normalization and weighting happen after, from the stored body.
- **Identity.** A tool reports its name and a version sufficient to distinguish
  builds (spec-02 §4.2).
- **Read only.** A tool reads the asset and writes nothing: not to storage, not
  to the catalog. The sidecar holds no database credentials and mounts primary
  storage read-only.

### 8.4 Re-derivation

A tool whose version changes makes every manifestation analysed at an earlier
version due for re-analysis. Finding them is spec-02 §4.2's query; re-analysing
them reads the normalized master again and never re-acquires anything. The
earlier results stand, superseded, until the household deletes them
(spec-02 §5.2).

---

## 9. Failure

A stage that cannot complete records why, against the asset, as a finding a
person can see. It does not skip the asset silently, and it does not retry
indefinitely.

| Failure | Examples | Handling |
| --- | --- | --- |
| **Permanent** | Undecodable bytes, a file too short to analyse, an unsupported codec | Recorded, not retried |
| **Transient** | A timeout, a tool unavailable, resources exhausted | Retried a bounded number of times with backoff; exhaustion is recorded as a finding |

A retry that eventually succeeds leaves the record of its failures in place. A
permanent failure is revisited only by a person, or by a new version of the
tool that failed, which makes the asset due again under §8.4.

---

## 10. Conformance

1. A file placed in the inbox is moved into primary storage, recorded as an asset
   whose nomen is the name it arrived under, and is no longer in the inbox.
2. A file whose size or modification time changed within the settle interval is
   not acquired.
3. An interruption after an asset is recorded and before its inbox file is
   removed leaves one asset, and the next pass removes the file without recording
   a second.
4. An asset's location does not change when the holding is renamed or re-placed.
5. Two tracks of one release are placed as track manifestations that are parts of
   one release manifestation, with their order as arrangement on the release's
   aggregation; neither is a singleton manifestation of its own work.
6. A container with several audio tracks is placed as parallel expressions of one
   manifestation and is not demultiplexed.
7. Essence that cannot be determined is never re-encoded.
8. Analysis reads the normalized master, and its annotations target the
   manifestation whose bytes were read.
9. The native and sidecar tools' measurements of one recording both stand, each
   naming its own tool and version.
10. A tool response carrying a positional vector, or a schema version the
    deployment does not know, is refused.
11. A tool whose version changes makes the manifestations it analysed earlier
    findable and due for re-analysis, without re-acquiring anything.
12. A permanent failure is recorded and not retried; a transient failure is
    retried a bounded number of times and its exhaustion is recorded.
13. Emptying the job queue loses no work: re-running the stages finds everything
    unfinished from catalog state.
14. A correction a member made to a placement survives placement running again.
15. The sidecar holds no database credentials and cannot write to primary
    storage.

---

## 11. Security considerations

Everything in the inbox is untrusted input. Probing, identification and analysis
parse arbitrary bytes, and parsers of media formats have a long history of
exploitable defects. Tools SHOULD run with bounded time and memory and without
access to anything they do not read, which the sidecar's read-only mount and
absent credentials provide for it.

Moving files out of the inbox means the deployment deletes from a directory the
household writes to. It deletes only a file it has just accounted for (§4.2), and
never anything it has not acquired.

---

## 12. References

### 12.1 Normative

- **[spec-01]** *Catalog Data Model*, this system, with Annex A.
- **[spec-02]** *Annotations and Derived Data*, this system.
- **[spec-03]** *Assets, Storage and Preservation*, this system.
- **[RFC2119]**, **[RFC8174]** as in spec-01 §18.1.

### 12.2 Informative

- **[PRONOM]** The National Archives (UK) format registry.
- **[MUSICBRAINZ]** MusicBrainz database schema: release, medium, track and
  recording, which §6.3's music placement mirrors.
