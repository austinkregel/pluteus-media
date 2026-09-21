# Annex A — Worked WEMI Mappings

**Companion to Specification 01**
**Status:** Draft
**Normative status:** Non-normative. LRM and spec-01 §5–6 are normative; this
annex shows how they land on real holdings.

## Scope

spec-01 §6.4 supplies one test for the work boundary — *was significant
independent intellectual or artistic effort involved?* — and §3.3 permits depth
to vary per instance. This annex applies both to each media class the system
holds, so that an ingest path knows what rows to create for a given kind of
file, and so that the categories §6.5's registry is keyed on are enumerated.

LRM settles most of the commercial cases. The household cases it does not.

---

## A.1 Music recording

| Level | Instance | Creator |
| --- | --- | --- |
| Work | the composition | composer / songwriter |
| Expression | one recorded performance or mix | performing artist |
| Manifestation | the track as released, a part of a medium (LRM-R26) | label |
| Manifestation | the medium, a disc or side, a part of the release (LRM-R26) | label |
| Manifestation | the release the track appeared on | label |
| Digital item | the ripped FLAC for one track | — |
| Asset | stored bytes, `acquired` + `normalized` roles | — |

A digital item carries one manifestation, and a release embodies every track's
recording, so a file carrying the release manifestation would not say which
track it holds. Each track is therefore a manifestation of its own, embodying
its recording and forming a part of a medium, which forms a part of the
release. Order is the position at each level: a track's within its medium and a
medium's within the release.

MusicBrainz is already WEMI-shaped, so external identifiers land cleanly:
work MBID → work, recording MBID → expression, track MBID → track
manifestation, release MBID → release manifestation. Recording this mapping is
what makes spec-05's matching tractable.

**An album is an aggregate** at work and expression level, not a whole-part
structure: per spec-01 §5.3 the aggregating work holds only selection and
arrangement, and aggregation happens at expression level via LRM-R25. The
release, as a manifestation, does have parts — media and tracks, through
LRM-R26 — and track order is the positions on those (spec-01 §12.1), never on
an asset and never repeated on the aggregation.

Covers and remixes follow §6.4: a cover is a new work via LRM-R22; a nightcore
or sped-up edit is a new expression via LRM-R24.

## A.2 Film

Work → the film. Expression → one cut in one language. Manifestation → the
release or encode. Digital item → the container.

A multi-track container holding English and French audio embodies **two parallel
expressions** (§5.3, LRM-R3 being many-to-many) and MUST NOT be demultiplexed at
ingest. Track selection at playback operates over tracks present in the
container (§8.6).

The theatrical cut is normally the representative expression (§6.5); other cuts
rank by distance from it, which is what orders them for selection. A re-cut that
alters meaning rather than length MAY be promoted to its own work (§6.4).

## A.3 Television episode

The counterintuitive one, and spec-01 §5.4 is explicit about it:

- **Each episode is its own work.** The series is a *serial work*.
- The series work has **no whole-part relation** to its episodes. They connect
  via LRM-R21, inspiration.
- **Season and episode structure lives at manifestation level**, via LRM-R26.

So "season 2, episode 5" is an arrangement fact on a manifestation-level
whole-part relation, not a property of the episode's work. Regional editions of
a series are distinct serial works, not expressions of one.

Per LRM §5.8, *"any serial work can be said to have only one expression and only
one manifestation."* The series resolves to a single complete serial
manifestation, and the episodes are parts of that one manifestation via LRM-R26.
A series given one expression per season models seasons as expressions of the
series, which LRM does not support: seasons are parts of the manifestation, like
episodes.

## A.4 Photograph

The first case where §3.3's variable depth does real work.

| Level | Instance |
| --- | --- |
| Work | the photograph as an act of capture |
| Expression | the image as captured — usually exactly one |
| Manifestation | the encoding |
| Digital item | the JPEG |

§3.3 names this case directly: one capture and one file does not require four
distinctly populated levels. §6.5 permits automatic promotion of expression
attributes to representative-expression attributes where a work has a single
expression in a single manifestation, which covers substantially all of them.

**The boundary that matters here is edit vs. derived asset.** A crop or colour
correction a person authored and keeps as a distinct thing is a new expression.
A thumbnail or preview the system generated is a derived asset (§5.5) and MUST
NOT become an expression or manifestation. The test is authorship, not
pixel difference — and getting it wrong in the permissive direction produces one
manifestation per generated artifact, which is what §5.5 forbids.

### A photograph of an artwork

A second boundary, which LRM settles for neither side. A photograph of a
painting can be read two ways:

| Reading | Structure | Consequence |
| --- | --- | --- |
| a reproduction | the painting is the work; the photograph is a manifestation of it, alongside any other shot | asking for the painter's work finds it; the photographer is credited on nothing, and two shots of one painting are the same thing however differently made |
| a photographic work | the photograph is a work of its own, related to the painting by LRM-R22 | the photographer is credited; asking for the painter's work does not find it without travelling the relation |

Both are correct for some holdings, and the difference is intent rather than
content. A documentation shot of a canvas is a reproduction. A composed
photograph that happens to contain a painting is a work.

**Placement therefore defaults to the photographic work**, because the bytes say
*photograph* and nothing says *reproduction*, and a member changes it. The
change is a decision at work level in spec-03 §8.3's vocabulary, which already
carries *same work*; no mechanism is added for it.

The default is the recoverable direction. Reading a reproduction as a work
leaves a photograph credited to its photographer and one relation short, which a
member repairs. Reading a work as a reproduction files somebody's photograph
under another artist's name and loses the photographer entirely.

## A.5 Scanned letter

The case with a genuine physical `item`, which is otherwise rare here (§5.2:
"substantially all holdings in this system are digital items").

| Level | Instance |
| --- | --- |
| Work | the letter as composed | 
| Expression | its text |
| Manifestation | its single production |
| **Item** | the physical letter |
| Manifestation (2nd) | a scan |
| Digital item | the scan's TIFF |

The author is an LRM person who holds no principal and never will — spec-01
§10.1 requires implementations to support exactly this.

**A second, higher-quality scan produces a new manifestation under the existing
expression** (conformance criterion 10), not a new work and not a duplicate.

The OCR transcript is a **derived asset** (§5.5), not an expression: it is
machine-generated, regenerable, and excluded from backup by §13.7. Consequently
`text_position` selectors against it address the transcript rather than the
letter, and a better OCR pass shifts them — which is precisely why §8.5 requires
text offsets to record what they are an offset into, and why a text-quote anchor
is more durable than a character offset.

## A.6 Ebook

Work → the novel. Expression → the edition or translation (a translation is an
expression, §6.4). Manifestation → the EPUB release. Digital item → the file.

Reflowable text has no stable character offset across rendering engines, so
reader highlights SHOULD anchor by text-quote rather than position (§8.5).
[EPUB-CFI] is cited informatively by spec-01 for its anchoring semantics.

## A.7 Home video

Work → the recording. Single expression, single manifestation, auto-promoted
under §6.5.

The creator is often **the household itself**, credited as an LRM collective
agent. This is where spec-01 §10.2's insistence that the household is both a
collective agent and an application concept stops being pedantic: the household
row is what the work's creation relation points at.

Whether an unedited capture clears §6.4's "significant independent intellectual
or artistic effort" bar is arguable. This annex takes the permissive reading —
it is a work — on the §3.1 principle that information should not be discarded,
and because the alternative leaves the holding with no work to hang naming,
dating, or place relations on.

---

## A.8 What never gets a work

Restating §5.5 because it is the rule most likely to be violated by an ingest
pipeline written without it:

Thumbnails, waveform data, sprite sheets, machine transcripts, extracted
subtitles that duplicate an embedded track, and parsed or cropped derivatives
are **derived assets**. They are not works, expressions, manifestations, or
digital items. They are excluded from backup (§13.7) and are regenerated after
loss.

---

## A.9 Categories, and what LRM already supplies

### Categorization is several schemes, not one list

LRM §4.2.3 permits several independent categorization schemes on one entity, and
LRM-E2-A1 demonstrates three at once for `work`: termination intention
(monograph / serial), creative domain (literature / music / fine arts), and
form / genre (novel, play, poem, symphony, sonata, drawing, painting,
photograph).

Household-created versus commercially acquired is therefore a **second scheme**,
orthogonal to the others, rather than a category value. Provenance cuts across
every value in every list above: a photograph may be commercial or household,
and so may a moving image.

### The representative expression attributes, and what they are not

spec-01 §6.5 carries the registry. LRM-E2-A2 supplies five of its rows directly;
two are authored here, because LRM has no analogue for them:

| Work type | Significant attributes | Source |
| --- | --- | --- |
| Textual | language, intended audience | LRM-E2-A2 |
| Musical | key, medium of performance | LRM-E2-A2 |
| Cartographic | cartographic scale, projection | LRM-E2-A2 |
| Moving image | aspect ratio, colourization | LRM-E2-A2 |
| Art | medium of execution | LRM-E2-A2 |
| Still image | capture device, orientation, colour or monochrome | authored |
| Personal record | the correspondents, the date of writing | authored |

LRM's *art works* row gives medium of execution, which suits a painting and says
nothing useful about a photograph — hence a still image row of its own. Personal
record has no LRM analogue because libraries do not catalogue a relative's
letters.

**The two registries are easy to confuse and answer different questions.** These
attributes exist to order competing expressions of one work. What a photograph
depicts, whether it is a portrait or a landscape, whether its subject is a
person or an animal, whether it reproduces another work — none of that belongs
here. It is categorization, and §A.9's first heading is the point: several
independent schemes may run on one entity at once, so a household wanting
subject, composition and provenance as three orthogonal axes may have all three
without touching this table.

LRM §5.6 grounds the automatic promotion §A.4 and §A.7 rely on: it applies "in
the vast majority of cases where new works are realized through a single
manifestation of a single expression," and "would also frequently (but not
always) be the case with art works." Home media is that case.


---

## A.10 Source

*IFLA Library Reference Model*, Riva, Le Bœuf and Žumer, 2017, as amended through
December 2021, issued July 2024 (CC BY 4.0) — the edition spec-01 §18.1 adopts.
Section references throughout are to that edition's numbering.
