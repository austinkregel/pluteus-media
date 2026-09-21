# Assets, Storage and Preservation

**Specification 03**
**Status:** Draft
**Version:** 0.2
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
| `roles` | One or more seed values, within the four classes (spec-01 §5.5) |
| `location` | Where the bytes are, as a storage-layer reference |
| name | A nomen (spec-01 §7), which spec-01 §6.1 requires of every asset. For an acquired asset it is the name the bytes arrived under — evidence of provenance that `location` does not preserve, since normalization files the bytes anew |
| `size` | Octets |
| `digest` | Cryptographic content digest, per §5.1 |
| `digest_algorithm` | The algorithm producing `digest`, per §5.1 |
| `format` | Identified format, per §6 |
| `essence` | Lossy, lossless, unknown, or not applicable, per [spec-04] §5.2. Only lossless is ever re-encoded |
| `part_sequence` | Nullable; only for multi-part digital items (spec-01 §12.1) |
| `verified_at` | Last successful verification, nullable |
| `verification_interval` | How often this asset must be verified |

`size`, `digest`, `digest_algorithm` and `format` are read from the bytes when the
asset is recorded and MUST NOT be accepted from the caller. A digest supplied
alongside the bytes is a claim about them; the record is of what was read.

### 3.3 Original and normalized-copy coupling

spec-01 §13.2 couples them: deleting the acquired original MUST delete the
normalized copy, because the copy is then unsupported by anything the household
can prove it held. The one exception is §4.3's discard, where the original was
deliberately replaced by a recompression verified against it; there the
recompression assumes the Acquired role and nothing remains to couple to.

This coupling runs one way only. Deleting a normalized copy MUST NOT delete the
acquired original, and MUST be permitted — a normalized copy is regenerable from
the original by definition.

Where a digital item is realized by parts (spec-01 §5.5), coupling is per part:
an acquired part supports only the normalized copy of the same part.

Where normalization was the identity, one asset carries both roles (spec-01 §5.5)
and there is nothing to couple: the two rules describe the same row.

---

## 4. Normalization

### 4.1 What it is for

Normalization produces the standardized master so that analysis, playback and
preservation do not each depend on the format the household happened to acquire,
and so that one standard path serves many acquisition formats. The standard
format for each media class is a registry (spec-01 §17).

### 4.2 The fidelity rule

spec-01 §13.3 is normative: **normalization MUST NOT reduce fidelity.** Within
that bound it MAY re-encode, so converting a camera raw capture or a lossless
recording in one codec into the standard codec for its media class is
normalization and is accepted.

Re-encoding lossy essence MUST be rejected. Where only a lossy record exists,
that lossy record is already the normalized master, and the same asset carries
both roles. There is no quality to recover and re-encoding only compounds
generation loss.

A lossy rendition made for a client to play is not normalization at all. It is a
transcode under spec-01 §13.6: produced on demand, retained only as a Derived
asset, never backed up.

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
sustained real-time transcoding on the critical path for playback.

The standardized format is nonetheless chosen for fidelity and longevity, not for
direct-play compatibility. Serving transcodes routinely as a result, and the cost
is accepted at one household's concurrency: the storage decision outlives every
client that exists today, and choosing it to suit them trades a permanent
property for a temporary convenience.

What follows is a capacity obligation rather than a format one. Implementations
SHOULD be able to serve the household's realistic concurrency, and the registry
SHOULD NOT adopt a standard format whose decode alone cannot keep pace with
real-time playback on the deployment's hardware.

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
rather than by trusting a filename extension. A match on the extension alone is
not an identification: such a file, and one no signature recognizes, is recorded
as `UNKNOWN`, which keeps it visible in a report of holdings by format rather
than filed under a format its bytes were never shown to have.

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

A candidate is raised by one of §8.2's signals, by matching ([spec-05] §8.5), or
by a member, who MAY propose a pair no signal found — two scans of one letter
differ in every byte.

A decision names the level at which the two are one:

| Decision | Means | Resolution |
| --- | --- | --- |
| *same holding* | one digital item | merge the holdings under one manifestation |
| *same manifestation* | one manifestation | move the digital items under one manifestation |
| *same expression* | one expression | move the manifestations under one expression |
| *same work* | one work | move the expressions under one work |
| *distinct* | not the same | recorded, and not asked again |

The vocabulary names a level because the decision is only ever about one. Two
scans of a letter are the same expression and remain two manifestations; two
pressings of a record are the same expression and two releases; two files of one
encode are the same holding. Collapsing these into a single "duplicate" decision
would force an implementation to guess which level a person meant, and a wrong
guess destroys a relation rather than a value.

Whichever level is chosen, the resolution moves children under the surviving res
and recycles whichever of the emptied res are left holding nothing. It MUST NOT
purge, and it MUST NOT delete an asset; assets are deleted only by the rules in
§3.3. Because the emptied res are recycled, spec-01 §14.1's window makes the
decision reversible for thirty days.

This follows spec-01 §7.5's pattern, where an automatic match and a human
correction are separate rows and the correction wins by preference rather than by
overwriting. A resolved duplicate decision MUST NOT be overturned by a later
automatic detection run.

Where the household decides two holdings are manifestations of one expression —
a second scan of a letter already catalogued — the resolution moves the second's
manifestation under the first's expression, and recycles whichever of the work
and expression the second was placed under are left holding nothing. That is the
*same expression* row above, worked through; every other row behaves the same way
at its own level.

### 8.4 Across media types

The same three signals apply to documents, photographs, and video. Perceptual
hashing is the visual analogue of an audio fingerprint, and near-duplicate
detection over artwork, video frames, and scanned pages is the same operation
with a different hash function. Implementations SHOULD share the mechanism rather
than building one per media type.

---

## 9. Conformance

1. An asset references exactly one digital item and carries at least one role
   within the four classes; an asset carrying both Acquired and Normalized is
   accepted.
2. An asset whose last successful verification exceeds its interval is reported
   as unverified.
3. An asset that has never been verified is reported as unverified.
4. A verification pass that fails to run is distinguishable from one that ran and
   found nothing wrong.
5. A digest mismatch is recorded and surfaced, and does not overwrite or
   re-derive the asset.
6. Normalization that re-encodes lossy essence is rejected; normalization that
   re-encodes lossless essence into the standard codec is accepted.
7. Discarding an acquired original in favour of a reversibly recompressed form is
   rejected unless reconstruction has been verified against the original's digest.
8. Deleting a normalized copy is permitted and leaves the acquired original
   intact; deleting the original removes the normalized copy, except after a §4.3
   discard.
9. Every asset carries a format identified from its bytes, not its filename.
10. Derived assets and derived annotations are excluded from backup; the catalog
    is included.
11. Two byte-identical assets of one digital item are not reported as duplicates.
12. Deduplication produces candidates and never merges automatically; a resolved
    decision survives a subsequent detection run.
13. A decision names one of *same holding*, *same manifestation*, *same
    expression*, *same work* or *distinct*, and resolving it moves children under
    the surviving res, recycles only what is left holding nothing, purges
    nothing, and deletes no asset.
14. A pair decided *distinct* is not raised again, by a detection run or by
    matching.

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

- **[spec-05]** *Metadata Acquisition and Matching*, this system. §8.4 equates
  res through §8.3's vocabulary and raises §8.5's candidates into it.
- **[PRONOM]** The National Archives (UK) format registry.
- **[JPEG-XL]** ISO/IEC 18181.
- **[PREMIS]** Library of Congress, *PREMIS Data Dictionary for Preservation
  Metadata*. Its event and agent model informed §5.2's insistence on recorded
  outcomes; not adopted.
- **[OAIS]** ISO 14721.
