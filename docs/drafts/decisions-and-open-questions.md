# Decisions and open questions

## 1. Scope and framing

- Goal is a public good. Not profit, not a company, not urgent.
- "Public good" is planning guidance, not a licensing decision.
- Current deliverable is specs to hand to parallel agents.
- Server comes before clients.
- Scope is everything a home user might consume, back up, keep records of, or
  synthesize into another format.
- All content is assumed lawfully obtained. Licensing is out of scope.
- One instance serves one household, many people.
- DRM-protected streaming content is out of scope. The system deals only with
  content the household holds.
- Implementation is Elixir: Phoenix PubSub for cross-device playback, LiveView
  for the user-facing layer and real-time updates, Membrane for media plumbing,
  plus pgvector, Ortex, Scholar, and ffmpex. Recorded as context; the stack is
  out of scope for this document.

The DRM exclusion is a larger simplification than it looks. It removes
availability resolution, deep-linking into native apps, and integration with any
streaming service.

How many specs there are, what they cover, and in what order has not been
reached. The only sequencing established is that the server precedes the
clients.

---

## 2. Decisions

### 2.1 Three domains, one system

Preservation, catalog, and consumption are distinct problem domains with
distinct bodies of research. The deliverable is a single application that covers
all three by virtue of existing.

### 2.2 IFLA LRM adopted

IFLA LRM (2024-07) is the base model, as discussed and recorded in section 3.

The provisional three-shape model is superseded. LRM absorbs two of the three
shapes: bytes are items and digital items, and person-scoped records fall
outside LRM's scope by §2.1 and remain ours to design. The third shape,
annotations anchored to a region of a target, has no LRM equivalent and is
recorded in 3.2 as a gap.

### 2.3 Bibliographic depth

Depth follows the actual information. Sometimes fewer than four levels,
sometimes more. Fixed depth oversimplifies and is rejected.

IFLA LRM (2024-07 edition, CC BY 4.0) does not impose the constraint previously
recorded here. Three findings from reading it:

**It is not a four-level model.** LRM declares eleven entities under a single
top-level entity, `res`. Work, expression, manifestation, and item are four of
the eight direct subclasses of `res`. The other four are agent, nomen, place,
and time-span, with person and collective agent below agent.

**Fewer levels is explicitly permitted.** Section 2.2 states that a compatible
implementation may omit one of the declared entities, giving the example of a
national bibliography with no item-level information. Omitting an entity means
omitting its attributes and relationships too.

**More depth is the sanctioned extension mechanism.** The `category` attribute
is declared on `res` and can be sub-typed for any entity. Section 4.2.3 states
that entity types defined through `category` can function as subclasses of the
entity in question, and that this is how the model is extended with specific
detail.

What LRM does require for a faithful implementation: the entity structure, the
relationships among entities including cardinality constraints, and correct
attachment of whichever attributes are implemented. Attributes and non-
structural relationships are optional.

LRM also leaves work boundaries to the implementation. Section 2.2 notes it does
not prescribe how much adaptation makes a derived expression a new work, and
observes that libraries treat translations as expressions of one work while
rights societies treat each as a distinct work. Both are compatible with the
model.

Open: whether to adopt LRM as the base model, and where to set work boundaries
if so.

### 2.4 Lossy essence

Where only a lossy record of something exists, that lossy record becomes the
normalized master. Normalization changes the wrapper, not the picture or sound.

JPEG-to-PNG conversion is specifically the case this excludes. PNG stores the
decoded pixels exactly, so no visual information is lost; the imperfection is
not in the image. What is lost is the ability to reproduce the original file,
and the PNG will typically be three to ten times larger than the JPEG it came
from. Bigger and less reversible. JPEG XL lossless recompression achieves the
intent: bit-exact reversible back to the original JPEG, roughly 20% smaller.

### 2.5 Corruption detection

Recovery is not guaranteeable. An N% recovery set recovers up to N% damage and
no further, so parity trades against overhead roughly linearly and does not
change the guarantee, only the odds. It also does nothing for whole-file loss,
drive failure, or deletion.

So detection is the requirement, not recovery. Detection is both cheap and
actually guaranteeable, and it is the thing that turns silent corruption into a
known fact rather than something discovered at playback.

Two distinct detection concerns:

**Corruption.** Per-asset checksums, verified on a schedule. This catches bit
rot regardless of what the storage layer does or does not do underneath.

**Format risk.** Identifying files in formats that are losing decoder support,
which is a separate problem from bit-level integrity — a perfectly intact file
in a dead codec is just as lost. This needs a format registry; PRONOM is the
established one, with DROID and Siegfried as identification tools against it.

Recovery relies on the NAS copy in 2.19 and on good data practice. Parity
recovery sets are optional and secondary rather than load-bearing.

### 2.6 Block-level self-healing

ZFS, Btrfs, or erasure coding beats per-file parity where the storage layer is
under our control. No such cluster exists today; roughly 40TB would be needed to
support one, and acquiring it is not ruled out.

Until then the filesystem will not notice corruption, so the application-level
checksums in 2.5 do that job. A future checksumming filesystem would make them
redundant at the primary tier but not on copies that leave it.

### 2.7 Identity

Identity is keyed on the `(iss, sub)` composite. OIDC guarantees `sub` is unique
within an issuer, so this is the standards-sanctioned identity key.

Residual risk: if the issuer URL changes through provider migration, realm
rename, or moving off a hosted IdP, the composite key changes with it and prior
history no longer resolves. For a single stable provider this is accepted.

### 2.8 Identifiers

UUIDv7 throughout, because it is the standard. The uuidv7 Elixir library covers
generation.

Seed rows (2.20) carry UUIDv7s minted when the seed is authored and committed to
the release, not generated at install. Every deployment therefore holds the same
identifier for the same seeded concept, which is what lets an upgrade converge.
This is a property of the seed loader inserting given IDs rather than a second
identifier scheme.

Asset deduplication is handled explicitly rather than falling out of
content-addressed identifiers, since that shortcut causes problems later.

Open: what "explicitly" means mechanically.

### 2.9 Events

Events describe what happened. They are descriptive records of past occurrences
and carry no notion of current state, so editability does not arise. Their
purpose is giving the user basic metrics about their media consumption.

Current state, such as the resume position in 2.10, is a separate concern from
the event history. Derived metrics like play count are counts over events.

Volume is bounded by human viewing time: even at 60 hours/week with aggressive
30-second checkpointing, one heavy user generates on the order of a few hundred
thousand small rows per year. This is not a scale problem and needs no
compaction policy.

### 2.10 Event visibility

Scoped to the logged-in principal. The household does not need to know what any
individual is watching.

Playback progress originates on the device the user authenticated to, and is
stored against the authenticated user so it syncs to their other devices.
External media providers are not a consideration; 1.8 removes them from scope.

### 2.11 Metadata sources

External metadata comes from public databases: MusicBrainz, The Movie DB, IMDb.
The internal source of truth is the format the media is standardized to.

MusicBrainz and TMDB both offer public APIs. IMDb does not; its data is licensed
commercially. Current terms for all three are unverified.

LRM's `nomen` entity is relevant here. It reifies naming as an entity rather
than a string attribute, with its own attributes for scheme, context of use,
reference source, language, and script. ISBN and ISNI are given as examples, so
identifiers and titles are the same kind of thing under this model. That
structure is a candidate for both this entry and 2.12.

### 2.12 External identifier overrides

Default to the public database match. When it gets a match wrong — matching a
live-action adaptation when the animated version is correct — the user can
explicitly override, and that override is never overwritten by subsequent
automatic matching. 2.20 applies the same pattern to shipped seed data.

### 2.13 Deletion

30-day recycle bin. Users may force-delete by emptying the bin, or restore from
it.

Recycled items return **410 Gone** with `Cache-Control: no-store`. 410 is
cacheable by default, and the explicit cache control is what prevents a stored
tombstone from outliving a restore. 410 fits because the resource is
intentionally unavailable and the origin knows why, which is the distinction
RFC 9110 draws from 404. It also stays clear of 401 and 403, which belong to the
auth layer.

The response body carries RFC 9457 problem details, so a client can distinguish
recyclable-until-a-date from permanently gone and offer a restore. The status
line says gone; the problem type says recoverable.

After the window elapses and the row is purged, 410 again, with default
cacheability allowed — permanence is true at that point.

Open: what happens after 30 days with respect to sync convergence and
annotations whose target has been purged.

### 2.14 Copies and modification

Normalization prevents asset and data duplication and should be done. But
modifications to a playable copy stay with that copy and never propagate to the
original.

Open: whether a copy is a separate entity or fields on an asset.

### 2.15 Originals

The original is proof-of-ownership, even when compressed or in a different
format from the standardized library copy. If the original is deleted, it should
probably delete the derived copy too, since the copy would then be out of sync.

Open: whether reversibility verification still has a role.

### 2.16 Annotation supersession

Depends on what is being superseded and on the confidence scores. A blind
"higher confidence wins" rule is rejected.

For transcripts, a diff between old and new is a better basis for judging
quality than a confidence comparison, particularly when surfaced to the user.

Open: what supersession looks like for annotation types where a diff is
meaningless, such as a numeric loudness measurement or a bounding box.

### 2.17 Ordering

A dedicated `order` column on assets, nullable. Null for singles, an integer
when there is more than one of something. Reordering and insertion are done as a
single grouped update.

Renumbering siblings is not a real cost at this scale. A grouped update across
several hundred rows is trivial for a relational database, and with one or two
people editing there is effectively no concurrent-reorder conflict.

Propagation is by notification, not by delta. The server emits an "asset
updated" notification and each device reconciles its own state when able. The
server's responsibility is telling clients something changed, not forcing them
to update or shipping them the rows. So a grouped update is one notification
regardless of how many rows moved.

These notifications are distinct from the consumption events in 2.9, which are
records of what a person did. Same word, different thing.

### 2.18 Playback transcoding

Transcoding for playback happens on the fly when content is accessed, rather
than being pre-generated and stored. The point of holding media in a standard
format is to minimize how much on-the-fly work is needed.

All compute is local, so CPU time is not a cost consideration.

This does bound what "standard format" means in practice. Sustained real-time
transcoding of high-bitrate video is the one place local compute is genuinely
constrained, and concurrent streams multiply it, so the standard format should
be chosen for direct-play compatibility with the intended clients rather than
purely for archival properties.

### 2.19 Storage topology and data protection

Primary storage holds the original and the read/playback copy. A backup NAS
holds a further copy; its size and location are unconstrained.

Protection is implicit in how data is handled rather than a dedicated construct
in the application. All data sits on RAID arrays, so drive failure is not
something the application reasons about.

The middle tier — transcripts, waveforms, parsed and cropped images — is
expendable. It is regenerated or refetched after a loss rather than backed up.

Two things this arrangement does not cover, noted because they bear on 2.5.
Conventional RAID protects against drive failure only; it has no block
checksums, so silent corruption is neither detected nor repaired and can be
propagated into a rebuild. Detecting that is what the 2.5 checksums are for.
Separately, RAID does not protect against deletion or ransomware, which is what
the NAS copy is for.

The original and the playback copy share a failure domain, being on the same
array, and under 2.15 they are coupled anyway. So this is two independent copies
rather than three. Whether the NAS is on-site determines whether site loss —
fire, theft, flood — is covered.

### 2.20 Shipped data and the emergent layer

Two layers of data, distinguished by provenance rather than by scope.

**Shipped.** Seeded at install from the release: base nomenclature and concepts,
generic and identical across every deployment. Updating it is a release, not a
schema migration.

**Emergent.** Everything the household adds — custom nomens, concepts, local
vocabulary. It accumulates as things change and requires no schema update. This
is the layer the household dialect lives in.

Seeds are never mutated in place. A user correcting a shipped name adds a local
nomen that outranks it at resolution rather than editing the seeded row. That
keeps upgrades free to replace the entire seed set, since no local data ever
lives inside it. Same shape as 2.12, where the automatic match and the correction
are separate rows and the correction wins by preference rather than by
overwriting.

The shipped layer is what gives every deployment a common baseline, which is
what makes external identifier matching land on the same concepts everywhere.

Open: what happens when a user adds something a later release ships as a seed,
leaving two rows for one concept.

Note the boundary against 3.1: category *values* are data and can emerge, but
promoting a category to a real subtype is a schema change and therefore a
release. Subtyping cannot be user-facing.

### 2.21 Addressing part of a resource

Fills the gap recorded in 3.2. An address is `res_id` plus a selector: the res
names the coordinate space, the selector names the region within it. Same
construction as a Plus Code, where the address carries the global cell and then
subdivides.

**Selectors are a typed closed set**, each storing coordinates natural to its
medium: temporal, spatial, spatiotemporal, text position, text quote, page.
Adding a capability later — volumetric media, point clouds — is a new type
rather than a re-encoding of what exists.

**Store natural units, derive normalized position.** Milliseconds, page and
character offset, sample index. Fractions are computed from the extent on
demand, never stored: a float at 0.5 of a three-hour film is imprecise to
several hundred milliseconds, and stored fractions break whenever the extent is
corrected. Computing down gives both exact in-resource addressing and
cross-media comparability, so "halfway through" is meaningful across an episode,
a film, a novel, and an album.

**The addressing basis is chosen to survive re-encoding.** Byte offsets die on
any re-encode; frame numbers die on a framerate change; absolute pixel
coordinates die on a rescan at a different resolution. Timestamps and
percentage-based spatial coordinates survive all three.

**Selector types are only valid at certain levels.** Duration is an expression
attribute, so a temporal selector against a work is meaningless where two cuts
exist with different runtimes. Temporal and text-position selectors are valid at
expression and below; spatial coordinates on a scan want manifestation, since
resolution differs per scan. Enforced, not conventional.

**Text offsets must record what they are an offset into.** For a scanned book,
character positions address a derived OCR transcript rather than the object, so
a better OCR pass shifts them. A word index is more stable than a character
offset, and a text-quote anchor more stable than either.

**Serialization is query-string, using W3C Media Fragments as the base grammar
and extending it.** Media Fragments covers four dimensions — temporal, spatial,
track, id — so it serves the temporal and spatial selectors directly and has no
form at all for text position, text quote, or page. Those get our own dimension
names in the same `&`-separated name-value grammar.

```
?t=140,148
?xywh=percent:25,25,50,50
?page=42&char=1200,1340
?quote=exact:...,prefix:...
```

Query form rather than fragment form. A fragment never reaches the server, which
permanently forecloses acting on the range — link previews, a thumbnail at the
linked moment, handing a range to a pipeline. Query form is a superset: the
client reads it just as easily via `URLSearchParams`, and the server can also
act. Cache keying ignores query parameters, so fragmentation is not a cost here.

Carrying both would be pure duplication; the client can read either, so there is
no information in a fragment that the query does not already hold. The fragment
component stays free for anything genuinely client-only later.

The dimension grammar is identical under either delimiter, so this is reversible
as a link-generation change rather than a model change.

Borrow anchoring semantics, not parsers: EPUB CFI for surviving reflow, RFC 5147
for integrity checks on text ranges, W3C Web Annotation's text-quote selector for
robust re-anchoring. What they anchor against is worth taking; their syntax is
not.

The set of dimension names is ours, documented, and extensible when volumetric
media arrives. Same line as 2.20: dimension names are a release, values are
data.

### 2.22 Deep links

Addresses under 2.21 are a public interface, not an internal schema.

Locally minted UUIDs are correct for links, and the earlier concern that they
are unshareable was wrong: a UUID plus a reachable origin is a valid public URL.
The real axis is whether the recipient resolves against **this** deployment or a
different one.

**Same instance.** UUID plus origin. Exact, resolves to the specific expression
held, works for home media where no external identifier exists or ever will, and
travels as far as reachability and auth allow. This is the common case —
phone to TV, or a link to a relative given access.

**Different instance.** An external identifier per 2.11, where one exists. Lossy,
since `tmdb:78` names a film rather than the particular cut, so a temporal
selector lands approximately on the recipient's copy.

The URL is not a secret. Access control is a separate layer, so identifier
guessability is not a naming concern. UUIDv7 embeds a timestamp and is not
random; this is stated rather than mitigated.

This puts a second consumer on the UUID: 2.8 made it an internal primary key, and
it is now also a permanent public address that people bookmark and paste. That is
a stronger stability commitment than internal keys usually carry, and it is why
recycled items get the 410 treatment in 2.13 rather than a 404.

### 2.23 Household representation

The household is both an LRM collective agent and a concept in the application
itself. Not one or the other. As a collective agent it is a `res`: nameable,
able to be credited as the creator of a work, able to assign nomens. As an
application concept it is the deployment and trust boundary, which §2.1 puts
outside LRM.

The known cost is drift. The two are updated through different paths, so a
rename or correction applied to one does not reach the other. Recorded as a risk
to manage rather than a reason to collapse them, since collapsing would discard
information either way.

Open: whether the two are reconciled, and on what signal.

---

## 3. LRM register

Adopted per 2.2. This section records every place we extend LRM, add something
outside its scope, or make a choice it leaves open. Nothing here contradicts the
model; there are currently no true divergences.

### 3.1 Extensions LRM explicitly sanctions

**Digital item.** §5.3 anticipates an extension defining a `digital item` entity
between manifestation and item, where item is purely physical and digital item
is a file or package of files that may be altered after acquisition by added
rights statements, annotations, or degradations of the octet stream. Our library
is almost entirely digital items. §5.3 also warns against treating every
downloaded file as a distinct singleton manifestation.

**Category as subtyping.** §4.2.3 permits the `category` attribute, declared on
`res`, to be sub-typed for any entity, and states that types so defined can
function as subclasses. This is the mechanism for the variable depth in 2.3.
Several independent categorization schemes may apply to one entity at once.

**Omitting entities.** §2.2 permits dropping declared entities entirely. We
omit none. Place and time-span are kept as entities rather than collapsed to
literals, on the principle that we should not discard information.

Note that category *values* are data and belong to the emergent layer in 2.20,
but promoting a category to a real subtype table is a schema change and
therefore a release.

### 3.2 Additions outside LRM scope

§2.1 puts administrative metadata outside the model. These are ours to design
and cannot be derived from LRM.

- **Events** (2.9). Consumption records and metrics.
- **Preservation and integrity** (2.5, 2.13, 2.14, 2.15, 2.19). Checksums,
  verification scheduling, format risk, recovery sets, copies, storage topology,
  the recycle bin. LRM has no lifecycle or integrity concept.
- **Principals and households.** LRM's agent, person, and collective agent are
  entities referenced *by* content. System users are a separate concern. The
  household exists on both sides — see 2.23.
- **Presentation and resolution.** The vanity layer, household dialect, and
  track selection. LRM supplies the nomens and expressions; the selection
  function over them is out of scope by construction.
- **Pointing at part of a resource.** LRM's smallest addressable thing is a
  whole item, manifestation, or expression. There is no way to say "this is
  true of seconds 140 to 148 of this file" or "this face is at these pixel
  coordinates." A subtitle *track* is fine — §5.7 makes it a parallel
  expression — but an individual cue at a timestamp has no representation.

  The same gap covers lyric timings, chapter markers, scene boundaries,
  credits-start and intro-skip ranges, speaker-attributed transcript segments,
  OCR word positions in a scanned letter, face tags in a photo, and a reader's
  highlight in an ebook.

  This is the surviving piece of the three-shape model. Addressed in 2.21;
  W3C Media Fragments supplies the serialization.
- **Ordering** (2.17). §5.7 says the essence of an aggregating work is its
  selection and arrangement criteria, but LRM declares no ordinal attribute.

### 3.3 Choices LRM leaves to the implementation

**Work boundaries.** §2.2 states the model does not prescribe how much
adaptation makes a derived expression a new work, and notes both the library
convention and the rights-society convention are compatible.

Decided: dubs and translations are separate expressions of a single work.
Grouping and search operate on the work; the localization effort justifies
distinct expressions.

LRM does settle adaptation across form — a film of a novel is a new work with a
transformation relationship, R22.

The test underneath every case below is LRM's own: was significant independent
intellectual or artistic effort involved? New material means a new work; a
different rendering of the same material means a new expression.

**Covers — new work.** Created by the performer via R5, linked back to the
original via R22. The original author is reached through a hop rather than by
direct attribution, which is correct, since the cover artist made something new.
Matches LRM's scope note placing free transcriptions and variations on a theme
in the new-work category.

**Remixes — new work by default, expression by exception.** The ordinary-language
category does not map to one answer. A dubstep remix is a new composition — new
percussion, restructured arrangement, often new tempo and time signature — with
the source becoming material inside something else. That is a new work with R22.
A nightcore remix is a pitch and tempo shift with structure and content intact,
which is a new expression of the same work, linked by R24 `is derivation of`
at expression level.

The exception cases are mechanically identifiable, being transforms of an
existing recording: nightcore, sped-up, slowed-and-reverbed.

**Live versions — expression.** LRM gives this directly: a recording of a
specific performance is an expression. Differing runtime is irrelevant, since
duration is an expression attribute.

**Alternate cuts — expression by default, work by exception.** Altered visuals
rather than altered audio or language, which is the same argument as a dub. Both
are a distinct realization rather than a distinct creation.

§5.6 does real work here: the theatrical cut is typically the representative
expression, and other cuts are ranked by distance from it — the same mechanism
that orders audio track fallback.

The exception is a re-cut that changes meaning rather than length. Blade Runner's
Final Cut removes the narration and alters the ending's implication, which is
genuinely arguable under LRM's test. Such a title can be promoted to its own
work with an R22 link where it warrants it.

Two defaults with two exception paths, one test underneath.

**Representative expression attributes.** §5.6 requires the implementation to
choose which attributes are significant per category of work, and permits
automatic promotion at ingest where a work has a single expression in a single
manifestation. This is the mechanism for identifying an original or canonical
version, and it ranks expressions by distance from it.

**Relationship refinements.** R33 and R35 associate any `res` with a place or
time-span, and both scope notes expect implementations to refine the
relationship into specific types — time of creation, time of publication, period
of ownership, time of validity of a nomen.

### 3.4 Binding constraints

§2.2 requires entity structure, relationships including cardinality, and correct
attribute attachment. The cardinalities that constrain the schema:

| Relationship | Cardinality |
| --- | --- |
| R2 Work is realized through Expression | 1 to M |
| R3 Expression is embodied in Manifestation | M to M |
| R4 Manifestation is exemplified by Item | 1 to M |
| R13 Res has appellation Nomen | 1 to M |
| R17 Nomen is derivation of Nomen | M to 1 |

R3 is the only many-to-many among the four structural entities, and it is what
makes a multi-track container expressible as one manifestation embodying several
parallel expressions.

Also binding, from §5.7: whole-part does not apply between an aggregating work
and the works it aggregates. Aggregation happens at expression level via R25.
From §5.8: a serial work does not have whole-part to its issues at work level;
they connect via the inspiration relationship, R21.

---

## 4. Standards referenced

IFLA LRM, 2024-07 edition, is adopted — see 3. PRESSOO is named by §5.8 for
implementations needing more depth on serials than LRM provides.

W3C Media Fragments URI is adopted as the base grammar for selector
serialization, extended with our own dimensions — see 2.21. RFC 9110 and
RFC 9457 govern the deletion responses in 2.13.

The rest are prior art, none adopted. W3C Web Annotation Data Model, whose
body-and-selector shape informed 2.21, and whose text-quote anchoring semantics
are a candidate alongside EPUB CFI and RFC 5147. OAIS /
ISO 14721. PREMIS. BagIt / RFC 8493. FFV1 / RFC 9043. JPEG XL lossless
recompression. PAR2. ZFS and Btrfs scrubbing. PRONOM, DROID, and Siegfried for
format identification. OIDC device authorization grant / RFC 8628. Library of
Congress Recommended Formats Statement, which updates annually and whose current
edition is unchecked.
