# Annotations and Derived Data

**Specification 02**
**Status:** Draft
**Version:** 0.1
**Depends on:** spec-01 (Catalog Data Model)
**Obsoletes:** nothing

## Abstract

spec-01 §8 supplies addresses — a way to name a region of a resource — and
deliberately says nothing about what may be attached to one. This document
supplies the other half: bodies, their provenance, and the rules governing what
happens when the code that produced them changes.

It covers both what a person asserts about a region and what code computes about
one, on the argument that these are the same structure with different provenance
and sharply different durability obligations.

---

## 1. Introduction

### 1.1 Scope

- The annotation structure: target, body, provenance
- The authored / derived distinction and what follows from it
- Derivation identity and version stamping
- Supersession
- Feature naming as a public interface
- Raw and normalized derived values
- Lifecycle: what happens to annotations when their target is purged

### 1.2 What this document does not specify

The extraction pipeline that produces derived annotations (spec-04). The
vocabularies of feature names and body types, which are seed data
(spec-01 §7.5). How annotations are searched or ranked (spec-09). Which
particular models or extractors are used.

### 1.3 Why one structure

Audio segments with feature vectors, video scene boundaries, document chunk
embeddings, OCR word positions, face tags, and reader highlights share a target
region, a body, and a provenance record. They differ only in the selector type
addressing them, which spec-01 §8.3 already types and §8.5 already constrains by
entity level.

They are therefore one structure.

**This is a logical claim, not a physical one.** Derived annotations over audio
segments will outnumber every other row class in the system by orders of
magnitude and carry vector indexes. Implementations MAY partition the store by
body type, and SHOULD expect to tune index parameters per partition rather than
globally. Conformance is behavioural (§8).

---

## 2. Conventions

BCP 14 key words per spec-01 §2. References of the form "spec-01 §x" refer to
the Catalog Data Model.

---

## 3. Structure

### 3.1 Annotation

An annotation has exactly three parts:

| Part | Is |
| --- | --- |
| Target | An address per spec-01 §8 — a res and a selector |
| Body | What is asserted or computed about that region |
| Provenance | Who or what produced it, and when |

An annotation is a res (spec-01 §3.1) and therefore carries a primary identifier
per spec-01 §4.1, is nameable, and is addressable.

An annotation MAY target a whole res rather than a region, by carrying no
selector. A track's loudness measurement and a photograph's face tag differ only
in whether the target is bounded.

### 3.2 Authored and derived

Every annotation MUST be exactly one of:

| | Authored | Derived |
| --- | --- | --- |
| Produced by | A principal, or an agent acting through one | Code |
| Provenance carries | An assigner (spec-01 §7.3) | A derivation (§4) |
| Regenerable | No | Yes, by construction |
| Backed up (spec-01 §13.7) | **MUST** | MUST NOT consume backup capacity |
| Superseded automatically | Never (§5.3) | By a newer derivation of the same tool |

This is the same seam as spec-01 §5.5's asset roles and §13.7's backup scope,
and for the same reason: a relative's identification of who appears in a
photograph is among the least replaceable data in the system, while a
machine transcript of the same recording can be recomputed on demand.

### 3.3 Authored annotations MUST NOT target a derived address

An authored annotation MUST target the resource directly, with its own selector.
It MUST NOT target an address that some derivation produced.

Without this rule, a preference recorded against a computed segment boundary
drifts silently onto the wrong content when re-analysis moves that boundary.

A person expressing a preference about a passage is asserting something about
*two minutes fourteen seconds into this recording*, which is stable, not about
*segment seven*, which is an artifact of one version of one segmenter. Recording
the timestamp makes the drift structurally impossible rather than requiring a
migration to repair it after the fact.

The association between an authored annotation and the derived regions covering
it is therefore a **query** — which segments under the current derivation
contain this instant — and not a stored reference. It is recomputed whenever the
derivation changes, at no cost.

Derived annotations MAY target derived addresses. A segment embedding legitimately
targets a segment boundary, because both are outputs of the same derivation and
are discarded together.

---

## 4. Derivation

### 4.1 Definition

A **derivation** is the identity of the code that produced a derived annotation.
Every derived annotation MUST carry exactly one.

**It names a tool, not an agent.** LRM-E6 defines an agent as capable of
deliberate action, of being granted rights, and of being held accountable, and
its scope note places automatons — naming software programs specifically —
outside that definition, as "tools used and set up by an actual agent." An
extractor or a model is such a tool. `agent` therefore MUST NOT name a deriving
component; it is reserved for its LRM sense throughout.

Strictly, every derivation also has an agent behind it: whoever configured and
ran the tool. Recording that is OPTIONAL — for a household running its own
pipeline it is always the same answer — but where a derivation's provenance is
disputed, the agent is the accountable party and the tool is not.

A derivation MUST record:

| Field | Purpose |
| --- | --- |
| `tool` | Which deriving component — a named extractor, model, or analyser |
| `version` | Its numerical identity, per §4.2 |
| `parameters` | The settings materially affecting output |
| `derived_at` | [RFC3339] UTC |

### 4.2 One mechanism, not two

Engineered feature extraction and neural embedding change independently: a
library upgrade shifts computed scalars without touching a model, and a model
swap changes embeddings without touching the extractor. This invites two
separate version stamps, one per kind of change.

They are one mechanism. An extractor and a model are both deriving tools, and
each derived annotation names the one tool that produced it. An annotation
holding an embedding names the model; one holding a spectral scalar names the
extractor. Nothing needs to carry both, and no annotation is stamped with a
version irrelevant to it.

`version` MUST be sufficient to distinguish any two builds that could produce
different numbers for the same input — library versions and the deriving code's
own build, not a semantic version chosen by hand.

The obligation this discharges: *re-derive everything produced before version X*
must be a query, not archaeology.

### 4.3 Determinism is not assumed

Two derivations of the same tool at the same version over the same input SHOULD
produce the same body, but implementations MUST NOT depend on it. Hardware
differences, non-deterministic kernels, and floating-point ordering all break
exact reproduction. Where reproduction matters, compare against the stored body
rather than recomputing and assuming equality.

---

## 5. Supersession

### 5.1 Confidence does not decide

A newer body MUST NOT supersede an older one on the basis of a confidence score
comparison. Confidence scores are not comparable across tools, are frequently
not comparable across versions of one tool, and are in general not calibrated.

### 5.2 Derivation identity decides

| Relationship | Outcome |
| --- | --- |
| Same tool, newer version | The newer supersedes the older |
| Same tool, same version | The later replaces the earlier; this is a re-run |
| Different tools | Neither supersedes. Both stand. |
| Derived vs. authored | Never. See §5.3. |

Where two tools both produce a body of the same kind — two OCR engines over one
scan — both annotations persist and selection among them is a query concern,
specified in spec-09. Discarding one at write time destroys information that
cannot be recovered without re-running the discarded tool.

An implementation MUST retain the ability to identify superseded annotations
rather than deleting them silently, and MAY delete them once the superseding
derivation is verified, since derived data is regenerable by construction.

### 5.3 Authored is never superseded

A derived annotation MUST NOT supersede an authored one, under any confidence,
version, or tool. This is spec-01 §7.5's rule — that a user correction survives
subsequent automatic matching — applied to bodies rather than to names.

### 5.4 Diff is review, not mechanism

Comparing an old and a new transcript is a good way for a person to judge whether
a re-derivation improved anything, and implementations SHOULD offer it.

It is not the supersession mechanism. Diff is only meaningful for text, and would
leave every non-diffable body — a loudness scalar, a bounding box, a 512-dimension
embedding — without a rule. Making derivation identity the mechanism covers every
body type uniformly and leaves diff as what it is: a presentation aid for
reviewing a change a person is about to accept.

---

## 6. Feature naming

### 6.1 Names are the interface

Where a derived body is a set of measurements, those measurements MUST be
addressed by name. A positional vector MUST NOT be the interchange
representation.

An ordering invariant maintained in several places, especially across a process
or language boundary, drifts silently: old rows misalign rather than failing.
Named values fail detectably — a missing key is visible — and a new measurement
is an additive change rather than a coordinated release.

### 6.2 Scalars and arrays

A measurement is either a scalar or an array of fixed length. An array element
is addressed as the array's name plus its index. Names MUST NOT encode the index
in the name itself, because that makes the array's length part of its
vocabulary and turns a length change into a vocabulary change.

### 6.3 Assembly into vectors is local

Where measurements are assembled into a vector for distance computation, the
canonical ordering, the normalization ranges, and any per-dimension weighting
are the concern of the assembling component alone. They MUST be defined in one
place, and MUST NOT be part of the annotation body or of any producer's
contract.

### 6.4 Feature groups are data

Semantic groupings of measurements — for weighting, for display, for
per-application emphasis — are seed data (spec-01 §7.5), not code and not part
of this specification. Adding a group is a seed change.

---

## 7. Raw and normalized values

A derived body MUST store the values as the deriving tool produced them.

Normalized, scaled, or weighted forms are derived from those values. An
implementation MAY materialize a normalized form for indexing, but it MUST be
recomputable from the stored raw body without re-reading the underlying media.

The property being protected: normalization ranges and weights change often, and
re-deriving them must never require re-reading a library. This is the
difference between a query and a full re-analysis.

Non-finite values MUST be rejected or scrubbed before persistence where the
storage layer cannot represent them.

---

## 8. Lifecycle

### 8.1 When a target is purged

spec-01 §14.1 left the fate of annotations whose target has been purged open.
The two classes diverge:

**Derived annotations MUST be purged with their target.** They are regenerable
from a resource that no longer exists, which makes them neither regenerable nor
meaningful.

**Authored annotations MUST be retained.** They are not regenerable, spec-01
§13.7 requires them to be backed up, and the assertion a person made retains
value independent of whether the household still holds the thing it was about.
An authored annotation whose target is purged is an orphan by design.

Implementations MUST be able to present an orphaned authored annotation —
including what it targeted, by identifier — and MUST NOT treat the dangling
target as an integrity error.

### 8.2 When a derivation is superseded

Superseding does not purge. See §5.2.

---

## 9. Conformance

1. An annotation carries exactly one of an assigner or a derivation, never both
   and never neither.
2. An authored annotation targeting a derived address is rejected.
3. Re-running a segmenting derivation at a new version does not change which
   region any authored annotation refers to.
4. A derived annotation carries a version sufficient to distinguish builds;
   "all annotations produced before version X" is answerable as a query.
5. An embedding annotation names the model that produced it and is not stamped
   with an unrelated extractor version.
6. A newer body from a different tool does not supersede an older body, whatever
   their confidence scores.
7. A derived annotation never supersedes an authored one.
8. A body's stored values are those the tool produced; changing normalization
   ranges or weights requires no access to the underlying media.
9. Purging a target purges its derived annotations and retains its authored ones.
10. An orphaned authored annotation renders, names its purged target, and does
    not raise an integrity error.

---

## 10. Security considerations

Authored annotations are personal in the sense of spec-01 §11.2: a face tag or a
highlight reveals what a principal was doing and what they think. Implementations
SHOULD treat authored annotation visibility as a household-scoping question and
resolve it deliberately, noting that spec-01 §7.3 already makes household naming
shared by construction while §11.2 makes consumption events private. Annotations
sit between those two rules and are not settled by either.

**OPEN:** whether authored annotations are household-visible like nomens or
principal-scoped like events. The face-tag case argues for shared; the reading
highlight argues for private. It may depend on body type, which would make it a
property of the body type registry rather than a single rule.

---

## 11. References

### 11.1 Normative

- **[spec-01]** *Catalog Data Model*, this system.
- **[RFC2119]**, **[RFC8174]**, **[RFC3339]** as in spec-01 §18.1.

### 11.2 Informative

- **[W3C-ANNO]** W3C, *Web Annotation Data Model*. Its body-and-target shape is
  the direct ancestor of §3.1. Its `motivation` vocabulary is a candidate for the
  body type registry; its identity and provenance model is not adopted.
