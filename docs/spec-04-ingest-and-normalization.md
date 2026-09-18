# Ingest and Normalization

**Specification 04**
**Status:** Draft
**Version:** 0.2
**Depends on:** spec-01 (Catalog Data Model), spec-02 (Annotations and Derived
Data), spec-03 (Assets, Storage and Preservation), spec-06 (Principals, Auth
and Authorization)
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
- The acquisition record that holds a file between acquisition and placement
- Identification of format, streams, essence and media class
- Placement in the catalog per media class, including how music releases are
  structured and grouped
- When normalization runs and what it reads
- Analysis by deriving tools, and the contract every tool meets
- Resumability, idempotency and failure

### 1.2 What this document does not specify

Matching holdings against external metadata sources, including linking the same
recording across releases (spec-05). Transcoding for playback (spec-08). The
feature, body-type, codec-essence and category vocabularies, which are seed data
(spec-01 §7.5, §17; spec-02 §6.1). How derived measurements are assembled,
weighted or searched (spec-09).

---

## 2. Conventions

BCP 14 key words per spec-01 §2.

---

## 3. The stages

A file passes through five stages. Each is a unit of scheduled work, and each is
idempotent: running a stage over something it has already completed changes
nothing.

| Stage | Reads | Produces |
| --- | --- | --- |
| Acquire | a file in the inbox | bytes in primary storage and an acquisition record |
| Identify | the stored bytes | format, streams, essence and media class, on the acquisition record |
| Place | the acquisition record | a holding in the catalog and its asset, in one transaction |
| Normalize | the acquired asset | the standardized master (spec-03 §4) |
| Analyse | the normalized master | derived annotations (spec-02) |

**Progress is recorded state, not queue state.** Each stage finds its work by
querying for what lacks its output and has no recorded failure for it (§9): an
acquisition not yet identified, an identified acquisition not yet placed, a
digital item with no normalized master, a manifestation with no current
derivation from a given tool. The job queue is a schedule and holds nothing that
cannot be reconstructed. Losing it loses no work.

Concurrency is set in one place, per stage, in the queue configuration. A stage
MUST NOT run a pool of its own underneath it.

All catalog writes ingest makes are the deployment's own and are attributed to
the System principal (spec-06 §6.1).

---

## 4. Acquisition

### 4.1 The inbox

Files enter through an inbox: a directory the household writes to and the
deployment watches. An existing library is imported by moving it into the inbox
once.

A file is acquired only once it has stopped changing. A file whose size or
modification time changed within the settle interval is still being written and
MUST NOT be acquired yet. Acquiring a half-copied file records bytes that were
never the file.

Some files in an inbox are not holdings: operating-system metadata such as
`.DS_Store`, `Thumbs.db`, `desktop.ini`, AppleDouble `._` files and a NAS's
`@eaDir` directories, and downloads still in progress under a temporary name
such as `.part` or `.crdownload`. They are recognized by a registry of names and
patterns (spec-01 §17), and are never acquired and never removed. A stalled
partial download that stops changing is exactly the file the settle interval
alone would acquire.

A symbolic link is not acquired: moving it moves the link and not the bytes, and
following it could read outside the inbox. A file with more than one hard link
is copied and never renamed, and only the inbox's link is removed afterwards,
since the bytes remain reachable, and changeable, through the other.

Each of these is reported, so the household can see what the inbox is holding
back.

### 4.2 The acquisition record

Between arriving and being placed, a file has no place in the catalog: an asset
must realize a digital item, which must carry a manifestation, which spec-01
§6.2 requires to embody an expression of a work. The acquisition record holds
the file in the meantime. It belongs to the custody layer, not the catalog, and
holds:

| Field | Holds |
| --- | --- |
| identifier | minted at acquisition; the asset placement creates carries it |
| inbox path | where the file arrived, relative to the inbox |
| location | where the bytes are in primary storage (§4.5) |
| size, digest, digest algorithm | measured from the stored bytes (spec-03 §3.2, §5.1) |
| format | PRONOM identification of the stored bytes (spec-03 §6) |
| probe output | streams, codecs, duration, dimensions, chapters, embedded tags |
| essence | per stream and for the whole (§5.2) |
| media class | §5.3 |
| state | how far the file has come, and any recorded failure (§9) |
| placement | the digital item it was placed under, once placed |

The record outlives placement. The inbox path and probe output are provenance,
and what placement concluded from them stays inspectable after the fact.

### 4.3 Order of operations

Acquisition proceeds in this order:

1. Mint the identifier, derive the location from it (§4.5), and write the
   acquisition record with the inbox path and the location, before any byte
   moves.
2. Place the bytes at the location. Within one filesystem this is a rename.
   Across filesystems it is a copy, digested and compared with the source.
3. Measure and identify the bytes where they now lie (§5).
4. Where the bytes were copied, remove the inbox file.

Because the record precedes the move, every interruption leaves a state the
next pass recognizes and completes:

| Found | Meaning | Next pass |
| --- | --- | --- |
| Record, inbox file, nothing at the location | interrupted before the move | moves the file |
| Record, inbox file, a partial copy at the location | interrupted during a copy | discards the partial copy and copies again |
| Record, bytes at the location, no inbox file | moved or copied and removed, not yet identified | identifies the bytes |
| Bytes under primary storage whose identifier has no record | cannot arise from this order | reported as a finding, never deleted |

### 4.4 Idempotency

An inbox file whose digest equals that of an acquisition recorded from the same
inbox path is already acquired. It MUST be removed from the inbox and MUST NOT
produce a second acquisition.

A file whose digest equals an acquisition from a different path is a new
acquisition, and a candidate for spec-03 §8. Acquisition does not decide it is a
duplicate; spec-03 §8.3 leaves that to a person.

### 4.5 Layout

A location derives from the identifier and from nothing else: not the file's
name, not its format, not its place in the catalog. Renaming, re-placing or
re-identifying a holding never moves its bytes. What a file was called is its
nomen; where it sat in the inbox is on its acquisition record.

### 4.6 Companion files

A companion is a file that describes another: a cover image, synchronized
lyrics, a cue sheet, an `.nfo`. It is recognized as one at identification,
before any category is decided, by its name and format against a registry of
companion patterns (spec-01 §17) — `cover.*`, `folder.*`, `*.lrc`, `*.cue`,
`*.nfo` among them — so that album art never reaches placement as a photograph,
nor lyrics as a document.

A companion is acquired as a holding of its own, whose category is its companion
kind — cover art, lyrics, cue sheet, description — and never its broad class's
default (§6.3). It is not an asset of the media it describes. A digital item's
assets are copies of one content (spec-01 §5.5), and a cover image made an
Acquired asset of a track would become the original the track's normalized
master depends on (spec-03 §3.3).

A companion finds what it describes through the inbox directory it arrived in,
which is the only link an untagged `cover.jpg` has to its album. The directory is
on its acquisition record, and the link is made once both the companion and a
holding acquired from the same directory are placed, in whichever order they
arrive:

| Companion | Describes |
| --- | --- |
| lyrics sharing a media file's base name | the track manifestation placed from that file |
| any other companion | the release placed from the directory's files |

Where a directory's files were placed into more than one release, a
directory-level companion is not linked, and the ambiguity is recorded as a
finding for a person. The directory is evidence for this link and for nothing
else; it does not group tracks into releases (§6.4).

The link is an association refining LRM-R1 (spec-01 §7.5) whose type names the
relation. A deriving tool then reads the companion into what it describes:
synchronized lyrics become derived temporal annotations on the track
manifestation (spec-02), and a cue sheet or `.nfo` becomes evidence for
placement. The companion itself is kept, since it cannot be regenerated.

---

## 5. Identification

Identification reads the stored bytes and nothing else, and writes what it finds
to the acquisition record.

### 5.1 Format and streams

Format is the PRONOM identifier of spec-03 §6. Streams, codecs, duration,
dimensions, chapters, embedded tags and embedded artwork come from probing the
container. On placement, the probe output becomes derived annotations of the
probing tool on the manifestation (spec-02 §4), since re-running the probe
regenerates them from the asset.

### 5.2 Essence

Essence — whether bytes have already discarded information — belongs to a
stream, and is decided per stream.

The codec registry (spec-01 §17) maps each codec to lossy, to lossless, or to
*by parameter* for codecs with both modes: WebP, JPEG XL, JPEG 2000 and HEVC
among them. For a by-parameter codec the stream's essence is read from the
probed parameters that distinguish the modes. Where the codec is not in the
registry, or its distinguishing parameters are not in the probe, the stream's
essence is **unknown**.

The file's essence follows from its streams:

| Streams | File essence |
| --- | --- |
| any stream lossy | lossy |
| every stream lossless | lossless |
| otherwise | unknown |

Unknown is recorded as unknown, never as lossy or lossless. An asset of unknown
essence is never re-encoded: normalization adopts it as its own master, the only
choice that cannot lose fidelity whatever the essence turns out to be. When the
registry learns more, the assets of unknown essence are found by query and
identified again.

### 5.3 Media class

Identification decides the broad media class: companion, when the file matches
a companion pattern (§4.6), which is decided first; otherwise audio, video,
image or text, from the format and the streams. It is recorded on the
acquisition record and routes placement (§6) and normalization (§7). The finer category a holding
belongs to — film, television episode or home video; photograph or scan — is
placement's decision (§6.3), since bytes alone do not carry it.

---

## 6. Placement

### 6.1 What placement writes

Placement writes a holding's work, expression, manifestation, digital item and
asset in one transaction, with the asset taking the acquisition's identifier.
No asset exists before its digital item does. The same transaction records the
placement on the acquisition record and turns its probe output into derived
annotations on the manifestation. The asset's verification interval (spec-03
§3.2) is the one the deployment configures for its broad class.

Placement MUST NOT treat each acquired file as a singleton manifestation of its
own work (spec-01 §5.2). Files that are one release are placed as one release
(§6.4).

### 6.2 Placement is provisional

Placement acts on evidence that is often incomplete and sometimes wrong. What it
creates is the household's catalog, and is corrected the way any catalog content
is.

Every name placement writes, and every category, carries **automatic**
provenance. A member's correction is local and outranks it under spec-01 §7.5;
without that distinction the two would tie, and the older of them — placement's
— would win. Placement running again MUST NOT overwrite or duplicate a name or
category, whether placement wrote it or a member did.

### 6.3 Category

Placement records a category on the work, drawn from the category registry
(spec-01 §17), with automatic provenance. It is decided from evidence — embedded
tags, a companion `.nfo`, the inbox path — and, where evidence decides nothing,
from the broad class:

| Broad class | Category without evidence |
| --- | --- |
| companion | its companion kind (§4.6) |
| audio | music recording |
| video | home video |
| image | photograph |
| text | document |

A member's correction outranks it (§6.2). Normalization's standard format is
looked up by the broad class, which the bytes decide and which does not change
when the category is corrected.

### 6.4 Music

#### Structure

| Level | Instance | Relation |
| --- | --- | --- |
| Work | the composition | — |
| Expression | the recording | realizes the work (LRM-R2) |
| Track manifestation | the track as released | embodies the recording; part of a medium (LRM-R26), positioned |
| Medium manifestation | one disc or side | part of the release (LRM-R26), positioned; embodies the album's aggregating expression |
| Release manifestation | the release | embodies the album's aggregating expression |
| Digital item | the track's file | carries the track manifestation |

The release is an aggregating work whose expression aggregates the track
recordings through LRM-R25 (spec-01 §5.3). Order lives on the whole-part
relations: a medium's position within the release and a track's position within
its medium, each as the arrangement integer of spec-01 §12.1, taken from the
release's medium and track positions. Placement does not set an arrangement on
the aggregation; the order is the whole-part positions, and a second copy of it
could only drift from the first.

Placement does not match works or recordings across releases. The same song on
an album and on a compilation is two works and two recordings after placement,
until matching (spec-05) or a person links them.

#### Grouping tracks into a release

A track joins a release when their release evidence agrees:

1. Where a track carries an external release identifier, such as a MusicBrainz
   release identifier, the release is the one bearing it.
2. Otherwise, the release is the one whose album title and album artist equal
   the track's, and whose release date and total disc count equal the track's
   where both carry them. A field is compared only where both sides carry it: a
   missing date neither matches nor contradicts another. A track carrying no
   album title or no album artist falls to rule 3.
3. A track with no album evidence is a release of its own.

Untagged files — a plain WAV rip carries no album evidence at all — therefore
each become a release of their own. That is accepted knowingly: a split release
is corrected by joining it, whereas two releases wrongly merged must first be
noticed.

The inbox directory is not release evidence. Files dropped loose at the inbox
root, or two releases fed through one directory at different times, are grouped
only by what they say about themselves.

Files settle one at a time, so a release arrives piecemeal. Placement MUST join
a track to a release placed earlier when their evidence agrees. The key each
release was grouped by is recorded by ingest, outside the catalog, so that a
later track can find the release, and so that a member's renaming of the release
does not change which tracks join it.

### 6.5 Film and television

Per Annex A §A.2–A.3. A container is not demultiplexed (spec-01 §5.3). Its
streams are placed as expressions by what distinguishes them:

| Streams | Placed as |
| --- | --- |
| differing only in channel layout or encoding — a 5.1 mix and its stereo downmix in one language | one expression |
| in different languages, spoken or subtitled | parallel expressions of the film |
| marked by the container as commentary | an expression of a work of its own, the commentary, embodied in the same manifestation as an augmentation (spec-01 §5.3) |

Every stream is addressed within the manifestation by a `track` selector
(spec-01 §8.3), whichever expression it belongs to, so a 5.1 mix and its
downmix are still told apart where analysis needs them to be.

### 6.6 Photographs and home video

One work, one expression, one manifestation, one digital item (Annex A §A.4,
§A.7).

### 6.7 Scans

A scan is placed as a manifestation of a work and expression of its own.
Placement cannot tell from the bytes that two scans are of one object: the scans
differ in digest, and nothing here computes a perceptual hash. That two scans are
of one object is a member's decision: the member raises the pair as a
deduplication candidate and decides it as *same expression* (spec-03 §8.3). Carrying it out moves the second scan's manifestation under the
first scan's expression, which is spec-01 conformance criterion 10's outcome.

### 6.8 Documents and ebooks

Per Annex A §A.6.

### 6.9 Idempotency

The acquisition record carries the placement once made. Placement over a placed
acquisition changes nothing.

---

## 7. Normalization

Normalization runs once placement is complete, and is governed by spec-03 §4.

Where the registry names no standard format for a broad class (spec-01 §17), the
acquired asset is the master: it is adopted in place and nothing is re-encoded.

When the registry's standard format for a class changes, the lossless holdings
of that class are normalized again. The new master takes the Normalized role and
the previous normalized asset is recycled, which spec-03 §3.3 permits since it
is regenerable from the original. A previous master that is also the Acquired
asset is left as it is.

---

## 8. Analysis

### 8.1 What analysis reads, runs over and targets

Analysis runs over a **manifestation**. It is the derivation's input (spec-02
§4.1), so re-analysing after a master is replaced supersedes the earlier results
for that manifestation rather than leaving both standing.

It reads the normalized master of one digital item carrying the manifestation:
the manifestation's analysis source, which ingest records and which is the
earliest placed digital item until a member names another. The asset read is
recorded in the derivation's parameters, and naming a different source makes the
manifestation due for analysis again.

A derived annotation targets the manifestation or an address on it. Two
manifestations of one expression — a remaster, a second scan — differ in timing
and in pixels, and a measurement of one is not a measurement of the other.
spec-02 §3.3's association between an authored annotation on an expression and
the derived regions covering it spans the manifestations embodying that
expression.

A stream of a multi-stream container is analysed as the stream it is: its
derived annotations target the `track` address of that stream, and a region
within the stream is addressed on the track address (spec-01 §8.5).

### 8.2 Tools

Each analysing component is a deriving tool in spec-02's sense. Two families run
from the start, side by side:

| Family | Runs | Provides |
| --- | --- | --- |
| **Native** | In the deployment, on the BEAM | Short-time Fourier and mel spectra from `nx_signal`; MFCC once a discrete cosine transform is added from `evision`, which is not yet a dependency; chroma from the short-time spectrum and loudness, which are code to write over those |
| **Sidecar** | A separate service | What it cannot: constant-Q chroma and the key, mode and harmony features built on it, beat and onset tracking, acoustic fingerprinting |

They are different tools, so neither supersedes the other (spec-02 §5.2). Where
both compute a measurement of the same name, both results stand, and which one a
vector uses is the assembling component's choice (spec-02 §6.3). A native tool
reaching parity with the sidecar for a measurement is established by comparing
their stored bodies over the same holdings, never by assuming it.

### 8.3 The tool contract

Every tool, whatever it runs on, meets the same contract.

- **Description.** A tool answers what it is — its name, its version (spec-02
  §4.2), and its wire schema version — without analysing anything.
- **One input per request.** A tool analyses one asset per call and holds no
  queue of its own. Concurrency is the stage's (§3).
- **Named values.** A tool returns measurements by name (spec-02 §6.1) and never
  a positional vector. The response carries its wire schema version, and a
  response whose schema version the deployment does not know is refused.
- **Raw values.** A tool returns values as it computed them (spec-02 §7).
  Normalization and weighting happen after, from the stored body.
- **Read only.** A tool reads the asset and writes nothing: not to storage, not
  to the catalog. The sidecar holds no database credentials and mounts primary
  storage read-only.

### 8.4 Re-derivation

The deployment asks each tool for its description on a schedule. A version it
has not recorded makes every manifestation analysed at an earlier version due
for re-analysis — spec-02 §4.2's query — before anything has been analysed at the
new version. Re-analysis reads the normalized master again and never re-acquires
anything. The earlier results stand, superseded, until the household deletes them
(spec-02 §5.2).

---

## 9. Failure

A stage that cannot complete records why, as a finding a person can see. It does
not skip the item silently, and it does not retry indefinitely.

| Failure | Examples | Handling |
| --- | --- | --- |
| **Permanent** | Undecodable bytes, a file too short to analyse, an unsupported codec | Recorded, not retried |
| **Transient** | A timeout, a tool unavailable, resources exhausted | Retried a bounded number of times with backoff; exhaustion is recorded as a failure |

A failure is recorded against what the stage was working on: the acquisition
record for acquisition, identification and placement — an unreadable inbox file
has no asset, but it has a record from the first step of §4.3 — and the
manifestation, tool and tool version for analysis.

The query for due work excludes anything with a recorded failure at the stage's
current tool version. A failure stops being recorded, and the item becomes due
again, only when:

- a person clears it, asking for it to be tried again, or
- the tool's version changes (§8.4).

A retry that eventually succeeds leaves the record of its failed attempts in
place.

---

## 10. Conformance

1. A file placed in the inbox is moved into primary storage and gains an
   acquisition record; once placed, it is an asset whose identifier is the
   acquisition's and whose nomen is the name it arrived under.
2. A file whose size or modification time changed within the settle interval is
   not acquired.
3. Operating-system metadata, partial downloads under a temporary name, and
   symbolic links are never acquired and never removed, and are reported; a file
   with more than one hard link is copied, not renamed.
4. An interruption at any step of §4.3 is completed by the next pass without
   losing the bytes and without a second acquisition.
5. An asset's location does not change when the holding is renamed or re-placed.
6. A companion is recognized before a category is decided: a cover image is
   never categorized as a photograph, nor lyrics as a document.
7. A companion is linked to what its directory's files were placed as, whichever
   arrives first; lyrics sharing a file's base name link to that track; a
   companion whose directory produced more than one release is not linked and is
   recorded as a finding.
8. Removing a companion does not remove the described holding's normalized
   master.
9. Placement writes a holding's work, expression, manifestation, digital item and
   asset in one transaction, and no asset exists without its digital item.
10. Names and categories placement writes carry automatic provenance; a member's
    correction outranks them and survives placement running again.
11. Two tracks of one release are placed as track manifestations positioned
    within a medium, which is positioned within the release; the aggregation
    carries no arrangement.
12. A track arriving after its release was placed joins that release.
13. Two files in one inbox directory whose release evidence disagrees are not
    placed in one release; a field one track lacks neither joins nor separates
    it.
14. In a multi-stream container, streams differing only in channel layout or
    encoding are one expression, streams in different languages are parallel
    expressions, a commentary stream is an expression of a work of its own, and
    each stream's analysis targets that stream's `track` address.
15. A file with a lossy stream is lossy; essence that cannot be determined is
    recorded as unknown and is never re-encoded.
16. Analysis runs over a manifestation, reads the normalized master of its
    analysis source, and records which asset it read.
17. The native and sidecar tools' measurements of one manifestation both stand,
    each naming its own tool and version.
18. A tool response carrying a positional vector, or a schema version the
    deployment does not know, is refused.
19. A tool reporting a new version makes the manifestations it analysed earlier
    due for re-analysis before any has been analysed at the new version.
20. A permanent failure is recorded and excluded from due work until a person
    clears it or the tool's version changes; a transient failure is retried a
    bounded number of times and its exhaustion is recorded.
21. A failure to acquire an inbox file is recorded against its acquisition
    record.
22. Emptying the job queue loses no work: the stages find everything unfinished
    from recorded state.
23. Changing a class's standard format leaves one Normalized asset per digital
    item.
24. Every catalog write ingest makes is attributed to the System principal.
25. The sidecar holds no database credentials and cannot write to primary
    storage.

---

## 11. Security considerations

Everything in the inbox is untrusted input. Probing, identification and analysis
parse arbitrary bytes, and parsers of media formats have a long history of
exploitable defects.

The sidecar reads storage read-only and holds no credentials. Probing and
identification SHOULD run with the same isolation. Where they run within the
deployment, as child processes of the application holding its database
credentials, a parser defect reaches everything the deployment can reach. Every
tool SHOULD run with bounded time and memory.

Moving files out of the inbox means the deployment deletes from a directory the
household writes to. It removes an inbox file only once the acquisition record
accounting for it exists (§4.3), and never removes anything it has not acquired.

---

## 12. References

### 12.1 Normative

- **[spec-01]** *Catalog Data Model*, this system, with Annex A.
- **[spec-02]** *Annotations and Derived Data*, this system.
- **[spec-03]** *Assets, Storage and Preservation*, this system.
- **[spec-06]** *Principals, Auth and Authorization*, this system.
- **[RFC2119]**, **[RFC8174]** as in spec-01 §18.1.

### 12.2 Informative

- **[PRONOM]** The National Archives (UK) format registry.
- **[MUSICBRAINZ]** MusicBrainz database schema: release, medium, track and
  recording, which §6.4's music structure mirrors.
