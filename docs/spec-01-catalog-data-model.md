# Catalog Data Model

**Specification 01**
**Status:** Draft
**Version:** 0.1
**Depends on:** nothing
**Obsoletes:** nothing

## Abstract

This document specifies the identity and relation model for a household media
system: the entities, identifiers, relationships, naming, addressing, and
lifecycle semantics that all other components build against. It adopts IFLA LRM
(2024-07) as its base model and records every extension, addition, and
implementation choice made on top of it.

This is the only specification in the system with no upstream dependency. It is
intended to be frozen early so that storage, ingest, playback, and client work
can proceed independently.

---

## 1. Introduction

### 1.1 Scope

The system serves one household from one deployment. Content is limited to what
the household holds; DRM-protected streaming content is out of scope, and with
it availability resolution, deep-linking into third-party applications, and
integration with streaming services.

Media in scope is anything a household might consume, back up, keep records of,
or synthesize into another format.

All content is assumed lawfully obtained. Rights and licensing are not modelled.

### 1.2 What this document specifies

- Identifier format and minting
- Entity structure, adopted from IFLA LRM with one extension
- Binding relationship cardinalities
- Naming, and resolution of names to a preferred form
- Addressing regions within a resource
- URI construction for deep links
- Principals and households
- Events
- Assets, their relation to digital items, copies, and integrity obligations
- Deletion lifecycle and its HTTP semantics

### 1.3 What this document does not specify

Wire protocol and authentication handshake; the ingest and normalization
pipeline; storage placement and scrub scheduling; metadata acquisition and
matching; playback session management and transcode negotiation; search,
ranking, and recommendation; presentation.

Controlled vocabularies are explicitly **not** specified here. See §7.5.

### 1.4 Implementation context

The reference implementation is Elixir: Phoenix PubSub for cross-device
notification, LiveView for the user-facing layer, Membrane for media plumbing,
PostgreSQL for storage. This specification is implementation-agnostic; the
context is given because §14 and §15 make assumptions about transactional
integrity and deferred constraint checking that a non-relational store would
have to satisfy some other way.

---

## 2. Conventions

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD",
"SHOULD NOT", "RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be
interpreted as described in BCP 14 [RFC2119] [RFC8174] when, and only when, they
appear in all capitals.

References of the form "LRM §x.y" or "LRM-Rn" refer to [IFLA-LRM].

Field names are given in `snake_case`. Timestamps are [RFC3339] in UTC.
Durations and intervals are ISO 8601.

Sections marked **OPEN** record decisions that have not been made. An
implementation MUST NOT treat an OPEN item as license to choose arbitrarily and
proceed; these are flagged for resolution before the affected component is
built.

---

## 3. Model overview

### 3.1 Base model

This system adopts IFLA LRM (2024-07) [IFLA-LRM] as its base model.

LRM declares eleven entities under a single top-level entity `res`. Work,
expression, manifestation, and item are four of the eight direct subclasses of
`res`; the others are agent, nomen, place, and time-span, with person and
collective agent below agent.

No LRM entity is omitted. LRM §2.2 permits omission, but this system keeps place
and time-span as entities rather than collapsing them to literals, on the
principle that information should not be discarded.

### 3.2 Layers

Three concerns share the model and MUST NOT be conflated:

| Layer | Governs | Source |
| --- | --- | --- |
| Catalog | What exists, how it relates, what it is called | LRM |
| Preservation | Custody, integrity, format risk | §13, outside LRM |
| Consumption | What a person did, and what they see | §11, §8, outside LRM |

LRM §2.1 places administrative metadata outside its scope. The preservation and
consumption layers are therefore specified here rather than derived.

### 3.3 Variable depth

Depth follows the information actually present. Fixed depth is not required and
MUST NOT be assumed.

Fewer levels: LRM §2.2 permits an implementation to omit a declared entity for a
given instance. A photograph with one capture and one file does not require four
distinct populated levels.

More depth: LRM §4.2.3 permits the `category` attribute, declared on `res`, to be
sub-typed for any entity, and states that types so defined MAY function as
subclasses. This is the sanctioned extension mechanism. Several independent
categorization schemes MAY apply to one entity simultaneously.

Note the boundary: category *values* are data (§7.5). Promoting a category to a
subtype table is a schema change and therefore a release.

---

## 4. Identifiers

### 4.1 Format

Every entity MUST have a primary identifier that is a UUID version 7 [RFC9562].

Identifiers MUST be immutable. Identifiers MUST NOT be reused after deletion.
Identifiers MUST NOT encode semantic content.

The primary identifier is itself a nomen (§7.1), of the scheme reserved for it,
and satisfies LRM-R13's lower bound for every res without a stored appellation
row. LRM-R13's scope note provides for this directly: where instances are
assigned an internal identifier, which is itself a nomen of a specific type, the
relationship is implicit in the system design. Implementations MUST NOT require
a stored nomen for a res that has no name, and MUST NOT mint a placeholder one.

This is what keeps §7's obligations proportionate. Assets, reified addresses and
annotations are res (§5.5, §8.2, [spec-02] §3.1) and vastly outnumber the
entities a person names; requiring an appellation row for each would double the
largest tables in the system to store nothing.

### 4.2 Seeded identifiers

Entities delivered as seed data (§7.5) MUST carry UUIDv7 values minted when the
seed is authored and committed to the release, not generated at install time.

A seed loader MUST insert the identifiers it is given and MUST NOT generate
identifiers for seeded rows.

This is what allows two deployments to converge on the same row for the same
concept during an upgrade. It is a property of the loader, not a second
identifier scheme.

### 4.3 External identifiers

An entity MAY carry zero or more external identifiers. External identifiers are
advisory. The catalog MUST tolerate their absence, their duplication across
entities, and their later revision.

Under LRM, an external identifier is a nomen (LRM §4.1.3 gives ISBN and ISNI as
examples). Implementations MUST model them as such rather than as a separate
field type. See §7.

### 4.4 Identifiers as public addresses

Primary identifiers are also permanent public addresses (§9). This is a stronger
stability commitment than an internal primary key normally carries.

The identifier is not a secret. UUIDv7 embeds a timestamp and is not random;
adjacent identifiers are somewhat predictable. Access control is a separate
layer and MUST NOT depend on identifier entropy.

---

## 5. Entities

### 5.1 Adopted from LRM

The eleven LRM entities are adopted as defined in LRM §4.1.3. This document does
not restate their definitions; LRM is normative for them.

### 5.2 Digital item

This system defines a `digital item` entity between manifestation and item, as
anticipated by LRM §5.3.

`item` is entirely physical. `digital item` is a file or package of files
carrying the content of a manifestation, which MAY be altered after acquisition
by added rights statements, annotations, or degradations of the octet stream.

Substantially all holdings in this system are digital items.

A digital item MUST carry exactly one manifestation. A manifestation MAY be
carried by zero or more digital items; zero denotes a manifestation the
household describes but holds no file for, and implementations MUST represent it
rather than reject it.

No relationship exists between digital item and item. Where a digital item has a
physical carrier, that carrier is recorded as an asset location (§5.5) and not as
an exemplar.

LRM-R4's lower bound is therefore not enforced. LRM §2.2 permits an
implementation to omit item-level structure for a given instance, and a
manifestation embodied only in digital items has no physical exemplar to record.

Implementations MUST NOT treat each acquired file as a distinct singleton
manifestation. LRM §5.3 states directly that doing so is impractical and does
not meet user needs.

### 5.3 Aggregates

An aggregate is a manifestation embodying multiple expressions (LRM §5.7). Three
types are recognized by LRM: collections, augmentations, and parallel
expressions.

A multi-track container — a file offering a choice of spoken languages and
subtitle tracks — is an **aggregate of parallel expressions**. LRM §5.7 gives
this exact case. It is expressible because LRM-R3 is many-to-many.

Implementations MUST NOT demultiplex a multi-track container at ingest for the
purpose of separating expressions. Track selection (§8.6) operates over tracks
present in the container.

An aggregating work MAY be described for any aggregate, and MAY be described
later if not identified initially (LRM §5.7).

**Constraint:** whole-part MUST NOT be used between an aggregating work and the
works it aggregates. LRM §5.7 states the aggregating work holds only the
selection and arrangement criteria and does not contain the aggregated works.
Aggregation occurs at expression level via LRM-R25.

### 5.4 Serials

A serial work is a specific kind of aggregating work (LRM §5.8).

The complete serial manifestation has a whole-part relationship to its issues
(LRM-R26, manifestation level). The serial work MUST NOT have a whole-part
relationship to its issues at work level; they connect via LRM-R21, the
inspiration relationship.

For episodic media, season and episode structure therefore lives at
manifestation level.

Regional editions of a serial are distinct serial works, not expressions of one
work (LRM §5.8).

[PRESSOO] is named by LRM §5.8 for implementations requiring more depth on
serials than LRM provides. It is not adopted here.

### 5.5 Asset

A digital item (§5.2) states what the household holds. An **asset** is a record
of one stored byte sequence realizing a digital item at one location.

The two are separated on the layer boundary of §3.2. A digital item is a catalog
fact: it survives the loss of every stored copy, and a household that has lost a
file still holds the knowledge that it had it. An asset is a custody fact,
meaningful only while bytes exist somewhere. Conflating them makes deletion of a
file indistinguishable from deletion of a holding.

An asset MUST realize exactly one digital item. A digital item MAY have zero or
more assets; zero denotes a holding whose copies are all lost, which
implementations MUST represent rather than reject.

`asset` is a subclass of `res` and is therefore identified per §4 and nameable
per §7. It is disjoint from work, expression, manifestation, item, and digital
item: no instance is simultaneously an asset and any of those. LRM §5.2 requires
disjointness of every entity not related by an isA hierarchy, and this extension
respects it.

Every asset MUST carry at least one role. Roles are seed data (§7.5, §17). At
minimum the registry distinguishes:

| Role class | Backed up (§13.7) | Examples |
| --- | --- | --- |
| Acquired | Yes | the original as received (§13.2) |
| Normalized | Yes | the standardized master (§13.3) |
| Redundant | — | the backup copy (§13.5) |
| Derived | No | thumbnail, waveform, sprite sheet, machine transcript, retained transcode (§13.6) |

An asset MAY carry more than one role where they coincide on one byte sequence.
A file acquired already in the standard format is both Acquired and Normalized,
and normalization writes no second copy; so is a lossy record, which §13.3 makes
its own normalized master. Implementations MUST NOT duplicate bytes to give each
role an asset of its own.

A playback rendition is not a role class. It is a transcode produced on demand
(§13.6), retained only as a Derived asset if at all.

**Derived assets MUST NOT be modelled as digital items.** A thumbnail carries no
manifestation content of its own; it is a regenerable projection of one. This is
the same prohibition as §5.2's against treating every acquired file as a
singleton manifestation, applied downstream of acquisition. Without it a library
acquires one manifestation per generated artifact.

Where a digital item is a package of files rather than a single file (§5.2), it
is realized by one asset per stored file, and those assets carry a part sequence
(§12.1).

A copy is an asset bearing a role. It is neither a distinct entity type nor a
set of fields on some other entity, and the acquired original and the
standardized master are two assets of one digital item where they differ, and
one asset bearing both roles where they do not.

---

## 6. Relationships

### 6.1 Binding cardinalities

LRM §2.2 requires that the entity structure, the relationships among entities
including cardinality constraints, and the correct attachment of implemented
attributes be respected for an implementation to be considered faithful.

The following are REQUIRED:

| Relationship | Cardinality |
| --- | --- |
| LRM-R2 Work is realized through Expression | 1 to M |
| LRM-R3 Expression is embodied in Manifestation | M to M |
| LRM-R4 Manifestation is exemplified by Item | 1 to M |
| LRM-R13 Res has appellation Nomen | 1 to M |
| LRM-R17 Nomen is derivation of Nomen | M to 1 |
| Manifestation is carried by Digital item (§5.2) | 1 to M |

The final row is this system's extension and carries no LRM relationship number.
Neither its lower bound nor LRM-R4's is enforced: a manifestation may be
described with no physical exemplar and no file held, for the reason given in
§5.2. Both upper bounds bind, and both M-to-1 sides bind absolutely.

LRM-R13's lower bound is enforced, with three exemptions. A nomen is itself a
res (§7.1), so requiring every res to carry a nomen would require every name to
be named, and so on without end. A reified address (§8.2) is identified by the
region it selects; a household holds one per subtitle cue, scene boundary and
OCR word position, and a name for each would restate the selector and say
nothing further. An annotation ([spec-02] §3.1) is identified by its target,
body and provenance; derived annotations outnumber every other row class by
orders of magnitude, and a name for one would restate its tool and body type.
Every other kind MUST carry at least one nomen. The exempt kinds remain
nameable.

LRM-R3 is the only many-to-many among the four structural entities. An
expression MUST realize exactly one work. An item MUST exemplify exactly one
manifestation. A digital item MUST carry exactly one manifestation. A nomen MUST
be the appellation of exactly one res.

### 6.2 Existence constraints

LRM states that no work exists without at least one expression, and no
expression without at least one manifestation.

The wording is "there being, or there having been at some point in the past."
This is a creation-time obligation, not a perpetual invariant. Implementations
MUST enforce it at creation. Implementations MUST NOT invalidate a work when its
last expression is deleted.

Where enforced in a relational store, the constraint MUST be deferred to
transaction commit, since the parent row must exist before a child can reference
it.

LRM-R13's lower bound (§6.1) is enforced the same way and for a further reason:
§7.5 replaces the entire shipped name set on upgrade, and a perpetual invariant
would refuse the removal of a shipped name from a res that carries no other.

### 6.3 Refinement

LRM-R33 (`res` to place) and LRM-R35 (`res` to time-span) are declared at
`res` level and are many-to-many. Both scope notes expect implementations to
refine them into specific association types.

Implementations SHOULD refine these. Candidate refinements named by LRM: time of
work conception or creation, time of expression creation, time of publication or
manufacture, period of ownership of an item, date of birth of a person, time of
validity of a nomen for a particular res.

**OPEN:** the refinement set is not specified. It is a registry (§7.5).

### 6.4 Work boundaries

LRM §2.2 does not prescribe how much adaptation makes a derived expression a new
work, and states that both the library convention and the rights-society
convention are compatible with the model.

This system applies one test throughout: **was significant independent
intellectual or artistic effort involved?** New material means a new work. A
different rendering of the same material means a new expression.

| Case | Treatment | Link |
| --- | --- | --- |
| Adaptation across form (film of a novel) | New work | LRM-R22 |
| Cover | New work, created by the performer | LRM-R22 |
| Remix with new composition | New work | LRM-R22 |
| Remix that is a transform only | New expression | LRM-R24 |
| Live version | New expression | LRM-R2 |
| Dub or translation | New expression | LRM-R2 |
| Alternate cut | New expression | LRM-R2 |
| Alternate cut that alters meaning | MAY be promoted to a work | LRM-R22 |

Notes:

Adaptation across form is settled by LRM itself, not by this document.

For covers, the original author is reached through LRM-R22 rather than by direct
attribution. This is correct: the cover artist created something new.

"Remix" does not map to a single treatment. A remix introducing new percussion,
restructured arrangement, or new tempo and time signature is a new composition.
A remix that is a pitch and tempo transform with structure and content intact —
nightcore, sped-up, slowed-and-reverbed — is a new expression derived at
expression level. These exception cases are mechanically identifiable as
transforms of an existing recording.

For alternate cuts, differing runtime is irrelevant, since duration is an
expression attribute. The promotion exception applies where a re-cut alters
meaning rather than length.

### 6.5 Representative expressions

A work MAY carry representative expression attributes (LRM §5.6): the
characteristics users treat as inherent to the work.

Expression-level values of the same attributes give a measure of distance from
the canonical form. Implementations SHOULD use this distance to order
expressions when selecting among them (§8.6).

Implementations MAY automatically promote expression attributes to
representative expression attributes at ingest where a work has a single
expression in a single manifestation (LRM §5.6). This covers the home-media case.

**OPEN:** which attributes are significant per category of work. LRM §5.6
requires the implementation to specify this. It is a registry (§7.5). LRM-E2-A2
supplies attribute sets for textual, musical, cartographic, moving image, and
art works, which the registry SHOULD adopt; [ANNEX-A] §A.9 records them and
identifies the two categories — still image and personal record — for which LRM
has no analogue and the selection must be authored.

---

## 7. Naming

### 7.1 Nomen

Names are entities, not string attributes. A nomen is an association between a
res and a designation referring to it (LRM-E9), carrying its own attributes:
`nomen_string`, `scheme`, `language`, `script`, `context_of_use`,
`reference_source`, `intended_audience`, `script_conversion`.

There MUST NOT be a title column on work, expression, manifestation, or item.

A nomen is itself a res and MAY therefore have nomens of its own.

Because a nomen belongs to exactly one res (§6.1), the appellation relation is
keyed on the nomen.

### 7.2 Language is nullable

`language` MUST be nullable, and null MUST mean genuinely absent rather than
unknown.

A household's vocabulary is a mixture of dialects and borrowed terms and does not
belong to a language in the relevant sense. Implementations MUST NOT infer or
detect a language for such names.

Queries decide how to treat null. A language-filtered query MAY include or
exclude untagged nomens depending on context; neither is mandated.

### 7.3 Assigners and the household layer

LRM-R14 (`Agent assigned Nomen`) carries name provenance.

The assigner MUST be nullable. A null assigner denotes the household's shared
vocabulary — the unmarked default. A non-null assigner denotes a name specific to
that agent.

This inversion is deliberate. Household names are the generic case; an
individual's variant is the marked case. Because the deployment *is* the
household (§10.2), a collective agent row representing it would partition
nothing.

A term migrating from one person's use into household use is recorded as a new
nomen with a null assigner, linked to the original via LRM-R15
(`is equivalent to`). The personal nomen is not removed.

`context_of_use` remains independent of assignment and carries relational
anchoring — which relation a kin term belongs to is a distinct question from who
assigned it.

Names MAY carry a period of validity via LRM-R35, so a name falling out of use
does not require deletion.

### 7.4 Resolution

Resolution is a pure function `(res_id, profile) → nomen`, evaluated at the
render boundary. It MUST NOT mutate. It MUST be deterministic: the same res and
profile MUST resolve to the same nomen across calls, or the same item will appear
under different labels between page loads.

Resolution MUST always return a nomen. Where several are visible, the terminal
fallback is the nomen with a null assigner.

There is no fallback to the primary identifier. §6.1 requires every res
resolution is called on to carry at least one nomen, and a res exempt from that
rule is not resolvable: resolution of one MUST fail rather than fabricate a
label from an identifier that was never a name.

Resolution applies to output only. It MUST NOT be assumed to constrain query
paths; how search treats the set of nomens is an application decision made per
query.

Implementations SHOULD provide batch resolution over a set of identifiers to
avoid per-entity resolution in list views.

Calendar and date-format preference is the same function applied to time-span
nomens (LRM §4.1.3 gives one time-span with nomens in Gregorian, Hebrew, and
Indian civil calendars). It is not a separate mechanism.

### 7.5 Shipped and emergent data

Two layers, distinguished by provenance.

**Shipped.** Seeded at install from the release: base nomenclature, concepts,
and controlled vocabularies. Generic and identical across every deployment.
Updating it is a release.

**Emergent.** Everything the household adds. Accumulates without schema change.

Seeded rows MUST NOT be mutated in place. A correction to a shipped name MUST be
recorded as a local nomen that outranks it at resolution. This allows an upgrade
to replace the entire seed set, since no local data lives inside it.

The same pattern applies to external identifier matches (§4.3): the automatic
match and the correction are separate rows, and the correction wins by
preference. A user correction MUST NOT be overwritten by subsequent automatic
matching.

It applies to categories (§17) as well. A category assigned automatically — by
ingest, or by matching — and a member's correction of it are separate records
carrying their provenance, and the correction wins by the same preference.

**All controlled vocabularies in this system are seed data, not specification.**
This includes category values, event types, asset roles, association refinements
(§6.3), and representative expression attribute selections (§6.5). LRM §4.2.3
states its own category examples are not intended as controlled vocabularies,
and this document follows that.

Where a household has already created something a later release ships as a seed,
there are two res for one thing. They MUST be linked and MUST NOT be merged.
Merging requires either mutating the seeded row, which this section forbids, or
destroying the local row, which discards the household's own provenance and
assigner. Both persist, and resolution (§7.4) prefers names carried by the local
one under the rule that makes a correction outrank a shipped name.

The link is an association refining LRM-R1, whose type is a registry entry
(§17). LRM-R15 does not reach this case: it relates two nomens that are
appellations of one res, and LRM gives it as a shortcut for exactly that path,
so it cannot span two. LRM-R15 does apply where §7.3 uses it, since a personal
name and the household name it migrated into name the same res.

---

## 8. Addressing part of a resource

### 8.1 Problem

LRM's smallest addressable unit is a whole entity. It has no representation for a
region within one: a timestamp range, a pixel area, a text offset. Subtitle cues,
lyric timings, chapter marks, scene boundaries, credits and intro ranges,
speaker-attributed transcript segments, OCR word positions, face tags, and
reader highlights all require this.

A subtitle *track* is a parallel expression (§5.3). A single cue within it has no
LRM form. This section supplies one.

### 8.2 Structure

An address is a res identifier and a selector. The res names the coordinate
space; the selector names the region within it.

An address MAY be reified: given a primary identifier per §4 and persisted as a
row in its own right. Reification is REQUIRED wherever anything must reference
the region durably — a preference expressed about it, a feature vector or
embedding computed over it, a face tag, a reader's highlight. An address used
once to serve a deep link (§9) need not be reified.

A reified address is a res, and therefore nameable (§7) and addressable (§9)
like any other.

This specification supplies addresses and says nothing about what may be
attached to one. Bodies — annotations, derived measurements, and their
provenance and supersession rules — are specified in [spec-02].

Where region boundaries are computed rather than authored — audio segmentation,
scene detection, OCR word positions — re-running the deriving code at a
different version yields different boundaries. Anything a person asserted about
such a region MUST therefore address the resource directly rather than the
computed region, so that re-derivation cannot move what the assertion refers to.
[spec-02] §3.3 is normative for this.

### 8.3 Selector types

Selectors are a typed closed set. The initial set:

| Type | Addresses |
| --- | --- |
| `temporal` | A time range |
| `spatial` | A region of an image or frame |
| `spatiotemporal` | A region of a moving image over a time range |
| `text_position` | A character or word offset range |
| `text_quote` | A text anchor with surrounding context |
| `page` | A page in a paginated resource |
| `track` | One stream of a multi-stream container |

Adding a capability later MUST be a new selector type rather than a re-encoding
of existing ones. Volumetric and point-cloud media are anticipated.

### 8.4 Units and basis

Selectors MUST store units natural to the medium: milliseconds, page and
character or word offset, sample index.

Normalized position MUST be derived from the extent, not stored. A stored
fraction loses precision on long media and is invalidated whenever the extent is
corrected. Deriving preserves both exact in-resource addressing and cross-media
comparability, so "halfway through" is meaningful across an episode, a film, a
novel, and an album alike.

The addressing basis MUST survive re-encoding:

| Basis | Survives re-encode | Permitted |
| --- | --- | --- |
| Byte offset | No | MUST NOT |
| Frame number | No (framerate change) | MUST NOT |
| Absolute pixel coordinates | No (rescan at other resolution) | MUST NOT |
| Timestamp | Yes | Yes |
| Percentage spatial coordinates | Yes | Yes |

### 8.5 Level validity

A selector type is valid only at certain entity levels, and implementations MUST
enforce this rather than treat it as convention.

Duration is an expression attribute, so a temporal selector against a work is
meaningless where two cuts of differing runtime exist.

| Selector | Valid at |
| --- | --- |
| `temporal`, `spatiotemporal` | Expression and below |
| `text_position`, `text_quote` | Expression and below |
| `spatial` | Manifestation and below |
| `page` | Manifestation and below |
| `track` | Manifestation and below |

`spatial` is bounded at manifestation because resolution differs per scan, and
`page` because pagination differs per edition. `track` names a stream of one
container, which exists only at manifestation and below.

A reified `track` address is itself a coordinate space: a `temporal` or
`spatiotemporal` selector MAY target one, addressing a region of that stream
alone. This is how a region of the French audio in a container carrying French
and English is told apart from the same region of the English.

Text offsets MUST record what they are an offset into. For a scanned book,
character positions address a derived OCR transcript rather than the object, so a
re-run with a better model shifts them. A word index is more stable than a
character offset; a text-quote anchor is more stable than either.

### 8.6 Selection among expressions

Where several parallel expressions are available (§5.3), selection occurs
server-side using household and personal preferences.

The selection set is never empty: the container's default track is always
present, and its presence in the library constitutes acceptance. Selection
therefore returns the preferred expression where available and the default
otherwise. Implementations MUST NOT report an absence.

Ordering SHOULD use distance from the representative expression (§6.5) rather
than container track order, so that "original audio" derives from what the work
is rather than from how the file was muxed.

Audio selection, subtitle selection, and subtitle visibility are independent
settings. Implementations MUST NOT collapse them into a single language
preference.

Where the resolved expression differs from the profile's preference,
implementations SHOULD indicate this unobtrusively. This is a display concern,
not an error.

Naming (§7) and expression selection are orthogonal axes. A household name in one
language and personal audio in another is coherent and MUST be supported.

---

## 9. URIs and deep links

### 9.1 Form

An address serializes as a query string on the entity URI:

```
/expressions/{uuid}?t=140,148
/manifestations/{uuid}?xywh=percent:25,25,50,50
/manifestations/{uuid}?page=42
/expressions/{uuid}?char=1200,1340
```

A link carries exactly one selector of one type (§8.3). `t` and `xywh` together
are the one `spatiotemporal` selector; any other combination of dimensions names
no type and MUST be rejected.

[MEDIA-FRAGS] is adopted as the base grammar and supplies the `t`, `xywh`,
`track`, and `id` dimensions. It has no form for text position, text quote, or
page; those use dimension names defined by this system in the same
`&`-separated name-value grammar.

The dimension name registry is seed data (§7.5) and is extensible.

### 9.2 Query form, not fragment

The query form is REQUIRED. Implementations MUST NOT use the fragment component
as the canonical carrier.

A fragment never reaches the server, which permanently forecloses server-side
handling of the range: link previews, a thumbnail at the linked moment, handing a
range to a processing pipeline. The query form is a superset — the client reads
it as readily — and preserves those options.

Implementations MUST NOT carry the same value in both a query parameter and a
fragment. The client can read either, so a fragment adds no information the query
does not hold. The fragment component is reserved for genuinely client-only use.

Cache keying MUST ignore these query parameters.

### 9.3 Scope

Two scopes, distinguished by whose deployment resolves the link.

**Same instance.** The primary identifier plus a reachable origin. Exact,
resolves to the specific expression held, works for home media where no external
identifier exists or ever will. This is the common case, including links between
a person's own devices.

**Different instance.** An external identifier (§4.3), where one exists. Lossy:
an external identifier names a work, not the particular cut held, so a temporal
selector lands approximately on the recipient's copy.

A link SHOULD indicate which scope it carries.

Level validity (§8.5) applies to both scopes. A deep link with a temporal
selector MUST name the expression, not the work.

---

## 10. Principals and households

### 10.1 Principals

A principal is an identity that uses the system. LRM's agent, person, and
collective agent describe entities referenced *by* content; principals are a
separate concern outside LRM's scope.

Principals MUST be minted locally with a primary identifier per §4.1 and mapped
to external identities, not keyed on them directly.

The identity key from an OIDC provider is the `(iss, sub)` composite. `sub` is
unique only within an issuer, so `sub` alone MUST NOT be used.

If the issuer URL changes through provider migration, realm rename, or a move off
a hosted provider, the composite changes. Because every reference is to the local
identifier and never to the composite, this is repaired by mapping the new
composite to the existing principal rather than by creating a new one.
[spec-06] §3.3 is normative.

A principal MAY link to the LRM person it corresponds to. A person who appears in
household media and assigns names to things but holds no login is an agent and
not a principal; implementations MUST support this case.

Every principal carries a role, which determines what it may do. The role set is
seed data (§17); the permissions each role carries are normative in [spec-06] §6.
Not every principal is a person: the deployment itself acts as one, and it is the
holder of operations that belong to no household member.

### 10.2 Household

The household is both an LRM collective agent and an application concept. Not one
or the other.

As a collective agent it is a `res`: nameable, creditable as the creator of a
work, able to assign nomens. LRM-E8 names families explicitly. As an application
concept it is the deployment and trust boundary, which LRM §2.1 places outside
the model.

The two are maintained through different paths.

They are not reconciled, because nothing is duplicated across them: the
collective agent holds naming and creation relations, the trust boundary holds
membership, policy, and device bindings, and neither holds an attribute the
other holds. [spec-06] §5.2 is normative.

### 10.3 Devices

Devices are scoped to a principal at authentication time. Input-constrained
clients such as televisions SHOULD use the OIDC device authorization grant
[RFC8628].

There is no shared or ambient session. Every playback is attributable to a
principal.

---

## 11. Events

### 11.1 Nature

Events are descriptive records of what happened. They carry no notion of current
state, and questions of editability do not arise. Their purpose is to give a
person basic metrics about their media consumption.

Current state — resume position — is a separate concern from event history.
Derived metrics such as play count are counts over events.

Event volume is bounded by human viewing time. At 60 hours per week of viewing
with 30-second checkpointing, one heavy user generates on the order of a few
hundred thousand small rows per year. No compaction policy is required, and a
time-series store is not warranted.

### 11.2 Scope and visibility

Events MUST be scoped to the principal. The household MUST NOT be shown what an
individual is watching.

Implementations MUST NOT expose one principal's events to another through any
aggregate, recommendation surface, or resumption list.

Playback progress originates on the device the principal authenticated to and is
stored against that principal so it reaches their other devices.

### 11.3 Distinct from notifications

The change notifications in §12.2 are also called events in common usage. They
are a different thing and MUST NOT share a representation with consumption
events.

**OPEN:** the event type vocabulary is seed data (§7.5).

---

## 12. Ordering and propagation

### 12.1 Ordering

Two distinct kinds of sequence exist, and §3.2 forbids conflating them.

**Arrangement** is a catalog fact: track 3 of the album, page 42 of the scan,
episode 5 of the season. LRM declares no ordinal attribute, but §5.7 makes
selection and arrangement the essence of an aggregating work, so the ordinal
belongs on the relationship that expresses the aggregation — LRM-R25 at
expression level for aggregates (§5.3), LRM-R26 at manifestation level for
serials and other whole-part structures (§5.4). Arrangement MUST NOT be stored
on an asset.

Where an aggregate is released as a structured manifestation — a release made of
media made of tracks — its order is the positions on those LRM-R26 relations,
and the LRM-R25 aggregation carries none, since a second copy of the order could
only drift from the first. LRM-R25's arrangement orders an aggregate with no
such structure, such as a sequence the household composes. It is a property of the holding, not of any stored copy, and it
survives the loss of every copy.

**Part sequence** is a preservation fact: disc 2 of a two-disc rip, the second
file of a split capture. It applies only where one digital item is realized by
several assets that are parts rather than alternatives (§5.5), and it MUST NOT
be used to express arrangement.

Both are a nullable integer: null where only one exists, an integer otherwise.
Reordering and insertion are performed as a single grouped update.

Renumbering siblings is not a material cost at household scale, and with one or
two people editing there is effectively no concurrent-reorder conflict.
Fractional indices and other renumbering-avoidance schemes are NOT REQUIRED.

### 12.2 Propagation

Propagation is by notification, not by delta. The server emits a change
notification; each device reconciles its own state when able.

The server's responsibility is to indicate that something changed. It MUST NOT be
responsible for forcing clients to update, and it need not transmit the changed
rows. A grouped update is therefore one notification regardless of how many rows
moved.

---

## 13. Assets, copies, and integrity

### 13.1 Assets and modification

Normalization to a standard format is performed so that playback, analysis and
preservation do not each depend on whichever format the household happened to
acquire.

Modifications to a playable copy MUST remain with that copy. They MUST NOT
propagate to the original.

A copy is an asset bearing a role (§5.5). The acquired original and the
standardized master are two assets of one digital item, not two entities and not
two states of one.

### 13.2 Originals

The original is retained as proof of ownership, including where it is compressed
or in a different format from the standardized master.

If the acquired original is deleted, the normalized copy MUST also be deleted,
since nothing remains to support it. This does not apply where the original was
discarded under [spec-03] §4.3 in favour of a recompression verified reversible
against it: there the recompression assumes the Acquired role, and no original
remains to couple to.

Reversibility verification retains a role in exactly one circumstance: where a
normalization claims reversibility and the acquired original is to be discarded
in favour of the recompressed form. [spec-03] §4.3 is normative.

### 13.3 Normalization

Normalization produces the standardized master: one designated format per media
class, so that analysis, playback and preservation read one format rather than
every format the household has ever acquired. The standard format for each media
class is a registry (§17).

Normalization MUST NOT reduce fidelity. Within that bound it MAY re-encode.
Converting a camera raw capture, or a lossless recording in one codec to the
standard lossless codec, is normalization: nothing is discarded, and the result
is exactly as recoverable as its input.

Implementations MUST NOT re-encode lossy essence. Where only a lossy record
exists it is already the normalized master, whatever its format; re-encoding it
compounds generation loss to no purpose, because there is no fidelity left to
preserve.

JPEG-to-PNG conversion is excluded by that rule. PNG stores decoded pixels
exactly, so no visual information is lost, but the essence is lossy, the ability
to reproduce the original file is lost, and the result is typically three to ten
times larger. [JPEG-XL] lossless recompression achieves the intent: bit-exact
reversible to the original JPEG and roughly 20% smaller.

Normalization is not transcoding. A rendition produced for a client to play —
lossy, lower bitrate, resampled, rescaled — is a transcode governed by §13.6. It
is produced on demand, it is never the normalized master, and it is never backed
up.

### 13.4 Detection over recovery

Recovery is not guaranteeable. An N% recovery set recovers up to N% damage and no
further, and covers neither whole-file loss, nor drive failure, nor deletion.

Detection is therefore the requirement. Two distinct concerns:

**Corruption.** Per-asset checksums, verified on a schedule. This catches bit rot
regardless of the storage layer. Verification MUST be a scheduled operation with
recorded outcomes, not an operator convention. An asset whose last successful
verification exceeds its interval MUST be reported as unverified.

**Format risk.** Identification of files in formats losing decoder support. An
intact file in a dead codec is equally lost. [PRONOM] is the established registry,
with DROID and Siegfried as identification tools.

Parity recovery sets are OPTIONAL and secondary. Recovery relies on the backup
copy (§13.5) and on operational practice.

### 13.5 Storage topology

Primary storage holds the acquired original and the standardized master. A backup
NAS holds a further copy; its size and location are unconstrained.

All data sits on RAID arrays, so drive failure is not something the application
reasons about. Two gaps follow, and implementations MUST account for them:

Conventional RAID has no block checksums. Silent corruption is neither detected
nor repaired and can be propagated into a rebuild. Detection is the job of §13.4.

RAID does not protect against deletion or ransomware. That is the backup copy's
purpose.

The acquired original and the standardized master share a failure domain and are
coupled under §13.2, so this is two independent copies rather than three. Whether
the backup is on-site determines whether site loss is covered.

A checksumming filesystem — ZFS, Btrfs, or erasure-coded object storage — is
preferred where available and would make application-level checksums redundant at
the primary tier, though not on copies that leave it. No such store is assumed.

### 13.6 Transcoding

Transcoding for playback is performed on demand when content is accessed.
Transcodes MUST NOT be pre-generated: transcoding MUST be triggered by an actual
request for the content, never by ingest, by a schedule, or in anticipation.

This section governs playback renditions only. Other derived assets — thumbnails,
waveforms, sprite sheets — MAY be generated at ingest; they are not transcodes,
and §5.5 governs them.

Retaining the output of an on-demand transcode is permitted, subject to all of:
it is a derived asset (§5.5) and therefore never backed up (§13.7); it is never
authoritative, so its loss is not a data loss and its absence is not an error;
and it is evictable under a bounded policy. A retained transcode is a cache. A
transcode produced before anything asked for it is pre-generation, whatever its
eviction policy.

Compute is local and CPU time is not a cost consideration. Sustained real-time
transcoding of high-bitrate video is nonetheless a capacity constraint, and
concurrent sessions multiply it, since a transcode is per-session and the
selected track (§8.6) is an input to it.

The standardized master (§13.3) is nonetheless chosen for fidelity and longevity,
not for direct-play compatibility. Serving therefore transcodes routinely rather
than exceptionally, and that cost is accepted: at one household's concurrency the
CPU time is available, whereas choosing the archival format to suit the clients
of the moment trades a permanent property for a temporary convenience.

### 13.7 Backup scope

Anything regenerable from a master and a recipe is expendable and MUST NOT
consume backup capacity: thumbnails, waveform data, parsed and cropped images,
machine-generated transcripts, retained transcodes. These are regenerated or
refetched after loss.

Acquired originals, standardized masters, human-generated annotations, events,
and the catalog itself — every entity, relationship, and nomen — are not
regenerable and MUST be backed up. A relative's identification of who appears in
a photograph is among the least replaceable data in the system, and the catalog
is what makes every backed-up file more than an unnamed byte sequence.

---

## 14. Deletion

### 14.1 Recycle bin

Deletion places an entity in a recycle bin for 30 days. A principal MAY restore
anything in the bin, and MAY force deletion of its own deletions by emptying
them. Emptying another principal's deletions is an administrative operation
([spec-06] §6), because it destroys the window that makes the bin a safety net
rather than a confirmation dialog.

### 14.2 HTTP semantics

A request for a recycled entity MUST return `410 Gone` with
`Cache-Control: no-store`.

410 is cacheable by default [RFC9110]; the explicit cache control is REQUIRED to
prevent a stored tombstone outliving a restore.

410 is correct because the resource is intentionally unavailable and the origin
knows why, which is the distinction [RFC9110] draws from 404. It also avoids
collision with 401 and 403, which belong to the authorization layer.

The response body MUST carry problem details [RFC9457] distinguishing
recyclable-until-a-date from permanently gone, so a client can offer restoration.
The status line reports gone; the problem type reports recoverable.

After the window elapses and the entity is purged, 410 is returned again, with
default cacheability permitted, since permanence is then accurate.

Annotations whose target has been purged are governed by [spec-02] §8.1: derived
annotations are purged with the target, authored annotations are retained as
orphans and MUST render.

**OPEN:** post-window behaviour with respect to propagation convergence.

### 14.3 Recycling, purge, and bytes

Recycling is a catalog state and nothing further. It MUST NOT transform, move, or
remove any stored byte sequence. An asset's bytes are retained unchanged for the
whole of the window, which is what makes restoration exact rather than
approximate.

Recycling cascades downward as one grouped operation with one restoration, and
MUST NOT cascade upward. A res recycles with a parent that is its only one: an
expression with its work, an item and a digital item with their manifestation,
an asset with its digital item, a reified address (§8.2) with the res it
addresses, and a derived annotation ([spec-02] §3.2) with what it targets. A
res's nomens travel with it, and the copies coupled by §13.2 recycle and restore
together.

Nothing authored is taken. An authored annotation outlives its target
([spec-02] §8.1), and so does the address it is anchored to: without that
address the annotation would no longer say what it was about.

A child with another parent that is not being recycled stays, and is unlinked
from the one that is. A manifestation embodying several expressions (§5.3)
therefore recycles with them only when every one of them recycles: deleting a
dub leaves the container that also carries the original audio. The link is
retained through the window, so that restoration is exact, and removed at purge.

Aggregation (§5.3) is not parentage — the aggregating work holds selection and
arrangement criteria and contains nothing — so recycling an album leaves its
tracks, and purge removes only the aggregation link.

Whole-part (LRM-R18) does not cascade either. A part is a work in its own right,
which may be realized and published apart from any whole, so recycling a whole
leaves its parts, and purge removes only the whole-part link.

A deletion MAY be extended to what an aggregate selects: deleting an album with
its tracks. An aggregated expression then recycles with the aggregate when no
other live aggregate selects it, so a track that also appears on a compilation
stays. The extension applies recursively, so a box set takes the albums it
selects and theirs. The work behind an aggregated expression recycles with it
only when every expression of that work does, so a song with a live recording
elsewhere keeps its work. This is the one case in which recycling reaches a work
from below, and it does so only where nothing of the work would remain.

References that record who or what a res was rather than what it contains — a
nomen's assigner, a principal's person, events, resume positions — neither
cascade nor unlink. They continue to name the purged identifier, which the
tombstone keeps from being reused.

Purge is permanent. At purge the bytes are removed from primary storage, and a
tombstone MUST be retained indefinitely recording the identifier, the entity
class, and the time of purge. §4.1's prohibition on identifier reuse and §14.2's
continued 410 both depend on that record; without it neither can be honoured.

Purge does not reach the backup copy, which [spec-03] §10 requires be unwritable
by the credentials that reach primary storage. Those bytes persist until backup
rotation retires them, and implementations MUST NOT represent purge as
guaranteeing their destruction.

---

## 15. Conformance

An implementation conforms to this specification if it satisfies all of the
following. These are behavioural rather than structural, so that storage engines
and languages may differ.

**Identifiers**

1. Every entity returns a UUIDv7 primary identifier.
2. Seeded entities carry identical identifiers across two independent installs of
   the same release.
3. An entity with zero external identifiers is fully functional.
4. Two entities may carry the same external identifier without error.

**Structure**

5. An expression referencing two works is rejected.
6. An item referencing two manifestations is rejected.
7. A manifestation embodying several expressions is accepted.
8. Creating a work with no expression in the same transaction is rejected;
   deleting a work's last expression is accepted.
9. A whole-part relation between an aggregating work and an aggregated work is
   rejected.
10. Ingesting a second, higher-quality scan of an already-catalogued original
    produces a new manifestation under the existing expression and does not
    duplicate the work.

**Naming**

11. No title column exists on work, expression, manifestation, or item.
12. A nomen with a null language round-trips and renders.
13. Resolution returns a nomen for every res, including one with only a
    null-assigner nomen. Resolution of a res exempt from LRM-R13 (§6.1) fails
    rather than returning a fabricated label.
14. Resolution called twice with the same res and profile returns the same nomen.
15. Replacing the entire seed set preserves every locally created nomen and every
    correction to a seeded name.
16. A user correction survives a subsequent automatic matching run.

**Addressing**

17. A temporal selector against a work is rejected; against an expression it is
    accepted.
18. A selector storing byte offsets or frame numbers is rejected.
19. Normalized position for the same selector changes when the resource's
    recorded extent is corrected.
20. A deep link carrying a selector in the fragment component rather than the
    query string is rejected or normalized.

**Principals and events**

21. Changing the OIDC issuer for a principal preserves that principal's events.
22. Principal A cannot observe principal B's events through any endpoint,
    including aggregates and resumption lists.
23. An agent with no principal can be recorded as the assigner of a nomen.

**Integrity and lifecycle**

24. An asset whose last successful verification exceeds its interval is reported
    unverified.
25. Normalizing a lossy acquisition writes no second copy: the acquired asset
    carries the Normalized role. Normalizing a lossless acquisition into the
    standard codec is accepted, and re-encoding lossy essence is rejected.
26. Deleting an acquired original deletes its normalized copy, except where that
    original was discarded under [spec-03] §4.3.
27. A recycled entity returns 410 with `Cache-Control: no-store` and a problem
    type distinguishing it from a purged entity.
28. A restored entity is reachable at its original identifier.

**Assets and ordering**

29. An asset referencing two digital items is rejected.
30. A digital item with zero assets is accepted and renders, representing a
    holding whose copies are all lost.
31. A thumbnail, waveform, or machine transcript is recorded as a derived asset
    and does not create a manifestation or digital item.
32. Deleting every asset of a digital item preserves that item's arrangement
    within its aggregate.
33. No transcode output exists for content that has never been requested;
    retaining the output of a requested transcode is accepted, and a thumbnail
    generated at ingest is accepted.
34. A locally created row and a later release's seed for the same concept both
    persist and are linked, and resolution prefers the local one.
35. A digital item referencing two manifestations is rejected; a manifestation
    carried by no digital item is accepted and renders.
36. Recycling an asset leaves its stored bytes byte-identical, and restoring it
    returns those same bytes.
37. Purging an entity removes its bytes from primary storage and retains a
    tombstone that prevents its identifier being reused.

---

## 16. Security considerations

Primary identifiers appear in public URLs (§4.4) and are not secrets. UUIDv7
embeds a timestamp and is not random. Authorization is a separate layer and MUST
NOT rely on identifier unpredictability.

Event data is personal. §11.2 requires principal scoping; implementations should
treat aggregate and recommendation surfaces as the likely leak path, since these
derive from events across the household by construction.

Exposing an origin for deep links (§9.3) makes the catalog reachable from outside
the household network. This specification does not address network exposure,
authentication, or authorization.

Household naming (§7.3) is shared by construction, so a name one person creates
becomes visible to the household. This is the first case in the model where a
personal contribution is household-visible by default, and it differs from the
event-scoping rule in §11.2.

---

## 17. Registries

The following are seed data (§7.5), maintained through releases, not specified
here:

- Category values, per entity and per categorization scheme
- Association refinement types for LRM-R33 and LRM-R35 (§6.3)
- Representative expression attribute selections per category of work (§6.5)
- Event types (§11.3)
- Asset roles (§5.5); the four role classes in §5.5 are normative, the values within them are seed data
- Selector dimension names beyond those supplied by [MEDIA-FRAGS] (§9.1)
- External identifier schemes (§4.3)
- Association refinement types for LRM-R1, including the link between a local
  res and a seeded res for the same thing (§7.5)
- The standardized master format per media class (§13.3)
- Codecs and their essence: lossy, lossless, or decided by the stream's
  parameters for codecs with both modes ([spec-04] §5.2)
- Companion file patterns, and the names and patterns an inbox never acquires
  ([spec-04] §4.1, §4.6)
- Annotation body types, feature names, and feature groups ([spec-02] §6.1, §6.4)
- Principal roles (§10.1); the role set is seed data, but the permissions each
  role carries are normative in [spec-06] §6, so adding one is a release

---

## 18. References

### 18.1 Normative

- **[IFLA-LRM]** Riva, P., Le Bœuf, P., Žumer, M., *IFLA Library Reference
  Model*, 2017, as amended through December 2021, issued July 2024. CC BY 4.0.
- **[MEDIA-FRAGS]** W3C, *Media Fragments URI 1.0 (basic)*, W3C Recommendation.
- **[RFC2119]** Bradner, S., *Key words for use in RFCs to Indicate Requirement
  Levels*, BCP 14.
- **[RFC8174]** Leiba, B., *Ambiguity of Uppercase vs Lowercase in RFC 2119 Key
  Words*, BCP 14.
- **[RFC3339]** Klyne, G., Newman, C., *Date and Time on the Internet:
  Timestamps*.
- **[RFC9110]** Fielding, R., Nottingham, M., Reschke, J., *HTTP Semantics*.
- **[RFC9457]** Nottingham, M., Wilde, E., Dalal, S., *Problem Details for HTTP
  APIs*.
- **[RFC9562]** Davis, K., Peabody, B., Leach, P., *Universally Unique
  IDentifiers (UUIDs)*.
- **[RFC8628]** Denniss, W., et al., *OAuth 2.0 Device Authorization Grant*.

### 18.2 Informative

- **[spec-02]** *Annotations and Derived Data*, this system. Normative for what
  attaches to an address (§8.2) and for the fate of annotations whose target is
  purged (§14.1).
- **[spec-03]** *Assets, Storage and Preservation*, this system. Normative for
  how §13's obligations are met, including reversibility verification (§13.2)
  and deduplication.
- **[spec-06]** *Principals, Authentication and Authorization*, this system.
  Normative for §10 and for enforcement of §11.2's scoping rule.
- **[ANNEX-A]** *Annex A — Worked WEMI Mappings*, companion to this
  specification. Non-normative. Shows §5–6 applied to music, film, television,
  photographs, scanned correspondence, ebooks, and home video, and enumerates
  the work categories §6.5's registry must cover.

- **[W3C-ANNO]** W3C, *Web Annotation Data Model*, W3C Recommendation. Its
  body-and-selector shape informed §8; its text-quote anchoring semantics are a
  candidate for §8.5.
- **[PRESSOO]** Named by LRM §5.8 for serials modelling. Not adopted.
- **[PRONOM]** The National Archives (UK) format registry. §13.4.
- **[JPEG-XL]** ISO/IEC 18181. §13.3.
- **[EPUB-CFI]** W3C, *EPUB Canonical Fragment Identifier*. Anchoring semantics
  candidate for §8.5.
- **[RFC5147]** Wilde, E., Duerst, M., *URI Fragment Identifiers for the
  text/plain Media Type*. Anchoring semantics candidate for §8.5.
- **[RFC8493]** Kunze, J., et al., *The BagIt File Packaging Format*.
- **[RFC9043]** Niedermayer, M., et al., *FFV1 Video Coding Format Version 0, 1,
  and 3*.
- **[OAIS]** ISO 14721, *Open Archival Information System*.
- **[PREMIS]** Library of Congress, *PREMIS Data Dictionary for Preservation
  Metadata*.
- **[LOC-RFS]** Library of Congress, *Recommended Formats Statement*. Updated
  annually; the current edition has not been checked.
