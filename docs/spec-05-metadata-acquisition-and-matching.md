# Metadata Acquisition and Matching

**Specification 05**
**Status:** Draft
**Version:** 0.2
**Depends on:** spec-01 (Catalog Data Model), spec-02 (Annotations and Derived
Data), spec-03 (Assets, Storage and Preservation), spec-04 (Ingest and
Normalization), spec-06 (Principals, Auth and Authorization)
**Obsoletes:** nothing

## Abstract

spec-04 places a holding from its own bytes and stops there. Two pressings of
one album are two works, a film is whatever its file name said, an artist is a
string, and the same song on an album and on a compilation is two recordings.
This document specifies how the catalog learns what else is known about a
holding — from the holding itself, from a corpus the household keeps, and from a
provider outside it — and, more importantly, what the catalog is permitted to
conclude from what it learns.

Its governing rule: **matching acts on an equality and never on a resemblance.**
A resemblance may supply a value. Only an equality may change the shape of the
catalog.

---

## 1. Introduction

### 1.1 Scope

- What a provider is, and why it is an agent where a deriving tool is not
- External identifier schemes, the entity level each one identifies, and what a
  match at one level licenses
- The three kinds of source, and the order of resort among them
- The match record, and the ranking of evidence when sources disagree
- The provider contract: what it answers, what a query discloses, what its
  terms oblige
- Acting on a match: names, identifiers, categories, credits, and equation of
  two res
- Candidates: what matching raises for a person rather than deciding
- Matching per media class, including classes spec-04 has no placement rule for
- The household's own catalog as an authority over its own media
- What matching may never assert

### 1.2 What this document does not specify

Placement (spec-04 §6); matching runs after it and never replaces it. The
computation of fingerprints, perceptual hashes and transcripts, which is
spec-04 §8's analysis — this document specifies only what is done with one.
Deduplication of assets (spec-03 §8), whose decision vocabulary §8.4 extends
rather than duplicates. Ranking, similarity and recommendation (spec-09). The
correction surface (spec-10 §15). The scheme, corpus and provider vocabularies,
which are registries (§15).

### 1.3 Why this is not part of placement

spec-04 §6.4 requires placement to yield the same releases whatever order the
files arrive in, and spec-04 §3 requires every stage to be idempotent and
resumable from recorded state. A network answer is neither ordered nor
repeatable: a provider consulted twice may answer differently, and a provider
consulted once may not answer at all.

Placement therefore completes without reaching outside the household, and
everything that does reach outside is here. The catalog is correct before the
first query is sent, and stays correct if none ever is.

---

## 2. Conventions

BCP 14 key words per spec-01 §2. References of the form "spec-0N §x" refer to
that document, and "Annex A" to spec-01's Annex A.

*Source* means anything matching takes evidence from. A source is of exactly one
of the three kinds in §5.1: **the holding**, **a corpus**, or **a provider**.

*Evidence* means one value a source supplied about one res.

*Match* means a conclusion drawn from evidence, recorded per §3.3.

*Equation* means concluding that two res in the catalog are one res, which §8.4
governs.

---

## 3. What matching is

### 3.1 A provider asserts; a tool computes

spec-02 §4.1 reserves `agent` for LRM's sense and forbids naming a deriving
component as one, because LRM-E6 places automatons — software programs
specifically — outside the definition of an agent, as "tools used and set up by
an actual agent."

A provider is not such a tool. MusicBrainz, the Grand Comics Database, Open
Library and TMDB are organizations. They can be granted rights, they are
accountable for what they publish, and what they supply is an assertion they
made rather than a measurement of the household's bytes.

**A provider is a collective agent (LRM-E8) and MUST be recorded as one.** A
deriving tool MUST NOT be.

The distinction is load-bearing in three places:

- A name a source supplies is a nomen that source assigned (LRM-R14), so
  spec-01 §7.3's nullable assigner already carries it, and resolution already
  prefers the household's own name over it with no further rule (§8.1).
- An assertion is not a derivation. It carries no tool version, and spec-02
  §5.2's supersession does not reach it; §6.5 governs it instead.
- A measurement a source *computed* is a derivation even though a source
  supplied it, and §8.6 governs importing one separately from the facts the
  same source asserts.

A source that is not an organization — a sidecar file, the holding's own tags —
asserts nothing on its own behalf. Its assigner is the agent that wrote it where
that is known, and null where it is not, and §8.1 is normative.

### 3.2 What matching writes, and what it never touches

| Matching MAY write | Matching MUST NOT touch |
| --- | --- |
| external identifier nomens (§8.2) | any asset, and any stored byte |
| names, as nomens assigned to their source (§8.1) | any digital item |
| categories, with automatic provenance (§8.3) | the seed set (spec-01 §7.5) |
| credits, and the agents they name (§8.3) | a value a member asserted |
| agents, places and time-spans its evidence names (§9.7) | an authored annotation (spec-02 §3.2) |
| relations among catalog res | a consumption event (spec-01 §11) |
| an equation of two res, under §8.4 | an arrangement (§9.2) |
| candidates and findings (§8.5, §12) | the last three states of spec-10 §5.2 (§11) |

Matching MUST NOT create a digital item or an asset. Those are custody facts,
established by acquisition from bytes that arrived (spec-04 §4), and a
manifestation the household does not hold is a manifestation with no digital
item — which spec-01 §5.2 requires be representable and is not something
matching invents a file for.

### 3.3 The match record

A match record holds what was asked, what was answered, and what was concluded.
It is recorded outside the catalog, as spec-04 §6.4's grouping key is, and it
stands in the same relation to matching that spec-04 §4.2's acquisition record
stands to placement.

| Field | Holds |
| --- | --- |
| identifier | minted per spec-01 §4.1 |
| res | what the match is about |
| scheme | the external identifier scheme, where the match is of one (§4) |
| source | the holding, the named corpus, or the named provider (§5.1) |
| rank | the source's rank under §5.3, and the order the deployment applied |
| query | what was sent, exactly as sent |
| response | what was received, unaltered (§6.1) |
| basis | equality or resemblance (§4.2), and the score where the source gave one |
| snapshot | the corpus snapshot, or the time a provider answered (§5.6, §6.5) |
| conclusion | what was written, including what moved where under §8.4 |
| state | applied, raised as a candidate, empty, or failed (§12) |

**The record outlives the match.** The response is provenance and cannot be
recovered: a provider's answer changes, and the household cannot ask it again
for what it said last year. §5.4's ranking cannot be re-evaluated against
evidence nobody kept, and §8.4's equations cannot be reversed exactly without
the record of what they moved.

---

## 4. Identifiers

### 4.1 A scheme identifies a level

An external identifier is a nomen (spec-01 §4.3). Every scheme in the registry
declares **the entity level it identifies**, alongside its syntax, whether it
validates itself (§4.4), its issuing agent, and whether one res may carry
several of them at that level.

The level is what makes a match actionable, and getting it wrong is the
commonest way a catalog is silently corrupted. A representative selection
follows; the registry (§15) holds the rest.

| Scheme | Identifies | Level |
| --- | --- | --- |
| MusicBrainz work | a composition | work |
| MusicBrainz release group | the release as a thing released | aggregating work |
| MusicBrainz recording | one recorded performance | expression |
| MusicBrainz release | one release | release manifestation |
| MusicBrainz disc ID | one disc's table of contents | medium manifestation |
| MusicBrainz track | one track as released | track manifestation |
| ISWC | a musical work | work |
| ISRC | one recording | expression |
| ISAN | an audiovisual work | work |
| EIDR content ID | per its own record type | work, expression or manifestation |
| TMDB movie | a film, all cuts | work |
| TMDB / TheTVDB series | a series | serial work |
| TMDB / TheTVDB episode | one episode | work |
| IMDb title | a film or an episode | work |
| Open Library work | a work | work |
| Open Library edition, OCLC number, LCCN | one edition | manifestation |
| ISBN | one edition in one format | manifestation |
| ISSN | one continuing resource in one medium | manifestation |
| ISSN-L | the serial across its media | serial work |
| GCD series | a comic series | serial work |
| GCD issue, Metron issue | one issue | manifestation |
| IGDB game, MobyGames game | a game | work |
| No-Intro / Redump entry | one dump of one release | manifestation |
| `podcast:guid` | the podcast | serial work |
| an item `<guid>` in a feed | one episode as published | manifestation |
| Audible ASIN | one audiobook edition | manifestation |
| GTIN, UPC, EAN | one product as sold | manifestation |
| VIAF, ISNI, ORCID | one agent | agent |
| GeoNames ID, Getty TGN | one place | place |
| Wikidata QID | per item | any res |

Two entries deserve their qualification. EIDR and Wikidata do not identify a
fixed level: an EIDR record states its own type, and a Wikidata item's level is
whatever the item is about. For both, the level is read from the record and MUST
NOT be assumed; a record whose level cannot be read is evidence for nothing
under §4.3.

### 4.2 Equality and resemblance

**Matching acts on an equality. It MUST NOT act on a resemblance.**

An **equality** is a value the holding itself carries, or one computed from its
bytes by a function that admits no near miss: an identifier in its tags, an
identifier in a companion that arrived with it (spec-04 §4.6), a digest found in
a corpus of digests, a disc table of contents, a GUID computed by a published
rule from a value the holding carries.

A **resemblance** is a judgement with a threshold: a provider's answer to a
search, an acoustic fingerprint's nearest neighbour, a perceptual hash within a
distance, a title and a duration that agree. A threshold is a place where a
wrong answer is produced by design, and no score makes it something else —
spec-02 §5.1 already refuses to let confidence decide, and this is that rule
applied to identity.

| Signal | Basis | Matching |
| --- | --- | --- |
| an identifier in the holding's own tags | equality | acts |
| an identifier in a colocated companion | equality | acts |
| a digest present in a corpus of digests | equality | acts |
| a disc table of contents from a cue sheet | equality | acts |
| a GUID computed by a published rule | equality | acts |
| an acoustic fingerprint's nearest match | resemblance | candidate |
| a perceptual hash within a distance | resemblance | candidate |
| a provider's search result | resemblance | candidate |
| a title, artist and duration agreeing | resemblance | candidate |
| a gazetteer's nearest named place | resemblance | §9.7 |

**The rule governs identity and structure, not every value.** A resemblance MAY
supply a name, a description, a cover image, a set of lyrics or a genre,
recorded with its source and its basis, because none of those changes what the
catalog says exists. What a resemblance MUST NOT do is establish that two res
are one (§8.4), or be written as an external identifier nomen — which would
become an equality on the next pass and act through §8.4 the second time.

**An identifier reached by resemblance is recorded on the match record and
raised as a candidate. It becomes a nomen when a member accepts it, or when an
equality confirms it, and not before.** Without this rule, one fuzzy search
launders into a permanent fact.

An equality is also not a guarantee of truth. A mistagged file carries another
recording's identifier and matching will act on it; §5.4 is how the contradiction
is found and §8.4 is why it is reversible.

**An identity key computed from bytes binds to the asset it was computed from,
and never to the manifestation.** A hash over a container, an OpenSubtitles
movie hash, a ROM digest and a disc image digest are all destroyed by
normalization (spec-04 §7), which re-encodes and remuxes. They are computed
against the Acquired asset, recorded against it, and MUST NOT be recomputed
against the Normalized master and expected to agree. This is spec-01 §8.4's
reasoning about addressing bases, arriving at the same place from identity.

### 4.3 What a match at one level licenses

Equating two res at one level:

- **forces** the equation of every res above them reached by a relation that is
  many-to-one (spec-01 §6.1), because the child can have only one;
- **implies nothing** about any res below them.

| Equated | Forced above | Not implied below |
| --- | --- | --- |
| two expressions | their works are one — LRM-R2 is 1-to-M | their manifestations stay distinct |
| two digital items | their manifestations are one | their assets stay distinct |
| two items | their manifestations are one | — |
| two manifestations | nothing — LRM-R3 is M-to-M | their expressions stay distinct |

Two traps this forbids, both of which a provider's own page invites:

**Two works carrying one TMDB movie identifier are one film, and their
expressions are not one.** The theatrical cut and the director's cut carry the
same identifier because the scheme identifies the film. A scheme that identifies
a work licenses nothing at expression level, whatever a provider displays on one
page.

**Two manifestations carrying one ISBN are one edition, and nothing follows
about what they embody.** LRM-R3 is many-to-many, so an edition carrying an
introduction embodies the novel's expression and the introduction's alike
(spec-01 §5.3), and equating the editions does not equate anything they carry.

### 4.4 Identifiers that validate themselves

Several schemes carry a check digit, and it is computed locally, before the
identifier is recorded or used as a key:

| Scheme | Check |
| --- | --- |
| ISBN-13, GTIN, ISWC | modulo 10 |
| ISNI | ISO/IEC 7064 MOD11-2, the check character being a digit or `X` |
| ISBN-10 | modulo 11 |

ISRC has no check digit; its 12 characters can be checked only for the shape the
standard defines — a five-character prefix, a two-digit year of reference and a
five-digit designation. A UUID's form can be checked and its existence cannot.

A syntactically invalid identifier in a holding's evidence is a finding (§12),
not a value silently discarded. It usually means a tagger wrote a field it did
not understand, and that is worth seeing.

Validation establishes form and never reference. A well-formed ISBN naming
another book is still a well-formed ISBN.

---

## 5. Sources

### 5.1 Three kinds

| Kind | Is | Discloses |
| --- | --- | --- |
| **The holding** | its bytes, its embedded tags, and the companions that arrived with it (spec-04 §4.6) | nothing |
| **A corpus** | a body of published data of which the household holds a copy | nothing |
| **A provider** | a service the household asks | the query, and over a library, the library |

### 5.2 The order of resort is not a fallback

The order among the three is a property of what each one is, and not of whether
one of them failed.

The holding is consulted first because it is the thing itself. A corpus is
consulted before a provider because it answers the same question without telling
anyone it was asked. A provider is consulted where the authority for a scheme
lives outside the household and publishes no corpus — a case in which nothing
failed, because there was never anything nearer to ask.

**A source that cannot answer has not failed.** A corpus with no row for an
identifier is silent. Silence is not an error, is not recorded as one, and is not
a reason to escalate to a provider *for that scheme* — the corpus answered
everything it knows. Matching moves outward when the scheme it needs is answered
only out there, which is a fact about the scheme and is in the registry.

A source that did not answer at all is a different thing, and §12 governs it.
The distinction is between a source that said "I do not hold this" and a source
that said nothing.

### 5.3 Evidence rank

spec-04 §4.6 states the order and permits a deployment to reorder the automatic
sources. Normatively:

| Rank | Source |
| --- | --- |
| 1 | a member's assertion about this res |
| 2 | a colocated companion (spec-04 §4.6) |
| 3 | the holding's own embedded tags |
| 4 | a corpus |
| 5 | a provider |

Rank 1 is never outranked (spec-01 §7.5, spec-02 §5.3) and MUST NOT be placed
anywhere but first. A deployment MAY order 2 through 5 otherwise, MUST apply one
order for the whole of a match, and MUST record on the match record which order
it applied — a rank means nothing without knowing which ranking produced it.

A companion outranks embedded tags because a companion was written about this
holding, in this directory, by the household's own tooling or by a person,
whereas a tag travelled with the file from wherever the file came from.

**Where a companion carries its own per-field provenance, that provenance is
used in place of the companion's rank.** A `MetronInfo.xml` field recording the
source it was taken from ranks as that source and not as rank 2, which is what
its carrying the information is for.

### 5.4 Disagreement

Where sources of different rank disagree, the higher-ranked value is recorded
and **the lower-ranked value is recorded too**, as a nomen of the source that
supplied it (§8.1). Two names are two nomens and spec-01 §7 holds both without
strain.

Identifiers are not like names. **Where two sources supply different identifiers
of one scheme at one level, matching MUST NOT choose between them.** A holding
whose tags carry one recording identifier and whose sidecar carries another is
not a holding with two recordings; it is a holding about which the evidence is
contradictory. The contradiction is a finding, and the value is left unwritten.

This is spec-04 §6.4's refusal to place a track whose own evidence names two
releases, applied after placement.

The exception is a scheme whose registry entry permits several at one level. A
recording may carry several ISRCs, because distributors assign their own to the
same recording; two ISRCs are therefore two identifiers of one expression and
not a contradiction.

### 5.5 Corpora

A corpus is a body of published data the household holds a copy of. It answers
without disclosing, and its terms are the terms of the published data rather than
of a service.

| Corpus | Answers | Terms | Held as |
| --- | --- | --- | --- |
| MusicBrainz | works, recordings, tracks, releases, artists, disc IDs, ISRCs | the core data is CC0 | a replicated PostgreSQL database |
| Wikidata | the mapping between schemes for one res; agents; places | CC0 | dumps, or a local query endpoint |
| Open Library | works, editions, ISBNs, authors, covers | CC0 | monthly JSON dumps |
| GeoNames | places, by coordinate and by name | CC BY 4.0 | the gazetteer dump |
| No-Intro, Redump | the identity of a cartridge or disc dump, by digest | per project | XML DAT files |
| Grand Comics Database | series, issues, creators | CC BY-SA 4.0 | SQLite dumps |
| AcousticBrainz | Essentia music-extractor descriptors per recording identifier | published; the project ended in 2022 | tarballs |
| PRONOM | format identity | — | already required by spec-03 §6 |

Wikidata earns its place by being the only one of these that answers a question
none of the others can: *what does this thing's identifier in one scheme
correspond to in another*. It holds over a thousand external-identifier
properties, so a holding that arrived knowing its ISBN can reach its VIAF author
and its Open Library work without a single provider query.

AcousticBrainz is a corpus of **derived** data, so §8.6 governs importing from it
and not this section's rules for asserted facts. Its frozen date is its snapshot
and will not advance: a recording it does not cover will never be covered, and a
deployment MUST NOT keep it perpetually due.

### 5.6 A corpus has a snapshot

Every corpus records the date of the data it holds, and every match drawn from
one records that snapshot. A newer snapshot makes the matches drawn from an
older one due again (§8.7).

A corpus whose snapshot cannot advance is recorded as frozen, and its matches
are never due again.

---

## 6. The provider contract

Every provider meets the same contract, in the shape spec-04 §8.3 gives a
deriving tool.

### 6.1 What a provider answers

- **Description.** A provider answers what it is — its name, the schemes it
  answers in, the entity levels those schemes identify, and its snapshot or that
  it has none — without being queried about any holding.
- **One query per request.** A provider client sends one query per call and
  holds no queue of its own. Concurrency is the stage's (§7).
- **Named values.** Values are returned by name, never positionally, as spec-02
  §6.1 requires of a derived body and for the same reason.
- **Raw values.** The response is stored as received (§3.3). Mapping a
  provider's vocabulary onto the household's happens afterward, from the stored
  response, so that a change to the mapping does not require asking again.
- **Read only.** A provider client writes nothing to storage and nothing to the
  catalog outside the applying stage's own transaction.
- **Declared disclosure.** §6.2.
- **Declared terms.** §6.4.

### 6.2 What a query discloses

Every provider registry entry states what a request sends and what that reveals
over a library.

spec-04 §11 states it for the one lookup ingest performs. Generally: a request
tells a provider that this household holds the thing the request names, and the
sequence of requests over a library is the library.

**A query MUST send the least that identifies the thing.** An identifier where
the holding carries one; a fingerprint where the scheme needs one; a title only
where nothing else exists. A query MUST NOT carry the file's name, its inbox
path, the household's other holdings, or any principal. A file name is
disclosure: inbox paths carry members' names, scanner software's defaults, and
the name of wherever the file came from.

A deployment MAY disable any provider. A deployment that discloses nothing runs
the first two kinds of source and states which schemes are therefore
unanswered — which is spec-10 §5.2's *not yet examined*, stated rather than
hidden.

### 6.3 Identification, rate and contact

Per spec-04 §6.4's precedent, requests carry a User-Agent naming the deployment
and the contact it is configured with. **A deployment configured with no contact
runs no provider stage, says so, and leaves those schemes unanswered.**

Rates are registry values. Where a provider publishes a figure, the registry
records it; where one does not, the registry records a rate the deployment
chose, and a provider whose rate is a guess is marked as one. The published
figures:

| Provider | Rate | Credential | Identification |
| --- | --- | --- | --- |
| MusicBrainz web service | 1 request a second (spec-04 §6.4) | none | contact in User-Agent |
| AcoustID | 3 requests a second | an application key | the key |
| LRCLIB | not fixed; answers 429 with `Retry-After` | none | client name, version and contact in User-Agent |
| IGDB | 4 requests a second, 8 concurrent | a Twitch client ID and OAuth token | the token |
| TMDB | not published as a fixed figure | an API key | the key |
| TheTVDB | not published as a fixed figure | a per-project key, and a subscriber PIN where the project is not licensed | the key |
| Nominatim, public instance | 1 request a second, and bulk reverse geocoding forbidden outright | none | User-Agent or Referer |
| EIDR | no published limit for lookup | none for lookup | User-Agent |

A `429` MUST be honoured and a `Retry-After` obeyed. **A `429` MUST NOT be
recorded as an empty result.** A rate limit recorded as "no match" disables the
scheme silently for every holding processed while the limit held, and the
library ends up marked as unmatchable by a condition that lasted a minute.

A rate limit is also not a transient failure in §12's sense: retrying it sooner
is the thing it forbids. It reduces the stage's rate and defers the work.

Nominatim's own policy forbids bulk reverse geocoding against its public
instance and directs power users to run their own. The operational constraint and
the privacy posture of §9.7 agree, and §9.7 takes the corpus.

### 6.4 Terms

Each provider registry entry records its terms and the obligations they place on
the deployment.

| Provider | Obligation |
| --- | --- |
| TMDB | non-commercial use only; attribution naming TMDB and using its logo; MUST NOT be used in connection with a machine-learning or artificial-intelligence application, including for training |
| TheTVDB | a per-project key; end users of a project holding no commercial licence require a subscriber PIN |
| AcoustID | free for non-commercial use |
| IGDB | free for non-commercial use, under the Twitch Developer Services Agreement |
| ScreenScraper | free, behind an account |
| TheGamesDB | a private key for usable limits |
| MobyGames | a paid API |
| Grand Comics Database | CC BY-SA 4.0: attribution, and share-alike on anything redistributed |
| GeoNames | CC BY 4.0: attribution |
| MusicBrainz, Wikidata, Open Library | CC0 |

These bind the deployment's use of the provider. They are not the rights
modelling spec-01 §1.1 excludes, which concerns rights in the household's own
holdings.

**Where a provider's terms cannot be met, the provider is not configured.** A
term is not met by declining to record it.

TMDB's prohibition reaches further than this document. A feature vector or an
embedding computed over TMDB content is the use that term forbids, and spec-09
§4.1 classes it as a use-class prohibition binding the computation rather than
the display. The provider registry is where that is knowable before the code that
would violate it is written, and a value's provider MUST remain recoverable from
the match record for exactly this reason: spec-09 §4.2 refuses the computation on
the terms the record carries, and a body that exists is evidence it occurred.

### 6.5 Snapshot and supersession

A provider has no snapshot. Its answer is true of the moment it was given, and
the match record holds that moment.

| Relationship | Outcome |
| --- | --- |
| the same provider, a later answer | the later supersedes the earlier for that res and scheme |
| a corpus, a later snapshot | the later supersedes the earlier |
| different sources | neither supersedes; both stand, as nomens of their own sources |
| any source against a member's assertion | never (spec-01 §7.5, spec-02 §5.3) |

A provider's changed answer MUST NOT silently undo an equation §8.4 performed.
An equation is reversed by a person, or through the record that made it, and
never by a later answer — otherwise a provider's edit reshapes the household's
catalog without the household hearing of it.

---

## 7. The stages

Four stages, each a unit of scheduled work, each idempotent, each finding its
work by querying for what lacks its output and carries no recorded failure for
it (spec-04 §3).

| Stage | Reads | Produces |
| --- | --- | --- |
| **Key** | a placed holding, its tags and its companions | the identifiers and computable keys it carries, as match records |
| **Resolve** | a match record carrying a key | the source's answer, recorded on it |
| **Apply** | a resolved match record | catalog writes under §8, or a candidate |
| **Reconcile** | the catalog | candidates from resemblance, and findings from contradiction (§5.4) |

Key discloses nothing and runs for every holding. Resolve is where §5.1's kinds
are consulted, and a deployment that discloses nothing runs it no further than
the corpus.

Concurrency is set once per stage, in the queue configuration, and a stage MUST
NOT run a pool of its own beneath it. The rate limits of §6.3 are a property of
the provider and bind across stages and across concurrency.

**No stage runs inside placement's transaction.** spec-04 §6.4 requires it of
the one lookup it describes; it holds generally.

All catalog writes matching makes are the deployment's own, attributed to the
System principal (spec-06 §6.1).

### 7.1 Cold start and re-matching

A catalog placed before a scheme existed in the registry is found by the same
query that finds a newly placed holding: adding a scheme, adding a corpus, or
advancing a corpus snapshot makes every affected holding due. There is no
separate backfill, and there is nothing to migrate.

A holding carrying no match record for a scheme is due for it, which makes a
catalog that predates a stage indistinguishable from one the stage has never
reached.

---

## 8. Acting on a match

### 8.1 Names

A name a source supplies is a nomen whose assigner is that source's agent
(spec-01 §7.3, LRM-R14).

**A source's name MUST NOT be written with a null assigner.** A null assigner
denotes the household's shared vocabulary, and writing a stranger's word into it
breaks spec-01 §7.3's inversion in the one direction it cannot recover from: the
marked case becomes unmarked, and the household's own name has nothing left to
outrank it by. Resolution then prefers a provider's title over the name the
household actually uses, on every surface, for good.

Where the source is not an agent — a tagger, a sidecar of unknown authorship —
there is no agent for the name to be assigned to. **Such a name is not written
as a nomen.** It is held on the match record until a member accepts it, and the
member is then its assigner. Writing it with a null assigner would put a
stranger's word into the household's shared vocabulary, which spec-01 §7.3
reserves for the household's own, and no third answer is true.

Script and language come from the source where the source states them. Where a
source states no language, the nomen's language is **unknown** (spec-01 §7.2),
which is a value of its own. It is not null: null means absent, absent means the
household's own untagged vocabulary, and a source's silence is not a claim to
belong to it.

### 8.2 External identifier nomens

An external identifier is written as a nomen in its scheme, with the scheme's
issuing agent as assigner where the registry names one, and the supplying
source otherwise.

An identifier is written only where it reached the holding as an equality
(§4.2), or where a member accepted a candidate.

A res MAY carry several identifiers of one scheme at one level only where the
registry entry permits it; otherwise the second is a contradiction under §5.4.

An identity key computed from bytes is recorded against the asset it was
computed from and not against the manifestation (§4.2).

### 8.3 Categories, credits and agents

**Categories.** Written with automatic provenance, as spec-04 §6.2 requires of
placement's. Matching MAY replace a category placement decided automatically,
because both are automatic and a source that identified the release knows more
than a tag, a directory or a format does. It MUST NOT replace a member's.

Placement decides a category from evidence and from nothing else (spec-04 §6.3),
so there is no category standing in for one nobody stated: a holding the catalog
records always carries a category something said, and what matching improves on is
a reading of weaker evidence rather than a filled-in blank.

**Credits.** spec-04 §6.4 places a credit for each value of a track's artist
tags, and names an artist for each. Matching MAY add an identifier to a credit's
artist, MAY narrow the artist (spec-01 §3.1), and MAY add credits a source names
that the tags did not — a composer, an engineer, a narrator, a letterer.

**Matching MUST NOT remove a credit placement wrote.** A credit is LRM's
statement of responsibility: it records what the release said, and a provider
disagreeing with the release does not change what the release said. Where a
source contradicts a credit, both stand and the source's is a credit of its own.

**Narrowing.** spec-04 §6.4's MusicBrainz artist-type lookup is one instance of
§6's provider contract, and the same narrowing applies from any source that
states an agent's kind. Where two sources disagree on an agent's kind, the agent
stays an artist and the disagreement is a finding: spec-01 §3.1 makes the artist
the honest record of a subclass not yet determined, and narrowing on a coin toss
is worse than not narrowing. An agent is never widened (spec-01 §3.1).

### 8.4 Equating two res

An equation concludes that two res in the catalog are one.

Matching MAY perform one only where all of the following hold:

1. both res carry the same identifier of one scheme;
2. the scheme's registry entry declares the level both res are at;
3. the identifier reached each of them as an equality (§4.2);
4. no member has decided the two are distinct (spec-03 §8.3).

Otherwise the conclusion is a candidate (§8.5).

**The operation is spec-03 §8.3's.** The children of one res move under the
other, and whichever of the emptied res are left holding nothing are recycled.
Matching MUST NOT purge, and MUST NOT delete an asset. spec-04 §6.7 already
performs exactly this for two scans of one letter.

The decision vocabulary is shared with spec-03 §8.3, extended here by two values
so that one vocabulary serves both documents:

| Decision | Means |
| --- | --- |
| *same holding* | one digital item; spec-03 §8.3 |
| *same manifestation* | one manifestation |
| *same expression* | one expression; spec-03 §8.3 |
| *same work* | one work |
| *distinct* | not the same, and not to be asked again |

Because the operation recycles rather than purges, spec-01 §14.1's window makes
an equation matching performed restorable for thirty days, and the match record
names exactly what moved and from where, so the restoration is exact rather than
approximate.

**An equation MUST be reported** on the surface spec-10 §16 requires of findings.
A change to the shape of the catalog that nobody is told about is
indistinguishable from a defect, and it is the one kind of change a member
cannot discover by looking at the value that changed — because no value changed.

### 8.5 Candidates

Everything resting on a resemblance, and every equation matching may not perform
itself, is raised as a candidate through spec-03 §8.3's mechanism: a pair, a
proposed decision, the source, the evidence, and the source's own score where it
gave one, labelled as that source's number and never compared with another's
(spec-02 §5.1).

A candidate matching raised and a candidate a member proposed are one kind of
thing and appear in one place.

Matching MUST NOT raise a candidate a member has already decided. A decided pair
is settled, and re-raising it is how a correction mechanism becomes something
people turn off.

### 8.6 Measurements a source computed

A corpus or a provider may carry values a tool computed rather than facts it
asserts: descriptors, a loudness, a tempo, an embedding. These are derived data
(spec-02 §3.2), and importing one is importing a derivation rather than
accepting an assertion.

**Such a value MAY be imported only where the source names the tool and the
version that produced it. Where it cannot, it MUST NOT be imported.** A number
with nothing behind it, presented as the household's own analysis, is a claim the
deployment cannot support, and spec-02 §4.2 requires a version sufficient to
distinguish any two builds that could produce different numbers.

The derivation recorded (spec-02 §4.1) names that tool and that version, and its
parameters record that the input was the source's copy rather than the
household's asset — the same slot in which spec-04 §8.1 records which asset was
read. spec-02 §5.2 then keeps the import and the household's own run of a
different tool apart without further rule, because they are different tools.

AcousticBrainz is the case this admits: its descriptors name Essentia's music
extractor and its version, so they import, and a household that later runs its
own extractor holds both. A provider field called `bpm` with nothing behind it
does not import.

An imported derivation's version is ordered by **the source's snapshot**, not by
when the household imported it, and spec-02 §4.2 is normative for that. Ordering
it by arrival would let a corpus frozen in 2022 supersede a fresh local run
merely by being imported afterwards. An import carrying no snapshot is not
ordered against local runs at all, and supersedes nothing.

### 8.7 When a match is examined again

| Event | Effect |
| --- | --- |
| a corpus snapshot advances | its matches are due again |
| a scheme is added to the registry | holdings that could carry it are due |
| a provider answers differently | the later answer supersedes (§6.5) |
| a member corrects the value | the value is settled and never due again |

A member's correction MUST make the value not due. spec-01 §7.5 requires the
correction to survive automatic matching, and continuing to query a corrected
value spends a request to re-raise a question a person already answered.

---

## 9. Matching per media class

### 9.1 Music

**Keys the holding carries.** MusicBrainz identifiers in tags, which Picard
writes as a matter of course; ISRCs in tags; and — for an untagged rip — a disc
table of contents, computed from the cue sheet that spec-04 §4.6 already
catalogues as a companion.

The disc-ID path is the strongest key an untagged rip has and it costs nothing:
a cue sheet gives a table of contents, a table of contents gives a MusicBrainz
disc ID, and a disc ID names a medium manifestation exactly. It is an equality
and matching acts on it, and it works for a plain WAV rip that spec-04 §6.4
could only place as a release of its own.

The disc ID has one bound worth recording in the registry entry: it encodes no
information about data tracks, so a cue sheet describing a mixed-mode disc does
not always yield a usable one. Where it does not, the rip falls to the
resemblance below and not to a disc ID computed from part of the disc.

**The same recording across releases.** spec-04 §6.4 places the same song on an
album and on a compilation as two works and two recordings, and defers linking
them here. Two expressions carrying one recording identifier are one expression
(§4.1), so the equation of §8.4 runs; §4.3 forces their works to one, because
LRM-R2 is one-to-many; and their manifestations — the album track and the
compilation track — stay two, which is correct, because they are two tracks on
two releases. The answer is §4 and §8.4 applied, and needs no mechanism of its
own.

**Where no identifier is tagged.** An acoustic fingerprint through AcoustID is a
resemblance and yields a candidate. The resemblance is irreducible rather than
merely imprecise: an AcoustID names a cluster of fingerprints the service holds
to be one recording, a cluster may carry several MusicBrainz recording
identifiers, and separating them requires copies known to come from each
release. It is not identity-bearing even when it answers confidently, and a
deployment MUST NOT record an AcoustID as an expression-level identifier.

**ISRCs.** The same recording is assigned different ISRCs by different
distributors, so several ISRCs on one expression are ordinary and not a
contradiction (§5.4). The registry entry permits it.

**Classical.** Annex A §A.1 already places the composer on the work and the
performer on the expression, and tags routinely put the performer in `artist` and
the composer nowhere, so placement credits the performer as though they wrote it.
Matching repairs this from a source that distinguishes them, and a movement's
place within its composition is a whole-part relation between works (LRM-R18),
which a source holding work hierarchies supplies. Neither is inferable from the
bytes, and both are the difference between a browsable classical library and a
list of file names.

**Values that arrive on a resemblance.** Synchronized lyrics from LRCLIB are
matched on track name, artist, album and duration, which is a resemblance, and
they are nonetheless written: they become derived temporal annotations on the
track manifestation (spec-04 §4.6), they change nothing structural, and a wrong
one is visible in two seconds. §4.2's rule governs identity and not every value,
and this is why it has to.

**Preservation, not identity.** AccurateRip and the CUETools database answer
whether a rip's bytes agree with other people's rips of the same disc. That is a
statement about integrity and belongs with spec-03 §5, not here. The disc ID it
is keyed on is an identity key and belongs here, and one table of contents serves
both.

### 9.2 Film and television

**Keys the holding carries.** A media manager's `.nfo` carrying `tmdbid`,
`imdbid` or `tvdbid`, and a `.plexmatch` carrying the same alongside a
`guid` of the form `source://id` — which is a scheme and a value, and maps onto
§4.1 with no translation. Both are companions under spec-04 §4.6. An identifier
in either is an equality.

**The level trap.** A TMDB movie identifier identifies the film and not the cut
(§4.3). Matching may equate two works carrying it and MUST NOT equate their
expressions, which is exactly the case Annex A §A.2 describes: the theatrical
cut and the director's cut, one identifier, two expressions, and the
representative expression ordering them.

**Episodes and numbering.** Annex A §A.3 makes each episode its own work and puts
season and episode structure at manifestation level. A provider's season and
episode numbers are therefore **arrangement on an LRM-R26 whole-part relation**
(spec-01 §12.1) and not attributes of the episode's work.

Numbering schemes disagree in a way that has no resolution: AniDB splits a
long-running series into one entry per season where TVDB and TMDB keep it under
one, and absolute numbering and season numbering describe the same episodes
differently. Under spec-01 §5.4 this is a disagreement about manifestation-level
arrangement, not about which episode a file holds.

**Matching MUST NOT renumber a household's arrangement to agree with a source.**
Arrangement is a catalog fact of the holding (spec-01 §12.1), the household's
serial manifestation carries one, and it is the household's. A source's
alternative numbering is recorded as that source's identifier for the episode,
and the match record holds the correspondence between the two.

Where a source's episode count and the household's disagree, the difference is a
finding. It usually means an episode is absent, or that a multi-episode file was
placed as one, and both are worth a person's attention.

**An identity key over bytes.** The OpenSubtitles movie hash — the file size plus
a checksum of the first and last 64 kibibytes — identifies one byte sequence and
nothing above it. It is an equality over digital items, it says nothing about the
manifestation, and it does not survive normalization, so §4.2's rule binds it to
the Acquired asset.

**EIDR** answers lookups with no credential and no published rate limit, and its
records state their own level, which makes it the one scheme in §4.1 that can
name an edit as against an abstraction without a per-provider convention.

### 9.3 Books, ebooks and audiobooks

**Keys the holding carries.** An EPUB's OPF package carries `dc:identifier`
elements with a scheme attribute, which is where its ISBN lives. Calibre writes a
`metadata.opf` beside the file — a companion under spec-04 §4.6 — using
`prefix:value` identifiers such as `isbn:`, `amazon:` and `goodreads:`, which is
again a scheme and a value.

**The level trap.** An ISBN identifies one edition in one format, which is a
manifestation. A paperback and a hardback of one edition are two ISBNs and one
expression; matching MUST NOT conclude from two ISBNs that there are two works,
nor from one ISBN that two holdings are one manifestation when one is an EPUB and
the other a PDF — those are two encodings, two manifestations, one expression,
and §4.3's rule about LRM-R3 is what keeps them apart.

**The corpus answers both levels.** Open Library distinguishes a work from an
edition and publishes both under CC0, so a household that knows an ISBN can reach
the work without asking anyone. Both levels are answered where elsewhere they
would require a provider.

**Audiobooks.** A narration is a new expression of the text under spec-01 §6.4's
test, in the way a translation is, so the narrator is credited on the expression
and the author on the work. Chapters become temporal addresses (spec-01 §8.3),
from the container where it carries them (spec-04 §5.1) and from a source
otherwise.

Identity keys on an Audible ASIN, and the services answering ASINs — Audnexus,
AudiMeta — are caches over a proprietary catalogue rather than publishers of
one. They are providers with no snapshot and an upstream the household has no
relationship with, and the registry entry says so. An audiobook holding an ISBN
is matched on the ISBN instead.

### 9.4 Comics and manga

**Keys the holding carries.** `ComicInfo.xml`, the de-facto standard inherited
from ComicRack and now maintained by the Anansi Project, and `MetronInfo.xml`,
which was designed to carry what ComicInfo cannot — typed arrays, identifiers on
the resources it names, and **the source each value came from**, which §5.3 uses
directly.

ComicInfo is conventionally stored *inside* the archive rather than beside it, so
it is not a companion at all. spec-04 §5.1 reads it from the container at
identification, as an embedded tag, which is what it is.

**Structure.** A comic series is a serial work and an issue is a work of its own,
connected by LRM-R21 inspiration, with the issue's place in the series carried at
manifestation level — the same shape as television (Annex A §A.3), for the same
reason, from the same section of spec-01. A trade paperback collecting issues is
an aggregate (spec-01 §5.3) and MUST NOT be given a whole-part relation to the
issues' works.

**Sources.** The Grand Comics Database publishes SQLite dumps under CC BY-SA 4.0
and is therefore a corpus; Metron and Comic Vine are providers. The share-alike
term binds anything the deployment redistributes and nothing it merely holds, and
the registry entry records it (§6.4).

### 9.5 Video games and ROMs

A No-Intro or Redump DAT is a corpus of digests. The SHA-1 of an acquired dump
either appears in it or does not, and where it appears it names the title, the
region, the revision and the entry's place in a parent/clone group — exactly,
offline, with no threshold and no disclosure. It is the shape every other match
in §9 approximates and none of the rest attains.

**Level.** A DAT entry names one dump of one release, which is a manifestation.
The digest identifies which digital items realize it, and §4.3 forces their
manifestations to one and implies nothing about their assets.

**Parent and clone.** A clone group holds regional releases and revisions
together. Under spec-01 §6.4's test a regional release carrying a translated
script is a parallel expression, and a revision that changes nothing but defects
is another manifestation of one expression — and the clone relation alone does
not say which. Matching records the relation and raises which it is as a
candidate, because the corpus genuinely does not answer it.

**Compression destroys the key.** CHD and RVZ re-encode a disc image, so the DAT
digest no longer matches. §4.2 already binds an identity key to the asset it was
computed from; here it means the digest is computed on acquisition, against the
Acquired asset, and a household that normalized before matching has lost the key
and is left with a resemblance.

**Descriptive metadata** — covers, genres, release dates, platforms — comes from
providers, which answer on a resemblance except where the holding already
carries one of their identifiers. Their terms differ enough to matter to the
registry: IGDB is free for non-commercial use behind a Twitch credential,
ScreenScraper is free behind an account and will match on a file's checksum as
well as its name, TheGamesDB requires a private key for usable limits, and the
MobyGames API is a paid feature. A deployment configuring none of them still has
the DAT, which is what establishes identity; what it loses is the cover art.

spec-04 §6.9 places a game as one work with a manifestation per dump, and leaves
to matching the question this section raises: whether a clone is a parallel
expression or another manifestation of one.

### 9.6 Podcasts and downloaded media

**A podcast's identity needs no lookup at all.** `podcast:guid` is a UUIDv5 over
the feed URL with a fixed namespace, minted once and carried thereafter, so the
household computes it by the published rule from a value the holding already
carries. Alone among the schemes in §4.1 it is an equality by construction, and
it survives a change of feed URL precisely because it was minted once rather
than derived on each use.

An episode's `<guid>` from the feed identifies the episode as published, which is
a manifestation.

**Downloaded media.** yt-dlp writes a `.info.json` beside the file carrying `id`,
`extractor`, `upload_date`, `uploader`, `duration` and `chapters`. The extractor
and the id together are a scheme and a value, and the chapters become temporal
addresses (spec-01 §8.3). Here the identifier is one nobody outside the
household can resolve, which spec-01 §4.3 tolerates explicitly and which spec-01
§9.3's same-instance scope makes sufficient.

`.info.json` is a companion pattern in spec-04 §4.6's registry, so a download's
sidecar is never catalogued as a document of its own.

### 9.7 Photographs

No registry knows a household photograph and none ever will. Everything here
comes from the file and from a corpus, and none of it leaves the house.

| Evidence | Becomes |
| --- | --- |
| EXIF `DateTimeOriginal` | a time-span, related to the work by an LRM-R35 refinement for the time of capture |
| EXIF GPS | a place, by LRM-R33, at the granularity the evidence supports |
| EXIF `Make`, `Model`, `LensModel` | the capture device — a candidate for the still-image representative expression attributes Annex A §A.9 leaves to be authored |
| IPTC `By-line`, XMP `dc:creator` | a credit, and the agent it names |
| IPTC and XMP keywords | categories, with automatic provenance |

spec-01 §6.3 requires LRM-R33 and LRM-R35 be refined and carries the refinement
set as a registry. The two refinements in the table above are what a household's
own photographs need; spec-01 §6.3's table already carries both, cited to this
section, and §15 holds what their entries say.

**A coordinate is not a place name.** A gazetteer answers with the nearest named
place and a distance, which is a resemblance. Rather than discard it or assert
it, **the answer is recorded at the granularity the evidence supports**: a
coordinate with a stated accuracy of thirty metres supports a locality, one with
no stated accuracy supports an administrative region, and the finer answer is
raised as a candidate. spec-10 §5.3 already requires a partially known value to
render with its partiality intact, and this is a value that is genuinely partial
rather than one made partial to be safe.

The gazetteer is GeoNames, held locally. Nominatim's published policy forbids
bulk reverse geocoding against its public instance and tells power users to run
their own, so the operational constraint and §14's privacy posture point the same
way, and the resulting rule needs no argument from either alone.

**A filesystem timestamp is not evidence of anything.** A copy resets it, an
archive extraction sets it to the extraction, and a restore sets it to the
restore. Matching MUST NOT take a file's modification time as the time of
capture, of creation, or of publication. Where a photograph carries no EXIF date,
its date is *not yet examined* (spec-10 §5.2) and stays so until a person says
otherwise.

**Faces are authored.** spec-02 §3.2 makes a face tag an authored annotation,
and §3.2 forbids matching from writing one. What matching may do is raise a
candidate from §10.

### 9.8 Scans and correspondence

The hardest class, and the one nothing external will ever answer. It is also the
class spec-01 §13.7 singles out as holding the least replaceable data in the
system, so declining to work on it is not available.

What exists to work from is the OCR transcript, which Annex A §A.5 makes a
derived asset, and which yields dates, place names and names of people. Every one
of those is a resemblance over a machine transcript, so every one is a candidate
and none is ever written as an assertion.

Two rules follow, and both are already in the model:

**An authored annotation may not target the transcript.** spec-02 §3.3 forbids an
authored annotation targeting a derived address, because re-running OCR at a
better version moves it. So a member accepting "this letter is from Eleanor"
asserts it about the letter, with the letter's own selector; the transcript span
is how they were shown the evidence and not what the assertion is anchored to.

**A date accepted from the text orders the file.** A correspondence file is an
ordered grouping (spec-10 §8.3), and its order is chronological. An extracted
date is a weak signal that, once a member accepts it, places the letter in the
sequence. This is what the candidate mechanism is for: a signal too weak to act
on and far too valuable to discard.

The author is an LRM person holding no principal and never acquiring one
(spec-01 §10.1). The household knows who they are and nothing else does, which is
what §10 is about.

The one case a provider reaches: a published edition of a historical
correspondence carries an ISBN and a catalogue record, and a scan of a letter
reproduced in one can be matched to it. It is rare and it is real.

### 9.9 Home video

Nothing external, by construction: the household made it.

What exists is the container's creation time, the capture device's own metadata —
a camera writes its make and model into a QuickTime atom, and a phone writes GPS
alongside it — and the household's own catalog.

The creator is the household itself, credited as the collective agent spec-01
§10.2 already requires to exist (Annex A §A.7). Where nothing else is credited,
matching relates the work to it, with automatic provenance, so that a member can
correct it the way any automatic value is corrected.

Scene boundaries, loudness and key frames are derived (spec-04 §8) and are not
matches.

### 9.10 What answers what

| Class | Equality available | Corpus | Provider |
| --- | --- | --- | --- |
| music recording | MusicBrainz IDs, ISRC, disc ID from a cue sheet | MusicBrainz, AcousticBrainz | AcoustID, LRCLIB, the Cover Art Archive |
| film | `.nfo`, `.plexmatch`, movie hash | Wikidata | TMDB, TheTVDB, EIDR, OpenSubtitles |
| television episode | `.nfo`, `.plexmatch` | Wikidata | TMDB, TheTVDB |
| ebook, document | ISBN in OPF, `metadata.opf` | Open Library, Wikidata | — |
| audiobook | ASIN, ISBN | Open Library where an ISBN exists | Audnexus, AudiMeta |
| comic issue | `ComicInfo.xml`, `MetronInfo.xml` | Grand Comics Database | Metron, Comic Vine |
| video game | a DAT digest | No-Intro, Redump | IGDB, ScreenScraper, TheGamesDB |
| podcast episode | `podcast:guid`, item `<guid>` | — | Podcast Index |
| downloaded media | `.info.json` extractor and id | — | — |
| photograph | — | GeoNames | — |
| scan, correspondence | — | — | — |
| home video | — | — | — |

The last three classes are the household's own, and nothing outside the house
will ever hold a row for them. §10 is what answers them.

---

## 10. The household as its own authority

The catalog is a corpus. Everything a member has named, corrected or identified
is evidence about every other holding; it discloses nothing; and it is the only
source that knows this household.

| Evidence | Bears on |
| --- | --- |
| a name a member gave an agent | the same name appearing as a credit elsewhere |
| a place a member confirmed for one photograph | another photograph at the same coordinates |
| a correspondent a member identified in one letter | the other letters in that correspondence file |
| a duplicate decision (spec-03 §8.3) | that pair, permanently |
| a category a member corrected | nothing; see below |

The household's own evidence ranks above every automatic source and below a
member's assertion about the holding in question — because it *is* a member's
assertion, made about a different holding. Carrying it across is therefore a
resemblance, and produces candidates: two credits sharing a name are not thereby
one agent, and spec-04 §6.4's rule that two untagged credits of one name *are*
one artist is a placement rule matching does not extend and does not undo.

**A member's correction MUST NOT be propagated to other holdings as an
assertion.** One correction becoming twenty silent edits is the failure this
prevents. The member corrected one thing; making them audit twenty to undo it
converts the correction surface spec-10 §15 requires into something people learn
not to touch.

---

## 11. Absence, and what matching may never assert

spec-10 §5.2 gives seven states a value can be in. Matching establishes three of
them, is forbidden three, and has nothing to do with the seventh.

| State | Matching |
| --- | --- |
| **Held** | where a source answered |
| **Not yet examined** | before a stage has run, and after a source was silent |
| **Attempted, failed** | where a source could not be reached or refused (§12) |
| **Not held** | not matching's; the catalog establishes it from zero digital items or zero assets (spec-01 §5.2, §5.5) |
| **Sought, not found** | **MUST NOT.** A person looked; matching is not a person |
| **Known unknowable** | **MUST NOT** |
| **Known absent** | **MUST NOT** |

The three prohibitions are one prohibition. Each of those states is an authored
annotation in spec-02 §3.2's sense, and §3.2 forbids matching from writing one.

A corpus holding no row is silent (§5.2), and a provider answering "no match" is
too: both leave the field *not yet examined*, because a later snapshot and a
growing catalogue may hold it. **A deployment MUST NOT record an empty result as
an absence.**

The empty result is nonetheless recorded on the match record, and that is what
stops the query running forever: the field is unexamined by anything that could
have answered it, and the stage has done everything it can until §8.7's
conditions change. The two statements are not in tension, and conflating them is
how a catalog acquires a permanent, confident record of not knowing.

---

## 12. Failure

Per spec-04 §9. A stage that cannot complete records why, as a finding a person
can see; it does not skip silently and it does not retry indefinitely.

| Failure | Examples | Handling |
| --- | --- | --- |
| **Permanent** | a provider refused the query; a syntactically invalid identifier (§4.4); a scheme not in the registry; a response the deployment cannot parse | recorded, not retried |
| **Transient** | unreachable, timed out, a server error | retried a bounded number of times with backoff; exhaustion is recorded |
| **Rate limited** | a `429` | honoured; `Retry-After` obeyed; the stage's rate reduced; **never recorded as an empty result** (§6.3) |
| **Contradiction** | two sources, one scheme, one level, different values (§5.4) | recorded; the value left unwritten |

A failure is recorded against the res, the scheme and the source. Due work
excludes anything carrying a recorded failure for that combination until a
person clears it, or until §8.7's conditions change.

A source that answered and held nothing is not a failure and is not recorded as
one (§5.2, §11).

---

## 13. Conformance

An implementation conforms to this specification if it satisfies all of the
following.

**Sources and records**

1. A match writes a record carrying the query as sent, the response as received,
   the basis, the source's rank and the order applied, and the conclusion.
2. A provider is recorded as a collective agent; a deriving tool is not.
3. Placement completes with every provider unreachable, and the catalog is
   unchanged by their being unreachable.
4. No match query is issued inside placement's transaction.
5. A deployment configured with no contact issues no provider query and states
   which schemes are unanswered.
6. A corpus holding no row for an identifier produces no finding and no failure.
7. A provider that cannot be reached produces a finding.

**Identifiers and levels**

8. Every scheme in the registry declares the entity level it identifies.
9. Two works carrying one work-level identifier are equated; their expressions
   are not.
10. Two manifestations carrying one manifestation-level identifier are equated,
    and the expressions they embody are not.
11. Equating two expressions equates their works; equating two manifestations
    equates nothing above them.
12. An identifier failing its scheme's check digit is recorded as a finding and
    is not written as a nomen.
13. An identifier reached by resemblance is not written as a nomen; accepted by a
    member, it is.
14. An identity key computed from bytes is recorded against the asset it was
    computed from, and recomputing it against the normalized master is not
    treated as a mismatch of the same key.

**Acting**

15. A name supplied by a source is written with that source as assigner, and
    never with a null assigner; resolution prefers a household name over it with
    no additional rule.
16. Matching does not remove a credit placement wrote.
17. Matching replaces a category placement decided automatically and does not
    replace one a member set.
18. An equation matching performed recycles rather than purges, is restorable at
    its original identifiers within spec-01 §14.1's window, and is visible on the
    findings surface.
19. An equation is not performed where a member has decided the pair distinct.
20. A candidate a member has decided is not raised again.
21. A measurement imported from a source names the tool and version that produced
    it, records that the input was not the household's asset, and does not
    supersede a measurement from the household's own tools.
22. An imported derivation frozen at an earlier snapshot does not supersede a
    later local run merely by being imported afterwards.

**Disagreement and absence**

23. Two sources supplying different identifiers of one scheme at one level
    produce a finding and no written value.
24. Two ISRCs on one expression produce no finding.
25. A source's empty result leaves the field *not yet examined* and does not make
    the work perpetually due.
26. Matching never writes *sought, not found*, *known unknowable* or *known
    absent*.
27. A `429` is not recorded as an empty result, and the stage's rate is reduced.

**Disclosure**

28. No query carries a file name, an inbox path, another holding, or a principal.
29. A provider's response cannot cause a write to a res the query did not
    concern.
30. No match query is triggered by a render, by a search, or by any action a
    principal takes on a surface.
31. Reverse geocoding is answered from a local corpus and issues no query.

**Class-specific**

32. A cue sheet yields a disc table of contents, which matches a medium
    manifestation as an equality.
33. The same recording on an album and on a compilation is equated to one
    expression and one work, and remains two track manifestations.
34. An AcoustID is not written as an expression-level identifier.
35. A source's episode numbering does not change the household's arrangement.
36. A DAT digest matching an entry equates manifestations, and the clone relation
    is raised as a candidate rather than resolved.
37. A `podcast:guid` is computed locally from the feed URL by the published rule
    and issues no query.
38. A filesystem timestamp is never recorded as a time of capture, creation or
    publication.
39. A gazetteer answer is recorded at the granularity the evidence supports, and
    a finer place is a candidate.
40. A member's correction on one holding produces candidates on other holdings
    and never writes to them.

---

## 14. Security and privacy considerations

**This is where the deployment reaches outside the household systematically.**
spec-04 §11 identifies one lookup as ingest's single outward reach. Matching
generalizes that reach to every scheme and every class, and the general shape is
a query per holding.

A provider learns that the household holds the thing each query names. Over a
library it learns the library, and from the order and rate of the queries it
learns roughly when the household acquired it. No single query is sensitive and
the sequence is, which is why §6.2 requires disclosure to be declared per
provider rather than assessed per request.

**A credential is a stable identity.** An API key or a token identifies the
deployment across every query it ever makes, which is what a key is for and
cannot be avoided — only declined, by not configuring that provider.

**A file name is disclosure.** Inbox paths carry members' names, the names of
whoever a file came from, and scanner defaults. §6.2 forbids sending one, and the
prohibition is a privacy control rather than a protocol nicety.

**Location is the sharpest case.** A photograph's coordinates are where a member
of this household stood. §9.7 answers them from a local corpus, and the public
gazetteer's own usage policy independently forbids what §9.7 forbids.

**Matching MUST NOT be triggered by a render.** A query issued because someone
opened a page tells a provider what that person is looking at, which converts the
catalog surface into a channel disclosing consumption — the thing spec-01 §11.2
and spec-06 §6.3 exist to prevent, arriving by a route neither anticipated.
Matching runs on a schedule, over the catalog, and never over events.

**A provider's response is untrusted input**, parsed by the deployment, as
everything in the inbox is (spec-04 §11). Two consequences beyond parser
hardening:

- A response MUST NOT be able to cause a write to a res the query did not
  concern. Without this, one compromised or hostile response rewrites arbitrary
  rows, and the match record makes it look deliberate.
- A response's identifiers are validated (§4.4) before they are used as keys, so
  that a malformed value does not reach a query or a join.

**The terms in §6.4 are a security control as much as a legal one.** A provider's
prohibition on machine-learning use binds the gate spec-09 §4.2 states; recording
each value's provider on the match record is what makes that gate answerable,
since it refuses a computation on the terms of every value that entered it and
cannot be enforced after the fact.

---

## 15. Registries

Seed data (spec-01 §7.5), maintained through releases, not specified here.
spec-01 §17 already names external identifier schemes; this document specifies
what an entry holds.

**External identifier schemes.** Per scheme: the entity level it identifies or
that the level is read per record (§4.1); the syntax; the check-digit algorithm
where one exists (§4.4); the issuing agent; whether one res may carry several at
one level (§5.4); and whether the scheme is answered by a corpus, a provider, or
neither.

**Corpora.** Per corpus: the schemes it answers, the levels, its terms, its
snapshot, and whether its snapshot can advance (§5.5, §5.6).

**Providers.** Per provider: the schemes it answers, the levels, what a query
discloses (§6.2), the rate limit, the credential, and the terms and the
obligations they place on the deployment (§6.4).

**The source rank order** a deployment applies (§5.3).

**The decision vocabulary** of §8.4, shared with spec-03 §8.3.

**Association refinements** this document writes, which spec-01 §6.3 carries:

- LRM-R35, the time of capture of a still or moving image (§9.7)
- LRM-R33, the place of capture (§9.7)
- LRM-R1, a place within a place, so that a gazetteer answer recorded at one
  granularity relates to the finer one (§9.7)
- LRM-R1, the correspondence between a household arrangement position and a
  source's numbering (§9.2)

spec-01 §6.3 carries no refinement nothing writes, so a match that needs one not
on that list raises a finding rather than attaching an untyped relation — a
relation written without its kind can never be classified afterwards.

**Companion patterns and root element names** in spec-04 §4.6's registry, which
this document reads: `ComicInfo.xml`, `MetronInfo.xml`, `*.info.json`,
`gamelist.xml`, and the sidecar edit formats `*.xmp`, `*.pp3`, `*.dop` and
`*.aae`.

**The documents read from inside a container** (spec-04 §5.1), keyed by the
container's format and the document's path or root element.

---

## 16. What this document rests on elsewhere

Six things this document needs belong to the specifications that own the
concepts, and are specified there rather than here.

| What this document needs | Where it is specified |
| --- | --- |
| a broad class, a placement structure and a category for audiobooks, podcast episodes, comics and games (§9.3–§9.6) | spec-04 §5.3, §6.3, §6.9 |
| `*.info.json`, `gamelist.xml` and the photographic edit sidecars as companion patterns, and `ComicInfo` and `MetronInfo` as root elements (§9.4, §9.6, §9.7) | spec-04 §4.6 |
| a metadata document read from inside a container rather than beside it (§9.3, §9.4) | spec-04 §5.1 |
| a nomen whose language is unknown, distinct from one whose language is absent (§8.1) | spec-01 §7.2 |
| an imported derivation ordered by its source's snapshot (§8.6) | spec-02 §4.2 |
| a decision vocabulary naming the level at which two res are one (§8.4) | spec-03 §8.3 |

Two of these were a choice between mechanisms rather than a gap. A nomen's
unknown language could have been a second meaning for null, and was made a third
value instead, because null already means the household's own untagged
vocabulary and a stranger's name does not belong in it. A decision could have
been a single *duplicate*, and names a level instead, because a wrong guess at
the level destroys a relation rather than a value.

---

## 17. References

### 17.1 Normative

- **[spec-01]** *Catalog Data Model*, this system, with Annex A. §4.3 rests on
  §6.1's cardinalities; §8.1 on §7.3's nullable assigner; §8.4 on §14.1's
  recycling window.
- **[spec-02]** *Annotations and Derived Data*, this system. Normative for §8.6
  and for the agent/tool distinction §3.1 turns on.
- **[spec-03]** *Assets, Storage and Preservation*, this system. §8.3 is
  normative for the operation §8.4 performs and for the vocabulary it extends.
- **[spec-04]** *Ingest and Normalization*, this system. Normative for what a
  holding is before matching runs, for the companions §9 reads, and for the
  stage and failure shapes §7 and §12 follow.
- **[spec-06]** *Principals, Auth and Authorization*, this system. §6.1 is
  normative for the System principal §7 attributes writes to.
- **[IFLA-LRM]** as in spec-01 §18.1. LRM-E6's exclusion of automatons grounds
  §3.1; LRM-E8 is what a provider is; LRM-R14 is how §8.1 records a name.
- **[RFC2119]**, **[RFC8174]** as in spec-01 §18.1.

### 17.2 Informative

- **[spec-09]** *Search, Ranking and Recommendation*, this system. Its §4.1
  classes each of §6.4's terms by what the term restricts, and its §4.2 is the
  gate they bind; its §5.2 and §12.3 consume the measurements §8.6 imports, and
  its §14.3 rests on §9.7 having made a face authored.
- **[spec-10]** *Presentation*, this system. §5.2's states are what §11 maps
  onto, §15 is the correction surface a candidate reaches a person through, and
  §16 is where §8.4's equations are reported.
- **[MUSICBRAINZ]** MusicBrainz, its database schema, its disc ID, and the
  published data dumps and replication tooling §5.5 holds locally.
- **[ACOUSTID]** AcoustID and Chromaprint, for the fingerprint §9.1 treats as a
  resemblance.
- **[ACOUSTICBRAINZ]** AcousticBrainz, for the Essentia music-extractor
  descriptors §8.6 admits, frozen in 2022.
- **[WIKIDATA]** Wikidata, for the cross-scheme mapping §5.5 relies on.
- **[OPENLIBRARY]** Open Library, for the work and edition levels §9.3 needs.
- **[GEONAMES]** GeoNames, for the gazetteer §9.7 holds locally.
- **[NOMINATIM-POLICY]** OpenStreetMap Foundation, *Nominatim Usage Policy*,
  which forbids bulk reverse geocoding against the public instance.
- **[NO-INTRO]**, **[REDUMP]** The DAT format and its digests, for §9.5.
- **[GCD]** Grand Comics Database, CC BY-SA 4.0, for §9.4.
- **[COMICINFO]** The Anansi Project, *ComicInfo* schema, for §9.4.
- **[METRONINFO]** The Metron Project, *MetronInfo* schema, whose per-field
  source attribution §5.3 uses.
- **[TMDB]**, **[TVDB]**, **[EIDR]**, **[ISAN]** for §9.2.
- **[PODCAST-NS]** *Podcast Namespace*, for the `podcast:guid` rule §9.6
  computes.
- **[OSHASH]** The OpenSubtitles movie hash, for §9.2.
- **[ACCURATERIP]** AccurateRip and the CUETools database, which §9.1 places
  with spec-03 §5 rather than here.
- **[ISO7064]** ISO/IEC 7064, for the MOD11-2 check §4.4 applies to ISNI.
