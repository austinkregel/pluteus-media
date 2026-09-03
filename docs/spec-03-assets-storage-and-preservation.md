# Assets, Storage and Preservation

**Specification 03**
**Status:** Draft
**Version:** 0.1
**Depends on:** spec-01 (Catalog Data Model), spec-02 (Annotations and Derived Data)
**Obsoletes:** nothing

## Abstract

spec-01 §5.5 defines an asset and §13 states the household's integrity
obligations. This document specifies how those obligations are met: what
normalization may and may not do, how integrity is verified and reported, how
format risk is identified, what is backed up, and how duplicates are found and
resolved.

Its governing principle, from spec-01 §13.4: **recovery cannot be guaranteed;
detection can.** Everything here is built to turn silent loss into a known fact.

---

## 1. Introduction

### 1.1 Scope

- Normalization: what it may change and what it must preserve
- Asset roles and the original/copy relationship
- Integrity verification, scheduling, and reporting
- Format risk identification
- Backup scope
- Deduplication

### 1.2 What this document does not specify

Where bytes physically live and how the ingest pipeline drives normalization
(spec-04). Playback-time transcode negotiation (spec-08). The asset role
vocabulary, which is seed data (spec-01 §7.5, §17).

---

## 2. Conventions

BCP 14 key words per spec-01 §2.

---

## 3. Assets and roles

### 3.1 Structure

spec-01 §5.5 is normative: an asset records one stored byte sequence realizing
one digital item at one location; a digital item may have zero or more assets;
every asset carries a role in one of four classes — acquired, normalized,
redundant, derived.

A copy is an asset. There is no separate copy entity.

### 3.2 What an asset MUST record

| Field | Purpose |
| --- | --- |
| `digital_item` | The holding it realizes (exactly one) |
| `role` | Seed value within one of the four classes |
| `location` | Where the bytes are, as a storage-layer reference |
| `size` | Octets |
| `digest` | Cryptographic content digest, per §5.1 |
| `format` | Identified format, per §6 |
| `part_sequence` | Nullable; only for multi-part digital items (spec-01 §12.1) |
| `verified_at` | Last successful verification, nullable |
| `verification_interval` | How often this asset must be verified |

### 3.3 Original and derived-copy coupling

spec-01 §13.2 couples them: deleting the original SHOULD delete the derived
playback copy, because the copy is then unsupported by anything the household
can prove it held.

This coupling runs one way only. Deleting a normalized copy MUST NOT delete the
acquired original, and MUST be permitted — a normalized copy is regenerable from
the original by definition.

---

## 4. Normalization

### 4.1 What it is for

Normalization produces a standardized copy so that playback does not depend on
the format the household happened to acquire, and so that one standard path
serves many acquisition formats.

### 4.2 The essence rule

spec-01 §13.3 is normative and absolute: **normalization changes the container,
not the essence.** Re-encoding lossy essence during normalization MUST be
rejected.

Where only a lossy record exists, that lossy record is the normalized master.
There is no quality to recover and re-encoding only compounds generation loss.

The excluded case worth naming, because it looks like an improvement: converting
JPEG to PNG loses no visual information, since PNG stores decoded pixels exactly,
but it destroys the ability to reproduce the original file and typically triples
to decuples the size. [JPEG-XL] lossless recompression achieves the actual
intent — bit-exact reversible to the original JPEG, roughly 20% smaller.

### 4.3 Reversibility verification

Reversibility verification applies in exactly one circumstance.

Where a normalization claims to be reversible to its input, and the household
intends to **discard the acquired original** in favour of the recompressed form,
the implementation MUST verify reversibility by reconstructing the original and
comparing its digest before the original is deleted. Deletion MUST NOT proceed
on the codec's claim alone.

Where the original is retained — the default under spec-01 §13.2 — reversibility
verification is unnecessary. The original is right there; a claim about
reconstructing it changes nothing.

The rule therefore reduces to: *verify reversibility if and only if you are
about to rely on it.*

### 4.4 Format selection

spec-01 §13.6 makes transcoding on-demand and forbids pre-generation, which puts
sustained real-time transcoding on the critical path for playback. The
standardized format SHOULD therefore be chosen for direct-play compatibility
with the clients the household actually uses, not solely for archival
properties. An archival format that every client must transcode away from
converts a storage decision into a per-session CPU cost.

---

## 5. Integrity

### 5.1 Digests

Every asset MUST carry a cryptographic content digest, recorded at the time the
bytes were written or first read.

The digest algorithm MUST be recorded alongside the value, so that an algorithm
change is a migration rather than an ambiguity.

### 5.2 Verification is scheduled, not incidental

Verification MUST be a scheduled operation with recorded outcomes. It MUST NOT
be an operator convention, a manual action, or a side effect of playback.

Each verification attempt MUST record its outcome — verified, mismatched, or
unreadable — with a timestamp, whether it succeeded or not. A verification pass
that fails to run is itself a finding, and is invisible if only successes are
recorded.

### 5.3 Unverified is a reportable state

**An asset whose last successful verification is older than its verification
interval MUST be reported as unverified.** This is spec-01's conformance
criterion 24 and the single most load-bearing requirement in this document.

Unverified is distinct from corrupt. It means the household does not currently
know, which is the state that silently becomes data loss.

An asset that has never been verified MUST be reported as unverified.

### 5.4 What detection does not do

Detection does not repair. On a digest mismatch the implementation MUST record
the finding and surface it; it MUST NOT overwrite, re-derive, or silently
replace the asset. Recovery is a decision made against the backup copy
(spec-01 §13.5) with a person in the loop.

Parity recovery sets remain OPTIONAL and secondary, per spec-01 §13.4. An N%
recovery set recovers up to N% damage and covers neither whole-file loss, nor
drive failure, nor deletion.

### 5.5 Interaction with the storage layer

spec-01 §13.5 notes that conventional RAID has no block checksums, so silent
corruption is neither detected nor repaired and may be propagated into a rebuild.
Application-level verification is what covers that gap.

Where a checksumming filesystem is in use, application-level verification is
redundant at that tier but MUST still be performed on copies that leave it —
notably the backup copy, whose whole purpose is to survive events that take the
primary tier with them.

---

## 6. Format risk

An intact file in a format nothing can decode is lost as thoroughly as a
corrupt one. Format risk is a separate concern from bit-level integrity and MUST
be tracked separately.

Every asset MUST carry an identified format, determined by inspecting the bytes
rather than by trusting a filename extension.

Identification SHOULD resolve to a registry entry rather than a local string, so
that risk assessments published against the registry apply. [PRONOM] is the
established registry; DROID and Siegfried are the identification tools against
it.

Implementations SHOULD be able to report holdings by format, so that "what do we
hold in formats losing decoder support" is answerable.

> **Availability.** No Elixir package performs PRONOM-based identification.
> Siegfried offers a server mode, making this an out-of-process call rather than
> a library dependency. No in-process path exists.

---

## 7. Backup scope

spec-01 §13.7 divides holdings by regenerability, and the division is normative.

**MUST be backed up** — not regenerable from anything the household retains:

- Acquired originals
- Normalized masters and standardized copies
- Authored annotations (spec-02 §3.2)
- Consumption events (spec-01 §11)
- The catalog itself — every entity, relationship, and nomen

**MUST NOT consume backup capacity** — regenerable from a master and a recipe:

- Derived assets: thumbnails, waveform data, sprite sheets, parsed and cropped
  derivatives, retained transcodes (spec-01 §13.6)
- Derived annotations (spec-02 §3.2): machine transcripts, feature values,
  embeddings, computed region boundaries

The catalog belongs in the first list and is easy to omit, because it is not a
media file. It is also the only thing that makes the media files intelligible:
restoring bytes without the catalog restores a directory of unnamed files.

---

## 8. Deduplication

### 8.1 Explicit, never implicit

Deduplication MUST be explicit. Identity MUST NOT be derived from content
addressing.

The reason is structural. spec-01 §4.1 requires identifiers to be immutable and
to encode no semantic content, and §5.2 anticipates that a digital item may be
altered after acquisition by added rights statements, annotations, or degradation
of the octet stream. A content-addressed identifier changes when any of those
happen, which is precisely the case the model was built to accommodate.

### 8.2 Three signals, three meanings

| Signal | Detects | Means |
| --- | --- | --- |
| Identical digest (§5.1) | Byte-identical assets | Possibly nothing — see below |
| Perceptual hash | Same content, different bytes | A candidate, never a fact |
| Shared external identifier (spec-01 §4.3) | Same catalogued thing | A candidate; §4.3 explicitly tolerates duplicates |

**Byte identity is not duplication.** The original and the backup copy of one
digital item are byte-identical by design. Two assets sharing a digest are
duplicates only where they realize different digital items, and even then the
household may have deliberate reasons for both.

### 8.3 Resolution is a decision, not a rule

Deduplication MUST produce candidate pairs for a person to resolve. It MUST NOT
merge, delete, or re-point references automatically.

This follows spec-01 §7.5's pattern, where an automatic match and a human
correction are separate rows and the correction wins by preference rather than by
overwriting. A resolved duplicate decision MUST NOT be overturned by a later
automatic detection run.

Where the household confirms two digital items are the same holding, the
resolution is a catalog operation — merging holdings under one manifestation —
and not the deletion of an asset. Assets are deleted only by the rules in §3.3.

### 8.4 Across media types

The same three signals apply to documents, photographs, and video. Perceptual
hashing is the visual analogue of an audio fingerprint, and near-duplicate
detection over artwork, video frames, and scanned pages is the same operation
with a different hash function. Implementations SHOULD share the mechanism rather
than building one per media type.

---

## 9. Conformance

1. An asset references exactly one digital item and carries a role in one of the
   four classes.
2. An asset whose last successful verification exceeds its interval is reported
   as unverified.
3. An asset that has never been verified is reported as unverified.
4. A verification pass that fails to run is distinguishable from one that ran and
   found nothing wrong.
5. A digest mismatch is recorded and surfaced, and does not overwrite or
   re-derive the asset.
6. Normalization that re-encodes lossy essence is rejected.
7. Discarding an acquired original in favour of a reversibly recompressed form is
   rejected unless reconstruction has been verified against the original's digest.
8. Deleting a normalized copy is permitted and leaves the acquired original
   intact; deleting the original removes the derived playback copy.
9. Every asset carries a format identified from its bytes, not its filename.
10. Derived assets and derived annotations are excluded from backup; the catalog
    is included.
11. Two byte-identical assets of one digital item are not reported as duplicates.
12. Deduplication produces candidates and never merges automatically; a resolved
    decision survives a subsequent detection run.

---

## 10. Security considerations

Location references disclose storage topology. They are not secrets in the sense
of spec-01 §16, but they are operational detail and SHOULD NOT be exposed on
surfaces reachable outside the household network.

The backup copy is the control against ransomware and deletion (spec-01 §13.5).
That control is only real if the backup is not writable by the same credentials
that reach primary storage; an application that can silently rewrite its own
backups has a copy, not a backup.

---

## 11. References

### 11.1 Normative

- **[spec-01]** *Catalog Data Model*, this system.
- **[spec-02]** *Annotations and Derived Data*, this system.
- **[RFC2119]**, **[RFC8174]**, **[RFC3339]** as in spec-01 §18.1.

### 11.2 Informative

- **[PRONOM]** The National Archives (UK) format registry.
- **[JPEG-XL]** ISO/IEC 18181.
- **[PREMIS]** Library of Congress, *PREMIS Data Dictionary for Preservation
  Metadata*. Its event and agent model informed §5.2's insistence on recorded
  outcomes; not adopted.
- **[OAIS]** ISO 14721.
