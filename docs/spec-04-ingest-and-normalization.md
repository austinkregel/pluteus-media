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
   moves. At most one acquisition in progress holds a given inbox path.
2. Place the bytes at the location. Within one filesystem this is a rename.
   Across filesystems it is a copy, digested and compared with the source.
3. Measure and identify the bytes where they now lie (§5).
4. Where the bytes were copied, remove the inbox file.

Because the record precedes the move, every interruption leaves a state the
next pass recognizes:

| Found | Meaning | Next pass |
| --- | --- | --- |
| Record, inbox file, nothing at the location | interrupted before the move | moves the file |
| Record, inbox file, bytes at the location | interrupted during or after a copy | compares digests: where identical it continues from identification; otherwise it discards the bytes at the location and copies again |
| Record, bytes at the location, no inbox file | moved, or copied and removed; not yet identified | identifies the bytes |
| Record, no inbox file, nothing at the location | the file left the inbox by other means before it was moved | records a finding against the record |
| Bytes under primary storage whose identifier has no record | cannot arise from this order | records a finding, and deletes nothing |

### 4.4 Idempotency

An inbox file whose digest equals that of an acquisition recorded from the same
inbox path, and whose holding is still live, is already acquired. It MUST be
removed from the inbox and MUST NOT produce a second acquisition. Where that
holding has since been recycled or purged, the file is a new acquisition: the
household is bringing back something it deleted.

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
stream, and is decided per content stream. A content stream carries the media
itself. Streams that accompany it are not counted: embedded cover art, data
streams, timecode tracks, and attached files such as fonts.

The registry (spec-01 §17) maps each codec to lossy, to lossless, or to *by
parameter* for codecs with both modes: WebP, JPEG XL, JPEG 2000 and HEVC among
them. For a by-parameter codec the stream's essence is read from the probed
parameters that distinguish the modes. Where the codec is not in the registry,
or its distinguishing parameters are not in the probe, the stream's essence is
**unknown**.

The file's essence follows from its content streams:

| Content streams | File essence |
| --- | --- |
| none | not applicable |
| any lossy | lossy |
| every one lossless | lossless |
| otherwise | unknown |

A file in which the probe finds no streams at all — a PDF, a plain text file —
takes its essence from its format instead, through the same registry, which maps
a format to lossy, lossless or not applicable, and gives unknown where it has no
entry.

Unknown is recorded as unknown, never as lossy or lossless; not applicable is
recorded as such, never as a vacuous lossless. Neither is ever re-encoded (§7).
When the registry learns more, the assets of unknown essence are found by query
and identified again.

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

Placement of a file waits until its inbox directory has settled: until no file
in the directory is still being written or awaiting identification. A
directory's companions are thereby identified before its media are placed, so a
cue sheet or an `.nfo` is read as evidence rather than arriving after the
decision it bears on.

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

A track's release is decided by its grouping key:

1. Where the track carries an external release identifier, such as a
   MusicBrainz release identifier, the key is that identifier.
2. Otherwise, where it carries an album title and an album artist, the key is
   the album title, album artist, release date and total disc count, compared
   exactly. A missing field is a value of its own: it equals another missing
   field and nothing else, so a track lacking a date and a track bearing one are
   placed in different releases.
3. A track with neither is a release of its own.

The key depends only on the track's own evidence, never on which tracks arrived
first, so placing the same files in any order yields the same releases.
Untagged files — a plain WAV rip carries no album evidence at all — each become
a release of their own, and a track whose date is missing where its siblings'
are present is split from them. Both are accepted knowingly: a split release is
corrected by joining it, whereas two releases wrongly merged must first be
noticed.

The inbox directory is not release evidence (§4.6).

Files settle one at a time, so a release arrives piecemeal, and placement joins
a track to the release already holding its key. The key is recorded by ingest,
outside the catalog, and is unique: two tracks with one key placed at the same
moment cannot create two releases, and a member's renaming of the release does
not change which tracks join it.

Placement does not guess. A track whose own evidence names two different
releases — two differing external release identifiers, as a file tagged by two
taggers can carry — and a track whose medium and track position are already
taken in its release, are each recorded as a finding and left unplaced until a
person decides. Where a track carries an external release identifier its tags
are not compared with other tracks' for this, since whether they disagree would
depend on which track was placed first.

#### A release in one file

A release ripped to a single file with a cue sheet beside it is one digital item
carrying the release manifestation. Its tracks are still track manifestations,
positioned within their medium as above, but no digital item carries them. Each
track's extent within the file is a temporal address on the release
manifestation, taken from the cue sheet and linked to its track manifestation by
an association refining LRM-R1. Analysing a track reads that extent of the
release's file.

### 6.5 Film and television

Per Annex A §A.2–A.3. A container is not demultiplexed (spec-01 §5.3). Its
content streams (§5.2) are placed as expressions by what distinguishes them:

| Streams | Placed as |
| --- | --- |
| differing only in channel layout or encoding — a 5.1 mix and its stereo downmix in one language | one expression |
| in different languages, spoken or subtitled | parallel expressions of the film |
| marked by the container as commentary | an expression of a work of its own, the commentary, embodied in the same manifestation as an augmentation (spec-01 §5.3) |

Placement creates a `track` address (spec-01 §8.3) for each content stream,
whichever expression it belongs to, so a 5.1 mix and its downmix are told apart
wherever analysis needs them to be. The address identifies its stream by kind,
language, disposition and channel count, with an ordinal among streams alike in
all four. It never identifies a stream by its index in the container, its codec,
or the name its codec gives the channel layout: normalization may reorder
streams and re-encode them, a layout one codec calls `5.1(side)` another calls
`5.1` and PCM leaves unnamed, and the address must still name the same stream
afterwards. Nor does the default flag enter into it, since a muxer sets it
freely.

### 6.6 Photographs and home video

One work, one expression, one manifestation, one digital item (Annex A §A.4,
§A.7).

### 6.7 Scans

A scan is placed as a manifestation of a work and expression of its own.
Placement cannot tell from the bytes that two scans are of one object: the scans
differ in digest, and nothing here computes a perceptual hash. That two scans are
of one object is a member's decision: the member raises the pair as a
deduplication candidate and decides it as *same expression* (spec-03 §8.3).
Resolving it moves the second scan's manifestation under the first scan's
expression and recycles whichever of the work and expression the second scan
was placed under are left holding nothing. One work remains, which is spec-01 conformance
criterion 10's outcome.

### 6.8 Documents and ebooks

Per Annex A §A.6.

### 6.9 Idempotency

The acquisition record carries the placement once made. Placement over a placed
acquisition changes nothing.

---

## 7. Normalization

Normalization runs once placement is complete, and is governed by spec-03 §4.

An asset whose essence is lossy, unknown or not applicable (§5.2) is adopted as
its own master: it takes the Normalized role and nothing is re-encoded. So is a
lossless asset of a broad class for which the registry names no standard format
(spec-01 §17).

The Normalized role is held by one asset per digital item, or per part where a
digital item is realized by parts. When the registry's standard format for a
class changes, the lossless holdings of that class are normalized again and the
new master takes the role. A previous normalized asset that is not also the
Acquired asset is recycled, as spec-03 §3.3 permits for a copy regenerable from
the original. A previous master that is the Acquired asset — adopted while no
standard format was named — gives up the Normalized role and keeps the Acquired
role.

---

## 8. Analysis

### 8.1 What analysis runs over, reads and targets

Analysis of a whole manifestation runs over the manifestation; analysis of one
stream runs over that stream's `track` address (§6.5). That is the derivation's
input (spec-02 §4.1). Re-analysing after a master is replaced therefore
supersedes the earlier results for the same manifestation or stream rather than
leaving both standing, and the French and English audio of one container are
never taken for re-runs of each other.

It reads the normalized master of one digital item carrying the manifestation:
the manifestation's analysis source, which ingest records and which is the
earliest placed digital item until a member names another. The asset read is
recorded in the derivation's parameters, and naming a different source makes the
manifestation due for analysis again.

A derived annotation targets its input or an address on it. Two manifestations
of one expression — a remaster, a second scan — differ in timing and in pixels,
and a measurement of one is not a measurement of the other. spec-02 §3.3's
association between an authored annotation on an expression and the derived
regions covering it spans the manifestations embodying that expression.

### 8.2 Tools

Each analysing component is a deriving tool in spec-02's sense. Two families run
from the start, side by side:

| Family | Runs | Provides |
| --- | --- | --- |
| **Native** | In the deployment, on the BEAM | Short-time Fourier and mel spectra, MFCC, chroma from the short-time spectrum, loudness |
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

A failure is recorded against what the stage was working on:

| Stage | Recorded against |
| --- | --- |
| Acquire, identify, place | the acquisition record, which exists from the first step of §4.3, so an unreadable inbox file has one |
| Normalize | the digital item |
| Analyse | the input, the tool and the tool's version |

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
   losing the bytes and without a second acquisition; a record whose file left
   the inbox before it moved is recorded as a finding; no two acquisitions in
   progress hold one inbox path.
5. A file dropped again while its holding is live is removed from the inbox and
   not acquired again; dropped after its holding was recycled or purged, it is a
   new acquisition.
6. An asset's location does not change when the holding is renamed or re-placed.
7. A companion is recognized before a category is decided: a cover image is
   never categorized as a photograph, nor lyrics as a document.
8. A directory's media are placed only once every file in the directory is
   settled and identified.
9. A companion is linked to what its directory's files were placed as, whichever
   arrives first; lyrics sharing a file's base name link to that track; a
   companion whose directory produced more than one release is not linked and is
   recorded as a finding.
10. Removing a companion does not remove the described holding's normalized
    master.
11. Placement writes a holding's work, expression, manifestation, digital item
    and asset in one transaction, and no asset exists without its digital item.
12. Names and categories placement writes carry automatic provenance; a member's
    correction outranks them and survives placement running again.
13. Two tracks of one release are placed as track manifestations positioned
    within a medium, which is positioned within the release; the aggregation
    carries no arrangement.
14. The same files placed in any order yield the same releases; a missing field
    equals only another missing field; a track arriving after its release was
    placed joins it.
15. Two concurrent placements of tracks with one grouping key create one release.
16. A track whose own evidence carries two different release identifiers, or
    whose position is already taken in its release, is recorded as a finding and
    not placed.
17. A release in one file with a cue sheet is one digital item carrying the
    release manifestation, and each track is a track manifestation located by a
    temporal address on it.
18. In a multi-stream container, streams differing only in channel layout or
    encoding are one expression, streams in different languages are parallel
    expressions, and a commentary stream is an expression of a work of its own.
19. Every content stream has a `track` address that names the same stream after
    normalization reorders or re-encodes the container's streams.
20. Essence counts content streams only; a file with a lossy content stream is
    lossy; a file with no content streams is not applicable; a file with no
    streams takes its essence from its format; unknown and not applicable are
    recorded as such and never re-encoded.
21. Per-stream analysis runs over the stream's `track` address and
    whole-manifestation analysis over the manifestation; analysis reads the
    normalized master of the analysis source and records which asset it read.
22. The native and sidecar tools' measurements of one input both stand, each
    naming its own tool and version.
23. A tool response carrying a positional vector, or a schema version the
    deployment does not know, is refused.
24. A tool reporting a new version makes the inputs it analysed earlier due for
    re-analysis before any has been analysed at the new version.
25. A permanent failure is recorded and excluded from due work until a person
    clears it or the tool's version changes; a transient failure is retried a
    bounded number of times and its exhaustion is recorded.
26. Failures are recorded against the acquisition record for acquisition,
    identification and placement, against the digital item for normalization,
    and against the input, tool and version for analysis.
27. Emptying the job queue loses no work: the stages find everything unfinished
    from recorded state.
28. One asset per digital item, or per part, holds the Normalized role; changing
    a class's standard format recycles a previous copy, and takes the role from a
    previous master that is the Acquired asset without recycling it.
29. Resolving two scans as the same expression leaves one work, and recycles
    the work and expression the second scan was placed under where they are left
    holding nothing.
30. Every catalog write ingest makes is attributed to the System principal.
31. The sidecar holds no database credentials and cannot write to primary
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
