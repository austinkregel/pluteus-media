# Spec-09 decisions

> **Non-normative.** Where this conflicts with [spec-01](../spec-01-catalog-data-model.md),
> the specification governs.

What the catalog does when someone asks it a question it cannot answer by
lookup: which of these, in what order, and what else is like this.

---

## 1. Scope

### 1.1 What spec-09 covers

- The four operations — search, ranking, similarity, recommendation — and which
  of them reads a principal
- The terms gate: what a derived body may be computed from, and what it may not
- Regions as the unit of comparison, and why a small library needs them
- Signal: what is computed here, what is imported, and what neither supplies
- The taste model over a principal's own preferences
- Set generation: coherence, duration and sequence
- Search: matching, fusion, and ordering
- Selection among competing bodies, which [spec-02] §5.2 hands here
- Absence in a ranked result
- The outbound direction, which no document in the series has yet had to face
- The surfaces: the native API, and the OpenSubsonic extensions that have been
  waiting on this document

### 1.2 What spec-09 does not cover

Identity and the facts a source asserts ([spec-05]); this document consumes
what matching wrote and adds no scheme, no provider and no equation. The
extraction pipeline ([spec-04] §8), which produces the bodies ranked here;
this document specifies what is done with one and never how it is computed.
What a surface draws ([spec-10]); §9.5 is the surface, this document is the
order. Wire form ([spec-07]).

The playlist as an object belongs to [spec-07] §6.6 and [spec-10] §8.3, which
already distinguish one principal's playlist from a household-composed
sequence. This document generates members for both and owns neither.

**Collaborative filtering is permanently closed.** Not forbidden — unavailable.
It needs a population and the household is one household, and [notes-07] is
right that saying so up front is the only way to stop it being chased. Every
mechanism here is content-based or catalog-based by construction. §12.3 is not
an exception: a similarity another service computed is a fact imported from
outside, not a population this deployment has.

---

## 2. Vocabulary

Four operations. Conflating any two of them produces either a privacy defect or
a false comparison, and which one depends on the pair.

**Search** takes a query and returns an ordered set. Its inputs are nomens
([spec-01] §7.4), text bodies, and derived vectors. No principal is an input
beyond the resolution profile.

**Ranking** takes a set that already exists — a facet result, a browse mode,
the members of a grouping — and returns an order over it. Same inputs.

**Similarity** takes two res and returns a number. Its inputs are derived
bodies and nothing else. **No principal is an input at all.**

**Recommendation** takes a principal and returns a set that did not previously
exist. Its inputs are that principal's own consumption ([spec-01] §11.2) and
their preferences, plus everything the first three use.

### 2.1 Only the fourth is private

[spec-06] §6.3 forbids one principal observing another's consumption and names
"recommendation output, which derives from events by construction" among the
surfaces that leak it. The prohibition reaches the fourth operation and not the
first three, because the first three read no consumption.

The consequences are practical rather than pedantic:

| Operation | Computed per | Cacheable | Answerable identically for every principal |
| --- | --- | --- | --- |
| search | query | yes, by query and profile | yes, modulo the resolution profile |
| ranking | set | yes | yes, modulo the resolution profile |
| similarity | pair | yes, household-wide | **yes** |
| recommendation | principal | per principal, never shared | no |

A similarity index is one index for the household. A taste model is one per
principal and is never an input to anything another principal sees.

### 2.2 The amendment this requires

[spec-10] §9.4 says of lateral movement: "This is the only 'more like this'
[spec-06] §6.3 permits." That holds for every *behaviour-derived* more-like-this
and is too strong by one case. Similarity (§2) reads no consumption, so §6.3
does not reach it either, and a recommendation composed from the requesting
principal's own consumption is what §6.3 permits rather than what it forbids —
it forbids A seeing B's.

[spec-10] §9.4's other claims survive intact and are the reason lateral
movement keeps its place: computed from the catalog, every result explained by
the property it shares, predictable before acting. Similarity has the first and
the third and buys the second back through §9.3.

---

## 3. What upstream binds

### 3.1 The six deferrals

| Deferred by | What waits here |
| --- | --- |
| [spec-02] §1.2, §5.2 | how annotations are searched, and **which of two tools' bodies a query uses** when both stand |
| [spec-04] §8.2 | which measurement a vector uses where native and sidecar both computed one of that name |
| [spec-05] §1.2 | ranking, similarity and recommendation |
| [spec-05] §6.4, §14 | the machine-learning terms, stated there as binding a document not yet written |
| [spec-07] §1.2, §6.2 | similarity, and the `sonicSimilarity` extension withheld from the advertised set |
| [spec-10] §9.5 | search result ordering, alphabetical in the interim "and the surface says so" |

### 3.2 The constraints that are not negotiable here

**Confidence does not decide** ([spec-02] §5.1). Scores are not comparable
across tools, frequently not across versions of one tool, and in general not
calibrated. §10 and §12 are built on this rather than around it.

**A source's score is that source's number** ([spec-05] §8.5), labelled as such
and never compared with another's.

**Assembly is local** ([spec-02] §6.3). Canonical ordering, normalization
ranges and per-dimension weights belong to the assembling component alone and
MUST NOT be in an annotation body or a producer's contract. This document is
that component's specification and holds no measurement definition.

**Raw values are what is stored** ([spec-02] §7). Changing a weight or a
normalization range must never require re-reading a library. Every decision
below preserves this.

**An authored annotation may not target a derived address** ([spec-02] §3.3).
§6 is the consequence.

**A member's assertion is never outranked** ([spec-01] §7.5, [spec-02] §5.3).
A ranking function may order what a person asserted; it may not contradict it.

---

## 4. The terms gate

### 4.1 Three kinds of restriction, three rules

[spec-05] §6.4 records each provider's terms and says plainly that a feature
vector or an embedding computed over TMDB content is the use that provider's
term forbids. The terms encountered in practice are not one kind of thing, and
one rule does not cover them.

**A use-class prohibition binds the computation.** TMDB's term prohibits use of
its content "in connection with, including for training, a machine learning
(ML) or artificial intelligence (AI) based Application." Embedding a TMDB
overview is the prohibited act. Displaying it is not — [spec-05] §8.1 already
wrote it as a nomen assigned to TMDB, and nothing here disturbs that.

**The line is computation, not display.** A value under a use-class prohibition
renders, resolves, and is corrected like any other, and MUST NOT enter a
vector, an embedding, a text index, a cluster or a prompt.

**A condition on redistribution binds what leaves the house.** CC BY-NC-SA,
CC BY-SA and ODC-By permit computing freely; they attach attribution and
share-alike obligations to anything redistributed. A household that
redistributes nothing discharges them by attribution alone. This is the
commonest case and the least restrictive, and it must not be confused with the
first — the two are frequently on the same shelf:

| Source | Terms | Computation | Redistribution |
| --- | --- | --- | --- |
| MusicBrainz core — artists, releases, recordings, works | CC0 | free | free |
| **MusicBrainz genres and tags** | CC BY-NC-SA 3.0 (supplementary) | free | attribution and share-alike |
| Discogs monthly dumps — including styles and genres | CC0 | free | free |
| AcousticBrainz | CC0, frozen | free | free |
| Wikidata, Open Library | CC0 | free | free |
| LCSH via id.loc.gov | public domain | free | free |
| Getty AAT, TGN, ULAN | ODC-By 1.0 | free | attribution |
| AudioSet ontology | CC BY-SA 4.0 | free | attribution and share-alike |
| Grand Comics Database | CC BY-SA 4.0 | free | attribution and share-alike |
| GeoNames | CC BY 4.0 | free | attribution |
| **TMDB** | proprietary | **prohibited** | prohibited |

MusicBrainz sits on both sides of that table. Its core data is CC0 and its
**genres and tags are not** — they are supplementary data under CC BY-NC-SA
3.0. Genres and tags are precisely what a ranking function wants from it.

**A tool carries terms of its own**, and no registry in the series holds them.

| Tool | Code | Weights |
| --- | --- | --- |
| Essentia | AGPLv3, or a commercial licence on request | **CC BY-NC-SA 4.0**, per the licence shipping with the weights; VGGish-derived models carry Apache-2.0 upstream and MusiCNN-derived models ISC |
| InsightFace | MIT | **non-commercial research only** |
| pyannote.audio | MIT | gated: an agreement and a token |
| EmbeddingGemma | — | Gemma terms, not an OSI licence |
| CLAP (`laion/larger_clap_music`) | Apache-2.0 | Apache-2.0 |
| AST (`MIT/ast-finetuned-audioset-…`) | — | BSD-3-Clause |
| SigLIP 2, DINOv2 | Apache-2.0 | Apache-2.0 |
| Whisper | MIT | MIT |
| BGE-M3, `gte-small` | MIT | MIT |
| librosa | ISC | — |
| pgvector, pgvectorscale | PostgreSQL License | — |
| pg_search (ParadeDB) | AGPL-3.0 | — |

### 4.2 The gate

A derived body carries the terms of everything it was computed from, and of the
tool that computed it.

**A body MUST NOT be computed where any input's terms forbid the computation.**
Not filtered at query time — never computed, because the computation is the
prohibited act and a body that exists is evidence it occurred.

The gate is checkable only where the records reach the values. [spec-05] §6.4
keeps each value's provider recoverable from the match record, and says
outright that it is retained "for exactly this reason." [spec-02] §4.1's
derivation records its tool, its version, its parameters and its input — which
is the res a tool ran over, and not the values it read.

**A derivation therefore records the terms of every value that entered it, and
a body computed from another body carries that body's terms forward.** Without
the second half the gate holds for a first-order computation and answers
nothing about a cluster over embeddings (§14.1), which is the case it most
needs to answer. §16 carries the field this requires.

**The tool contract gains two declarations.** [spec-04] §8.3 requires a tool to
answer its name, its version and its wire schema version. It gains:

- **Terms.** What licence the code and the weights carry, and what obligations
  they place on the deployment.
- **Disclosure.** What acquiring the tool tells anyone. A gated model is
  fetched under an accepted agreement against an identified account, which is
  a disclosure in [spec-05] §6.2's sense arriving by a route that section did
  not anticipate.

A tool whose terms the deployment cannot meet is not configured, which is
[spec-05] §6.4's rule for a provider applied to a tool. **A term is not met by
declining to record it.**

### 4.3 What the gate costs, and what it does not

The prohibited set is small and it is concentrated: film and television
descriptive metadata from TMDB, and the face and music-tagging model weights.
Every other descriptive source the household would reach is CC0 or an
attribution licence.

Where TMDB is the only source for a film's description, that description is
displayed and is not ranked on, and the film is ranked by what else it carries:
its credits, its time-span, its category, its own derived bodies from its own
bytes. §11 is why that degrades honestly rather than silently.

A deployment configuring no TMDB loses cover art and descriptions and loses
nothing here, since [spec-05] §9.2 already establishes identity from the
`.nfo`, the `.plexmatch` and EIDR.

---

## 5. Where signal comes from

### 5.1 Three origins, and the household's own media has only one

| Origin | Is | Available for |
| --- | --- | --- |
| **Derived** | computed here from the household's own bytes ([spec-04] §8) | everything |
| **Imported** | a measurement a source computed ([spec-05] §8.6) or a fact it asserts | published media only |
| **Catalog** | relations, categories, credits, places, time-spans, arrangement | everything |

[spec-05] §9.10 already records that no source outside the house holds a row
for a photograph, a scan, a letter or a home video, and none ever will; its
GeoNames column answers where one was taken and nothing about the thing
itself. They are the
household's least replaceable holdings ([spec-01] §13.7) and the ones no import
reaches, so the derived origin is not an optimisation. It is the only origin
half the library has.

### 5.2 What is imported, and under what rule

[spec-05] §8.6 already governs importing a measurement: it may be imported only
where the source names the tool and the version that produced it, it is ordered
by the source's snapshot rather than by arrival, and it never supersedes a
local run of a different tool.

Descriptive *facts* — a genre, a style, a subject heading — are assertions
rather than measurements, and [spec-05] §8.1 and §8.3 already govern them: a
name is a nomen assigned to its source, a category is written with automatic
provenance and never replaces a member's.

**spec-09 adds no import mechanism.** It adds a register of which corpora carry
descriptive signal worth holding, and the terms column of §4.1.

The concrete additions to [spec-05] §5.5's corpus table:

| Corpus | Carries | Terms | Held as |
| --- | --- | --- | --- |
| Discogs | styles and genres per release and master, richer than any other music corpus | CC0 | monthly XML dumps |
| MusicBrainz supplementary | genres and folksonomy tags | CC BY-NC-SA 3.0 | with the database dump |
| Getty AAT | a subject and material thesaurus for scans, art and photographs | ODC-By 1.0 | N-Triples, refreshed monthly |
| LCSH | subject headings for books and documents | public domain | bulk MADS/SKOS RDF |
| AudioSet ontology | the label hierarchy the instrument and vocal detector classifies into | CC BY-SA 4.0 | one JSON file |

Open Library's dumps carry works, editions and authors; its subject data is
reachable from them and is not a dump of its own.

### 5.3 What is derived, per category

The tools are [spec-04] §8's, whose two families §16 extends to the detectors,
segmenters, transcribers and embedders below, and their measurement names are
that document's. What follows is which derived bodies each category needs for
§7 through §9 to have anything to work on.

| Category | Derived body | On |
| --- | --- | --- |
| music recording | engineered measurements, a neural audio embedding, segment boundaries | the manifestation, and a `temporal` address per segment |
| film, television, home video | scene boundaries, a key-frame image embedding per scene, loudness, a transcript where speech is present | the manifestation, each content stream's `track` address ([spec-04] §8.1), and a `temporal` address per scene |
| photograph | an image embedding, a face embedding per detected region | the manifestation, and a `spatial` address per region |
| scan, correspondence | a transcript, word positions, a text embedding per passage | the manifestation, and a `text_quote` address per passage |
| document, ebook | a text embedding per passage | a `text_position` or `text_quote` address per passage |
| audiobook, podcast | a transcript, a text embedding per passage, a neural audio embedding | the manifestation, and a `temporal` address per passage |
| comic issue | an image embedding per page, a transcript where the lettering is legible | a `page` address per page |
| agent | a component set (§7.1) over the regions of everything credited to it | the agent |

A software holding carries no derived body: [spec-04] §5.3 gives it no streams
and nothing decodes it into anything a measurement is about. It is ranked on
catalog signal alone, which §5.1's third origin supplies for everything.

Every address in that table is a reified address under [spec-01] §8.2, which
already requires reification "wherever anything must reference the region
durably — a preference expressed about it, a feature vector or embedding
computed over it, a face tag, a reader's highlight."

---

## 6. Regions

### 6.1 Why a small library needs them

The mean over a whole track describes a thing nobody listens to. A song with a
quiet opening and a loud chorus has a mean that is neither, and a person whose
preference is for the chorus is modelled by a vector that resembles no part of
what they liked.

A household library is small. The lever a large service pulls — a population,
and co-occurrence across it — is permanently closed (§1.2). **Subdivision is
the only lever that remains**, because it multiplies the number of comparable
units without acquiring any media: one library of *n* holdings becomes a
library of many times *n* comparable regions, each of which is internally
coherent in a way the whole is not.

Regions are therefore load-bearing rather than an enhancement added later. The
structure also generalizes, which [spec-02] §1.3 anticipated in refusing to
give audio segments, video scenes, document chunks and face regions four
structures: they "share a target region, a body, and a provenance record" and
are "therefore one structure", and the retrieval code over them is one body of
code.

### 6.2 What targets what

| Thing | Targets | Because |
| --- | --- | --- |
| a segment boundary | the manifestation, as a derived annotation | it is an output of the segmenter |
| a vector over a region | that region's reified address | [spec-01] §8.2 |
| **a person's preference about a region** | **the res, with its own selector** | [spec-02] §3.3 |

A member who likes the passage two minutes and fourteen seconds into a
recording has asserted something about *that instant of that expression*, which
is stable. They have not asserted anything about *segment seven*, which is an
artifact of one version of one segmenter.

**The association between a preference and the regions covering it is a query,
never a stored reference.** Which regions under the current derivation contain
this instant is recomputed whenever the derivation changes, at no cost.

This is [spec-02] §3.3 applied, and it discharges without further work the
migration problem a segment-keyed preference otherwise creates: re-segmenting
at a new extractor version cannot move what a preference refers to, because the
preference never referred to a segment.

### 6.3 A text region is a structural unit, never a fixed window

Audio has a segmenter and moving image has a scene detector. Text has its own
structure already, and it is better than anything a window produces: a
paragraph in reflowable text, a block or a line in a scan's transcript, a cue
in a subtitle track.

**A text region follows the document's structure wherever the document has
one.** A fixed window is used only where it has none — a wall of unbroken
transcript, an OCR pass that recovered no layout — and is recorded as the
lesser thing it is.

The reason is the one [spec-01] §8.5 already gives for preferring a text-quote
anchor to an offset. A paragraph survives re-derivation: a better OCR model
reads the same paragraph and the region still names it. A window at characters
4096 to 5120 names different text after every re-run, so a vector over one
window is not comparable with a vector over its successor, and §10.3's rule
that an index belongs to one tool at one version would be doing all the work
that the region boundary should have done itself.

### 6.4 Regions are not required to be exhaustive or disjoint

A segmenter that leaves gaps is producing a truthful description of a recording
with nothing salient in the gap. A scene detector that overlaps at a dissolve
is describing a dissolve.

What is required is that every region carry the derivation that produced it, so
that two segmenters' regions over one manifestation are never mixed in one
index (§10.3).

---

## 7. The taste model

### 7.1 One centroid is the wrong shape

Inverse-variance weighting over a principal's liked region vectors — features
they are consistent about get high weight, the centroid is the ideal point — is
sound, and it is unsound with one centroid per principal.

A person who likes two unrelated things has a centroid describing neither, and
variance is highest on exactly the dimensions that tell the two apart, so
inverse-variance weighting *suppresses* the features that define the real
clusters. The model actively destroys the signal it exists to find.

**A taste model is a set of components**, each with its own centroid and its own
inverse-variance weight vector, fitted by clustering the principal's liked
region vectors. Each component is a coherent region of taste, and is the scope
argument §8 takes.

The number of components is fitted rather than fixed, bounded below by one and
above by the count the registry (§17) names, because a household's libraries
differ by an order of magnitude and a fixed count is either one centroid for
someone with four tastes or four centroids for someone with one. Below the
minimum preference count the model is not fitted at all (§7.3).

**An agent carries a component set fitted the same way**, over the region
vectors of everything credited to it ([spec-04] §6.4, LRM-R5). The argument is
§7.1's own: an artist with a folk record and an electronic record has a mean
that describes neither, and the dimensions that separate the two are exactly
the ones inverse-variance weighting would suppress. Two agents are near where
any component of one is near a component of the other, so the folk record
reaches folk artists without the electronic record dragging the comparison.

A component set is derived and carries a derivation ([spec-02] §4.1) whose
input is the res it is about. A principal is not a res ([spec-01] §10.1), so a
taste model is not an annotation and is held with that principal's other
consumption data; an agent's component set is an annotation on the agent, is
household-wide, and is §2's similarity rather than recommendation, since it
reads no consumption.

### 7.2 What a preference is

Two granularities, both real, and the document says how they relate rather than
choosing:

- **A region preference** is the primary signal: an authored annotation on a
  res with its own selector (§6.2), and the reason to build this rather than
  adopt something.
- **A whole-res star or rating** is what an existing client sends ([spec-07]
  §6.3), and is an authored annotation with no selector — which [spec-02] §3.1
  already permits: "an annotation MAY target a whole res rather than a region,
  by carrying no selector."

A whole-res preference contributes the res's own vector to the model. It is
**not** projected onto every region, because that asserts the person liked
parts they may not have heard.

Three of the four res a client stars carry no vector of their own. An artist is
an agent and an album is a release manifestation that, held as separate track
files, has no master ([spec-04] §6.4); both contribute their component set
(§7.1) instead, each component weighted by the preference. A star on a work
contributes the resolved expression's, under the same rule [spec-10] §8.1 uses
to resolve the primary action. Only a song contributes a single vector.

Where a principal has expressed both about one res, both stand. They are two
annotations about two targets and [spec-02] holds both without strain.

### 7.3 The cold start is a real state, not an empty one

A model with too few preferences to fit is *not yet examined* in [spec-10]
§5.2's sense and MUST be rendered as that. A surface offering a personalised
set composed from nothing is asserting a taste the household has not expressed.

What is offered instead is §2's first three operations, which need no
preferences at all.

---

## 8. Sets

### 8.1 Coherence is the constraint; duration is a target

The property being bought is a set a person can start and not think about
again. That is a **variance constraint over the set**, not accuracy per member.
A set whose every member is individually defensible and whose sequence is not
is the failure mode of per-track relevance scoring, and it is the failure mode
to design against.

A candidate is admitted only while the set's variance in the weighted space
stays under a threshold. The threshold is the tight-mix against broad-mix knob
and is exposed rather than tuned in code.

**Duration is fitted within a tolerance and never bought by admitting an
incoherent member.** "About half an hour that holds one mood" is the request;
the mood is the requirement and the half hour is the shape. A set that reaches
its target by breaking coherence has delivered the opposite of what was asked.

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

SCOPE through FIT read one principal's data and are recommendation (§2).
RETRIEVE alone, from an explicit seed, is similarity and reads no principal.

**A generated set does not cross categories.** Search does (§9.2), because rank
fusion is defined where averaging a photograph's image-embedding distance
against a letter's text-embedding distance is not. Generation is the other
case: §8.1 buys a variance constraint over the set, and a set spanning a letter
and a film has no shared space for its variance to be measured in, so the
constraint it is sold on cannot be evaluated. The scope argument names a
category and the set stays inside it.

### 8.3 A theme is a weight vector

Per-theme weight overrides turn one distance metric into an unlimited family of
them: a driving set weights tempo and rhythm and loosens timbre, a focus set
inverts it. No new measurement, no new model, no new storage.

[spec-02] §6.3 already puts weights in the assembling component and §6.4 makes
semantic groupings seed data. A theme is therefore a registry entry, and adding
one is a seed change rather than a release.

### 8.4 Sequencing

Shortest Hamiltonian path over a complete graph whose edges are distance in the
weighted space [BITTNER]. Cost is dominated by building the matrix, which is
quadratic in set length and irrelevant at the length of a set a person plays.

**With regions, the edge is end-of-A to start-of-B**, not centroid to centroid.
That is strictly better than the published method and it is available only
because §6 exists: the published work restricts transition points to downbeats
"heavily weighted to occur on section boundaries," which is a description of
the region table.

The honest effect size is recorded rather than implied: sequencing concentrates
its gain on sets drawn from across the library and does approximately nothing
on a set that was already tight. It is worth building and it is not the thing
that makes §8.1 work.

### 8.5 Naming

A generated set's name is not a nomen of anything in the catalog. It belongs to
the set, and §13 governs the tool that produces it.

**Where the pipeline read a principal's consumption, the set is that
principal's playlist ([spec-07] §6.6), and MUST NOT be written as a
household-composed sequence ([spec-10] §8.3).** A household-composed sequence
is a catalog res, rendered to every member through [spec-10] §8.3's template
and listed in its Sets mode; a set BALANCE shaped from one principal's play
counts is recommendation output, which [spec-06] §6.3 forbids another principal
from observing. A set generated from an explicit seed or a stated theme alone
reads no consumption and MAY be either.

SEQUENCE and NAME inherit the classification of the set they are given. A label
computed from a set that BALANCE built is recommendation output as much as the
set is, and is the most portable part of it.

---

## 9. Search

### 9.1 What is matched

Every nomen a res carries ([spec-01] §7.4 confines resolution to output and
leaves search free), every text body, and every vector.

[spec-10] §6.2 already requires a result to carry the nomen that matched
wherever a search reached a res through a name other than the one displayed.
That obligation is what makes matching every nomen safe to do.

### 9.2 Fusion is over ranks and never over scores

Lexical matching and vector matching produce numbers that are not on one scale
and never will be. Calibrating them against each other is the thing [spec-02]
§5.1 and [spec-05] §8.5 forbid for tools and for sources, and the reasoning
does not stop at the boundary of this document.

**Reciprocal rank fusion is adopted as the only fusion mechanism**, because it
consumes a position in each ranking and discards the score that produced it.
Two rankers, four rankers, or a lexical ranker and three vector rankers over
different derived bodies combine without any of them being comparable to any
other.

This is also what makes a cross-category result set possible. A photograph's
image-embedding distance and a letter's text-embedding distance are not
comparable quantities; their ranks within their own categories are, and fusing
them is defined where averaging them is not.

### 9.3 Where a result came from

A fused result MUST be able to say which ranker placed it and where. A result
that appears because one ranker put it first and three put it nowhere is a
different thing from one every ranker agreed on, and the surface that cannot
tell them apart cannot explain itself.

This is [spec-10] §9.4's "explained by the property it shares", extended to a
ranking that has no single property to point at.

---

## 10. Selection among competing bodies

### 10.1 The handover

[spec-02] §5.2: where two tools both produce a body of the same kind — two OCR
engines over one scan — "both annotations persist and selection among them is a
query concern, specified in spec-09." [spec-04] §8.2 produces the same
situation by design, running a native and a sidecar tool side by side and
requiring that "a native tool reaching parity with the sidecar for a
measurement is established by comparing their stored bodies over the same
holdings, never by assuming it."

### 10.2 The rule

**Selection is per query and per use. It is never stored, and it is never a
confidence comparison** ([spec-02] §5.1).

The deployment holds, **per body type** ([spec-01] §17, [spec-02] §6.1), an
ordering of tools. A query uses the highest-ordered tool that produced a body
of that type for this input. Where the registry orders none, every body stands
and the query states that it read several.

Body type rather than measurement name, because [spec-02] §5.2's own case is
two OCR engines over one scan and a transcript is not a measurement —
[spec-02] §6.2 makes a measurement a scalar or an array of fixed length. A
segmenter's regions are not measurements either, nor is an embedding's 512
dimensions a vocabulary. Keyed on measurement name the ordering would reach
[spec-04] §8.2's two extractors and nothing else, which is a fraction of what
§10.1 was handed.

An ordering is a deployment's judgement about its own tools, which is a
different thing from a confidence score and is allowed to be one. It is
therefore deployment configuration and not seed data: [spec-01] §7.5 makes seed
data "generic and identical across every deployment" and forbids mutating a
seeded row in place, and a judgement about the tools this deployment runs is
neither. Changing it changes no stored row.

### 10.3 An index belongs to one tool at one version

This falls out of §10.2, and it reaches further into an implementation than
anything else here.

Two tools' embeddings are not in one space. Two versions of one tool's
embeddings are frequently not either. **A vector index therefore names the tool
and the version whose bodies it holds**, and a re-derivation at a new version
builds a new index rather than writing into the existing one.

Superseding does not purge ([spec-02] §5.2, §8.2), so the old index remains
answerable while the new one fills, and a query states which it used.

The same reasoning binds regions: two segmenters' regions over one
manifestation are two sets of regions, and an index mixing them is measuring
distances between coordinates from different frames.

**Re-derivation runs one body type at a time**, which is what bounds the cost
of that second index. [notes-09] already flags segment tables as the largest in
the system by an order of magnitude with vector indexes over them, and §5.3
extends regions across four more media classes. The peak is one duplicate index
rather than a duplicate of every index, and which one is the deployment's
choice of what to re-derive first.

---

## 11. Absence in a ranked result

### 11.1 A missing value is not a low value

[spec-10] §5.2 gives seven states. A recording whose loudness has not been
measured is *not yet examined*; it is not a recording whose loudness is zero,
and a ranking function that substitutes zero has invented a fact and then
sorted on it.

**A ranking function MUST NOT substitute a value for an absent one.** A res
missing a signal is ranked on the signals it has, and the result states that
the comparison was made on fewer.

A substituted default is least visible here of anywhere in the system: a wrong
number in a sort order produces a plausible-looking list and no error anywhere.

### 11.2 Two absences mean different things to a ranker

*Not held* is permanent and is a fact about the holding. *Not yet examined* is
a scheduling fact that resolves itself, and a result set ranked while analysis
is pending will rank differently tomorrow.

A surface MUST be able to say so: *three of these were ordered without tempo,
which has not been measured yet*. A ranking that silently changes when a
background job finishes is indistinguishable from a defect.

### 11.3 A similarity that cannot be computed is not answered

The OpenSubsonic `sonicMatch` type carries `similarity: -1` for a server that
does not compute similarity **at all**. That is a statement about the
deployment rather than about a pair, so it is not §11.1's slot: a client shown
-1 for one recording may conclude the extension is unanswerable and stop
asking.

Where a res carries no body from the ordered tool it is **left out of the
result**, and never returned with a fabricated 0.0, which would mean *maximally
dissimilar* and is a claim the deployment cannot support. The count returned is
then smaller than the count requested, which both endpoints permit — `count` is
a maximum. The native API (§15.1) carries the absence as [spec-10] §5.2's
state, having a field to carry it in.

---

## 12. The outbound direction

### 12.1 Every existing rule points inward

[spec-05] §14 governs what a *query* discloses, and every request it describes
is one the deployment makes about a holding. [spec-01] §11.2 and [spec-06] §6.3
govern who inside the household may see consumption data, and enumerate the
surfaces it must not leak through — resumption lists, play counts,
recommendation output, aggregates. All of them are internal.

Consumption data leaving the household is unaddressed in every direction.
[notes-07] proposes it directly: implementing `scrobble` outbound and
submitting listens to ListenBrainz.

### 12.2 The rules

**No consumption datum leaves the household except by a per-principal election
that is off by default and revocable.** One principal's election MUST NOT
export another's, and a household-level setting cannot exist, because
consumption is not a household-level thing ([spec-01] §11.2).

**No operation of §2 may issue an outbound request, and none may be triggered
by a render where it would.** [spec-05] §14 states this for matching and gives
the reason: a query issued because someone opened a page tells an outside party
what that person is looking at, converting a catalog surface into a channel
disclosing consumption. Everything in that argument applies to all four
operations and one thing more — spec-09's are the ones a surface most naturally
calls on render. Ranking a facet result, ordering a browse mode and answering a
search reach nothing outside the house, and the rule does not touch them.

**No derived body leaves the household.** A vector, an embedding, a transcript,
a segment boundary, a component set and a face embedding are each computed from
the household's own bytes or about its own people, and no election reaches
them: the first rule above is about what a person did, and this is about what
the house holds. §14.3 rests on this rule.

**Model weights are fetched once, at deployment time.** Never per holding,
never carrying anything about a holding, and never on a path a render can
reach. A gated model's acceptance is a one-time disclosure of the deployment
and is recorded as one (§4.2).

### 12.3 Importing a population's judgement is not collaborative filtering here

A similarity fact a service computed over *its* users is an imported
measurement under [spec-05] §8.6 — a number the source computed, importable
only where the source names the tool and version. It is not this household's
consumption and [spec-06] §6.3 does not reach it.

It does disclose, at the ordinary [spec-05] §6.2 rate: a query names a
recording the household holds. That is the existing bargain and needs no new
rule. What needs a new rule is §12.2's first, and only because the traffic runs
the other way.

**An imported similarity is held as a cache keyed by the pair, and never as an
annotation.** [spec-02] §3.1 gives an annotation one target and a similarity is
about two res, so no annotation shape holds one. The cache carries the source
and the source's snapshot ([spec-05] §8.6), is evicted rather than migrated,
and its loss is not data loss — which keeps a number the household did not
compute out of the catalog and out of backup ([spec-03] §7).

Which pairs are asked about is itself a disclosure, because the pairs a
recommendation needs are a function of one principal's taste. An import
therefore runs on a schedule over the catalog and never over a recommendation's
candidates, which is §12.2's second rule reaching the one operation that would
otherwise carry consumption outward a pair at a time.

---

## 13. The generative tool

### 13.1 It is a deriving tool and nothing else

A locally-run language model is a deriving tool in [spec-02] §4.1's sense. It
is not an agent ([spec-02] §4.1, LRM-E6), it asserts nothing, and [spec-05]
§3.1's distinction holds unchanged: a provider asserts, a tool computes.

**It runs locally, and a hosted model is not admissible.** The distinction that
makes it a tool rather than a provider is what would place it outside [spec-05]
§6.2's disclosure rules, which bind a provider and not a tool; [spec-04] §8.3's
tool contract constrains what a tool writes and says nothing about what it
sends. §13.4's first use would then put the transcript of the household's
correspondence — [spec-01] §13.7's least replaceable holding — on a third
party's wire under no rule in the series. §12.2's second rule is the general
form and this is the case that makes it necessary.

Its output is a derived body or a candidate. It is never an assertion, never a
nomen with a null assigner ([spec-05] §8.1), never a category a member set,
never a face tag ([spec-05] §9.7), and never one of the three absence states
only a person may establish ([spec-05] §11).

### 13.2 Its version is more than its name

[spec-02] §4.2 requires a version "sufficient to distinguish any two builds that
could produce different numbers for the same input." For a language model that
is the weights, the quantization, and the decoding parameters, because each
changes the output and two of them are deployment choices rather than
properties of the model.

[spec-02] §4.3's refusal to assume determinism is more true here than anywhere
else in the series, and nothing is compared by recomputing.

### 13.3 A prompt is a computation

§4.2's gate applies to what enters a prompt exactly as it applies to what
enters a vector. A value under a use-class prohibition MUST NOT be placed in
one.

Summarising a film's description is the most natural thing to do with a local
model and a catalog, and it is the one thing TMDB's terms name. A gate that is
asserted rather than enforced fails first here.

### 13.4 What it is good for

- Subject and topic extraction over a transcript, as a candidate a member
  accepts ([spec-05] §9.8's mechanism, which exists for signals "too weak to act
  on and far too valuable to discard")
- Naming a generated set (§8.5)
- Turning a stated request into a scope and a weight override (§8.2), which is
  a query-side use that writes nothing

---

## 14. Faces

### 14.1 Recognition produces candidates; only a person produces a name

[spec-05] §9.7 is already normative: "Faces are authored." Matching may not
write a face tag and neither may this document.

The mechanism is three steps, and the split between them is [spec-02] §3.2's:

1. A detector produces a `spatial` address per detected region — derived.
2. An embedding over each region, and a clustering over the embeddings —
   derived, and re-derivable.
3. A member names a cluster. That produces **one authored annotation per
   member photograph, each targeting its photograph with its own selector** —
   never one annotation targeting the cluster.

Step 3's shape is §6.2 again. The cluster is derived and will move when the
detector or the embedder changes version; the names survive because they were
never anchored to it.

The grouping does not survive, and §6.2's recomputation does not carry it.
A region query is spatial containment — which regions under the current
derivation hold this instant — and a cluster is an identity grouping in an
embedding space, where a new embedder's clusters stand in no containment
relation to the old. **A re-clustering therefore proposes each new cluster's
name from the names already carried by the photographs it contains**, as a
candidate a member accepts ([spec-05] §8.5). Where the photographs under one
new cluster carry two names it proposes neither, which is the case a person
needs to see.

### 14.2 The sharpest terms in the space

The strongest open face-recognition weights — InsightFace's `buffalo` and
`antelopev2` packages — are released for non-commercial research only, with the
MIT licence covering the code and not the weights. This deployment is one
household running its own holdings and meets that term, so those are the
weights it uses.

What the registry records is the split rather than the conclusion: a project's
code licence is not its weights' licence, and the two differ here. CompreFace
is the case that makes the distinction worth holding — Apache-2.0 as a system,
shipping InsightFace weights in its default configuration, and stating no
licence for them anywhere. §17 records the weights' terms and not the
project's.

### 14.3 What a face embedding is

A face embedding of a relative is biometric data about a person who holds no
principal and never will ([spec-01] §10.1). It never leaves the household under
§12.2, and the thing worth preserving — the name a member gave the cluster — is
authored and is backed up.

**Derived does not mean disposable here; it means re-created.** [spec-02] §3.2
keeps an embedding out of backup because [spec-01] §13.7 expects it to be
regenerated after loss, and [spec-04] §8.4 regenerates it on every version
change without being asked. Deleting a face embedding therefore does not delete
it, and for biometric data that is the wrong default.

**A member may withdraw a face, and a withdrawal is authored.** It records the
res and the person, it is backed up and survives re-derivation like any
authored annotation, and analysis reads it before detecting: a withdrawn
photograph produces no `spatial` address and no embedding, and a withdrawn
person's name is removed from every cluster it was given to. Any member may
withdraw any face, because [spec-06] §6.2 makes members peers over the catalog
and the person in the photograph is not there to ask. Withdrawal is the one
face operation that needs no cluster to exist first.

---

## 15. Surfaces

### 15.1 The native API

Search, similarity and recommendation are operations rather than res, so they
are paths of their own rather than second addresses for a res, which [spec-10]
§10.1 forbids.

Every result carries what [spec-10] §6.2 requires of one, the states of §11,
and the ranker attribution of §9.3.

### 15.2 What the OpenSubsonic surface gains

[spec-07] §6.2 advertises exactly six extensions and records that
"`sonicSimilarity` waits for spec-09." It has stopped waiting.

| Extension | Version | Endpoints |
| --- | --- | --- |
| `sonicSimilarity` | 1 | `getSonicSimilarTracks`, `findSonicPath` |

| Endpoint | Parameters | Returns |
| --- | --- | --- |
| `getSonicSimilarTracks` | `id`, `count` (default 10) | `sonicMatch[]` |
| `findSonicPath` | `startSongId`, `endSongId`, `count` (default 25) | `sonicMatch[]`, start first and end last |

`sonicMatch` carries `entry` (a `Child`) and `similarity`, a number where 1.0
is identical and 0.0 is maximally different. §11.3 governs a res carrying no
body, and -1 is reserved to its protocol meaning: this deployment computes
similarity, so it never answers -1.

Both are §2's similarity operation and neither reads consumption, so both are
answerable identically for every principal and both cache household-wide.

`findSonicPath` is where regions pay for themselves on a surface a third-party
client already speaks: a path between two recordings through intermediates,
built on end-of-region to start-of-region distance (§8.4) rather than on track
centroids.

[spec-07] §6.3's **Browsing** group also gains `getSimilarSongs` and
`getSimilarSongs2`, where the protocol puts them.

| Endpoint | Parameters | Returns |
| --- | --- | --- |
| `getSimilarSongs` | `id` — an artist, an album or a song — and `count` (default 50) | `similarSongs` |
| `getSimilarSongs2` | `id` — an artist — and `count` (default 50) | `similarSongs2` |

Given a song, both are §2's similarity unchanged. Given an artist or an album,
§7.1's component set is what answers: the near agents are those with a
component near one of this agent's, and the songs returned are this agent's and
theirs. Both read no consumption, so both cache household-wide and answer
identically for every principal.

They are worth adding because the implementations a client is used to require a
third-party scrobble-network key to answer them at all, and answering from
content requires no outside party and works for a recording nobody else holds.

### 15.3 A score on the wire is this deployment's number

Exposing `similarity` does not breach [spec-02] §5.1 or [spec-05] §8.5. Those
forbid comparing one tool's confidence with another's; `similarity` is one
deployment's statement about one comparison method over one pair.

What follows is that the response must be produced by one method. A `similarity`
fused across two rankers is a number with no meaning, and §9.2's fusion
produces ranks rather than a score precisely so that this is never tempting.

---

## 16. What this requires of other documents

| Document | What changes |
| --- | --- |
| [spec-01] §17 | the registry list gains the body-type ordering §10.2 selects by |
| [spec-02] §4.1 | a derivation records the terms of every value that entered it, and carries an input body's terms forward (§4.2) |
| [spec-02] §5.2 | satisfied by §10; the handover is discharged, for every body type and not for measurements alone |
| [spec-04] §8.2 | the two families gain the detectors, segmenters, transcribers and embedders §5.3 requires; each meets §8.3's contract unchanged |
| [spec-04] §8.3 | the tool contract gains a terms declaration and a disclosure declaration (§4.2) |
| [spec-04] §8.4 | re-analysis reads a §14.3 withdrawal before detecting, and produces no region for a withdrawn holding |
| [spec-05] §3.2 | matching may write a description a source supplies, which §4.1's display case needs and which no write class currently holds |
| [spec-05] §5.5 | the corpus table gains §5.2's five rows, one of which distinguishes MusicBrainz supplementary data from its core |
| [spec-05] §6.4 | satisfied by §4; the term it said "binds spec-09" is now bound |
| [spec-06] §6.1 | a Member's own consumption data includes the export election of §12.2 and the taste model of §7.1 |
| [spec-07] §1.2 | the interim "matches names and orders them alphabetically" is superseded by §9 |
| [spec-07] §4.1 | the resource table gains §15.1's three operation paths, and a result set carries the ranker attribution of §9.3, the index attribution of §10.3 and the states of §11 |
| [spec-07] §6.2 | `sonicSimilarity` version 1 is advertised |
| [spec-07] §6.3 | the Searching group gains `getSonicSimilarTracks` and `findSonicPath`; the Browsing group gains `getSimilarSongs` and `getSimilarSongs2` |
| [spec-07] §6.4 | `search2` and `search3` match what §9.1 matches, which includes the credit names they already reach |
| [spec-10] §9.2, §13.4 | Continue and Recently added keep the orderings those sections fix; §2's ranking orders what they do not |
| [spec-10] §9.4 | the "only 'more like this'" sentence gains similarity, and a recommendation composed from the requesting principal's own consumption, as two further permitted kinds (§2.2) |
| [spec-10] §9.5 | the interim ordering by [spec-10] §6.4 is superseded, and the rule that the surface matches every nomen is read against §4.1's gate: a value under a use-class prohibition is matched by scan and not held in an index |

---

## 17. Registries

Seed data ([spec-01] §7.5), maintained through releases. **A registry this
section names MUST be populated before the section depending on it is built,
and no code path may supply a value a registry omits.**

- **Themes**: per theme, the per-dimension weight override (§8.3), the
  set-variance ceiling, the duration tolerance (§8.1) and the familiarity
  ratio (§8.2)
- **Tool terms**: per tool, the code licence, the weights licence, the
  obligations, and what acquiring it discloses (§4.2). Each is recorded with
  the URL it was read from and the date it was read, because a project's own
  summary page and the licence shipping with its weights disagree often enough
  that a licence name alone is not a record
- **Source terms for computation**: per source, which of §4.1's three kinds its
  terms are
- **Descriptive corpora**: which of [spec-05] §5.5's corpora carry descriptive
  signal worth holding, and for what (§5.2)
- **Component bounds**: the largest number of components a model may be fitted
  to, and the minimum preference count below which one is not fitted (§7.1,
  §7.3)

Two things §10.2 and §12.2 need are not seed data and are not held here.

The **body-type tool ordering** is deployment configuration: [spec-01] §7.5
makes seed data identical across every deployment and forbids mutating a seeded
row, and §10.2's ordering is a judgement about the tools this deployment runs.

A principal's **export elections** and **taste model** are that principal's own
consumption data, held where [spec-01] §11.2 holds the rest of it. Neither is
shipped, neither is household-visible, and neither is a res, so neither is an
annotation ([spec-02] §3.1).

---

## 18. References

- **[spec-01]** through **[spec-08]**, **[spec-10]**, this system.
- **[notes-07]** [Analysis, taste and playlists](../notes/07-analysis-taste-and-playlists.md).
- **[notes-09]** [Open questions](../notes/09-open-questions.md).
- **[BITTNER]** Bittner, R., Gu, M., Hernandez, G., Humphrey, E., Jehan, T.,
  McCurry, P., Montecchio, N., *Automatic Playlist Sequencing and Transitions*,
  ISMIR 2017, for §8.4's graph traversal.
- **[OPENSUBSONIC]** OpenSubsonic API, the `sonicSimilarity` extension and the
  `sonicMatch` response type, for §15.2.
- **[TMDB-TERMS]** TMDB API Terms of Use, §1.C, for §4.1's use-class
  prohibition.
- **[METABRAINZ-LICENCE]** MusicBrainz database licensing, for the core and
  supplementary split §4.1 records.
- **[DISCOGS-DATA]** Discogs monthly data dumps, CC0, for §5.2.
- **[ESSENTIA-MODELS]** The licence distributed with the Essentia model files,
  for the CC BY-NC-SA 4.0 weights and the two upstream lineages §4.1 records.
  It governs over the project's own licensing page, which states a different
  Creative Commons clause.
