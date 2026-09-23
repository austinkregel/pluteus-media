# Search, Ranking and Recommendation

**Specification 09**
**Status:** Draft
**Version:** 0.1
**Depends on:** spec-01 (Catalog Data Model), spec-02 (Annotations and Derived
Data), spec-03 (Assets, Storage and Preservation), spec-04 (Ingest and
Normalization), spec-05 (Metadata Acquisition and Matching), spec-06
(Principals, Auth and Authorization), spec-07 (Wire Protocol), spec-10
(Presentation)
**Obsoletes:** nothing

## Abstract

spec-01 through spec-07 establish what the household holds, what may be
computed about it, and how a client reaches it. Each of them defers the same
class of question: what the catalog does when someone asks it something it
cannot answer by lookup — which of these, in what order, and what else is like
this.

This document specifies the four operations that answer it, what a derived body
may be computed from, the regions those bodies are computed over, and what each
operation is permitted to read. Three properties follow from the model rather
than from taste. Only one of the four reads a principal, so the other three are
answerable identically for everyone. A derived body carries the terms of
everything it was computed from, so a licence is honoured before a computation
rather than filtered after it. And a missing signal is not a low one, so a
ranking states what it could not compare on.

---

## 1. Introduction

### 1.1 Scope

- The four operations — search, ranking, similarity, recommendation — and which
  of them reads a principal
- The terms gate: what a derived body may be computed from
- Regions as the unit of comparison
- Where signal comes from: derived, imported, catalog
- The component set, over a principal's preferences and over an agent
- Set generation: coherence, duration, sequence, and where a generated set goes
- Search: matching, fusion, and attribution
- Selection among competing bodies, which spec-02 §5.2 defers here
- Absence in a ranked result
- What may leave the household
- The generative tool, and faces
- The native API and the OpenSubsonic extensions

### 1.2 What this document does not specify

Identity and the facts a source asserts (spec-05); this document consumes what
matching wrote and adds no scheme, no provider and no equation. The extraction
pipeline (spec-04 §8), which produces the bodies ranked here; this document
specifies what is done with one and never how it is computed. What a surface
draws (spec-10). Wire form (spec-07).

The playlist as an object belongs to spec-07 §6.6, and the household-composed
sequence to spec-10 §8.3. This document generates members for both and owns
neither.

**Collaborative filtering is unavailable.** It needs a population and the
household is one household. Every mechanism here is content-based or
catalog-based by construction, and §12.3's import of a similarity another
service computed is a fact taken from outside rather than a population this
deployment has.

---

## 2. Conventions

BCP 14 key words per spec-01 §2. References of the form "spec-0N §x" refer to
that document.

Four terms are used precisely:

| Term | Is |
| --- | --- |
| **search** | a query in, an ordered set out (§3.1) |
| **ranking** | an order over a set that already exists (§3.1) |
| **similarity** | a number over two res (§3.1) |
| **recommendation** | a set that did not previously exist, for one principal (§3.1) |

*Body type* means the value spec-02 §6.1's registry names for a kind of derived
body — an embedding of a named model's space, a transcript, a set of
measurements, a region boundary.

*Component set* means §7.1's structure: several centroids over one space, each
with its own weight vector.

---

## 3. The four operations

### 3.1 What each is

Conflating any two of them produces either a privacy defect or a false
comparison, and which one depends on the pair.

**Search** takes a query and returns an ordered set. Its inputs are nomens
(spec-01 §7.4), text bodies and derived vectors. No principal is an input
beyond the resolution profile.

**Ranking** takes a set that already exists — a facet result, a browse mode,
the members of a grouping — and returns an order over it. Same inputs.

**Similarity** takes two res and returns a number. Its inputs are derived
bodies and nothing else. **No principal is an input at all.**

**Recommendation** takes a principal and returns a set that did not previously
exist. Its inputs are that principal's own consumption (spec-01 §11.2) and
their preferences, plus everything the first three use.

### 3.2 Only recommendation is private

spec-06 §6.3 forbids one principal observing another's consumption and names
"recommendation output, which derives from events by construction" among the
surfaces that leak it. The prohibition reaches the fourth operation and not the
first three, because the first three read no consumption.

| Operation | Computed per | Cacheable | Answerable identically for every principal |
| --- | --- | --- | --- |
| search | query | by query and profile | modulo the resolution profile |
| ranking | set | by set and profile | modulo the resolution profile |
| similarity | pair | household-wide | **yes** |
| recommendation | principal | per principal, never shared | no |

A similarity index is one index for the household. A taste model is one per
principal and MUST NOT be an input to anything another principal sees.

**A cache keyed in part by a resolution profile is keyed in part by a
principal**, since spec-07 §4.1 resolves under the requesting principal's
profile. Such a cache is that principal's own data, MUST be scoped to it, and
MUST NOT be readable by another. Cache occupancy and response latency are not
relied upon as privacy boundaries, which spec-06 §6.3 forbids at household
scale.

### 3.3 Where each may be offered

spec-10 §9.4 permits lateral movement as a "more like this" computed from the
catalog. Similarity is permitted on the same footing: it reads no consumption,
so spec-06 §6.3 does not reach it, every result is explained by §9.3's
attribution, and it is predictable before acting.

A recommendation composed from the requesting principal's own consumption is
permitted and is what spec-06 §6.3 allows rather than what it forbids, which is
A observing B's. It MUST NOT be offered on any surface another principal reads.

spec-10 §9.2's Recently added and §13.4's Continue keep the orderings those
sections fix. Ranking orders what spec-10 has not already ordered.

---

## 4. The terms gate

### 4.1 Three kinds of restriction

spec-05 §6.4 records each provider's terms. The terms encountered in practice
are not one kind of thing, and one rule does not cover them.

**A use-class prohibition binds the computation.** TMDB's term prohibits use of
its content "in connection with, including for training, a machine learning
(ML) or artificial intelligence (AI) based Application." Embedding a TMDB
overview is the prohibited act.

**The line is computation, not display.** A value under a use-class prohibition
renders, resolves and is corrected like any other, and MUST NOT enter a vector,
an embedding, a text index, a cluster or a prompt.

**A condition on redistribution binds what leaves the house.** CC BY-SA, CC
BY-NC-SA and ODC-By permit computing freely and attach attribution and
share-alike obligations to anything redistributed. A household that
redistributes nothing discharges them by attribution alone.

**A condition on the class of use binds the deployment as a whole.** A
NonCommercial term conditions every right the licence grants, not redistribution
alone. This deployment is one household running its own holdings and meets it;
the registry records the term met rather than the term absent.

| Source | Terms | Computation | Redistribution |
| --- | --- | --- | --- |
| MusicBrainz core — artists, releases, recordings, works | CC0 | free | free |
| **MusicBrainz tags, including genre associations** | CC BY-NC-SA 3.0 (supplementary) | free | attribution and share-alike |
| Discogs monthly dumps — including styles and genres | CC0 | free | free |
| AcousticBrainz | CC0, frozen | free | free |
| Wikidata | CC0 | free | free |
| Open Library | no copyright asserted over the database | free | free |
| LCSH via id.loc.gov | public domain | free | free |
| Getty AAT, TGN, ULAN | ODC-By 1.0 | free | attribution, in the wording each vocabulary requires |
| AudioSet ontology | CC BY-SA 4.0 | free | attribution and share-alike |
| Grand Comics Database | CC BY-SA 4.0 | free | attribution and share-alike |
| GeoNames | CC BY 4.0 | free | attribution |
| **TMDB** | proprietary | **prohibited** | prohibited |

MusicBrainz sits on both sides of that table. Its core data is CC0, and its
tags — which carry the genre associations a ranking function wants — are
supplementary data under CC BY-NC-SA 3.0.

**A tool carries terms of its own**, and they are recorded per §4.3.

### 4.2 The gate

A derived body carries the terms of everything it was computed from and of the
tool that computed it.

**A body MUST NOT be computed where any input's terms forbid the computation.**
Not filtered at query time — never computed, because the computation is the
prohibited act and a body that exists is evidence it occurred.

**A derivation MUST record the terms of every value that entered it**, and a
body computed from another body MUST carry that body's terms forward. spec-02
§4.1's derivation records the res a tool ran over, which is not the values it
read; without the recorded terms the gate holds for a first-order computation
and answers nothing about a cluster over embeddings (§14.2).

A value whose provenance cannot be established is treated as carrying the terms
of the most restrictive source the deployment has configured. A companion that
arrived with a holding (spec-04 §4.6) carries the terms of whatever produced
it, and a media manager's `.nfo` populated from a provider carries that
provider's.

### 4.3 What a tool declares

spec-04 §8.3 requires a tool to answer its name, its version and its wire
schema version. It also answers:

- **Terms.** What licence the code carries, what licence the weights carry, and
  what obligations each places on the deployment. Code and weights are recorded
  separately, because they differ.
- **Disclosure.** What acquiring the tool tells anyone. A gated model is fetched
  under an accepted agreement against an identified account, which is a
  disclosure in spec-05 §6.2's sense.

A tool whose terms the deployment cannot meet MUST NOT be configured, which is
spec-05 §6.4's rule for a provider applied to a tool. **A term is not met by
declining to record it.**

### 4.4 What the gate costs

The prohibited set is small and concentrated: film and television descriptive
metadata from TMDB. Every other descriptive source the household reaches
permits computation.

Where a provider under a use-class prohibition is the only source for a film's
description, that description is displayed and is not ranked on, and the film is
ranked on what else it carries: its credits, its time-span, its category and its
own derived bodies from its own bytes. §11 is why that degrades visibly rather
than silently.

---

## 5. Where signal comes from

### 5.1 Three origins

| Origin | Is | Available for |
| --- | --- | --- |
| **Derived** | computed here from the household's own bytes (spec-04 §8) | everything |
| **Imported** | a measurement a source computed (spec-05 §8.6) or a fact it asserts | published media only |
| **Catalog** | relations, categories, credits, places, time-spans, arrangement | everything |

spec-05 §9.10 records that no source outside the house holds a row for a
photograph, a scan, a letter or a home video, and none ever will. They are the
household's least replaceable holdings (spec-01 §13.7), so the derived origin is
not an optimisation: it is the only origin half the library has.

### 5.2 What is imported

spec-05 §8.6 governs importing a measurement: it may be imported only where the
source names the tool and the version that produced it, it is ordered by the
source's snapshot rather than by arrival, and it never supersedes a local run of
a different tool.

Descriptive facts — a genre, a style, a subject heading — are assertions rather
than measurements, and spec-05 §8.1 and §8.3 govern them.

This document adds no import mechanism. It adds a register (§18) of which
corpora carry descriptive signal worth holding, and the terms of each.

### 5.3 What is derived, per category

The tools are spec-04 §8's, and their measurement names are that document's.

| Category | Derived body | On |
| --- | --- | --- |
| music recording | engineered measurements, a neural audio embedding, segment boundaries | the manifestation, and a `temporal` address per segment |
| film, television, home video | scene boundaries, a key-frame image embedding per scene, loudness, a transcript where speech is present | the manifestation, each content stream's `track` address (spec-04 §8.1), and a `temporal` address per scene |
| photograph | an image embedding, a face embedding per detected region | the manifestation, and a `spatial` address per region |
| scan, correspondence | a transcript, word positions, a text embedding per passage | the manifestation, and a `text_quote` address per passage |
| document, ebook | a text embedding per passage | a `text_position` or `text_quote` address per passage |
| audiobook, podcast | a transcript, a text embedding per passage, a neural audio embedding | the manifestation, and a `temporal` address per passage |
| comic issue | an image embedding per page, a transcript where the lettering is legible | a `page` address per page |
| agent | a component set (§7.3) over the regions of everything credited to it | the agent |

A software holding carries no derived body: spec-04 §5.3 gives it no streams and
nothing decodes it into anything a measurement is about. It is ranked on catalog
signal alone.

Every address in that table is a reified address under spec-01 §8.2, which
requires reification wherever anything references a region durably.

---

## 6. Regions

### 6.1 The unit of comparison

A mean over a whole track describes a thing nobody listens to. A song with a
quiet opening and a loud chorus has a mean that is neither, and a person whose
preference is for the chorus is modelled by a vector resembling no part of what
they liked.

A household library is small, and the lever a large service pulls — a
population and co-occurrence across it — is unavailable (§1.2). Subdivision
multiplies the number of comparable units without acquiring any media: one
library of *n* holdings becomes a library of many times *n* regions, each
internally coherent in a way the whole is not.

Regions are therefore load-bearing rather than an enhancement. The structure is
spec-02 §1.3's: audio segments, video scenes, document chunks and face regions
"share a target region, a body, and a provenance record" and are "therefore one
structure".

### 6.2 What targets what

| Thing | Targets | Because |
| --- | --- | --- |
| a segment boundary | the manifestation, as a derived annotation | it is an output of the segmenter |
| a vector over a region | that region's reified address | spec-01 §8.2 |
| **a person's preference about a region** | **the res, with its own selector** | spec-02 §3.3 |

A member who likes the passage two minutes and fourteen seconds into a recording
has asserted something about that instant of that expression, which is stable.
They have not asserted anything about segment seven, which is an artifact of one
version of one segmenter.

**The association between a preference and the regions covering it MUST be a
query and MUST NOT be a stored reference.** Which regions under the current
derivation contain this instant is recomputed whenever the derivation changes,
at no cost, and re-segmenting at a new extractor version cannot move what a
preference refers to.

### 6.3 A text region is a structural unit

**A text region MUST follow the document's own structure wherever the document
has one** — a paragraph in reflowable text, a block or a line in a scan's
transcript, a cue in a subtitle track. A fixed window MAY be used only where the
document has none, and is recorded as such.

A paragraph survives re-derivation: a better transcriber reads the same
paragraph and the region still names it. A window at characters 4096 to 5120
names different text after every re-run, so a vector over one window is not
comparable with a vector over its successor. This is the reasoning spec-01 §8.5
gives for preferring a text-quote anchor to an offset.

### 6.4 Regions need not be exhaustive or disjoint

A segmenter that leaves gaps is describing a recording with nothing salient in
the gap. A scene detector that overlaps at a dissolve is describing a dissolve.

Every region MUST carry the derivation that produced it, so that two segmenters'
regions over one manifestation are never mixed in one index (§10.2).

---

## 7. Preferences and component sets

### 7.1 One centroid is the wrong shape

Inverse-variance weighting over liked region vectors — features a person is
consistent about get high weight, the centroid is the ideal point — is sound,
and it is unsound with one centroid.

A person who likes two unrelated things has a centroid describing neither, and
variance is highest on exactly the dimensions that tell the two apart, so
inverse-variance weighting suppresses the features that define the real
clusters.

### 7.2 What a preference is

- **A region preference** is the primary signal: an authored annotation on a res
  with its own selector (§6.2).
- **A whole-res star or rating** is what an existing client sends (spec-07 §6.3)
  and is an authored annotation with no selector, which spec-02 §3.1 permits.

A whole-res preference contributes the res's own vector. It MUST NOT be
projected onto every region, because that asserts the person liked parts they
may not have heard.

Three of the four res a client stars carry no vector of their own. An artist is
an agent, and an album is a release manifestation which, held as separate track
files, has no master (spec-04 §6.4); both contribute their component set (§7.3),
each component weighted by the preference. A star on a work contributes the
resolved expression's, under the rule spec-10 §8.1 uses to resolve the primary
action. Only a song contributes a single vector.

Where a principal has expressed both a region preference and a whole-res
preference about one res, both stand.

### 7.3 The component set

**A component set is several centroids over one space, each with its own
inverse-variance weight vector, fitted by clustering the vectors it is fitted
over.** Each component is a coherent region, and is the scope argument §8 takes.

The number of components is fitted rather than fixed, bounded below by one and
above by the count §18's registry names.

| Fitted over | Is | Reads consumption |
| --- | --- | --- |
| a principal's preferred region vectors | that principal's **taste model** | yes |
| the region vectors of everything credited to an agent | that agent's component set | no |

**Two component sets are near where any component of one is near a component of
the other.** An artist with a folk record and an electronic record is near folk
artists through the first component, without the second dragging the
comparison.

A taste model is that principal's own consumption data, held where spec-01 §11.2
holds the rest of it. A principal is not a res (spec-01 §10.1), so a taste model
is not an annotation. An agent's component set is a derived annotation on the
agent, is household-wide, and is similarity rather than recommendation.

### 7.4 The cold start is a real state

A taste model with fewer preferences than §18's registry names is *not yet
examined* in spec-10 §5.2's sense and MUST be rendered as that. A surface
offering a personalised set composed from nothing asserts a taste the household
has not expressed. What is offered instead is §3.1's first three operations,
which need no preferences at all.

---

## 8. Sets

### 8.1 Coherence is the constraint; duration is a target

The property being bought is a set a person can start and not think about again.
That is a **variance constraint over the set**, not accuracy per member. A set
whose every member is individually defensible and whose sequence is not is the
failure mode of per-track relevance scoring.

A candidate is admitted only while the set's variance in the weighted space
stays under a threshold. The threshold is the tight-mix against broad-mix knob
and is a registry value (§18).

**Duration is fitted within a tolerance and MUST NOT be bought by admitting a
member the variance constraint excludes.** A set that reaches its target by
breaking coherence has delivered the opposite of what was asked.

### 8.2 The pipeline

```
SCOPE      a taste component, or an explicit seed, or a stated theme
WEIGHT     apply the theme's per-dimension weight override
RETRIEVE   nearest neighbours to the scope in the weighted space
CONSTRAIN  admit while set variance stays under the threshold
BALANCE    a familiarity ratio, from the principal's own consumption
FIT        approach the duration target within tolerance
SEQUENCE   order the admitted set
NAME       label the result
```

SCOPE through FIT read one principal's data and are recommendation. RETRIEVE
alone, from an explicit seed, is similarity and reads no principal. SEQUENCE and
NAME inherit the classification of the set they are given.

**A generated set MUST NOT cross categories.** Search crosses (§9.2), because
rank fusion is defined where averaging a photograph's image-embedding distance
against a letter's text-embedding distance is not. §8.1 buys a variance
constraint, and a set spanning a letter and a film has no shared space in which
its variance can be measured.

### 8.3 A theme is a weight vector

Per-theme weight overrides turn one distance metric into a family of them: a
driving set weights tempo and rhythm and loosens timbre, a focus set inverts it.
spec-02 §6.3 puts weights in the assembling component and §6.4 makes semantic
groupings seed data, so a theme is a registry entry (§18) and adding one is a
seed change.

**A theme weights named measurements.** spec-02 §6.1 forbids a positional vector
as an interchange representation and §6.2 makes a measurement a scalar or an
array of fixed length, so an embedding is one named array whose dimensions carry
no semantics to weight. A category whose only derived bodies are embeddings
(§5.3) takes a theme as a scope and a retrieval bound and not as a
per-dimension override.

### 8.4 Sequencing

Shortest Hamiltonian path over a complete graph whose edges are distance in the
weighted space [BITTNER]. Cost is dominated by building the matrix, which is
quadratic in set length and irrelevant at the length of a set a person plays.

**With regions, the edge is end-of-A to start-of-B**, not centroid to centroid.
The published method restricts transition points to downbeats "heavily weighted
to occur on section boundaries," which is a description of the region table.

Sequencing concentrates its gain on sets drawn from across the library and does
approximately nothing on a set that was already tight.

### 8.5 Naming and destination

A generated set's name is not a nomen of anything in the catalog. It belongs to
the set, and §13 governs the tool that produces it.

**Where the pipeline read a principal's consumption, the set is that principal's
playlist (spec-07 §6.6) and MUST NOT be written as a household-composed sequence
(spec-10 §8.3).** A household-composed sequence is a catalog res, rendered to
every member through spec-10 §8.3's template and listed in its Sets mode; a set
BALANCE shaped from one principal's play counts is recommendation output, which
spec-06 §6.3 forbids another principal from observing.

A set generated from an explicit seed or a stated theme alone reads no
consumption and MAY be either.

---

## 9. Search

### 9.1 What is matched

Every nomen a res carries (spec-01 §7.4 confines resolution to output and leaves
search free), every text body, and every vector.

spec-10 §6.2 requires a result to carry the nomen that matched wherever a search
reached a res through a name other than the one displayed. That obligation is
what makes matching every nomen safe to do, and a result the native API returns
carries it as spec-10 §6.2 requires of the interface.

A value under a use-class prohibition (§4.1) MUST NOT be held in a text index.
It remains matchable by scan, which is not the prohibited act.

### 9.2 Fusion is over ranks and never over scores

Lexical matching and vector matching produce numbers that are not on one scale.
Calibrating them against each other is what spec-02 §5.1 and spec-05 §8.5 forbid
for tools and for sources.

**Reciprocal rank fusion is the only fusion mechanism**, because it consumes a
position in each ranking and discards the score that produced it. Two rankers,
or a lexical ranker and three vector rankers over different derived bodies,
combine without any of them being comparable to any other.

This is also what makes a cross-category result set possible. A photograph's
image-embedding distance and a letter's text-embedding distance are not
comparable quantities; their ranks within their own categories are.

### 9.3 Where a result came from

**A fused result MUST be able to say which ranker placed it and where.** A
result that appears because one ranker put it first and three put it nowhere is
a different thing from one every ranker agreed on, and a surface that cannot
tell them apart cannot explain itself.

---

## 10. Selection among competing bodies

### 10.1 The rule

spec-02 §5.2 defers here: where two tools both produce a body of the same kind —
two OCR engines over one scan — both annotations persist and selection among
them is a query concern. spec-04 §8.2 produces the same situation by design.

**Selection is per query and per use. It MUST NOT be stored, and it MUST NOT be
a confidence comparison** (spec-02 §5.1).

The deployment holds, **per body type**, an ordering of tools. A query uses the
highest-ordered tool that produced a body of that type for this input. Where the
ordering names none, every body stands and the query states that it read
several.

Body type rather than measurement name, because spec-02 §5.2's own case is two
OCR engines and a transcript is not a measurement — spec-02 §6.2 makes a
measurement a scalar or an array of fixed length. A segmenter's regions are not
measurements either.

An ordering is a deployment's judgement about its own tools, which is a
different thing from a confidence score and is allowed to be one. It is
deployment configuration and not seed data: spec-01 §7.5 makes seed data
identical across every deployment and forbids mutating a seeded row. Changing it
changes no stored row.

### 10.2 An index belongs to one tool at one version

Two tools' embeddings are not in one space, and two versions of one tool's
embeddings frequently are not either.

**A vector index MUST name the tool and the version whose bodies it holds**, and
a re-derivation at a new version MUST build a new index rather than writing into
the existing one. Superseding does not purge (spec-02 §5.2, §8.2), so the old
index remains answerable while the new one fills, and a query states which it
used.

The same binds regions: two segmenters' regions over one manifestation are two
sets of regions, and an index mixing them measures distances between coordinates
from different frames.

**Re-derivation runs one body type at a time**, which bounds the cost of the
second index to one duplicate rather than a duplicate of every index.

---

## 11. Absence in a ranked result

### 11.1 A missing value is not a low value

spec-10 §5.2 gives seven states. A recording whose loudness has not been
measured is *not yet examined*; it is not a recording whose loudness is zero,
and a ranking function that substitutes zero has invented a fact and sorted on
it.

**A ranking function MUST NOT substitute a value for an absent one.** A res
missing a signal is ranked on the signals it has, and the result states that the
comparison was made on fewer.

A substituted default is least visible here of anywhere in the system: a wrong
number in a sort order produces a plausible-looking list and no error anywhere.

### 11.2 Two absences mean different things

*Not held* is permanent and is a fact about the holding. *Not yet examined* is a
scheduling fact that resolves itself, and a result set ranked while analysis is
pending will rank differently tomorrow.

**A surface MUST be able to say which**: *three of these were ordered without
tempo, which has not been measured yet*. A ranking that silently changes when a
background job finishes is indistinguishable from a defect.

### 11.3 A similarity that cannot be computed is not answered

Where a res carries no body from the ordered tool, it MUST be left out of the
result and MUST NOT be returned with a substituted 0.0, which would mean
*maximally dissimilar* and is a claim the deployment cannot support. The count
returned is then smaller than the count requested.

The native API carries the absence as spec-10 §5.2's state, having a field to
carry it in.

---

## 12. The outbound direction

### 12.1 The rules

**No consumption datum leaves the household except by a per-principal election
that is off by default and revocable.** One principal's election MUST NOT export
another's, and a household-level setting MUST NOT exist, because consumption is
not a household-level thing (spec-01 §11.2).

**No operation of §3 may issue an outbound request, and none may be triggered by
a render where it would.** spec-05 §14 states this for matching: a query issued
because someone opened a page tells an outside party what that person is looking
at, converting a catalog surface into a channel disclosing consumption. Ranking
a facet result, ordering a browse mode and answering a search reach nothing
outside the house, and this rule does not touch them.

**No derived body leaves the household.** A vector, an embedding, a transcript,
a segment boundary, a component set and a face embedding are each computed from
the household's own bytes or about its own people, and no election reaches them.

**Model weights are fetched once, at deployment time.** Never per holding, never
carrying anything about a holding, and never on a path a render can reach.

### 12.2 An election is visible to the principal who made it

An export election is that principal's own consumption data and is not
household-visible. spec-01 §11.2 forbids a platform event that carries or is
derivable into what a principal consumed, so an export MUST NOT be recorded as
one.

**The electing principal MUST be able to see what has left under their own
election, and when.** The record is that principal's, reaches no other, and is
what keeps an election from being a setting nobody can audit.

### 12.3 Importing a similarity

A similarity fact a service computed over its users is an imported measurement
under spec-05 §8.6 — a number the source computed, importable only where the
source names the tool and version. It is not this household's consumption and
spec-06 §6.3 does not reach it.

**An imported similarity is held as a cache keyed by the pair, and MUST NOT be
an annotation.** spec-02 §3.1 gives an annotation one target and a similarity is
about two res. The cache carries the source and the source's snapshot, is
evicted rather than migrated, and its loss is not data loss, which keeps a
number the household did not compute out of the catalog and out of backup
(spec-03 §7).

**An import MUST run on a schedule over the catalog and MUST NOT run over a
recommendation's candidates.** Which pairs are asked about is a function of one
principal's taste, so a candidate-driven import carries consumption outward a
pair at a time.

---

## 13. The generative tool

### 13.1 It is a deriving tool, and it runs locally

A language model is a deriving tool in spec-02 §4.1's sense. It is not an agent
(spec-02 §4.1, LRM-E6), it asserts nothing, and spec-05 §3.1's distinction holds
unchanged: a provider asserts, a tool computes.

**It MUST run locally.** The distinction that makes it a tool rather than a
provider is what would place it outside spec-05 §6.2's disclosure rules, which
bind a provider and not a tool, and spec-04 §8.3's tool contract constrains what
a tool writes and not what it sends. §13.4's first use would otherwise put the
transcript of the household's correspondence — spec-01 §13.7's least replaceable
holding — on a third party's wire under no rule in the series.

Its output is a derived body or a candidate. It is never an assertion, never a
nomen with a null assigner (spec-05 §8.1), never a category a member set, never
a face tag (spec-05 §9.7), and never one of the three absence states only a
person may establish (spec-05 §11).

### 13.2 Its version is more than its name

spec-02 §4.2 requires a version "sufficient to distinguish any two builds that
could produce different numbers for the same input." For a language model that
is the weights, the quantization and the decoding parameters, because each
changes the output and two of them are deployment choices rather than properties
of the model.

spec-02 §4.3's refusal to assume determinism is more true here than anywhere
else in the series, and nothing is compared by recomputing.

### 13.3 A prompt is a computation

§4.2's gate applies to what enters a prompt exactly as it applies to what enters
a vector. A value under a use-class prohibition MUST NOT be placed in one.

Summarising a film's description is the most natural thing to do with a local
model and a catalog, and it is the one thing a use-class prohibition names.

### 13.4 What it is good for

- Subject and topic extraction over a transcript, as a candidate a member
  accepts (spec-05 §9.8)
- Naming a generated set (§8.5)
- Turning a stated request into a scope and a weight override (§8.2), which is a
  query-side use that writes nothing and carries no derivation

---

## 14. Faces

### 14.1 Recognition produces candidates; only a person produces a name

spec-05 §9.7 is normative: faces are authored. Matching may not write a face tag
and neither may this document. The mechanism is three steps, and the split
between them is spec-02 §3.2's:

1. A detector produces a `spatial` address per detected region — derived.
2. An embedding over each region, and a clustering over the embeddings —
   derived, and re-derivable.
3. A member names a cluster, which produces **one authored annotation per member
   photograph, each targeting its photograph with its own selector** — never one
   annotation targeting the cluster.

### 14.2 A re-clustering proposes, and does not carry

The cluster is derived and moves when the detector or the embedder changes
version; the names survive because they were never anchored to it.

The grouping does not survive, and §6.2's recomputation does not carry it. A
region query is spatial containment; a cluster is an identity grouping in an
embedding space, where a new embedder's clusters stand in no containment
relation to the old.

**A re-clustering MUST propose each new cluster's name from the names already
carried by the photographs it contains**, as a candidate a member accepts
(spec-05 §8.5). Where the photographs under one new cluster carry two names it
proposes neither.

### 14.3 What a face embedding is, and how it is withdrawn

A face embedding of a relative is biometric data about a person who holds no
principal and never will (spec-01 §10.1). It never leaves the household under
§12.1, and the thing worth preserving — the name a member gave the cluster — is
authored and is backed up.

Derived does not mean disposable here; it means re-created. spec-02 §3.2 keeps
an embedding out of backup because spec-01 §13.7 expects it to be regenerated
after loss, and spec-04 §8.4 regenerates it on every version change without
being asked.

**A member MAY withdraw a face, and a withdrawal is authored.** It records the
res and the person, it is backed up and survives re-derivation like any authored
annotation, and analysis MUST read it before detecting: a withdrawn photograph
produces no `spatial` address and no embedding, and a withdrawn person's name is
removed from every cluster it was given to. Any member may withdraw any face,
because spec-06 §6.2 makes members peers over the catalog and the person in the
photograph is not there to ask.

---

## 15. Surfaces

### 15.1 The native API

Search, similarity and recommendation are operations rather than res, so they
are paths of their own rather than second addresses for a res, which spec-10
§10.1 forbids.

Every result carries the nomen that matched (§9.1), the states of §11, the
ranker attribution of §9.3, and the index attribution of §10.2.

### 15.2 The OpenSubsonic surface

spec-07 §6.2's advertised set gains one extension:

| Extension | Version | Endpoints |
| --- | --- | --- |
| `sonicSimilarity` | 1 | `getSonicSimilarTracks`, `findSonicPath` |

| Endpoint | Parameters | Returns |
| --- | --- | --- |
| `getSonicSimilarTracks` | `id`, `count` (default 10) | `sonicMatch[]` |
| `findSonicPath` | `startSongId`, `endSongId`, `count` (default 25) | `sonicMatch[]`, start first and end last |

`sonicMatch` carries `entry` (a `Child`) and `similarity`, a number where 1.0 is
identical and 0.0 is maximally different. **`-1` is reserved to its protocol
meaning — that the server does not compute similarity at all — and MUST NOT be
returned for a res carrying no body**, which §11.3 governs. This deployment
computes similarity, so it never answers `-1`.

`findSonicPath` states which of the two readings its `similarity` carries: it is
the distance from `startSongId`, so a path reads as a monotonic departure rather
than a sequence of unrelated hops.

spec-07 §6.3's **Browsing** group gains two endpoints:

| Endpoint | Parameters | Answered from |
| --- | --- | --- |
| `getSimilarSongs` | `id` — an artist, an album or a song — and `count` (default 50) | a song's own bodies, or the component set of an artist or album |
| `getSimilarSongs2` | `id` — an artist — and `count` (default 50) | that agent's component set |

All four read no consumption, so all four cache household-wide and answer
identically for every principal.

### 15.3 A score on the wire is this deployment's number

Exposing `similarity` does not breach spec-02 §5.1 or spec-05 §8.5. Those forbid
comparing one tool's confidence with another's; `similarity` is one deployment's
statement about one comparison method over one pair.

**A response's `similarity` MUST be produced by one method.** A value fused
across two rankers has no meaning, and §9.2's fusion produces ranks rather than
a score precisely so that this is never tempting.

---

## 16. Conformance

An implementation conforms to this specification if it satisfies all of the
following.

**The operations**

1. Search, ranking and similarity read no consumption event and no preference of
   any principal.
2. Two principals issuing one query against one catalog receive the same set in
   the same order, modulo their resolution profiles.
3. A similarity between two res is the same number whichever principal asks.
4. A cache keyed in part by a resolution profile is scoped to its principal and
   is not readable by another.
5. Principal A cannot observe principal B's recommendation output, taste model,
   or generated sets through any surface.
6. Continue and Recently added retain the orderings spec-10 §13.4 and §9.2 fix.

**The terms gate**

7. A body is not computed where an input's terms forbid the computation, and the
   refusal is recorded.
8. A derivation records the terms of every value that entered it.
9. A body computed from another body carries that body's terms forward, and the
   terms of a cluster over embeddings are answerable.
10. A value under a use-class prohibition renders, resolves and is correctable,
    and appears in no vector, embedding, text index, cluster or prompt.
11. A tool declares its code licence, its weights licence and what acquiring it
    discloses, and a tool whose terms cannot be met is not configured.
12. A value whose provenance cannot be established is treated as carrying the
    most restrictive configured source's terms.

**Signal and regions**

13. Every derived body names the reified address it was computed over, and that
    address is of a type spec-01 §8.5 permits at that level.
14. Per-stream analysis targets the stream's `track` address, and two streams of
    one container are never taken for re-runs of each other.
15. An authored preference targets a res with its own selector and never a
    derived address.
16. Re-running a segmenter at a new version changes which regions cover a
    preference and changes no preference.
17. A text region follows the document's own structure where it has one; a fixed
    window is used only where it has none and is recorded as such.
18. A region carries the derivation that produced it, and two segmenters'
    regions over one manifestation are never mixed in one index.

**Preferences and sets**

19. A component set carries more than one component where the vectors fitted
    over it are multi-modal, and the count is bounded by the registry.
20. A taste model below the registry's minimum preference count is reported *not
    yet examined* and no personalised set is offered from it.
21. A whole-res preference contributes the res's own vector and is not projected
    onto its regions.
22. A star on an artist, an album or a work contributes a component set or a
    resolved expression's vector, and is not discarded.
23. An agent's component set is a derived annotation on the agent and reads no
    consumption.
24. A candidate is admitted to a set only while set variance stays under the
    threshold, and the duration target never admits one that breaks it.
25. A generated set does not cross categories.
26. A set whose pipeline read consumption is written as its principal's playlist
    and never as a household-composed sequence.
27. A theme applies a per-dimension override only to named measurements, and a
    category whose bodies are embeddings alone takes it as a scope.

**Search**

28. A search matches every nomen a res carries, every text body and every
    vector, and a result reached through a name other than the displayed one
    states which nomen matched.
29. A value under a use-class prohibition is matchable and is in no index.
30. Fusion consumes ranks and no score crosses between rankers.
31. A fused result states which ranker placed it and at what position.

**Selection and indexes**

32. Two tools' bodies of one type over one input both persist, and the query
    selects by the configured ordering without writing anything.
33. Where the ordering names no tool for a body type, every body stands and the
    query states that it read several.
34. Selection over two OCR transcripts and over two segmenters' regions is
    answerable by the same mechanism as selection over two extractors'
    measurements.
35. A vector index names the tool and version whose bodies it holds, and a
    re-derivation builds a new index while the old one keeps answering.
36. A query states which index answered it.

**Absence**

37. No ranking substitutes a value for an absent one.
38. A result set states how many of its members were ordered on fewer signals,
    and which signal was missing.
39. *Not held* and *not yet examined* are distinguishable in a ranked result.
40. A res carrying no body from the ordered tool is absent from a similarity
    result rather than present with a substituted score.

**The outbound direction**

41. No consumption datum leaves the household without a per-principal election
    that is off by default; one principal's election exports nothing of
    another's; no household-level election exists.
42. No derived body leaves the household under any election.
43. No operation of §3 issues an outbound request, and none is triggered by a
    render.
44. An electing principal can see what has left under their own election and
    when, and no other principal can.
45. Model weights are fetched at deployment time only, on no path a render can
    reach.
46. An imported similarity is a cache keyed by its pair, carries its source's
    snapshot, is excluded from backup, and is not an annotation.
47. An import runs on a schedule over the catalog and never over a
    recommendation's candidates.

**The generative tool**

48. The language model runs in the deployment and no inference request leaves
    the household.
49. Its version distinguishes weights, quantization and decoding parameters.
50. Its output is a derived body or a candidate, and never an assertion, a
    nomen with a null assigner, a category, a face tag, or one of spec-05 §11's
    three prohibited states.
51. A value under a use-class prohibition never enters a prompt.

**Faces**

52. A detector and an embedder write no face tag, and only a principal does.
53. Naming a cluster writes one authored annotation per photograph, each with
    its own selector, and none targeting the cluster.
54. Re-clustering at a new embedder version preserves every name and proposes
    new groupings as candidates, proposing none where a new cluster spans two
    names.
55. A withdrawal is authored, is backed up, and survives re-derivation.
56. Analysis reads withdrawals before detecting: a withdrawn photograph gains no
    `spatial` address and no face embedding on any subsequent run.
57. Any member may withdraw any face.

**The surfaces**

58. Search, similarity and recommendation are reached at paths of their own, and
    no res gains a second address.
59. Every result carries the matched nomen, its states, its ranker attribution
    and its index attribution.
60. `getOpenSubsonicExtensions` advertises `sonicSimilarity` version 1.
61. `getSonicSimilarTracks` and `findSonicPath` answer `sonicMatch[]`, and
    `findSonicPath` returns the start first and the end last.
62. `-1` is never returned for a res carrying no body.
63. `getSimilarSongs` and `getSimilarSongs2` answer from the household's own
    derived bodies and require no third-party credential.
64. A `similarity` on the wire is produced by one method and is never fused
    across rankers.

---

## 17. Security and privacy considerations

**Only one of four operations is private, and the boundary is drawn around
consumption rather than around preference.** A region preference is an authored
annotation and is household-visible under spec-02 §10, so another principal can
already read what one member liked. What they cannot read is what anyone played,
and §8.2's BALANCE is the only step of the pipeline that touches it. §3.2's
scoping rule and §8.5's destination rule are the two controls that keep it that
way.

**A cache is a surface.** spec-06 §6.3 covers "every surface, not merely direct
queries", and a household-wide cache keyed by query and resolution profile is a
record of what each member searched for. A search query is not a consumption
event under spec-01 §11.2 and the series classifies it nowhere else, which is
why §3.2 scopes the cache rather than relying on the query's classification.

**The outbound direction is the one spec-05 §14 does not cover.** That section
governs what a query discloses about a holding; §12 governs what leaves about a
person and about the household's own computations. An export election is the
only mechanism in the series by which consumption data leaves, and §12.2 makes
it visible to the person whose data it is, since spec-01 §11.2 forecloses
recording it anywhere household-visible.

**A face embedding is biometric data about someone who cannot consent.** The
depicted person holds no principal (spec-01 §10.1) and has no standing anywhere
in the series. §14.3's withdrawal is the household's mechanism for acting on
their behalf, and it is authored precisely so that spec-04 §8.4's scheduled
re-derivation cannot undo it.

**The gate is enforced at computation and cannot be enforced afterwards.** A
body that exists is evidence the computation occurred, and spec-02 §5.2 retains
superseded bodies by rule. Where a source's terms change after a body was
computed, the deployment deletes the body; nothing in the series does so
automatically.

---

## 18. Registries

Seed data (spec-01 §7.5), maintained through releases. **A registry this section
names MUST be populated before the section depending on it is built, and no code
path may supply a value a registry omits.**

| Registry | Holds |
| --- | --- |
| themes | per theme: the per-dimension weight override (§8.3), the set-variance ceiling, the duration tolerance (§8.1) and the familiarity ratio (§8.2) |
| tool terms | per tool: the code licence, the weights licence, the obligations each places on the deployment, and what acquiring it discloses (§4.3), each recorded with the URL it was read from and the date it was read |
| source terms for computation | per source: which of §4.1's kinds its terms are, and whether the deployment meets them |
| descriptive corpora | which of spec-05 §5.5's corpora carry descriptive signal worth holding, and for what (§5.2) |
| component bounds | the largest number of components a set may be fitted to, and the minimum preference count below which a taste model is not fitted (§7.3, §7.4) |

A licence name alone is not a record of a term. A project's own summary page and
the licence distributed with its weights disagree often enough that the registry
holds the source read and the date read alongside the name.

Two things are not seed data and are not held here. The **body-type tool
ordering** of §10.1 is deployment configuration. A principal's **export
elections** and **taste model** are that principal's own consumption data, held
where spec-01 §11.2 holds the rest of it.

---

## 19. What this document rests on elsewhere

| What this document needs | Where it is specified |
| --- | --- |
| a derivation recording the terms of every value that entered it (§4.2) | spec-02 §4.1 |
| a body-type vocabulary to key §10.1's ordering on | spec-01 §17, spec-02 §6.1 |
| the detectors, segmenters, transcribers and embedders §5.3 requires | spec-04 §8.2 |
| a tool declaring its terms and its disclosure (§4.3) | spec-04 §8.3 |
| analysis reading a withdrawal before detecting (§14.3) | spec-04 §8.4 |
| a write class for a description a source supplies (§4.4) | spec-05 §3.2 |
| an imported measurement naming its tool and version (§5.2, §12.3) | spec-05 §8.6 |
| a principal's own consumption data, which holds a taste model and an election (§7.3, §12.1) | spec-01 §11.2, spec-06 §6.1 |
| paths for three operations, and a result set carrying attribution and state (§15.1) | spec-07 §4.1 |
| the advertised extension set (§15.2) | spec-07 §6.2, §6.3 |
| the seven states a value can be in (§11) | spec-10 §5.2 |
| a result carrying the nomen that matched (§9.1) | spec-10 §6.2 |
| the household-composed sequence a generated set may not become (§8.5) | spec-10 §8.3 |

---

## 20. References

### 20.1 Normative

- **[spec-01]** *Catalog Data Model*, this system. §7.4 confines resolution to
  output; §8.2 requires reification; §11.2 scopes consumption.
- **[spec-02]** *Annotations and Derived Data*, this system. §3.3 anchors a
  preference; §4.1 identifies a derivation; §5.1 refuses confidence; §5.2 defers
  selection here; §6.1 names measurements; §7 stores raw values.
- **[spec-03]** *Assets, Storage and Preservation*, this system. §7 is the
  backup scope §12.3 keeps an imported number out of.
- **[spec-04]** *Ingest and Normalization*, this system. §8 produces every body
  ranked here; §8.1 is what a derivation ran over; §8.3 is the tool contract
  §4.3 extends; §8.4 is the re-derivation §14.3 reads a withdrawal before.
- **[spec-05]** *Metadata Acquisition and Matching*, this system. §6.4 records a
  provider's terms; §8.5 labels a source's score; §8.6 imports a measurement;
  §9.7 makes faces authored; §11 is what matching may never assert; §14 forbids
  a query on a render.
- **[spec-06]** *Principals, Authentication and Authorization*, this system.
  §6.1 holds a Member's own consumption data; §6.2 makes members peers; §6.3 is
  the prohibition §3.2 is drawn against.
- **[spec-07]** *Wire Protocol*, this system. §4.1 is the representation §15.1
  extends; §6.2 and §6.3 are the surfaces §15.2 adds to; §6.6 is the playlist a
  generated set becomes.
- **[spec-10]** *Presentation*, this system. §5.2's seven states are what §11
  reports; §6.2 is the matched nomen; §8.3 is the sequence §8.5 forbids; §9.4 is
  the lateral movement §3.3 joins; §9.5 is the ordering this document supersedes.
- **[RFC2119]**, **[RFC8174]** as in spec-01 §18.1.

### 20.2 Informative

- **[OPENSUBSONIC]** OpenSubsonic API, for the `sonicSimilarity` extension, the
  `sonicMatch` response type, and the `getSimilarSongs` and `getSimilarSongs2`
  endpoints of §15.2.
- **[BITTNER]** Bittner, R., Gu, M., Hernandez, G., Humphrey, E., Jehan, T.,
  McCurry, P., Montecchio, N., *Automatic Playlist Sequencing and Transitions*,
  ISMIR 2017, for §8.4's graph traversal and its restriction of transitions to
  section boundaries.
- **[TMDB-TERMS]** TMDB API Terms of Use, §1.C, for §4.1's use-class
  prohibition. It reaches TMDB Content and not API access alone, and is not
  conditioned on commercial use.
- **[METABRAINZ-LICENCE]** MusicBrainz database licensing, for the core and
  supplementary split §4.1 records.
- **[DISCOGS-DATA]** Discogs monthly data dumps, CC0, for §5.2.
- **[ESSENTIA-MODELS]** The licence distributed with the Essentia model files,
  which governs over the project's own licensing page where the two state
  different Creative Commons clauses.
- **[notes-07]** [Analysis, taste and playlists](notes/07-analysis-taste-and-playlists.md),
  the research this document's §7 and §8 are drawn from.
- **[notes-09]** [Open questions](notes/09-open-questions.md), whose segment-scale
  estimate §10.2 bounds.
