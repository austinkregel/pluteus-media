# Presentation

**Specification 10**
**Status:** Draft
**Version:** 0.3
**Depends on:** spec-01 (Catalog Data Model), spec-02 (Annotations and Derived
Data), spec-03 (Assets, Storage and Preservation), spec-04 (Ingest and
Normalization), spec-06 (Principals, Auth and Authorization), spec-07 (Wire
Protocol)
**Obsoletes:** nothing

## Abstract

spec-01 §7.4 places name resolution at a render boundary and does not say what
that boundary is. This document specifies it: what the catalog becomes when a
person looks at it, on a surface the deployment draws and on one it does not.

Three obligations follow from the model rather than from taste. Names resolve
per principal, so two members of one household see one holding under different
labels. Consumption is private, so no surface may be composed from more than
one principal's. And the catalog is full of gaps the household has not filled,
so the interface needs a vocabulary for what is not known as precise as its
vocabulary for what is.

---

## 1. Introduction

### 1.1 Scope

- The render boundary: what crosses it, and what MUST NOT
- Surfaces: the interface the deployment draws, and the television client it
  does not
- Absence, and the states an interface distinguishes
- Names at the point of display
- Browsing a catalog of many categories without ranking them
- Regions, deep links, and what a shared link opens
- Presentation assets: the derived artefacts a surface needs, as a closed set
  of named profiles
- Per-category presentation, and the transport contract
- Continuity, identity, correction, and the state of the holdings
- The accessibility floor, and what a household cannot supply
- The television client contract

### 1.2 What this document does not specify

The transcode decision and the streams it produces (spec-08); this document
names the profiles a surface may ask for, and spec-08 says how the bytes are
made. Search ranking, similarity and recommendation (spec-09); this document
specifies the search surface and what a result carries, not the order results
arrive in. Metadata matching (spec-05); this document presents the provenance
a match carries, and spec-05 says how the value was arrived at.

Wire form is spec-07's. Seven things this document needs are specified by the
documents that own the concepts rather than here; §19 says where each one lives.

The values of the design language are [ANNEX-A].

### 1.3 Implementation context

The interface is Phoenix LiveView: rendered on the server and patched into a
document over a WebSocket. Four obligations in §17.7 are broken by DOM
patching and by nothing else, and naming the mechanism is what makes them
enforceable.

The household's televisions run Roku, which has no browser, no embedded web
view and no web runtime. §4.3 and §18 are written against that.

### 1.4 What gates what

§5 through §17 govern the interface and build against spec-01 to spec-04,
spec-06 and spec-07 as they stand; §19 names the seven places this document
rests on a section of one of them.

One dependency runs outward and is not met: §18's playback waits on spec-08.
§8.1's default expression no longer waits on anything — spec-01 §6.5 carries the
significant attributes per category, so the ordering that section requires is
computable.

---

## 2. Conventions

BCP 14 key words per spec-01 §2.

*Surface* means one presentation of the catalog to a person, as §4 defines it.
*The interface* means the surface the deployment draws. *A client* means a
surface it does not. A normative statement is marked **[I]** where it binds the
interface only, **[C]** where it binds a client only, and is unmarked where it
binds both.

*Category* means the value a res carries under spec-01 §3.3's categorization,
written by placement under spec-04 §6.3. This document uses it in preference
to "media class", which spec-04 §5.3 defines as a property of an acquisition
record in the custody layer rather than of a res.

---

## 3. The render boundary

### 3.1 What crosses it

The render boundary is where the catalog stops being a set of relations and
becomes something a person perceives. spec-01 §7.4 places name resolution
there and requires it to be a pure function of the res and a profile.

Three further operations belong there because each depends on who is looking,
none may be stored, and all MUST be recomputed rather than cached against the
catalog:

| Operation | Depends on | Specified in |
| --- | --- | --- |
| Resolving a name | the principal's resolution profile | spec-01 §7.4, §6 |
| Selecting among parallel expressions | the principal's preferences | spec-01 §8.6, §5.3 |
| Attaching consumption | the requesting principal alone | spec-01 §11.2, spec-06 §6.3 |

A fourth operation belongs there for a different reason. **Stating absence**
(§5) does not depend on the principal; it belongs at the boundary because the
catalog's gaps are not rows and cannot be read from a field, so they must be
computed where the thing is rendered.

Everything upstream of the boundary is structure. Everything at it is a view.

### 3.2 Presentation is not stored as catalog

No operation at the render boundary writes to the catalog. A resolved name is
not persisted as a title, a selected expression is not recorded as the
preferred one, and a rendered absence is not recorded as a fact about the
holding.

spec-01 §7.1 forbids a title column, and a cache of resolved names keyed by
res is that column under another name: correct for one profile, stale for
every other, and wrong the moment a member adds a name. spec-01 §7.4's
determinism requirement makes the cache unnecessary as well as forbidden — the
same res and profile resolve alike on every call, so a result MAY be memoized
within one render and MUST NOT outlive it.

### 3.3 Two kinds of obligation

The deployment owes a surface it draws a design: the type, colour, focus,
motion and components of [ANNEX-A]. It owes a surface it does not draw a
contract: what the boundary emits, in what profiles, carrying what state.

These MUST NOT be conflated, and every normative statement in this document
carries the marking §2 defines.

---

## 4. Surfaces

### 4.1 Three surfaces

| Surface | Drawn by | Input | Specified by |
| --- | --- | --- | --- |
| The interface | the deployment | pointer, touch, keyboard | §4.2, [ANNEX-A] |
| The television | a client | a directional remote | §4.3, §18 |
| A music client | a third party | its own | spec-07 §6 |

A surface is not a screen size. It is a combination of who draws it, what
input reaches it, and how far away the person sits, and no two of those vary
independently enough for one layout to span them.

### 4.2 The interface

The interface is one Phoenix LiveView application served to a browser, and it
serves the phone, the tablet and the desktop. Those differ in width and in
pointer, and one responsive layout spans them because the viewing distance is
the same to within a factor of two.

**[I]** The interface MUST remain complete at a viewport of 320 CSS pixels
[WCAG22] §1.4.10 and MUST be operable by keyboard alone [WCAG22] §2.1.1. It
MUST NOT require hover for any function, since a touch surface has none.

### 4.3 The television

The deployment does not draw the television. The household's televisions are
Roku, which runs no general-purpose browser, no embedded web view and no web
runtime; the interface therefore cannot reach the television, and no
arrangement of the interface makes it reach.

This is an absence, not a degradation, and §5's rule applies to it as it
applies to a holding: the deployment states plainly that it does not draw this
surface rather than offering a diminished one.

The television is reached by a client the deployment serves under the contract
of §18, which is the arrangement spec-07 §6 makes for music.

### 4.4 Declaring a surface

A surface MUST be declared and MUST NOT be inferred.

No media query distinguishes a television from a desktop monitor. Both may
report the same width, neither reports its distance from the viewer, and
`pointer: coarse` is as true of a touchscreen at arm's length as of a remote
at three metres. The `tv` media type is specified to match nothing, and the
form-factor client hints define no television value. An interface that guesses
will guess wrong, and differently between two loads on one device.

The declaration is made when a device is bound to a principal (spec-06 §4) and
is recorded with the device. A principal MAY change it in one interaction.

**Where no declaration exists the surface is undetermined**, and the
deployment asks before it renders. It does not choose. A default here would be
a value substituted for data that should have been present, and the wrong
default is not recoverable by the person who cannot read what it produced.

---

## 5. Absence

### 5.1 The catalog is mostly holes

A household catalog is incomplete by nature. A photograph carries no
description and never will. A scanned letter has no author recorded until
someone recognizes the hand. A track's loudness is unmeasured because the tool
has not run. An asset's integrity is unknown because its interval has not
elapsed.

None of these is an error. Each is a different fact, and an interface that
renders them alike tells the household something false.

### 5.2 The states

Every value a surface can show is in exactly one of these states, and **a
surface MUST distinguish all seven**:

| State | Means | Established by |
| --- | --- | --- |
| **Held** | the value is known | the value |
| **Not held** | the household does not have the thing | zero digital items (spec-01 §5.2) or zero assets (spec-01 §5.5) |
| **Not yet examined** | no tool has looked | no derivation for the tool over this input (spec-02 §4.1) |
| **Attempted, failed** | a tool looked and could not | a finding at the current tool version (spec-04 §9) |
| **Sought, not found** | a person looked; it may be findable later | an authored annotation (spec-02 §3.2) |
| **Known unknowable** | it will not be recovered | an authored annotation |
| **Known absent** | the thing positively does not exist | an authored annotation |

The first four are established by the catalog and by the derivation record. The
last three are assertions a person makes and are never inferred from the
catalog's silence: a deployment MUST NOT report *sought, not found* where
nobody has looked, and MUST NOT report *known absent* where nothing has said
so.

Three pairs in that table are the ones an interface is most likely to
collapse, and each pair answers a different question:

- *Not yet examined* against *attempted, failed*. The first resolves itself;
  the second needs a person to clear it (spec-04 §9). A surface reporting
  "nothing here" while analysis is pending is worse than one reporting nothing.
- *Not yet examined* against *sought, not found*. The first is a question for
  the deployment; the second is a question for a person, and only a person can
  answer it.
- *Sought, not found* against *known absent*. The first invites the household
  to keep looking; the second closes the question. Rendering them alike either
  wastes effort or discards a fact.

The last three states are per field, and spec-01 to spec-04 record provenance
per row. spec-02 §6.5 is the body whose subject is a named field, which is what
carries them, and §20's registry names the fields one may be about.

A deployment MUST NOT render a field it cannot state the state of. A field the
registry does not name cannot carry one of the last three, and its absence is
rendered as *not yet examined*, which is true; the deployment says which fields
it can carry the others for.

### 5.3 Rendering an absence

An absence MUST be rendered in the place the value would have gone, in words,
as an assertion.

- A value not held MUST NOT be rendered as a default, a zero, an epoch date or
  an empty string that reads as a value.
- A res that resolution returns no displayable name for is named by §6.3.
- A partially known value MUST render with its partiality intact: a time-span
  known only to a decade renders as the decade. The partiality is carried by
  the time-span's own nomens under spec-01 §7.4, which is where spec-01 already
  puts calendar and date-format presentation.
- An absence MUST be available to assistive technology, not conveyed by
  emptiness. An empty cell is indistinguishable from a cell that failed to
  render.
- **[I]** A facet with no available values MUST still be shown, named and
  inert, rather than removed. Removing it changes the shape of the interface
  according to what the household happens to hold.

### 5.4 Placeholders

A placeholder derived from the thing it stands for is a low-fidelity rendering
of that thing and is permitted: a blurred approximation computed from an
image's own pixels asserts nothing the image does not. It is a loading state.

A placeholder invented where the thing does not exist is a fabrication and
MUST NOT be used. A generated cover for a release that has none asserts a fact
about the release. Where there is no image, the surface renders what the thing
*is* — its category and its name — which is true.

### 5.5 Absence on the wire

A representation MUST carry each field as a value and a state, rather than
carrying absence by omission. spec-07 §4.1 specifies the shape.

A client receiving no field cannot tell *not yet examined* from *attempted,
failed* from a field it does not understand, and will render one as another.

---

## 6. Names at the boundary

### 6.1 Resolution and the language step

Resolution is spec-01 §7.4's function, which returns exactly one nomen. This
section specifies its language step.

[IIIF-PRES] §4.4 gives a selection algorithm over language-tagged values. It
is adopted here **as a filter that narrows the candidate set**, after which
spec-01 §7.4's ordering chooses within it. Its clauses, in order:

1. Where every candidate has no language, all are candidates.
2. Where some candidates match the profile's language, only those are
   candidates.
3. Where **all** candidates have a language and none matches, the candidates
   are those of one language.
4. Where only some candidates have a language and none matches, the candidates
   are those carrying none.

Clause 4 is the household's commonest shape, because spec-01 §7.2 makes the
household's own vocabulary deliberately untagged. Clause 3 therefore requires
the word *all*: without it, clause 3 swallows clause 4 and a seeded name in a
language nobody asked for displaces the household's own.

[IIIF-PRES] leaves clause 3's choice of language to the client. This document
does not: the language chosen is that of the candidate the ordering would
select, so that the function stays deterministic. spec-01 §7.4 requires the
same res and profile to resolve alike across calls, and an unspecified choice
would break it.

Adopting the filter changes precedence. spec-01 §7.4's ordering puts a
personal nomen before a household one and treats language as a later
tiebreak; under the filter, language narrows first. That is a deliberate
change and it is stated rather than implied: a name in a language the person
cannot read is not a better answer for being personal.

**Resolution MUST be batched over a set of identifiers.** spec-01 §7.4
recommends this; this document requires it, because on a grid of two hundred
tiles it is not an optimisation.

### 6.2 What a result carries

**[I]** A result row or tile MUST carry three things:

1. The resolved name.
2. A disambiguating parenthetical wherever another res resolves to the same
   string for this profile. LRM's requirement is that homonymy be avoided, not
   synonymy; where the catalog holds a homonym, the interface resolves it.
3. **The nomen that matched**, whenever a search reached this res through a
   name other than the one displayed.

Without the third, a result that matched a name the person cannot see looks
like a defect. spec-01 §7.4 confines resolution to output and leaves search
free to match every nomen a res carries; this is the other half of that rule.

### 6.3 The composed name

spec-01 §4.1 makes the primary identifier a nomen, and spec-01 §7.4 forbids
falling back to it. A res whose only nomens are that identifier-nomen, or
whose nomens the profile excludes, therefore satisfies LRM-R13 and still has
nothing displayable. Every reified address and every annotation is in this
position by construction (spec-01 §6.1).

For such a res the surface composes a name from the entities it is related to
— the agents credited on it, the place, the time-span — and from its kind:

> A photograph, at Bridgeport, with Eleanor and Thomas, in July 2009.

The composition degrades as relations are absent. **Its terminal is a noun for
the res's kind** — a name, a region, a note, a photograph — which is always
available because kind is a non-null property of every res.

The composed name is not a nomen. It MUST NOT be written to the catalog, and
resolution's contract is untouched: resolution returned nothing displayable,
and this is what the surface shows instead. It is also the accessible name for
the same res, so one string serves both.

The composed name MUST be carried in the representation (spec-07 §4.1), so that
a client does not have to compose it from bare identifiers.

### 6.4 Sorting

Where a res is ordered by name, the ordering nomen is a nomen of its own, in
the scheme §20 names. A transliteration MUST NOT be generated: spec-01 §7.2
forbids inferring a language, and the same reasoning forbids inferring a
reading.

Where a res carries several ordering nomens, §6.1 chooses among them. **Where a
res carries none, it is ordered by its resolved nomen and the surface says so**
— which is honest, costs nothing, and is the only available answer while no
ingest path writes an ordering nomen.

---

## 7. Interface language and direction

**[I]** The interface's own words — labels, absence statements (§5.3), the
composed name (§6.3) — are rendered in the requesting principal's resolution
profile language where the deployment has a translation, and in the
deployment's configured language otherwise. The surface MUST NOT render its own
words in one language and an absence statement in another.

Because §6.1 selects nomens across languages and §6.4 forbids generating a
transliteration, a name in a right-to-left or vertical script WILL be
displayed. A surface MUST therefore set the direction of a rendered nomen from
the nomen's own script rather than from the surface's language, and MUST use
direction-relative rather than side-absolute layout.

---

## 8. What the interface shows a thing as

### 8.1 The browse entry is the outermost res

A person believes there is one film, and one series rather than two hundred
episodes. The catalog holds a work per episode, several expressions per film,
and a serial work connected to its episodes only by inspiration (spec-01 §5.4).
Both are true, and the interface MUST honour the first without discarding the
second.

**A res is a browse entry where no other res in the catalog presents it.** A
res is presented by another where:

- an aggregating work selects its expression (spec-01 §5.3, LRM-R25), or
- its manifestation is a part under a whole-part relation (spec-01 §5.4,
  §12.1, LRM-R26).

So a release carries the entry and its tracks do not. A complete serial
manifestation carries the entry and its seasons and episodes do not — which is
what spec-01 §5.4 means by episode structure living at manifestation level,
and what spec-01 Annex A §A.3 means in quoting LRM that a serial work "can be
said to have only one expression and only one manifestation".

**[I]** The primary action MUST resolve to a specific expression and digital
item without asking. Choosing MUST NOT be a precondition of acting. The
alternatives MUST be reachable in one action from the same place, and that
action MUST state how many there are.

The ordering is spec-01 §8.6's: distance from the representative expression
(spec-01 §6.5), under the requesting principal's profile. spec-01 §8.6
recommends that ordering; this document requires it.

spec-01 §6.5 carries the significant attributes per category, so the distance
that ordering rests on is computable. Where §6.5's automatic promotion applies —
one expression in one manifestation, which is most of a household's own media —
that expression is the default and no ordering is needed. Where a work has
several and the category's attributes do not separate them, the default is the
expression spec-01 §8.6's parallel-expression selection yields for the profile,
and where that is silent the surface asks once and records the answer as an
authored preference. It does not guess.

Where the resolved expression differs from the profile's preference, the
surface SHOULD say so unobtrusively; spec-01 §8.6 makes this a display concern
rather than an error.

The default MUST NOT come from an aggregate over what the household has played,
which spec-06 §6.3 forbids and which no member could predict or correct.

### 8.2 Alternatives are a list, not a grid

**[I]** The set of expressions and manifestations of one work is presented as
a list, ordered, each line described by **what distinguishes it** — language,
cut, colour, carrier, scan — and not by a repeated name. Where an alternative
carries a name of its own that differs, that name is shown: two editions
published under different titles are otherwise indistinguishable.

A grid is for browsing; comparing four cuts of a film is not browsing.

### 8.3 Ordered groupings

A release, a complete serial manifestation and its seasons, an anthology, a
photograph album and a correspondence file share one page template, because
each is **a res carrying ordered members**.

The order is where spec-01 §12.1 puts it, and that differs by shape:

| Shape | Order lives on |
| --- | --- |
| a release and its media and tracks | the LRM-R26 whole-part positions |
| a serial manifestation and its seasons and episodes | the LRM-R26 whole-part positions |
| an aggregate with no such structure | the LRM-R25 aggregation's arrangement |

spec-01 §5.3 forbids whole-part between an aggregating work and what it
aggregates, and spec-01 §5.4 forbids it between a serial work and its episodes
at work level. The template therefore renders *positions on whichever relation
carries them*, and the deployment MUST NOT present one relation's positions as
the other's.

**[I]** The interface MAY say that a release has twelve tracks and a season
eight episodes. The word is containment and the data is arrangement, and
nothing is lost by saying it the way a person would.

A household-composed sequence is spec-01 §12.1's aggregate "with no such
structure, such as a sequence the household composes", and renders through the
same template. **It is not spec-07 §6.6's playlist**, which is one principal's
consumption data, lives outside the catalog, and is never household-visible. A
surface MUST NOT present the two as one thing.

### 8.4 An entity's page

**[I]** One template serves every res that has an interface page (§9.1). Its
bands are ordered, and a band with nothing in it is absent rather than empty:

| Band | Carries |
| --- | --- |
| 1 Identity | the resolved name (§6.1), its disambiguation and matched-as (§6.2), and what kind of thing this is |
| 2 The action | one primary action, resolved per §8.1, and the count of alternatives |
| 3 The thing | the poster, scan, waveform, key frame, first page — the medium itself |
| 4 Facts | a short list, omitting what is unknown unless the unknown is worth asserting (§5.3) |
| 5 Structure | the ordered members (§8.3), and the expressions, manifestations, digital items and assets (§8.2) |
| 6 Connections | lateral links, each labelled with the relationship it travels on (§9.4) |
| 7 Annotations | authored first and attributed, derived below and labelled with its tool and version (spec-02 §4.1, §4.2) |

Bands 1 to 3 are reachable without scrolling on every surface. Bands 4 to 7
are progressive disclosure on the same page. There MUST NOT be a second
interface for the model.

A reified address (spec-01 §8.2) is a res and gets this page, with the res it
addresses as its band 5. A named thirty seconds of a home video is a thing the
household can reach, name and talk about.

### 8.5 Level vocabulary is not a label

**[I]** The words *work*, *expression*, *manifestation*, *item*, *digital
item*, *res* and *asset* MUST NOT be used as a navigation label, a heading, a
control's name or a column header.

They are the model's vocabulary and are opaque even to motivated readers. The
interface says *versions*, *copies*, *scans*, *editions*, *tracks*. The rule
governs labels rather than running prose, because a rule against the string
would fail on *artwork* and on *does this work*.

---

## 9. Browsing and searching

### 9.1 Which res have an interface page

**[I]** The res kinds that content-negotiate to an interface page (§10.1) are
works, expressions, manifestations, items, digital items, agents, places,
time-spans and reified addresses.

Nomens, annotations and assets do not. A nomen has no poster, no action and no
members, and spec-03 §10 asks that an asset's location not be exposed on a
reachable surface. They remain reachable as JSON under spec-07 §4.1, and they
appear in the interface as part of the res they belong to.

### 9.2 The top level

**[I]** The top level MUST NOT be a list of categories, and MUST NOT be
reachable only through one. The modes are:

| Mode | Is |
| --- | --- |
| **Continue** | the requesting principal's own resume list (§13.4) |
| **Recently added** | the catalog by acquisition time |
| **People** | agents with holdings |
| **Places** | places, as a list and as a map |
| **Time** | a spine over time-spans, with a counted **Undated** bucket |
| **Sets** | every res carrying ordered members (§8.3) |
| **Everything** | the whole catalog, faceted |

Continue is a mode and not a subordinate surface: it is the most-used entry
point in a household media system, and burying it would be a design defect
dressed as a principle.

**[I]** Every mode's surface MUST carry the category facet as a first-class
control, not as one facet among many. The prohibition in this section is on
category as the *only* axis, which forces every capability to be built per
category and cannot answer "everything from 1994". It is not a prohibition on
reaching a film by asking for films, which is the commonest thing a household
does and MUST be short.

A mode MAY be hidden per principal. Hiding a mode MUST NOT hide content.

Where an index would be too long to be an index — People, after credits
resolve, holds every credited artist — a mode MAY bound its index by the
facets §20 names, provided every res excluded remains reachable by search and
by lateral movement (§9.4).

### 9.3 Facets

**[I]** Every mode resolves to one faceted surface. Facets are disjunctive
within a facet and conjunctive across facets.

- Every facet value MUST carry a count computed against the current query. A
  count not recomputed is a false statement about what selecting it will do.
- A facet with no available values MUST still be named and shown inert (§5.3).
- Each active facet MUST be removable independently.
- Results MUST be visible without scrolling past the facets.

### 9.4 Lateral movement

Every relationship a res carries is a link to the set of res sharing it, and
the link MUST state the relationship it travels on: *also written from this
place*, *also credited to this person*, *the previous letter in this exchange*.

This is the only "more like this" spec-06 §6.3 permits, and it is better than
the forbidden kind: computed from the catalog rather than from behaviour, every
result explained by the property it shares, and predictable before acting.

### 9.5 The search surface

**[I]** Search is its own surface and does not share a results page with the
browse modes. Browsing is exploration with no stated goal and wants rich,
image-led results; searching is a stated goal and wants dense, scannable ones.

The search surface MUST match every nomen a res carries (spec-01 §7.4) and
MUST carry §6.2's three slots on every result. It MUST be reachable from every
mode, and reaching it MUST NOT discard an active facet set: a query is one more
term over the current selection, and §9.3's chips carry it.

Ranking is spec-09's. Until spec-09, results are ordered by the ordering of
§6.4 and the surface says so.

---

## 10. Regions, links and arrival

### 10.1 One address, two representations

spec-01 §9 makes the entity URI a permanent public address and the carrier of
a deep link. spec-07 §4.1 makes the same URI a representation. A person sent
`/expressions/{uuid}?t=140,148` MUST arrive somewhere they can watch it.

The entity URI therefore serves both, for the kinds §9.1 names. A request
whose `Accept` header contains `text/html` renders the interface positioned at
the selector; every other request returns the representation spec-07 §4.1
specifies, unchanged.

**The negotiation MUST be on the presence of `text/html` in the header, not on
a media-type preference list.** A framework accept-negotiation that treats
`*/*` as matching HTML will serve HTML to every programmatic client, because
`*/*` is what a command-line client, a fetch call and most HTTP libraries send
by default. An explicit `_format` parameter MUST be honoured where a client
cannot control its header, and a selector parser MUST ignore query parameters
that name no selector dimension, as spec-07's already does for a resolution
profile's.

**No second address for one res may be introduced.** Interface surfaces that
are not a res — a mode, the findings surface — have paths of their own; what is
forbidden is a second path that resolves to a res that already has one.

### 10.2 What a link opens

**[I]** A surface reached by a link carrying a selector MUST:

- open positioned at the region, not at the beginning of the res;
- **show** the region and not merely scroll to it — a band on the scrub bar, an
  outline on the scan, a highlight in the text — since a recipient who cannot
  see what they were sent has not received it;
- carry enough of band 1 (§8.4) to say what the thing is;
- offer one control that leaves the region for the whole;
- not begin playback. A link opened on a phone in a quiet room that starts
  making noise is a hostile artefact.

### 10.3 A link that no longer resolves

Where the medium has been replaced and a text-quote anchor no longer matches,
the surface MUST say that the link pointed at a passage that is no longer
present. It MUST NOT silently land at the beginning.

spec-01 §8.5 prefers a text-quote anchor to an offset, and this is why: an
offset that has drifted still resolves, to the wrong text, undetectably. A
quote that has drifted fails to match, visibly. The durable anchor is the one
that fails loudly.

### 10.4 What travels

A link the deployment emits MUST carry its selector in a basis spec-01 §8.4
permits.

spec-01 §9.1 admits exactly one selector of one type per link. Where the
durable anchor for a text range is a quote and the stored selector is a
position, the deployment emits the quote selector; where both are wanted, they
are two links and the surface says which is which.

---

## 11. Presentation assets

### 11.1 Profiles are a closed set

A presentation asset is a derived asset in spec-01 §5.5's sense: regenerable,
never backed up (spec-01 §13.7), never a digital item.

A surface MUST request a presentation asset by **profile name** from §20's
registry, and MUST NOT request arbitrary dimensions. An endpoint accepting
arbitrary dimensions is an unbounded transcoder addressable by anyone who can
construct a query string.

This answers what spec-07 §6.7 defers. On the OpenSubsonic surface, where the
protocol's `getCoverArt` carries an integer `size`, that integer maps to the
smallest profile at or above it, and the response carries the profile name in
the header spec-07 §4.6 defines. On every other surface an arbitrary dimension
is refused.

### 11.2 Still images

Image profiles are the graded widths §20 names. Beyond the threshold §20 names,
a scan is served as a tiled pyramid under the [IIIF-IMAGE] URL grammar.

That grammar's bare region form is absolute pixels, which spec-01 §8.4 forbids
as an addressing basis. **spec-01 §8.4 governs stored selectors, which must
survive a re-encode; a display-time crop against a named derivative is not
one.** The deployment MUST accept the percentage region form, MUST be able to
translate between `/pct:25,25,50,50/…` and `?xywh=percent:25,25,50,50`, and
MUST NOT store a pixel region as a selector.

Adopting the grammar is not a route: it is region, size, rotation, quality and
format parsing, an information document, a declared compliance level, and a
pyramid generator. It is worth it for the scans and is not required below the
threshold, where a graded profile set is smaller and simpler.

**Geometry before bytes.** A surface MUST know a visual res's intrinsic
dimensions and aspect ratio before it fetches an image, so that a rendered
collection does not shift as images arrive.

Those dimensions are the probe's, which spec-04 §5.1 already records as a
derived annotation on the manifestation. This document does not reclassify
them: it requires that they be **queryable from the catalog layer in one
batched call**, alongside the names §6.1 resolves. A work's tile takes the
geometry of the manifestation §8.1 resolves for it.

Where the probe has not run, the geometry is *not yet examined* (§5.2) and the
surface MUST reserve a box of the aspect ratio §20 names for the category
rather than collapsing to zero.

Every derivative MUST have its orientation applied and its orientation
metadata removed, and MUST be converted to a known colour space. A derivative
requiring its consumer to reapply an orientation will be displayed rotated.

All region coordinates are expressed against the display orientation.

### 11.3 Moving image

| Artefact | Carries | Required |
| --- | --- | --- |
| Key frame | one still, for the poster position and a link preview | yes |
| Trickplay | frames at a fixed interval, tiled, with an index from time to tile and rectangle | yes |
| Chapter list | titles and time ranges, from container chapters where present | where present |
| Segment markers | detected intro, recap and credit ranges | no |

Trickplay frames are extracted once and MAY be packaged more than once: the
interval and width §20 names serve both the interface's tiles and a client's
own packaging from one extraction.

Segment markers are optional because detecting them needs a whole season's
corpus and cross-holding comparison, which §11.6's on-demand default does not
fit. Where they have not been derived, the skip affordance is absent under
§17.2's rule for a control with nothing behind it.

A detected marker is a derived annotation on a time range (spec-02),
superseded by a newer version of the same tool and replaced by a re-run at the
same version (spec-02 §5.2). It MUST NOT be the anchor for anything a person
asserts (spec-02 §3.3).

**[I]** Where a skip affordance is offered it MUST appear only while the
playhead is inside the segment, MUST NOT take focus, and MUST be undoable.

### 11.4 Audio

Two waveform artefacts with different scaling laws, which MUST NOT be
conflated:

- An **overview** of the fixed point count §20 names, independent of duration.
  It is a constant few kilobytes for a track or a nine-hour recording, and it
  is what a transport bar draws.
- A **detail** waveform whose size scales with duration, generated on demand
  and evictable, for inspecting a region.

A waveform declares its own resolution, and a surface MUST NOT offer a zoom
finer than the stored artefact supports. Decimating a stored waveform is
correct; interpolating one draws a shape the audio does not have.

### 11.5 Text

| Artefact | Carries |
| --- | --- |
| Extracted text | normalised text, the substrate for search and for anchors |
| Word positions | per-word regions on a scan, for overlay and correspondence |
| Position list | an exhaustive integer index over a publication |

A position list exists because reflowable text has no stable coordinate until
a viewport exists. It is what makes "a third of the way through" answerable
without the answer changing when the reader changes the font size.

### 11.6 Generation, retention and eviction

A presentation asset MAY be generated at ingest where it is cheap and
universally needed, and is generated on demand otherwise. spec-01 §13.6's
prohibition on pre-generation governs playback renditions; it names thumbnails,
waveforms and sprite sheets as outside it, and a tiled trickplay sheet is a
sprite sheet in spec-01 §5.5's sense.

Every presentation asset MUST be evictable under a bounded policy, its absence
MUST NOT be an error (§16), and **the eviction MUST be observable as having
run**, because a timer that silently fails fills a disk and the failure is
invisible until it is total.

---

## 12. Per-category presentation

### 12.1 Surfaces and assets

The categories below are the values spec-04 §6.3's registry writes on
placement. §20 names the registry and holds this table's values; what follows
is the shape it takes.

| Category | Primary surface | Selectors | Requires |
| --- | --- | --- | --- |
| music recording | transport and queue | `temporal`, `track` | overview waveform, cover profiles |
| film, television episode, home video | player | `temporal`, `spatiotemporal`, `track` | key frame, trickplay, chapters |
| photograph | viewer in a justified grid | `spatial` | image profiles, geometry |
| scan | scan beside its transcript | `spatial`, `page`, `text_quote` | image profiles or tiles, word positions |
| document, ebook | reader | `text_quote`, `text_position`, `page` | extracted text, position list |
| companion kinds | never its own surface | — | — |

### 12.2 Three rules across all of them

**Choosing a variant and displaying it are separate state.** Turning subtitles
off MUST NOT forget which subtitle track was chosen; closing a transcript MUST
NOT forget which transcript. spec-01 §8.6 forbids collapsing audio selection,
subtitle selection and subtitle visibility into one preference.

**A companion is never presented as a holding.** spec-04 §4.6 catalogues a
cover, a lyric file, a subtitle and a sidecar as holdings of their own so that
ingest does not mistake them; the render boundary presents them as properties
of what they describe. A cover image MUST NOT appear in a photograph grid.

**A track of a release held in one file is the stored temporal address spec-04
§6.4 records on the release manifestation.** The coordinate frame is the
medium; track coordinates are projected from that address at the surface.
Playing track four is a range-limited play of the medium, not a separate
stream.

### 12.3 The transport

**[I]** A surface that plays time-based media MUST provide:

| Control | Obligation |
| --- | --- |
| play and pause | one control whose accessible name states the action it will perform |
| position | a slider carrying its minimum, maximum, current value and a human-readable value; steps of the two granularities §20 names; home and end |
| skip | where offered, an interval stated in the control's name |
| audio track, subtitle track, subtitle visibility | three independent controls (§12.2) |
| volume and mute | a non-drag path, since no function may require dragging (§17.5) |
| what happens at the end | stated in §12.4 |

The position slider MUST NOT be inside a live region (§17.7). It MUST NOT be
the only way to seek: a non-drag path is required, and on a directional remote
seeking is a repeated key rather than a gesture.

A queue is a res-ordered list belonging to the requesting principal. It MUST
support appending, inserting next, removing, reordering, clearing and jumping
to an entry, and each entry MUST record what it was queued from, so that
"clear the rest of this release" is answerable without guessing. Where a
principal's queue is also exposed on the OpenSubsonic surface, spec-07 §6.5's
play queue is the same object and the two MUST NOT diverge.

### 12.4 At the end

**[I]** Where the played res is a member of an ordered grouping (§8.3) and a
next member exists, the surface offers it. The offer MUST carry a visible
interval before it acts, MUST be cancellable, and MUST be disableable per
principal. Audio MUST NOT begin without a person having asked.

---

## 13. Continuity

### 13.1 Position is a fact about a person

A resume position is consumption data (spec-01 §11), belongs to its principal,
and lives on the server. Every surface reports it; no surface owns it.

A position records the principal, the res, the device, the position in the
medium's own unit, that unit, when it was reported, a per-session sequence, and
whether the reporting session was playing. The device is part of its identity,
because §13.3 keeps two of them.

spec-01 §11.4 records exactly these, one per device rather than one per res.
This section is what they are for.

### 13.2 Thresholds

A position below a floor is discarded: the person did not really start. Above
a ceiling it is discarded and the res is recorded as consumed. A res below a
minimum length never carries a position.

The floor and ceiling are proportions for short media and absolute quantities
for long ones, because a proportion of a long work is not a small amount: five
per cent of a nine-hundred-page novel is forty-five pages, which is a real
resume. §20 holds the values and says which regime each category uses.

### 13.3 Conflict

Two devices reporting different positions for one principal and one res is the
ordinary case, not the error case.

- The most recent report from a session that was **playing** wins. A paused
  session's position is a statement about the past; a playing session's is a
  statement about the present.
- Furthest-position-wins MUST NOT be used: an accidental scrub to the end would
  be unrecoverable.
- Last-writer-wins alone MUST NOT be used. A report is ordered by its recorded
  time and its session sequence, and **a live report from a session idle
  beyond the reporting interval is ignored**.
- **A report flushed from a declared offline queue is not a live report.** It
  carries its original time and sequence and is ordered by them (§16). The idle
  rule would otherwise discard exactly the reports §16 exists to preserve.
- Where two sessions are playing one res at once, both positions stand, each
  attributed to its device.
- A resume that would move the position backwards by more than the threshold
  §20 names MUST say so rather than jumping silently, naming where each
  position came from.

### 13.4 The continue surface

**[I]** One surface answers what the requesting principal was in the middle of.

It MUST be ordered by that principal's own most recent interaction,
descending. Every other ordering is a judgement about what a person should
return to, computed from their behaviour; recency is a fact the person
generated and can predict.

- It MUST be composed from the requesting principal's consumption alone
  (spec-06 §6.3).
- Each entry MUST state its position in the medium's own unit — a time of a
  duration, a page of a count, a track of a release — and MUST NOT state a
  proportion **across** entries. A proportion within an entry is a fact about
  that res; a proportion compared between a novel and a film is a ranking.
- Where §13.3 holds two positions for one res, the surface renders one entry
  and names the device of the winning position.
- An entry MUST be dismissable, permanently and silently.
- A res with no position has no entry, **except** the next member in
  arrangement order after a consumed member of an ordered grouping (§8.3).
  That is a catalog fact, fully predictable and explained by the property it
  travels on, of the kind §9.4 already permits — not a ranking. It is the
  next episode, and excluding it would remove the most valuable thing this
  surface does.

---

## 14. Identity at the boundary

### 14.1 Who is looking

spec-06 §4 forbids a shared or ambient session and requires every playback to
be attributable to a principal. The render boundary is where that is honoured
or quietly lost.

Every surface MUST state, continuously and without being asked, which
principal it is acting as. A person who cannot see whose session they are in
cannot know their viewing is being recorded against someone else.

### 14.2 Switching

Switching principal MUST be reachable from every surface and MUST NOT require
entering a credential on a surface with no keyboard.

spec-06 §4 requires the switch be "cheap enough that people actually do it",
and states the reason: otherwise one principal's history silently absorbs the
household's. A surface that makes switching expensive corrupts the record
spec-01 §11 exists to keep.

Switching is distinct from enrolling. Switching selects among principals the
surface may already act as; enrolling establishes that it may. A surface shared
by the household SHOULD return to the choice of principal after the period §20
names.

### 14.3 One principal per surface

No surface may be composed from more than one principal's consumption
(spec-06 §6.3). At the render boundary this binds a list of what is in
progress, a play count, any ordering computed from consumption, and any
household total at any granularity.

A surface not composed from consumption — the catalog, names, annotations — is
household-visible, as spec-01 §7.3 and spec-02 §10 establish. **[I]** An
interface SHOULD make that visibility evident where a person contributes
something personal, such as a face tag, since spec-02 §10 identifies it as the
second case where a personal contribution is household-visible by default.

### 14.4 Control from another surface

A principal MAY drive playback on another surface. The playback is attributed
to the principal the **playing** surface is acting as, never to the one that
sent the command.

Otherwise attribution launders: a person could record their viewing against
someone else by driving that person's session. Where the two differ, the
sending surface MUST say whose session it is about to act on before it acts.

### 14.5 Preferences that reveal

A principal's caption styling, motion preference, contrast preference, text
size and described-audio default are that principal's and MUST NOT be visible
to another. They are not consumption data, but they disclose a disability as
directly as a play history discloses a taste.

Where a surface's platform holds these settings device-wide (§17.3), that
guarantee does not reach it. The deployment MUST NOT write a principal's stored
preference into a device-wide setting, and §21 records the residual exposure.

---

## 15. Correction at the boundary

### 15.1 Correction happens where the error is seen

spec-04 §6.2 makes every name and category placement writes provisional, and
spec-01 §7.5 makes a member's correction outrank it. That mechanism is worth
nothing if the correction is hard to reach.

**[I] A value displayed with automatic provenance MUST be correctable from
where it is displayed.** Not from an editing mode, not from an administrative
screen.

Nobody goes looking for errors in a catalog. They meet them while doing
something else — playing a record and seeing the wrong artist, opening a scan
and recognizing the hand. A correction path that requires leaving what they
were doing is a correction that does not happen.

### 15.2 Three tiers over one model

| Tier | Is | Available on |
| --- | --- | --- |
| a question | a yes-or-no answer, asked beside the thing | every surface |
| a field | one value, edited in place | the interface |
| an editor | the full annotation | the interface |

A one-confirm answer MUST produce an authored annotation identical in kind to
one made in the editor, with the same provenance (spec-02 §3.4). The first tier
MUST NOT be gated behind the third.

An accepted correction MUST be acknowledged visibly. In a household of a few
people, what sustains the naming of faces is that the naming changed
something.

### 15.3 Provenance is visible

A surface MUST distinguish a value a person asserted from a value a tool
produced wherever both are possible. spec-02 §3.2 makes the distinction
structural, and it is the household's only means of calibrating trust. A
machine transcript presented as a transcript is a claim the deployment cannot
support.

A derived value MUST NOT be presented in a way that implies authorship, and a
derived value MUST NOT overwrite an authored one (spec-02 §5.3). Correcting a
derived value produces an authored one, which then outranks every later run of
the tool.

### 15.4 What is correctable

At minimum, from where each is shown: a name (spec-01 §7), a category (spec-01
§7.5), a credit (spec-04 §6.4), a duplicate candidate's decision (spec-03
§8.3), a face or region annotation (spec-02), an agent's narrowing (spec-01
§3.1), and a finding's clearing (spec-04 §9).

An agent's person-or-group nature MUST NOT be asked as a taxonomy. It is asked
only where an operation needs it, phrased as the operation.

---

## 16. The state of the holdings

### 16.1 Nothing is hidden

The deployment knows things the household does not: an asset unverified past
its interval (spec-03 §5.3), an acquisition that could not be placed (spec-04
§9), a companion in a directory that produced two releases and so was linked
to neither (spec-04 §4.6), a tool that failed, a digital item whose every copy
is lost (spec-01 §5.5).

Each is already required to be recorded. This section requires it be shown. A
finding recorded in a table nobody renders is a finding the household does not
have.

**[I]** The interface MUST carry a surface on which every open finding is
visible, and each MUST state what was attempted, what happened, and what may
be done. A finding MUST NOT be summarized into a count that conceals which
holdings are affected.

### 16.2 A finding belongs on its holding

**[I]** A finding MUST also be visible on the res it concerns. A person
looking at a scan does not first consult a list of problems.

### 16.3 Unverified is a third state

spec-03 §5.3 makes *unverified* distinct from *corrupt*: it means the household
does not currently know. A surface MUST render it as that third thing and MUST
NOT render an unverified asset as sound.

---

## 17. Degradation and accessibility

### 17.1 Degradation

| Condition | Behaviour |
| --- | --- |
| A presentation asset is absent | degrade visibly and continue: a scrub bar without thumbnails, a flat colour without a placeholder, a transport without a waveform |
| A source medium is absent | surface it loudly. This is data loss, not a missing derivative |
| The connection drops with media buffered | keep playing; show a persistent, non-modal notice; queue position reports |
| The buffer empties and the deployment is unreachable | stop, and say the deployment is unreachable — not a spinner, and not "something went wrong" |
| The connection returns | flush queued position reports as §13.3 requires |
| A rendition fails mid-stream | surface the failure and its reason. Do not silently restart |

A presentation asset's absence is a designed condition because spec-03 §7
declares it regenerable and excludes it from backup. A source's absence is not,
because spec-03 §7 requires it backed up. The interface's behaviour differs for
the reason the backup policy differs.

A silent retry that hides a persistent failure behind eventual success is
forbidden.

### 17.2 The conformance floor

**[I]** The interface MUST conform to [WCAG22] Level AA **for every success
criterion outside Guideline 1.2**, and MUST additionally satisfy [WCAG22]
§2.4.13 Focus Appearance, which is Level AAA and which keyboard navigation
needs. **[C]** A television client MUST satisfy §2.4.13 too, where focus is the
cursor rather than a hint.

**The deployment MUST NOT publish a bare Level AA conformance claim.** WCAG
conformance is all-or-nothing at the claimed level, and §17.3 declines
Guideline 1.2, which contains criteria at A and AA. A claim names Guideline 1.2
as excluded scope, names §17.3 as what replaces it, and names the surfaces and
view types assessed and the combinations untested.

### 17.3 What the household cannot supply

Guideline 1.2 is an obligation on content, and this deployment presents content
the household did not author and will not caption. A home video has no caption
file and nobody will write one. A specification demanding captions for all
video would be false on the day it shipped.

The obligation that survives is representational, and it is strict:

- Every accessibility affordance a res carries MUST be recorded, and its
  absence recorded as an absence, distinctly from *not yet examined* (§5.2).
- A control for an affordance that does not exist MUST be rendered disabled and
  MUST carry a description saying why. A captions control that is available and
  does nothing is a lie told by an interface.
- Affordances MUST be filterable, so "what here has subtitles" is answerable.
- The deployment MUST NOT assert an affordance or a hazard it has not
  established. The default is *not yet examined*, never a negation.

The one criterion the household can discharge is a text alternative for its own
media. **[I]** The interface SHOULD invite one by §15.2's second tier at the
point the holding is viewed; it is free text, so §15.2's first tier does not
carry it, and §18.6 keeps it off the television.

### 17.4 Captions and subtitles

A text track MUST carry a classification from §20's registry — captions,
subtitles, SDH, forced, commentary, unknown — derived from container flags
where present, with the derivation's source recorded. The picker MUST show the
classification beside the language, MUST NOT merge distinct classifications of
one language, and MUST show unknown as unknown rather than guessing.

These are different products under one language label. A person who cannot hear,
offered "English" and given a plain subtitle track, loses every cue the plot
turns on.

A bitmap subtitle track produces no text. It MUST be labelled as image-based,
MUST NOT count toward any conformance claim, and MUST NOT be burned into a
rendition as its only presentation, since that removes the ability to turn it
off.

**[I]** Caption presentation MUST be adjustable by the person, persisted per
principal (§14.5), and previewed against real content. **[C]** Where a client's
platform owns caption styling device-wide, the client MUST use the platform's
settings and MUST NOT build its own; §14.5's guarantee does not reach that
surface.

### 17.5 Operability without a pointer

Every function MUST be operable by keyboard alone, and every function on a
surface reached by a remote MUST be operable with four directions, a confirm
and a back.

That six-key floor is the poorest input the system serves, and designing to it
makes the television case and the keyboard case one case.

- No function may require dragging. Seeking, volume, ranges and reordering each
  need a non-drag path.
- Pointer targets are at least 24 by 24 CSS pixels or satisfy an exception of
  [WCAG22] §2.5.8; the design targets are [ANNEX-A]'s.
- Single-character shortcuts MUST be scoped to the focused component, MUST NOT
  fire while focus is in a text field or a type-ahead, and MUST be disableable.
- Focus MUST NOT be moved except as the direct result of a person's action.
- Every overlay MUST close on a back or escape and MUST return focus to what
  opened it.

### 17.6 Collections

**[I]** A collection MUST be traversable by an explicit control that does not
depend on scroll position; scroll-triggered loading is an enhancement over it.

Each entry MUST carry its position within the rendered window and the total
size of the set. **A position within the whole set is not required**, because
spec-07 §4.2 forbids offset paging and computing a global rank on every page of
a large collection reintroduces the cost keyset paging was chosen to avoid.

Every collection MUST offer at least one non-sequential path — search, a
filter, a jump — because no annotation makes sequential traversal of twenty
thousand photographs usable. The accessible affordance for a large collection
is skipping.

### 17.7 Server-rendered patching

**[I]** The interface is patched into a live document (§1.3). Four obligations
are broken by that mechanism and by nothing else, and they are invisible to
automated checks and to sighted people using a pointer.

**Focus survives a patch.** Phoenix LiveView 1.1 protects only a focused form
input — an `input`, `select` or `textarea` — from being patched, and restores
focus only to a select or a textual input. A focused button, link or
`tabindex` element is neither protected nor restored, and a focused element
inside a stream the server removes is deleted outright whatever its identity.

The deployment MUST therefore:

- give every focusable element a stable, content-derived identity;
- record the focused element's identity on the client and restore it after a
  patch, a route change and a reconnection, since a reconnection remounts and
  no server rule survives it;
- where the focused element is gone, move focus to the nearest surviving
  sibling in document order, failing that its container, failing that the
  surface's first focusable — **in that order**, so that two implementations
  agree;
- hold this in the client hook that records the identity, which is the
  assertion point.

**A live region exists before it speaks.** A region rendered conditionally,
appearing in the same patch as its content, is frequently not announced,
because it did not exist to be observed. Live regions MUST be rendered
unconditionally and empty, and messages inserted into them.

**A live region is not a telemetry channel.** Playback position, buffer state
and scan progress MUST be rendered outside any live region, and the position
slider MUST NOT be inside one: its value is announced when a person moves it,
and a live region makes it announce continuously.

**An unchanged message does not re-announce.** Announcement content MUST be
computed so that re-rendering an unchanged message produces no change.

### 17.8 Motion and hazard

Under a reduced-motion preference, transform-based animation, parallax,
auto-advance and automatic preview MUST be disabled; short opacity transitions
MAY remain, since a change of opacity is not motion.

Anything that moves automatically for more than a few seconds alongside other
content MUST have a control to pause it — an auto-scrolling lyric pane, an
advancing slideshow, an animated backdrop alike.

Automatic preview of a holding on hover or focus MUST default off, MUST be a
per-principal preference, MUST be suppressed under reduced motion regardless of
that preference, MUST start silent, MUST be dismissable, and **MUST NOT record
a consumption event**. A preview that writes history turns a glance into a fact
about a person.

The deployment cannot inspect content for photosensitive hazards. A hazard is
*not yet examined* by default, never negated, and recordable once by a member
for everyone.

### 17.9 Colour

Text MUST meet [WCAG22] §1.4.3, and interface components and meaningful
graphics MUST meet §1.4.11, by the WCAG 2 relative-luminance formula. The dark
theme's additional floor, and the instrument that measures it, are [ANNEX-A]
A.2.4.

No information may be carried by colour alone.

Under forced colours a shadow computes to none, so focus indication MUST be
drawn with an outline, and every state carried by colour MUST have a second
carrier that survives.

---

## 18. The television client contract

### 18.1 The projection

The deployment does not draw the television (§4.3). It projects the catalog
into a model an existing client can consume, as spec-07 §6 projects it into
OpenSubsonic.

**The projection target is the Jellyfin server API** [JELLYFIN], and the client
is the Jellyfin Roku client. The choice is forced rather than preferred: Roku
removed non-certified channels in February 2022, a beta channel is deleted for
every installer after 120 days, and a sideloaded channel permits one
application per device and must be re-uploaded to each television on every
change. A client already in the channel store, installed in one action and
updated by its publisher, is the only arrangement a household sustains.

The deployment declares the API version §20 names. That string is a behaviour
switch in the client rather than decoration, and it is chosen deliberately.

**[C]** The correspondence:

| Projected | Catalog |
| --- | --- |
| library | a browse mode (§9.2), not a category |
| item | a manifestation, or a work where one expression in one manifestation is held |
| an ordered grouping | a res carrying ordered members (§8.3) |
| media source | a digital item |
| media stream | a content stream of that digital item (spec-04 §5.2) |
| person | an agent (spec-01 §3.1), whether or not narrowed |
| user data on an item | the requesting principal's own consumption |

**Identifiers are the res's primary identifier as a string**, as spec-07 §6.4
does. Where the target model types an identifier as something a UUID cannot
be, the deployment says which and why, as spec-07 §6.4 does for a folder and
a player.

Names are resolved per §6.1, and the composed name of §6.3 is carried where
resolution yields nothing displayable. Absence is carried per spec-07 §4.1.

A work with several expressions held has no place in the projected model. It is
projected as its resolved expression under §8.1 with the alternatives projected
as an ordered grouping. A household member browsing from the television reaches
versions through a grouping rather than through the work; this is lossy, and
naming the loss is the condition of the projection.

### 18.2 The projected surface

**[C]** The deployment projects the endpoint groups §20 enumerates: the public
system description, authentication, the user's own record, library and item
browsing, images, playback negotiation, byte serving, and playback-state
write-back. It does not project live television, synchronised playback, or
anything §18.6 excludes.

The router serving them MUST be case-insensitive in path and parameter name and
MUST tolerate a trailing slash, because the client is inconsistent in all
three.

### 18.3 Identity

**[C]** Authentication establishes a **person**, not a device, and every
request carries that person. Every consumption datum the client reports is that
principal's (spec-01 §11.2).

The preferred enrolment displays a short code on the television which the
person approves from their own authenticated session on another device. That is
a deployment-minted credential approved in-band; it is **not** the OIDC device
grant spec-06 §4 recommends, because this deployment runs no login flow of its
own and reads an identity a proxy asserts (spec-06 §3.2). A client key in
spec-07 §3.2's sense is what it is.

spec-07 §3.1 refuses a client key on the native API and spec-07 §3.4 admits one
here. **§18's surface is the third authentication surface that section names.**

A credential issued to a television is scoped to that device and separately
revocable. spec-07 §3.4 and spec-06 §4.2 carry the grant narrower than its
principal's role; spec-06 §4.1 carries more than one principal enrolled on one
device.

**The compromise, and it is not concealed.** A television client holds its
credential in device storage and remains signed in as whoever last used it.
spec-06 §4's prohibition on ambient sessions holds at the protocol level —
every request carries a person, no playback is unattributed — and not at the
sofa. The deployment MUST NOT represent this as satisfying spec-06 §4 in full.

Where a television holds more than one principal's credential, switching is a
selection among stored credentials, which is an ambient session for the set of
enrolled people and multiplies §21's plaintext-storage exposure by their
number. A deployment MAY instead hold one credential at a time and re-run the
approval on a switch, which is slower and honest. §20 records which it does.

The credential grants reading the catalog, streaming, and writing its own
principal's consumption. It MUST NOT grant administration, identity mapping, or
the catalog writes of §15.

### 18.4 Playback

**[C]** The client declares what it can decode, per playback attempt, and the
deployment answers with the stored bytes or a rendition. The deployment MUST
NOT infer capability from a device name: decoding capability varies within one
product line and changes with the audio path.

Where the normalized master is within the declared capability, it is served as
stored, with byte ranges (spec-07 §4.4). Where it is not, a rendition is
required and producing one is spec-08's. **Until spec-08, such a holding is
refused with a statement of why.**

spec-07 §6.7 makes the opposite choice on its surface — it serves the master
whatever format was asked for, and lets the content type say what was served.
The television contract refuses instead, because a client handed bytes it cannot
decode has no fallback and no way to explain itself.

This limitation follows from a decision made upstream: spec-01 §13.3 chooses
the standardized master for fidelity and longevity and explicitly not for
direct-play compatibility, and spec-01 §13.6 accepts that serving therefore
transcodes routinely. Two format facts bind regardless of spec-08:

- Where the household's televisions differ in capability, one holding may be
  served on one and refused on another, and the deployment MUST say which.
- A rendition MUST carry an audio track the device can decode on its own
  speakers. An audio codec the device can only pass through to a receiver is
  silence on a television that has none.

### 18.5 Presentation assets on the contract

**[C]** The client receives presentation assets by profile (§11.1). The
extraction is shared with the interface (§11.3); only the packaging differs.

The deployment MUST honour byte ranges for every asset served to a client, not
only for media, because a client that cannot range-request an image fails to
display it.

Images MUST be served at or near the size the client will draw. A client's
binding resource is decoded bitmap memory rather than bandwidth, and an
oversized image costs a multiple of its displayed size.

### 18.6 What is not projected

Correction (§15), the findings surface (§16), library administration, metadata
editing, and anything requiring text entry beyond a short search belong to the
interface.

Documents, ebooks and scanned correspondence are not projected. A client has no
reader, no reflow, no text selection and no find; presenting a letter there as
an image of a letter is worse than not presenting it.

**The television carries moving image, audio and still image. The interface
carries everything.**

### 18.7 What binds a client

**[C]** A client honours §5 (absence, as carried by spec-07 §4.1), §6.1 to §6.3
(names), §8.1 (which res is an entry, and the resolved default), §8.3 (ordered
members), §10.2 to §10.4 (regions and links), §11 (profiles), §12.2 and §12.3
(the three rules and the transport), §13 (continuity), §14.1 to §14.4
(identity), §16.3 (unverified), §17.2 and §17.4 to §17.9 (accessibility, with
§17.4's device-wide exception), and §18.

A client does not honour §7 (the interface's own language), §8.2, §8.4, §8.5,
§9, §15, §16.1, §16.2, §17.3's invitation, §17.6 or §17.7, each of which is
marked **[I]** or belongs to a surface the client does not draw.

### 18.8 Drift

The deployment is coupled to a client it does not control and cannot pin.

**[C]** Every request the projection does not handle MUST be logged with its
full path and parameters, so that a client which has drifted appears in the log
the same evening. A response to an unimplemented request MUST be well-formed
and MUST NOT be an empty success: a client told there is nothing behaves as
though there is nothing.

---

## 19. What this document rests on elsewhere

Seven things this document needs belong to the specifications that own the
concepts, and are specified there rather than here. Six are properties of the
wire; the seventh is a kind of annotation.

| What this document needs | Where it is specified |
| --- | --- |
| every field carrying a value and a state (§5.5) | spec-07 §4.1 |
| the composed name carried in a representation (§6.3) | spec-07 §4.1 |
| an entity URI content-negotiating to the interface (§10.1) | spec-07 §4.1 |
| a presentation asset served by profile name (§11.1) | spec-07 §4.6 |
| a key admitted on a third surface, narrower than its principal, several to a device (§18.3) | spec-07 §3.4, spec-06 §4.1 and §4.2 |
| a resume position carrying a device, a unit, a time, a sequence and whether it was playing (§13.1) | spec-01 §11.4 |
| a body whose subject is a named field of its target (§5.2) | spec-02 §6.5 |

Two of these carry a vocabulary this document owns rather than the other
document: §20's registry names the presentation profiles spec-07 §4.6 serves,
and the fields an absence assertion may be about. Neither mechanism is duplicated
here — a surface that needs one of them uses the section above.

---

## 20. Registries

These are seed data (spec-01 §7.5), maintained through releases. **A registry
this section names MUST be populated before the section depending on it is
built, and no code path may supply a value a registry omits.**

**Presentation profiles (§11)**

| Registry | Holds |
| --- | --- |
| image profiles | the graded widths, and the aspect ratio assumed per category before a probe has run (§11.2) |
| tiling threshold | the pixel count above which a scan is tiled rather than profiled |
| trickplay profile | the frame interval and frame width, and the tile geometry |
| waveform profiles | the overview point count, and the detail resolutions |
| key frame position | where in a moving image the poster frame is taken |

**Continuity (§13)**

| Registry | Holds |
| --- | --- |
| resume thresholds | per category: the regime (proportional or absolute), the floor, the ceiling, and the minimum length below which no position is kept |
| reporting interval | the heartbeat, which §13.3's idle rule is measured against |
| backwards threshold | how far a resume may move backwards before §13.3 requires it be stated |
| inactivity period | after which a shared surface returns to the choice of principal (§14.2) |

**Presentation (§6, §9, §12, §17)**

| Registry | Holds |
| --- | --- |
| nomen schemes | including the scheme reserved for an ordering nomen (§6.4) |
| browse modes | the modes of §9.2 and the default and bounding facets of each (§9.3) |
| category presentation | per spec-04 §6.3 category: the primary surface, the selectors honoured, and the presentation assets required (§12.1) |
| seek granularities | the small and large position steps of §12.3 |
| text track classifications | the values of §17.4 |
| accessibility affordances and hazards | the vocabularies of §17.3 |
| absence field names | the fields an absence assertion may be about, which spec-02 §6.5 requires be drawn from a registry |

**The television contract (§18)**

| Registry | Holds |
| --- | --- |
| projected API version | the version string §18.1 declares |
| projected endpoints | the endpoint groups §18.2 serves |
| credential policy | whether a television holds one credential or several (§18.3) |

**The design language**

[ANNEX-A]'s token values, and the values A.2.4, A.3.4, A.4.2 and A.7 name that
are not token values.

---

## 21. Security considerations

The render boundary is where consumption privacy is enforced, and §14.3's rule
covers surfaces rather than endpoints. spec-06 §6.3 identifies aggregate and
recommendation surfaces as the likely leak path; this document adds three.

An automatic preview that records a consumption event converts a glance into a
fact about a person. §17.8 forbids it, and the prohibition is a privacy control
rather than an accessibility one.

A presentation preference discloses a disability (§14.5). These are per
principal and are not household-visible, even though the annotations a
principal authors are. **On a surface whose platform holds caption settings
device-wide, that guarantee does not hold**, and the residual exposure is that
every member of the household who uses that television sees that someone needs
captions. The deployment does not write a principal's preference there; it
cannot prevent a person from setting it.

A television credential is a bearer token held in plaintext on a device that
may be reachable on the local network, and physical access to the television is
access to whatever it holds. §18.3 bounds the damage by scope and by revocation
rather than by secrecy, which is the only control that platform offers. Where
several principals are enrolled on one television the exposure multiplies by
their number, which is why §18.3 offers the one-credential alternative.

Content negotiation on the entity URI (§10.1) does not widen what is reachable:
the same authorization applies to both representations, and spec-07 §4.5's rule
that another principal's consumption datum answers as absent applies unchanged.

---

## 22. Conformance

An implementation conforms if it satisfies all of the following.

**Machine-checkable (1–33)**

1. Resolving a name, selecting an expression, and attaching consumption are
   recomputed per request and write nothing to the catalog.
2. No stored column holds a resolved name; changing a principal's profile
   changes what is displayed without a catalog write.
3. An entity URI of a kind §9.1 names answers with the interface where the
   request's `Accept` header contains `text/html`, and with the spec-07 §4.1
   representation, unchanged, for a header containing `*/*` and no `text/html`.
4. A representation carries a value and a state for every field, and all seven
   states of §5.2 are distinguishable in it. No state is inferred from the
   absence of a value: *sought, not found*, *known unknowable* and *known
   absent* appear only where an authored annotation establishes them, and a
   field §20's registry does not name reports *not yet examined*.
5. A res whose only nomens are its identifier-nomen or are excluded by the
   profile carries a composed name, terminating in a noun for its kind, and
   never an identifier.
6. A value not held is never rendered as a default, a zero, an epoch date or an
   empty string.
7. A time-span known only to a decade renders as the decade.
8. A facet with no available values is present, named and inert.
9. No image is generated to stand for a holding that has none.
10. Resolution's language step follows §6.1's four clauses in order, and clause
    3 applies only where every candidate carries a language.
11. Resolution of one res and profile returns the same nomen across calls,
    including where clause 3 applies.
12. Resolution over *n* identifiers performs a number of queries bounded
    independently of *n*.
13. A search matching a nomen other than the displayed one returns a result
    stating which nomen matched.
14. Two res resolving to one string for one profile are each rendered with a
    disambiguator.
15. No ordering is derived from a resolved nomen where an ordering nomen
    exists, and no transliteration is generated.
16. A res presented by an aggregating work or by a whole-part relation is not a
    browse entry; the res presenting it is.
17. A serial manifestation is one browse entry, whatever its episode count.
18. The primary action resolves without asking; where spec-01 §6.5's promotion
    does not apply, the ordering is distance from the category's significant
    attributes, and where those do not separate two expressions and spec-01 §8.6
    is silent, the surface asks and records rather than guessing.
19. Alternatives are reachable in one action and are counted.
20. A res carrying ordered members renders them in the order held by whichever
    of LRM-R25 and LRM-R26 carries it.
21. A household-composed sequence and a spec-07 §6.6 playlist are distinct
    objects and are never presented as one.
22. No res is reachable only through one browse mode.
23. Every facet value's count is computed against the current query.
24. A link carrying a selector opens positioned at the region and does not
    begin playback.
25. A link whose anchor no longer matches says so and does not land at the
    beginning.
26. An emitted link carries its selector in a basis spec-01 §8.4 permits.
27. A presentation asset requested by arbitrary dimensions is refused, except
    that an OpenSubsonic `size` maps to the smallest profile at or above it; a
    request by profile name is served and the response names the profile.
28. A visual res's geometry is available in the batched call that resolves its
    name, and a rendered collection does not shift as images arrive.
29. Every derivative has its orientation applied and its orientation metadata
    removed.
30. A surface does not offer a waveform zoom finer than the stored artefact.
31. A position below the floor or above the ceiling for its category is
    discarded, the res is recorded as consumed above the ceiling, and a res
    below the minimum length carries none.
32. Of two live reports for one principal, res and device, the more recent from
    a playing session wins; a live report from an idle session is ignored; a
    report flushed from an offline queue is ordered by its original time and
    sequence and is not ignored.
33. The continue surface is ordered by the requesting principal's own last
    interaction, renders one entry per res, states no proportion across
    entries, and contains no position-less entry other than the next member
    after a consumed one.
34. No surface is composed from more than one principal's consumption.
35. A playback driven from another surface is attributed to the principal the
    playing surface is acting as.
36. An automatic preview records no consumption event.
37. A one-confirm correction writes an authored annotation with the same
    provenance as one made in the editor.
38. A control for an accessibility affordance the res does not carry is
    disabled and carries a description saying why.
39. A cover companion does not appear in a photograph grid.
40. A track of a release held in one file resolves through the temporal address
    spec-04 §6.4 records, not through a second stream.
41. Focus is restored after a patch, a route change and a reconnection, to the
    nearest surviving sibling, else the container, else the surface's first
    focusable.
42. Every live region is present and empty before its first message, and an
    unchanged message produces no re-announcement.
43. No live region contains a position, a buffer state or a progress value.
44. Under forced colours every focus indicator is drawn with an outline.
45. A presentation asset's eviction is observable as having run.
46. Every registry §20 names is populated, and no code path supplies a value a
    registry omits.

**Requiring review (47–52)**

47. Every surface states which principal it is acting as, continuously.
48. Switching principal is reachable from every surface without entering a
    credential on a surface with no keyboard.
49. A value displayed with automatic provenance is correctable from where it is
    displayed.
50. Every open finding is visible on a surface of its own and on the res it
    concerns; an unverified asset is rendered as neither sound nor corrupt.
51. Every function is operable with four directions, a confirm and a back.
52. Browsing and searching do not share a results page, and reaching search
    from a mode does not discard the active facet set.

**The television contract (53–60)**

53. Authentication establishes a principal, and every consumption datum a
    client reports is attributed to it.
54. A credential issued to a client grants reading, streaming and its own
    principal's consumption, and is refused for administration, identity
    mapping and catalog writes.
55. A credential is revocable per principal per device without disturbing
    another principal's enrolment on the same device.
56. Every projected identifier is the res's primary identifier as a string,
    except where §18.1 names a type that forbids it.
57. Capability is taken from the client's declaration, never inferred from a
    device name.
58. A holding the client cannot decode is refused with a statement of why, and
    is not silently substituted.
59. Byte ranges are honoured for every asset served to a client, including
    images.
60. An unhandled request is logged with its full path and parameters and
    answered with a well-formed refusal, never an empty success.

---

## 23. References

### 23.1 Normative

- **[spec-01]**, **[spec-02]**, **[spec-03]**, **[spec-04]**, **[spec-06]**,
  **[spec-07]**, this system.
- **[ANNEX-A]** *Annex A — Design Language*, companion to this specification.
  Normative for the interface and for the token definition a client's theme is
  generated from.
- **[IFLA-LRM]** as in spec-01 §18.1. §8.1 orders by §5.6's representative
  expression; §8.3 rests on §5.7's account of an aggregate and §5.8's of a
  serial.
- **[WCAG22]** W3C, *Web Content Accessibility Guidelines 2.2*, W3C
  Recommendation, 5 October 2023. Level AA outside Guideline 1.2, and §2.4.13.
  §4.1.1 Parsing is obsolete and removed in 2.2 and is not cited.
- **[IIIF-PRES]** IIIF, *Presentation API 3.0*, §4.4, for the language
  selection filter adopted in §6.1.
- **[IIIF-IMAGE]** IIIF, *Image API 3.0*, for the region and size grammar
  adopted in §11.2.
- **[JELLYFIN]** *Jellyfin Server API*, as published in its OpenAPI document,
  for the projection of §18.
- **[MEDIA-FRAGS]** W3C, *Media Fragments URI 1.0*, as adopted by spec-01 §9.1.
- **[RFC2119]**, **[RFC8174]** as in spec-01 §18.1.

### 23.2 Informative

- **[spec-05]** *Metadata Acquisition and Matching*, this system. §15.3's
  provenance rules govern what its matches render as, and its §11 maps onto
  §5.2's states.
- **[spec-08]** *Playback and Transcode Negotiation*, not yet written. §18.4
  waits on it.
- **[spec-09]** *Search, Ranking and Recommendation*, not yet written. §9.5
  orders results until it exists.
- **[W3C-ANNO]** W3C, *Web Annotation Data Model*. Its `creator` and
  `generator` distinction is spec-02 §3.2's authored and derived split under
  other names, and its selector types correspond closely to spec-01 §8.3's.
- **[EDTF]** Library of Congress, *Extended Date/Time Format*. A candidate
  representation for the partial and qualified time-spans §5.3 renders, which
  spec-01 §2 does not currently adopt.
