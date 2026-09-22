# Playback and Transcode Negotiation

**Specification 08**
**Status:** Draft
**Version:** 0.1
**Depends on:** spec-01 (Catalog Data Model), spec-03 (Assets, Storage and
Preservation), spec-04 (Ingest and Normalization), spec-06 (Principals, Auth and
Authorization), spec-07 (Wire Protocol), spec-10 (Presentation)
**Obsoletes:** nothing

## Abstract

spec-01 §13.3 chooses the standardized master for fidelity and longevity and
explicitly not for direct-play compatibility, and §13.6 accepts that serving
therefore transcodes routinely. This document specifies what happens between a
person pressing play and bytes a client can decode: what a client declares about
itself, how the deployment decides between serving the master and producing a
rendition, what a rendition may be and what becomes of it, how a person moves
within one, and what the occasion that contains all of it reports about itself.

Three things are distinguished throughout, and conflating any two produces a
rule that cannot be enforced: the viewing occasion, the production of bytes that
serves part of it, and the bytes themselves.

---

## 1. Introduction

### 1.1 Scope

- The session: one viewing occasion, what continues it and what ends it
- The delivery: one continuous production of bytes, and its lifetime
- Capability declaration, and what it is not
- The path decision — direct play, remux, transcode, refuse
- Track selection at playback, and subtitles
- Delivery forms per media class
- Seeking, and what a seek costs
- Renditions: production, retention, eviction
- Capacity, allocated per principal
- What a session reports, and what it never reports
- Holdings that are not one file per holding
- The surfaces a rendition is reached on

### 1.2 What this document does not specify

Which expression and digital item a person meant, which spec-10 §8.1 resolves
before playback begins. The queue, which is spec-10 §12.3 and spec-07 §6.5 and
is one object per principal. Which of two positions a surface shows, which is
spec-10 §13.3. Presentation assets — trickplay, waveforms, key frames, extracted
text — which are spec-07 §4.6 by profile and spec-10 §11 in substance, and which
spec-01 §13.6 places outside transcoding. Output transports, which the deployment
consumes rather than implements. Ranking, similarity and recommendation
(spec-09).

Documents, ebooks, scans and photographs never reach a rendition, and neither do
the package and software classes spec-04 §5.3 names, which spec-04 §6.9 adopts
as their own masters. Moving image and audio do.

Taking a holding onto a device to play while disconnected is not specified. The
declared offline queue of spec-10 §13.3 is a queue of position reports
accumulated during spec-10 §17.1's connection drop with media already buffered,
and is not a downloaded copy.

A sleep timer, a subtitle timing offset and playback speed reach no server and
change no rendition. They are transport controls and belong to spec-10 §12.3.

---

## 2. Conventions

BCP 14 key words per spec-01 §2.

Three terms are used precisely:

| Term | Is |
| --- | --- |
| **session** | one viewing occasion of one principal on one device (§3) |
| **delivery** | one continuous production of bytes serving a session (§4) |
| **rendition** | the bytes a delivery produces where its path is remux or transcode (§10) |

A session holds many deliveries in succession. Concurrency, capacity and the
selected track are properties of a delivery. A sequence counter and a resume
position are properties of a session.

---

## 3. The session

### 3.1 What one is

A session is one viewing occasion of one principal on one device. It is opened
by that principal, is scoped to it (spec-06 §4), and the System principal MUST
NOT be the subject of one (spec-06 §6.1).

A device hosts a session and never owns one. Where a device holds credentials
for several principals (spec-06 §4.1), each principal's sessions are its own and
no principal reaches another's.

### 3.2 What continues one

**A session continues across whatever the requesting principal's queue holds.**
The queue is spec-10 §12.3's, one object per principal, which spec-10 §12.3
requires not diverge from spec-07 §6.5's.

Playing a release from end to end is the case where the queue carries its
arrangement order. A shuffled release, a queue assembled from several releases,
and a crossing from the last member of one ordered grouping into the first of
the next are each one occasion and MUST be one session.

Arrangement order alone MUST NOT be the rule. A shuffled release would otherwise
be one session per track, and spec-10 §8.3 carries two seasons on two whole-part
orderings, which would divide one evening.

A holding played from outside the queue opens a new session.

### 3.3 What ends one

A session ends on whichever of these comes first:

- the principal stops playback explicitly;
- the surface switches principal, because spec-06 §4 admits no ambient session;
- no report arrives for longer than the session inactivity period;
- the session ceiling elapses.

Both periods are registries (§18). spec-10 §20's `inactivity period` is not one
of them: §20 scopes it to spec-10 §14.2, after which a shared surface returns to
the choice of principal, which is a different event from a session ending.

### 3.4 Its counter and its state

A session carries a sequence counter, which increases once per report the
session emits and is shared with no other session on the same device. It is the
counter spec-01 §11.4 records and spec-10 §13.3 orders reports by.

A session carries whether it is playing. **That describes the principal's
intent rather than whether bytes are moving**, so it remains true through a
buffering stall and through a restart under §9.4, and becomes false only on a
pause or a stop. spec-10 §13.3 prefers "the most recent report from a session
that was playing" on the understanding that a paused session's position is a
statement about the past, which a stall is not.

---

## 4. The delivery

### 4.1 What one is

A delivery is one continuous production of bytes for one session. It carries the
path §6 decided, the capability declaration §5 supplied, the tracks §7 selected,
and the position it began at.

A session holds one delivery at a time. Producing bytes for a holding the person
has not reached is producing bytes nothing requested, which §10.1 forbids;
spec-10 §12.4's offer of the next member "MUST carry a visible interval before
it acts", and until it acts nothing has been requested.

Two sessions MAY play one res at once, each on its own device with its own
position (spec-10 §13.3).

### 4.2 What a request is

spec-01 §13.6 triggers transcoding on "an actual request for the content". **A
request is a client opening a delivery, and nothing else.**

None of the following is a request, and none MAY open a delivery:

- rendering a surface that carries the holding;
- arriving at a deep link carrying a selector, which spec-10 §10.2 requires "not
  begin playback" and spec-10 criterion 24 tests;
- an automatic preview, which spec-10 §17.8 requires record no consumption event;
- adding a holding to a queue;
- spec-10 §12.4's offer of the next member, before it acts.

### 4.3 What it reads

A delivery reads the digital item spec-10 §8.1 resolves, on every surface.
§8.1's ordering is spec-01 §8.6's — distance from the representative expression
under the requesting principal's profile — which depends on the person rather
than on the order files arrived in.

spec-04 §8.1's analysis source is a designation for analysis and MUST NOT decide
what a delivery reads. A member naming a different source so that a tool reads
better bytes would otherwise change what plays.

Within that digital item, a delivery reads the asset holding the Normalized role
(spec-01 §13.3), or, where the digital item is realized by parts, each part's
own master in part order (spec-04 §7).

---

## 5. Capability

### 5.1 It is declared, not known

**A client declares what it can decode on the request that opens a delivery.**
The declaration is not stored against the device, is not inferred from a device
name or model, and is not looked up from a registry of products. spec-10 §18.4
requires this and spec-10 criterion 57 tests it: decoding capability varies
within one product line and changes with the audio path.

A declaration MAY carry a name; the name MUST NOT be read to decide capability.

Capability is not the surface. spec-10 §4.4 requires a surface be declared and
never inferred, and records that declaration with the device when it is bound.
Which surface a device is persists; what it can decode this time does not.

### 5.2 What a declaration carries

A declaration carries, at minimum:

| Carries | For |
| --- | --- |
| containers and codecs the client plays directly | §6's direct-play branch |
| containers and codecs the client plays where the deployment produces them | §6's remux and transcode branches |
| per-codec limitations — profile, level, bit depth, channel count, sample rate | bounding what §6 may produce |
| subtitle formats and the delivery methods available for each | §8 |
| a maximum bitrate | §6's ceiling, and §11 |
| the audio path | §5.3 |

### 5.3 The audio path is its own dimension

A declaration MUST distinguish what the device decodes on its own speakers from
what it can only pass through to a receiver.

spec-10 §18.4: "A rendition MUST carry an audio track the device can decode on
its own speakers. An audio codec the device can only pass through to a receiver
is silence on a television that has none."

---

## 6. The path

### 6.1 Four branches

A delivery takes exactly one path, decided once:

| Path | Where |
| --- | --- |
| **direct play** | the master is within the declared capability and within the declared bitrate ceiling |
| **remux** | the codecs are within capability and the container is not |
| **transcode** | a rendition within the declared capability can be produced |
| **refuse** | one cannot |

Direct play serves the master as stored and MUST honour byte ranges (spec-07
§4.4, spec-10 §18.4, spec-10 §18.5). Remux changes the container and re-encodes
nothing.

**Transcoding is the ordinary path and not the exception.** spec-01 §13.6 and
spec-03 §4.4 both state it, and spec-03 §4.4 puts sustained real-time
transcoding on the critical path for playback.

### 6.2 The refusal

A holding for which no rendition within the declared capability can be produced
MUST be refused with a statement of why, and MUST NOT be silently substituted.

§5.3's rule is what makes this branch non-empty: a device declaring no audio
codec it can decode on its own speakers is refused rather than served silence.

The refusal names the client that made the attempt and what it declared. It is a
statement about the device in front of the person, at the moment of the attempt.

### 6.3 It is decided once and stated

The path is decided once per delivery and is carried in the response that opens
it. Where a fallback selection differs from the profile's preference,
implementations SHOULD indicate this unobtrusively; spec-01 §8.6 makes it a
display concern rather than an error.

Where a digital item is realized by parts whose masters differ in codec (§4.3),
the path is decided for the delivery rather than per part, and a part outside
the decided path is transcoded to match it.

### 6.4 It consults nothing outside the household

Opening a delivery MUST NOT issue a query to any provider or corpus. spec-05 §14
forbids matching triggered "by a render, by a search, or by any action a
principal takes on a surface", and spec-05 criterion 30 tests it: a query issued
because someone pressed play tells a provider what that person is watching.

The facts the decision reads — format, codecs, streams, duration, essence — are
recorded already, on the asset (spec-03 §3.2) and as the probe annotations
spec-04 §5.1 writes on the manifestation.

### 6.5 Serving performs no verification

Reading an asset to serve it verifies nothing. spec-03 §5.2 requires
verification be scheduled with recorded outcomes and MUST NOT be "a side effect
of playback".

---

## 7. Track selection

### 7.1 Server-side, over the container

Selection is spec-01 §8.6's and occurs server-side. A container MUST NOT be
demultiplexed (spec-01 §5.3); selection operates over the tracks present in it.

The selection set is never empty: the container's default track is always
present, and implementations MUST NOT report an absence (spec-01 §8.6).

### 7.2 How a track is named

A selected track is addressed as spec-01 §8.5 requires: by kind, language,
disposition and channel count, with an ordinal among tracks alike in all four.
It MUST NOT be addressed by its index in the container, by its codec, or by the
name its codec gives the channel layout, and spec-04 §6.5 excludes the
container's default flag from the address because a muxer sets it freely.

Where a projected model addresses a stream by index, that index is a handle
valid within the response that issued it and MUST NOT be stored as a selector.
spec-10 §11.2 draws the same distinction for pixel regions: spec-01 §8.4 governs
stored selectors, which must survive a re-encode, and a display-time reference
against a named derivative is not one.

### 7.3 Three settings, never one

Audio selection, subtitle selection and subtitle visibility are three
independent settings and MUST NOT be collapsed (spec-01 §8.6, spec-10 §12.2).
Turning subtitles off MUST NOT forget which subtitle track was chosen.

A downmix and its parent mix are one expression with two `track` addresses; two
languages are parallel expressions (spec-04 §6.5). A channel decision is
therefore within an expression and a language decision across them.

---

## 8. Subtitles

### 8.1 Classification, not language alone

A text track carries the classification spec-10 §17.4 requires — captions,
subtitles, SDH, forced, commentary, unknown — and selection is over language and
classification together. Distinct classifications of one language MUST NOT be
merged.

### 8.2 Delivery beside the rendition

**Where the client declares it can render a track's format, the track is
delivered beside the rendition and MUST NOT be burned in.**

### 8.3 Where it cannot

A bitmap track — the ordinary outcome of ripping a disc — on a client declaring
no renderer for it MAY be burned into a rendition **only where the person asked
for that track**, and turning it off produces a delivery without it.

spec-10 §17.4 forbids burning a bitmap track in "as its only presentation, since
that removes the ability to turn it off". A delivery without it, on request, is
that ability.

A bitmap track MUST be labelled image-based on every surface and MUST NOT count
toward any conformance claim (spec-10 §17.4). It answers spec-10 §17.3's
affordance filter as present, because the holding carries the affordance; what
differs per surface is the delivery method.

Burn-in couples visibility to the delivery for one track on one kind of client.
That coupling is stated to the person rather than concealed: turning that track
off is a new delivery, and turning it on again is another.

---

## 9. Delivery form and seeking

### 9.1 Form per media class

Moving image is delivered as a segmented stream. Audio is delivered
progressively, with a declared bitrate ceiling.

The deployment declares which per media source. A segmented form makes a
backward seek within the produced range free; a progressive form is what the
retrieval endpoints of spec-07 §6.7 carry.

**No adaptive ladder is produced.** Every rendition in a ladder beyond the one
being played is a transcode nothing requested, which §4.2 excludes and spec-01
§13.6 forbids.

### 9.2 Offsets are timestamps

Every offset a delivery accepts or emits is a timestamp. A byte position, a
frame number and a segment index MUST NOT be accepted as an offset. spec-01 §8.4
permits a timestamp because it survives re-encoding and forbids the others
because they do not.

### 9.3 Within the produced range

A seek within the delivery's produced range reaches no transcoder. On direct
play and remux that range is the whole holding and a seek is a byte range, which
spec-07 §4.4 honours "since a player seeks by range".

**The produced range belongs to the delivery, not to an encoder process.** A
restart extends the delivery's stream over segments it has already produced
rather than abandoning them, so a seek back into anything already played remains
free however many restarts have intervened. Segments produced during a delivery
are not retention in §10.2's sense.

### 9.4 Beyond it

A seek beyond the produced range restarts the transcode at an offset.

A restart MUST wait at least the seek settling period from the seek that
provoked it, and seeks arriving within that period are coalesced to the newest
by sequence rather than to the last to arrive. A directional remote emits a
burst, and the order of arrival is not the order of intent.

**A delivery begins producing one large seek granularity before its offset.**
Without that lookback, a seek backwards shortly after a resume or a deep-link
arrival restarts the encoder to recover a few seconds, while the same gesture a
minute later costs nothing — one action with two costs and nothing visible to
distinguish them.

The two granularities are spec-10 §20's, and spec-10 Annex A A.8.7 draws them;
a registry naming other values requires those glyphs be redrawn.

Seek to start and seek to end (spec-10 §12.3) are seeks under this section.

### 9.5 A restart is not a failure

A restart under §9.4 MUST NOT be reported as a rendition failure. spec-10
§17.1's prohibition on silent restart governs a delivery that failed, not one a
person moved.

While a restart produces its first bytes, the surface renders spec-10 §17.1's
condition for a reachable deployment whose bytes have not arrived.

### 9.6 Renegotiating

A client MAY re-attempt at a lower declared ceiling. That opens a new delivery,
which replaces the current one at the position last reported, and the replaced
delivery ends.

One rendition exists at a time and each was requested, so §4.2 and spec-01 §13.6
are satisfied. This is not a ladder.

---

## 10. Renditions

### 10.1 Produced on request, never in anticipation

A rendition is produced only by a delivery, which §4.2 defines. It MUST NOT be
produced by ingest, by a schedule, or in anticipation of a request (spec-01
§13.6).

### 10.2 Retention

Retention is OPTIONAL and is off unless the registry (§18) names a bound.

A retained rendition:

- is a Derived asset (spec-01 §5.5) and MUST NOT consume backup capacity
  (spec-01 §13.7, spec-03 §7);
- is never authoritative, so its loss is not data loss and its absence is not an
  error;
- MUST be evictable under a bounded policy, and the eviction MUST be observable
  as having run (spec-10 §11.6);
- MUST NOT be modelled as a digital item or a manifestation (spec-01 §5.5).

A rendition MUST NOT take the Normalized role (spec-01 §13.3), and no identity
key computed over its bytes identifies the holding (spec-05 §4.2).

### 10.3 Reachable only with what the deployment issued

A rendition is reachable only with parameters the deployment issued when it
decided the path. A client MUST NOT reconstruct them, and a request carrying
reconstructed parameters MUST be refused.

spec-10 §11.1 states the reason for presentation assets and it holds here: an
endpoint accepting arbitrary parameters is an unbounded transcoder addressable
by anyone who can construct a query string.

---

## 11. Capacity

### 11.1 The bound is on transcodes

Direct play and remux hold no encoder and MUST NOT be refused for capacity.

### 11.2 Allocated per principal

**Transcode capacity is allocated per principal.** A principal is refused only
by its own transcodes. The sum of allocations MUST NOT exceed what the
deployment sustains, and unused allocation MUST NOT be lent to another
principal.

A household-wide bound would make a refusal a report of a household-level total
over everyone's current playback, which spec-06 §6.3 forbids: the prohibition
covers "every surface, not merely direct queries" and names "Aggregates,
including any household-level total". In a household of two, such a refusal
states that the other member is watching.

Lending the surplus reintroduces it. spec-06 §6.3 requires that implementations
"MUST NOT rely on aggregation as a privacy mechanism at household scale", and a
refusal that usually cannot happen is that reliance.

The allocation is a registry value (§18). spec-01 §13.6 records that compute is
local and CPU time is not a cost consideration, so serving more at once is a
matter of raising it.

### 11.3 At the bound

A delivery at the bound is refused with its reason and MUST NOT be queued.

A restart under §9.4 replaces a transcode and does not add one; otherwise a
person would be refused for seeking within a film they are already watching.

### 11.4 Abandonment

A delivery is abandoned when nothing has been requested of it for longer than
the abandonment period, and an abandoned delivery MUST be torn down.

The period MUST exceed the lead a delivery produces ahead of the playhead, or it
ends a delivery whose client is legitimately playing from its buffer — spec-10
§17.1's first row, which requires that a client keep playing and queue its
position reports.

An abandoned transcode holds its own principal's allocation until it is torn
down, and no other principal's.

---

## 12. What a session reports

### 12.1 Position

A session reports the position of what it is playing, in the medium's own unit,
with the unit named. spec-01 §11.4 records the principal, the res, the device,
the position, the unit, the reporting time, the session's sequence and whether
the session was playing, one per device rather than one per res.

A proportion MUST NOT be reported in place of a position (spec-01 §11.4, §8.4).

Where a digital item is realized by parts, the position reported is a position
in the holding and not in the part being read.

### 12.2 When

A session reports at the reporting interval spec-10 §20 names, and **on each
seek at the moment it commits**.

A seek is the largest single change a position makes, and the interval alone
does not carry it: a scrub to the last act followed by a stop otherwise leaves
the deployment holding the position from before the scrub, and spec-10 §13.3's
backwards threshold does not fire, having only one position to compare.

### 12.3 What is not reported

A session emits *started* and *progressed*. It MUST NOT emit *completed*, which
spec-01 §11.3 establishes when a position passes the ceiling spec-10 §13.2 names
for the category, so that a surface and a count cannot disagree about what
finishing means.

A position below spec-10 §13.2's floor is not kept, and a res below the minimum
length that section names carries none.

### 12.4 Where it goes

A report belongs to its principal and reaches no other (spec-01 §11.2, spec-06
§6.3). A report a client declares flushed from an offline queue carries its
original time and sequence and is ordered by them, and spec-10 §13.3's idle rule
MUST NOT discard it.

Because a session spans holdings (§3.2) while a position is kept per res, the
idle rule of spec-10 §13.3 is measured against the session: a session playing
its second holding keeps its first holding's position live.

### 12.5 Attribution

Playback is attributed to the principal the playing surface is acting as, never
to a principal that sent a command from elsewhere (spec-10 §14.4). No playback
is recorded without an attributable principal (spec-06 criterion 6).

---

## 13. Holdings that are not one file

### 13.1 A release held in one file

Where a release was ripped to a single file and its tracks are temporal
addresses on the release manifestation (spec-04 §6.4), the track is played as a
range-limited play of the medium and not as a second stream. spec-10 §12.2 and
spec-10 criterion 40 require it of the surfaces spec-10 governs.

On the OpenSubsonic surface a track is served by cutting its extent from the
release's master, because a client given a song's stream URL expects a response
of that song's duration. That cut is a transcode.

`download` continues to refuse such a track. Its contract is the bytes as they
arrived (spec-07 §6.7), and a cut of a release's master is not those bytes.

### 13.2 A holding realized by parts

Where a digital item is realized by several assets carrying a part sequence
(spec-01 §5.5, §12.1) — an audiobook arriving as several files, which spec-04
§6.9 places as parts rather than as tracks — one delivery spans them in part
order.

**The part sequence is not the structure a person navigates by.** spec-04 §6.9
records the file split as arbitrary and places the real structure elsewhere:
chapters are temporal addresses on the manifestation. A delivery's reported
position resolves against those chapters.

---

## 14. The surfaces

### 14.1 Where a rendition is reached

A rendition is served on the surfaces spec-07 §3.4 names and on no others.
Spec-08 introduces no surface, no credential type and no signed URL.

Streaming is a grant recorded with a credential and checked on every request
(spec-07 §3.4, spec-06 §4.2), and it MUST NOT widen when its principal's role
changes.

### 14.2 Provenance

spec-06 §3.2 requires the implementation establish that a request came through
the authenticating proxy before reading an identity, and requires the same of a
key-bearing surface before a key is read. Every endpoint this document adds is
covered by the mechanism in force for every other route and MUST NOT take a
weaker one.

### 14.3 What a URI carries

An absolute URI a delivery emits is built from the deployment's configured
external origin — the origin spec-01 §9.3 requires for a deep link — and MUST
NOT be derived from a forwarded header, which is set by the sender wherever the
proxy does not overwrite it.

A segment URI within a playlist MAY be relative, resolving against the
playlist's own URL.

No URI a delivery emits may disclose an asset location (spec-03 §10).

### 14.4 The credential on the wire

A rendition endpoint accepts its credential in a header, which spec-07 §3.2
prefers because query strings reach access logs. Where a protocol places the
credential in the query string, the deployment keeps it out of the logs of the
proxy and of the application, and a credential found in a log is revoked rather
than trusted (spec-07 §8).

### 14.5 Requests not handled

A request on a projected surface this document does not handle MUST be logged
with its full path and parameters and answered well-formed, and MUST NOT be
answered with an empty success (spec-10 §18.8).

---

## 15. Failure

| Condition | Behaviour |
| --- | --- |
| a rendition fails mid-stream | surface the failure and its reason; do not silently restart (spec-10 §17.1) |
| a restart under §9.4 | not a failure; render spec-10 §17.1's bytes-not-yet-arrived condition |
| the link is slower than the rendition | the same condition, until §9.6's re-attempt lands |
| a proxy timeout cuts a delivery | the same condition; the rendition did not fail and the deployment is reachable |
| the buffer empties and the deployment is unreachable | say so; not a spinner and not "something went wrong" (spec-10 §17.1) |
| the connection drops with media buffered | keep playing; queue position reports (spec-10 §17.1) |
| the source asset is absent | surface it loudly; this is data loss (spec-10 §17.1) |

A silent retry that hides a persistent failure behind eventual success is
forbidden (spec-10 §17.1).

Playback failure is the one condition spec-10 Annex A A.9.3 renders as an
assertive notice rather than a polite one.

---

## 16. Conformance

An implementation conforms to this specification if it satisfies all of the
following.

**Sessions and reports**

1. A session names one principal and one device; playback carrying no
   attributable principal is refused, and the System principal is never a
   session's subject.
2. A session's sequence increases once per report and is shared with no other
   session on the same device.
3. Playing an entry of the requesting principal's queue continues the session;
   a holding played from outside the queue opens a new one. A shuffled release
   is one session.
4. A session ends on an explicit stop, on a principal switch, on inactivity
   beyond the registry's period, and at the registry's ceiling, whichever comes
   first.
5. Two devices reporting different positions for one principal and one res
   produce two positions, each naming its device, its unit, its reporting time,
   its session sequence and whether that session was playing.
6. A session reports on each seek as well as at the reporting interval.
7. `playing` is true through a buffering stall and through a §9.4 restart, and
   false after a pause.
8. A report flushed from a declared offline queue carries its original time and
   sequence and is not discarded by the idle rule.
9. A session emits *started* and *progressed* and never *completed*; a position
   below the category's floor is not kept, and a res below the minimum length
   carries none.
10. A position is reported in the medium's own unit with the unit named, and
    never as a proportion.

**Requesting and retention**

11. No rendition exists for a holding no delivery has opened.
12. Rendering a surface, arriving at a deep link, an automatic preview, and
    queueing a holding each produce no delivery.
13. A retained rendition is a Derived asset, is excluded from backup, is
    evictable under the registry's bound, and its eviction is observable as
    having run; its absence is not an error.
14. A rendition never holds the Normalized role and never becomes a digital item
    or a manifestation.
15. One rendition is produced per delivery, and no second quality is produced
    beside the one being played.
16. A rendition is reachable only with parameters the deployment issued; a
    reconstructed parameter is refused.
17. Opening a delivery issues no query to any provider or corpus.
18. Serving a delivery performs no integrity verification.

**The path**

19. A master within the declared capability and ceiling is direct-played, served
    as stored, honouring byte ranges.
20. A master whose codecs are within capability and whose container is not is
    remuxed.
21. A holding for which no rendition within the declared capability can be
    produced is refused with its reason, naming the client and what it declared,
    and is not silently substituted.
22. The path is decided once per delivery and is stated in the response that
    opened it.
23. Capability is taken from the declaration on the request that carried it, is
    never stored against a device, and is never inferred from a device name.
24. A declaration distinguishes what the device decodes on its own speakers from
    what it passes through, and every rendition carries an audio track of the
    former kind.
25. A selection differing from the profile's preference is reported and is not an
    error, and the selection set is never empty.
26. A delivery reads the tracks the container holds and demultiplexes nothing.
27. A selected track is addressed by kind, language, disposition and channel
    count with an ordinal, never by container index, codec or default flag.
28. Audio selection, subtitle selection and subtitle visibility are three
    settings; turning subtitles off preserves which track was chosen.
29. A subtitle track the client can render is delivered beside the rendition and
    is not burned in; an image-based track is labelled as such, is burned in only
    where the person asked for it, and a delivery without it is available.
30. A delivery reads the digital item spec-10 §8.1 resolves, not spec-04 §8.1's
    analysis source.
31. Where a digital item is realized by parts, the delivery spans them in part
    order and reports a position in the holding.

**Form and seeking**

32. Moving image is delivered segmented and audio progressively, and the form
    declared per media source is the form served.
33. Every offset accepted or emitted is a timestamp; a byte position, a frame
    number and a segment index are refused as offsets.
34. A seek within the produced range reaches no transcoder, and the produced
    range spans the delivery's restarts rather than one encoder process.
35. A seek beyond the produced range restarts no sooner than the settling period
    after the seek that provoked it, and seeks within that period coalesce to
    the newest by sequence.
36. A delivery begins producing one large seek granularity before its offset.
37. A restart is not reported as a rendition failure; a rendition failing
    mid-stream is reported with its reason and is not silently restarted.
38. A re-attempt at a lower ceiling opens a delivery that replaces the current
    one at the position last reported.

**Capacity**

39. Direct play and remux are never refused for capacity.
40. A principal is refused for capacity only by its own transcodes, and unused
    allocation is not lent to another principal.
41. A restart replaces a transcode and does not add one.
42. A delivery from which nothing has been requested for longer than the
    abandonment period is torn down, and the period exceeds the lead a delivery
    produces.

**On the wire**

43. A rendition endpoint refuses a request carrying no proxy assertion before
    any credential is read.
44. Spec-08 issues no credential spec-07 §3.4 does not admit, and the streaming
    grant is checked on every request.
45. An emitted absolute URI is built from the configured external origin and
    never from a forwarded header, and no emitted URI discloses an asset
    location.
46. A track of a release held in one file is served by cutting its extent on the
    OpenSubsonic surface, is a range-limited play of the medium on the surfaces
    spec-10 governs, and continues to be refused by `download`.
47. A projected request this document does not handle is logged with its full
    path and parameters and answered well-formed, never as an empty success.

---

## 17. Security considerations

**A refusal carries no fact about another principal.** §11.2 allocates capacity
per principal for this reason. Every refusal this document emits is about the
refusing principal's own declaration, its own ceiling or its own transcodes, and
none is computed over the household. spec-06 §6.3 forbids the alternative, and
spec-01 §16 identifies aggregate surfaces as the likely leak path.

**A reason is required and is not a disclosure.** A refusal distinguishable from
a fault is what stops a person pressing play again. That requirement and spec-06
§6.3 conflict only where the reason is computed over more than the requesting
principal.

**Opening a delivery tells nobody outside the household.** §6.4 forbids a
provider query on the playback path. spec-05 §14 records why: a query issued
because someone opened something converts a catalog surface into a channel
disclosing consumption.

**A rendition URL is not a secret.** It is reached on a surface behind the
authenticating proxy, with a credential whose damage is bounded by its recorded
grant and by revocation rather than by secrecy (spec-06 §8). §14.3 keeps an
asset location out of it.

**A credential in a query string is multiplied by segmentation.** A progressive
delivery is one request; a segmented one is a playlist and every segment, each
carrying the credential into an access log. §14.4 is what bounds it.

**Reach does not widen the boundary.** Playback from outside the household
network is served on the surfaces spec-07 §3.4 already names, behind the proxy
spec-06 §3.2 already requires. Who may stream is the identity provider's
decision (spec-06 §6.1), and an admitted identity becomes a Member on its first
request.

---

## 18. Registries

Seed data (spec-01 §7.5), maintained through releases. A registry this section
names MUST be populated before the section depending on it is built, and no code
path may supply a value a registry omits.

| Registry | Holds |
| --- | --- |
| session inactivity period | after which a session with no report ends (§3.3) |
| session ceiling | the longest a session runs (§3.3) |
| seek settling period | the minimum between a seek and the restart it provokes (§9.4) |
| transcode allocation | per principal, the concurrent transcodes it may hold (§11.2) |
| abandonment period | after which a delivery from which nothing is requested is torn down (§11.4) |
| rendition retention bound | the size and age within which a retained rendition is kept, and none where retention is off (§10.2) |

spec-10 §20's `reporting interval`, `resume thresholds`, `seek granularities`
and `category presentation` are read by this document and are not restated here.

---

## 19. What this document rests on elsewhere

| What this document needs | Where it is specified |
| --- | --- |
| which expression and digital item a person meant (§4.3) | spec-10 §8.1 |
| the queue a session follows (§3.2) | spec-10 §12.3, spec-07 §6.5 |
| which of two positions a surface shows, and the idle rule (§12.4) | spec-10 §13.3 |
| the floor, ceiling and minimum length a position is bounded by (§12.3) | spec-10 §13.2 |
| the reporting interval (§12.2) | spec-10 §20 |
| the seek granularities the lookback is measured in (§9.4) | spec-10 §20, Annex A A.8.7 |
| a text track's classification (§8.1) | spec-10 §17.4 |
| what a surface renders for each failure (§15) | spec-10 §17.1 |
| the surfaces a credential is admitted on (§14.1) | spec-07 §3.4 |
| that a request came through the proxy (§14.2) | spec-06 §3.2 |
| a stream addressed so that it survives a re-encode (§7.2) | spec-01 §8.5, spec-04 §6.5 |
| the extent of a track of a release held in one file (§13.1) | spec-04 §6.4 |
| the chapters a part-realized holding is navigated by (§13.2) | spec-04 §6.9 |

---

## 20. References

### 20.1 Normative

- **[spec-01]** *Catalog Data Model*, this system. §13.6 governs when a
  transcode may be produced; §8.4 and §8.5 govern how a position and a track are
  addressed; §11.4 is the position this document reports.
- **[spec-03]** *Assets, Storage and Preservation*, this system. §4.4 is the
  capacity obligation; §5.2 forbids verification as a side effect of playback;
  §7 excludes a rendition from backup.
- **[spec-04]** *Ingest and Normalization*, this system. §5.1 records the probe
  §6.4 reads; §6.4, §6.5 and §6.9 are the holdings §7 and §13 play.
- **[spec-06]** *Principals, Auth and Authorization*, this system. §4 scopes a
  session to a principal; §6.3 is why §11.2 allocates per principal.
- **[spec-07]** *Wire Protocol*, this system. §3.4 names the surfaces a
  rendition is served on; §4.4 is the untransformed byte route; §6.7 is the
  OpenSubsonic retrieval this document completes.
- **[spec-10]** *Presentation*, this system, with Annex A. §12 and §13 are the
  transport and the continuity a session reports into; §17.1 is what a failure
  renders as; §18 is the television client contract; §20 holds the registries
  §18 reads.
- **[RFC9110]** HTTP Semantics, §14 (range requests).
- **[RFC9457]** Problem Details for HTTP APIs.
- **[RFC8216]** HTTP Live Streaming, for the segmented form §9.1 names.
- **[JELLYFIN]** *Jellyfin Server API*, as published in its OpenAPI document,
  for the projection spec-10 §18 makes.
- **[OPENSUBSONIC]** OpenSubsonic API, for the `transcoding` and
  `transcodeOffset` extensions spec-07 §6.2 advertises.
- **[RFC2119]**, **[RFC8174]** as in spec-01 §18.1.

### 20.2 Informative

- **[spec-02]** *Annotations and Derived Data*, this system. §3.3 is why a
  detected segment marker anchors nothing a person asserted.
- **[spec-05]** *Metadata Acquisition and Matching*, this system. §14 and
  criterion 30 are why §6.4 consults nothing outside the household.
- **[spec-09]** *Search, Ranking and Recommendation*, not yet written.
- **[RFC8628]** OAuth 2.0 Device Authorization Grant, by which a television
  enrols (spec-07 §3.4).
