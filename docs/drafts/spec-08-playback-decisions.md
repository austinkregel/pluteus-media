# Spec-08 decisions and open questions

> **Non-normative.** Where this conflicts with [spec-01](../spec-01-catalog-data-model.md),
> the specification governs.

The path from a person pressing play to bytes a client can decode, and the
viewing occasion that path belongs to.

---

## 1. Scope

### 1.1 What spec-08 covers

- The viewing session: what it is, what starts one, what ends one, and what it
  reports
- The path decision: direct play, remux, transcode, and what chooses among them
- Capability declaration: what a client says about itself and when
- Track selection at playback, over the streams a container holds
- The delivery forms a rendition takes, per media class
- Seek within a delivery, and what a seek costs
- Capacity: concurrency, refusal, and abandonment

### 1.2 What spec-08 does not cover

Presentation assets — thumbnails, trickplay sheets, waveforms, extracted text —
which are spec-07 §4.6 by profile and spec-10 §11 in substance, and which
spec-01 §13.6 places outside transcoding. The queue, which is spec-10 §12.3 and
spec-07 §6.5, and is one object per principal. Resume position arbitration,
which is spec-10 §13.3. Which expression plays, which spec-10 §8.1 resolves
before playback begins. Output transports — AirPlay, Cast, Snapcast, DLNA —
which the deployment consumes rather than implements. Ranking and
recommendation (spec-09).

Documents, ebooks, scans and photographs never reach a rendition, and neither do
the package and software classes spec-04 §5.3 names, which spec-04 §6.9 adopts
as their own masters. Moving image and audio do.

Taking a holding onto a device to play while disconnected is not specified here.
spec-10 §13.3's "declared offline queue" is a queue of position reports
accumulated during §17.1's connection drop with media already buffered, not a
downloaded copy, and nothing in the series provides for one.

A sleep timer and a subtitle timing offset are surface affordances that reach no
server and change no rendition. They belong to spec-10 §12.3 beside playback
speed (§5.14), and spec-08 specifies none of the three.

---

## 2. Vocabulary

Three things are distinguished, and conflating any two of them produces the
contradiction recorded in §5.1.

**A session** is one viewing occasion of one principal on one device. It spans
pauses, seeks, and successive holdings within one ordered grouping. It is what
spec-01 §11.4's `sequence` counts, and what spec-10 §13.3's idle rule measures
against the reporting interval.

**A delivery** is one continuous production of bytes for one session: one
direct-play response, one remux, or one transcode process. A session holds many
deliveries in succession. Concurrency and capacity are counted in deliveries.

**A rendition** is the bytes a delivery produces where the path is remux or
transcode. It is a Derived asset if retained at all (spec-01 §5.5), and never
a digital item, a manifestation, or a normalized master.

---

## 3. What upstream binds

### 3.1 The trigger, and the criteria that wait

spec-01 §13.6: transcoding "MUST be triggered by an actual request for the
content, never by ingest, by a schedule, or in anticipation." spec-01 criterion
33 tests it: "No transcode output exists for content that has never been
requested; retaining the output of a requested transcode is accepted, and a
thumbnail generated at ingest is accepted."

Spec-08 must define *requested* precisely enough that criterion 33 is
machine-checkable.

spec-01 criterion 40 waits on it too. It requires two devices reporting
different positions for one principal and one res to produce two positions,
"each naming its device, its unit, its reporting time, its session sequence and
whether that session was playing."

`resume_positions` is keyed on principal and res, carries `position_ms` and a
`comment`, and carries no device, unit, reporting time, sequence or playing
flag. `Pluteus.Consumption` carries positions and devices elsewhere —
`save_play_queue/5` takes a position and the device it was saved from, and
`playing/4` and `now_playing/1` record what a device is playing now — but
nothing it exposes reports a position against a session.

The implementation also records the event type `"played"` rather than spec-01
§11.3's *started*, *progressed* and *completed*.

A per-session sequence has no producer until a session exists. Criterion 40 is
therefore reachable only once spec-08 defines one, and the schema change that
carries it belongs with spec-08 rather than before it.

The conformance suite carries a `describe` block per numbered criterion and
holds none for criterion 33, running 29 through 32 and then 36, 37, 34 and 35.
There is no transcode path to assert against.

### 3.2 Transcoding is the normal path

spec-01 §13.6: the standardized master "is nonetheless chosen for fidelity and
longevity, not for direct-play compatibility. Serving therefore transcodes
routinely rather than exceptionally, and that cost is accepted." spec-03 §4.4
restates it and adds a capacity obligation: implementations "SHOULD be able to
serve the household's realistic concurrency."

spec-03 §4.4: on-demand transcoding puts "sustained real-time transcoding on the
critical path for playback."

spec-03 §5.2 names playback as a forbidden trigger for something else:
verification "MUST NOT be an operator convention, a manual action, or a side
effect of playback." Reading an asset to serve it verifies nothing.

Byte ranges bind the direct-play path from three directions. spec-07 §4.4 honours
them "since a player seeks by range"; spec-10 §18.4 serves a master within
capability "as stored, with byte ranges"; spec-10 §18.5 requires them "for every
asset served to a client, not only for media". Tested by spec-07 criterion 8 and
spec-10 criterion 59.

spec-04 §7 holds the Normalized role "one asset per digital item, or per part
where a digital item is realized by parts", so the parts §3.6a spans may differ
in codec and a path decision made once per delivery has to hold across them.

spec-10 §18.8 binds every endpoint spec-08 adds: an unhandled request "MUST be
logged with its full path and parameters" and answered well-formed, "never an
empty success". Criterion 60 tests it.

### 3.3 Retention

Permitted under spec-01 §13.6 subject to all of: a Derived asset (§5.5),
therefore never backed up (§13.7); never authoritative, so its loss is not a
data loss and its absence is not an error; evictable under a bounded policy.
"A transcode produced before anything asked for it is pre-generation, whatever
its eviction policy."

spec-10 §11.6 supplies the model for the bound: eviction "MUST be observable as
having run, because a timer that silently fails fills a disk and the failure is
invisible until it is total."

### 3.4 Capability

spec-10 §18.4: "The client declares what it can decode, per playback attempt,
and the deployment answers with the stored bytes or a rendition. The deployment
MUST NOT infer capability from a device name: decoding capability varies within
one product line and changes with the audio path." Criterion 57 tests it.

Two format facts bind regardless of spec-08 (spec-10 §18.4):

- "Where the household's televisions differ in capability, one holding may be
  served on one and refused on another, and the deployment MUST say which."
- "A rendition MUST carry an audio track the device can decode on its own
  speakers. An audio codec the device can only pass through to a receiver is
  silence on a television that has none."

The audio path is therefore a capability dimension distinct from codec support.

Both surfaces already carry a declaration shaped the same way. Jellyfin's
`DeviceProfile` holds `DirectPlayProfiles`, `TranscodingProfiles`,
`CodecProfiles`, `ContainerProfiles`, `SubtitleProfiles`, `MaxStreamingBitrate`,
`MaxStaticBitrate` and `MusicStreamingTranscodingBitrate`. OpenSubsonic's
`getTranscodeDecision` takes a `ClientInfo` body carrying `directPlayProfiles`,
`transcodingProfiles` and `codecProfiles`, the last with `limitations` of
`name`, `comparison`, `values` and `required`, plus `maxAudioBitrate` and
`maxTranscodingAudioBitrate`.

One internal capability model therefore serves both projections, and neither
projection needs a vocabulary of its own.

`DeviceProfile` also carries `Id` and `Name`. Neither is read. Capability comes
from the profile's contents on the request that carried it, which is what
criterion 57 tests and what spec-10 §18.4's prohibition is about.

Capability is not the surface. spec-10 §4.4 requires a surface to be declared
and never inferred, and records that declaration with the device when it is
bound. The two are different facts: which surface a device is stays recorded,
and what it can decode this time does not.

### 3.5 Two surfaces, two defaults

spec-07 §6.7 serves the master whatever `format` was asked for and lets the
content type say what was served. spec-10 §18.4 refuses instead, "because a
client handed bytes it cannot decode has no fallback and no way to explain
itself." spec-10 criterion 58: a holding the client cannot decode "is refused
with a statement of why, and is not silently substituted."

Both stand. The difference is a property of the surface, not a contradiction.

### 3.6 Track selection

spec-01 §8.6: selection is server-side, over parallel expressions, using
household and personal preferences. "The selection set is never empty: the
container's default track is always present… Implementations MUST NOT report an
absence." Ordering is distance from the representative expression (§6.5), not
container track order. "Audio selection, subtitle selection, and subtitle
visibility are independent settings. Implementations MUST NOT collapse them into
a single language preference."

spec-01 §5.3: a multi-track container is an aggregate of parallel expressions
and MUST NOT be demultiplexed at ingest. "Track selection (§8.6) operates over
tracks present in the container."

spec-01 §8.5: a `track` selector "identifies its stream by kind, language,
disposition and channel count, with an ordinal among streams alike in all four.
It MUST NOT identify a stream by its index in the container, its codec, or the
name its codec gives the channel layout." spec-04 §6.5 adds that the container's
default flag does not enter into the address either, "since a muxer sets it
freely" — while spec-01 §8.6 still uses the default track as the fallback
*selection*.

spec-04 §6.5: a 5.1 mix and its stereo downmix are one expression with two
`track` addresses; different languages are parallel expressions. A downmix
decision is therefore within an expression, a language decision across them.

The wire vocabulary exists already: spec-01 §9.1 adopts [MEDIA-FRAGS], which
supplies a `track` dimension alongside `t` and `xywh`.

### 3.6a What a delivery reads

A manifestation may be carried by several digital items (spec-01 §6.1), and
spec-04 §8.1 designates one of them the manifestation's **analysis source** —
"the earliest placed digital item until a member names another". That
designation is analysis's, and whether playback follows it is not decided
(§6.5).

A digital item may itself be realized by several assets. spec-04 §6.9 places an
audiobook arriving as several files as "parts of one digital item" carrying a
part sequence (spec-01 §12.1), rather than as tracks of a release, because
"nothing was released as a track". One delivery therefore spans several assets
in part order, and the position it reports is a position in the holding rather
than in the file being read.

The part sequence is not the structure a person navigates by. spec-04 §6.9 calls
the file split arbitrary — treating it as arrangement "would put a reading's
arbitrary file split into the catalog as though it were arrangement" — and puts
the real structure elsewhere: "Chapters become temporal addresses (spec-01 §8.3)
on that manifestation… so that a chapter is a region of the reading rather than
a holding of its own." A delivery's reported position resolves against those
chapters, and a person resuming at hour nine reaches the chapter they were in
rather than the file it happened to fall in.

### 3.7 Addressing and seek

spec-01 §8.4: the addressing basis MUST survive re-encoding. Byte offset, frame
number and absolute pixel coordinates are MUST NOT; timestamp and percentage
spatial coordinates are permitted. "Normalized position MUST be derived from the
extent, not stored."

Every offset spec-08 accepts or emits is therefore a timestamp, including
OpenSubsonic's `transcodeOffset`, even though a transcoded stream is naturally
byte- and segment-addressed.

spec-10 §12.3 and §17.5: seeking needs a non-drag path, and "on a directional
remote seeking is a repeated key rather than a gesture." The two granularities
are spec-10 §20 registry values; Annex A A.8.7 draws back 10s and forward 30s.

Both projections already express an offset as a time. OpenSubsonic's
`getTranscodeStream` takes `offset`, "the time offset in seconds from which to
start transcoding." Nothing converts from a byte position.

`getTranscodeStream` also takes `transcodeParams`, which the client must obtain
from `getTranscodeDecision` and may not reconstruct. A rendition is therefore
reachable only with a token the deployment issued, which is the control spec-10
§11.1 requires of a presentation asset — "an endpoint accepting arbitrary
dimensions is an unbounded transcoder addressable by anyone who can construct a
query string" — arriving by a different route.

### 3.8 The session's reports

spec-01 §11.4 records the position: principal, res, device, position, unit,
`reported_at`, `sequence`, `playing`. Kept per device, not per res. spec-10
§13.1: "Every surface reports it; no surface owns it."

spec-01 §11.3: "*completed* is not reported by a client. It is established when
a position passes the ceiling [spec-10] §13.2 names for the category." Spec-08
emits `started` and `progressed`.

spec-01 §11.1 sizes the corpus at 30-second checkpointing. The interval itself
is spec-10 §20's `reporting interval`, against which spec-10 §13.3's idle rule
is measured.

spec-10 §13.3: a report "flushed from a declared offline queue is not a live
report." Spec-08's report must be able to declare itself one. That queue is
spec-10 §17.1's connection-drop row — reports accumulated while a client keeps
playing buffered media — and not a holding taken offline, which §1.2 excludes.

spec-10 §13.2 bounds a report at both ends, not one: "A position below a floor
is discarded… Above a ceiling it is discarded and the res is recorded as
consumed. A res below a minimum length never carries a position." Criterion 31
tests all three.

**A seek is reported.** §3.8's heartbeat is spec-10 §20's reporting interval,
which spec-01 §11.1 sizes at thirty seconds, and a seek is the largest single
change a position ever makes. Scrubbing to the last act, watching a minute and
stopping otherwise leaves the deployment holding the position from before the
scrub, and spec-10 §13.3's backwards-threshold warning never fires because it
compares two positions and there is only one. A report at the moment a seek
commits needs no field spec-01 §11.4 does not already carry.

Because §4.6 lets a session span holdings, spec-10 §13.3's idle rule — "a live
report from a session idle beyond the reporting interval is ignored" — is
measured per session while a position is kept per res. A session playing its
second holding keeps the first holding's position live.

### 3.9 Attribution and privacy

spec-06 §4: "There is no shared or ambient session. Every playback MUST be
attributable to a principal. A device is not an identity and MUST NOT accumulate
consumption history of its own." A device may hold credentials for several
principals (§4.1), each separately revocable.

spec-06 §6.1: the System principal "MUST NOT be a playback subject."

spec-06 §6.3 and spec-01 §11.2: no principal observes another's consumption,
through any aggregate, count or ordering. A household of two makes almost any
aggregate re-identifying. A "what is playing now" surface across the deployment
is exactly the forbidden shape.

spec-10 §14.4: playback driven from another surface "is attributed to the
principal the playing surface is acting as, never to the one that sent the
command."

spec-10 §17.8: an automatic preview "MUST NOT record a consumption event."

spec-07 §4.5: another principal's datum answers 404, never 403, because 403
would confirm it exists.

spec-05 §14: "Matching MUST NOT be triggered by a render. A query issued because
someone opened a page tells a provider what that person is looking at, which
converts the catalog surface into a channel disclosing consumption." Criterion
30 is wider than a render: no match query is triggered "by a render, by a
search, or by any action a principal takes on a surface."

Opening a delivery is such an action. A path decision therefore consults no
provider and no corpus, and reads only what the catalog and the probe already
hold.

spec-03 §10: location references "SHOULD NOT be exposed on surfaces reachable
outside the household network." Playback reaches such a surface once §4.1's
decision stands, so nothing a rendition URL carries may disclose where the bytes
sit.

### 3.10 Credentials

spec-07 §3.4: three surfaces, and a key is accepted on two — the OpenSubsonic
surface and the projected surface spec-10 §18 serves. Streaming is an enumerated
grant, checked on every request, and does not widen when its principal's role
changes. spec-06 §8: a credential in device storage "cannot be kept secret from
whoever holds the device, so its damage is bounded by what it may do and by how
quickly it can be revoked, and not by secrecy."

A stream URL spec-08 issues is therefore scoped and revocable rather than
secret, and is not a fourth credential type. The candidate that would introduce
one is named: `audio_proxy` renders its variants from signed URLs, and adopting
it means either replacing that mechanism or accepting a credential spec-07 §3.4
does not admit.

### 3.11 The television

spec-10 §18.1: "The projection target is the Jellyfin server API [JELLYFIN], and
the client is the Jellyfin Roku client," forced by Roku's channel-store rules.
The deployment declares the API version spec-10 §20 names, and that string is a
behaviour switch in the client.

spec-10 §18.2 already enumerates "playback negotiation, byte serving, and
playback-state write-back" among the projected endpoint groups. The router
serving them is case-insensitive in path and parameter name and tolerates a
trailing slash.

spec-10 §18.1 maps a media source to a digital item and a media stream to a
content stream of it. Spec-08's negotiation is expressible in that shape.

spec-10 §23.1 makes [JELLYFIN] normative, "as published in its OpenAPI
document," so the shapes below bind rather than inform.

`/Items/{itemId}/PlaybackInfo` takes a `DeviceProfile` and answers a
`PlaybackInfoResponse` of `MediaSources`, `PlaySessionId` and `ErrorCode`. A
`MediaSourceInfo` carries `SupportsDirectPlay`, `SupportsDirectStream`,
`SupportsTranscoding`, `TranscodingUrl`, `TranscodingSubProtocol`,
`TranscodingContainer`, `Container`, `Bitrate`, `RunTimeTicks`, `MediaStreams`,
`DefaultAudioStreamIndex` and `DefaultSubtitleStreamIndex`.

The three support flags are the path decision of §4.7 under other names, direct
stream being remux.

`TranscodingSubProtocol` is `MediaStreamProtocol`, whose members are `http` and
`hls` and nothing else. The deployment declares which, per media source. Neither
is forced by the protocol.

`PlaySessionId` identifies an active playback instance, which is a delivery in
§2's sense and not a session. The projection names the delivery; the session is
the deployment's own and is not projected.

`ErrorCode` is `PlaybackErrorCode`, whose members are `NotAllowed`,
`NoCompatibleStream` and `RateLimitExceeded`. `NoCompatibleStream` is the slot
criterion 58's statement of why occupies, and OpenSubsonic's
`transcodeDecision` carries `transcodeReason` for the same purpose.

`DefaultAudioStreamIndex` and `DefaultSubtitleStreamIndex` are container
indices, which spec-01 §8.5 forbids as an addressing basis. They are wire
handles valid within the response that issued them and are not stored. spec-10
§11.2 makes the same distinction for pixel regions: "spec-01 §8.4 governs stored
selectors, which must survive a re-encode; a display-time crop against a named
derivative is not one."

spec-10 §18.7: the client honours spec-10 §12.2, §12.3 and all of §13.

### 3.12 Subtitles

spec-10 §17.4: a text track carries a classification from spec-10 §20's registry
— captions, subtitles, SDH, forced, commentary, unknown — shown beside the
language, never merged across classifications of one language. Selection is
therefore over language × classification.

"A bitmap subtitle track produces no text. It MUST be labelled as image-based,
MUST NOT count toward any conformance claim, and MUST NOT be burned into a
rendition as its only presentation, since that removes the ability to turn it
off."

Caption styling is the person's, persisted per principal, and on a client whose
platform owns it device-wide, the platform's.

The projection expresses all of this. A `SubtitleProfile` carries `Container`,
`Format`, `Language` and `Method`, and `SubtitleDeliveryMethod` has five
members: `Encode` (burn into the video track), `Embed` (in the file or stream),
`External` (a separate file), `Hls` (a separate HLS stream) and `Drop`. Four of
the five are not burn-in, so spec-10 §17.4 is satisfiable without leaving the
projected model.

### 3.13 Failure

spec-10 §17.1: a connection dropping with media buffered keeps playing and
queues position reports; an empty buffer with the deployment unreachable stops
and says so, "not a spinner, and not 'something went wrong'"; "A rendition fails
mid-stream — surface the failure and its reason. Do not silently restart." A
silent retry that hides a persistent failure behind eventual success is
forbidden.

Annex A A.9.3 designates playback failure the one assertive-alert condition.

### 3.14 The single-file release

spec-04 §6.4: a release ripped to one file with a cue sheet is one digital item
carrying the release manifestation; each track's extent is a temporal address on
that manifestation.

spec-10 §12.2: "Playing track four is a range-limited play of the medium, not a
separate stream." Criterion 40 tests that it resolves through the stored
temporal address and not through a second stream.

spec-07 §6.7: on the OpenSubsonic surface, serving such a track means "cutting
its extent from the release's master, which is a transcode," and `stream`
answers error 0 until spec-08. Criterion 20 records that.

A Subsonic client given a `stream` URL expects a response whose duration is the
song's, so the surfaces answer differently: the interface performs a
range-limited play of the medium, and the OpenSubsonic surface cuts.

Everything but the bytes is already in place. A cue sheet beside a single-file
release is acquired, placed and addressed, and `getSong` answers the cut track's
own duration from the stored temporal address. `stream` and `download` are what
refuse.

---

## 4. Decisions

### 4.1 Reach

Playback from outside the household network is in scope. Bandwidth is a
negotiation input alongside decode capability, and `maxBitRate` means something.

**Reach adds no authentication surface.** The deployment sits behind Traefik,
which is the forward-authenticating proxy spec-06 §3.2 reads an identity from,
and spec-07 §3.4's three surfaces already sit behind it. Remote means that proxy
is reachable from outside; it does not mean a rendition is reached any other
way. Spec-08 introduces no credential, no signed URL and no second path (§3.10).

What reach does change is volume through that proxy, which §7 records.

### 4.2 Delivery form

HLS for moving image, progressive for audio.

Neither projection forces this. `TranscodingSubProtocol` permits `http` and
`hls` and the deployment declares which; OpenSubsonic's transcoding extension
never carries video at all, its `mediaType` admitting only "song" and
"podcast", and `getTranscodeStream` answers "the raw transcoded media stream".

Video segments because a backward seek into the produced range lands on a
segment boundary and restarts no encode. A forward seek beyond the encoder's
lead still restarts, and spec-10 §20's forward granularity — drawn as forward
30s in Annex A A.8.7 — is beyond that lead essentially always, so the control
that skips a recap is a restart every press. Segmenting halves the seek cost of
§4.4 rather than removing it.

Audio is progressive because the Subsonic surface's retrieval endpoints are
progressive, and because a short track's re-encode is cheap enough that a
restart on seek costs little. That reasoning is a song's, not a fourteen-hour
reading's, where the cost is locating the offset across parts rather than
re-encoding.

Which sub-protocol the Jellyfin Roku client handles for a given container is a
property of a client the deployment does not control and cannot pin (spec-10
§18.8). It is established by testing against the client, not by specification.

An adaptive ladder is not produced. Every rendition in a ladder beyond the one
being watched is a transcode nothing asked for, and spec-01 §13.6 forbids it.

### 4.3 Capability

Declared per playback attempt. Never stored against a device, never inferred
from a device name, never looked up from a model registry. The declaration
carries the audio path — own speakers or passthrough — as a dimension of its
own.

### 4.4 Seek

Seeking reaches no transcoder within the delivery's produced range. On direct
play and remux that range is the whole holding and a seek is a byte range
(spec-07 §4.4, which honours ranges "since a player seeks by range").

A seek beyond the produced range restarts the transcode at an offset. A restart
waits at least one second from the seek that provoked it, and successive seeks
arriving inside that window coalesce: the newest by sequence wins, not the last
to arrive, because a directional remote emits a burst and the order of arrival
is not the order of intent.

**The produced range is the delivery's, not the encoder process's.** A restart
extends one playlist over the segments the delivery has already produced rather
than abandoning them, so a seek back into anything already watched is free
however many restarts happened since. Segments produced during a delivery are
not retention in §4.5's sense — §4.5 governs what survives a delivery, and these
do not.

**A delivery begins producing one large seek granularity before its offset.**
Without it, resuming a film at 1:12:00 and pressing back-10s four seconds later
restarts the encoder to recover four seconds, and the same gesture costs nothing
a minute later — the same action with two costs and nothing on screen to explain
which. One bounded lookback per delivery removes the class. Every resume, every
deep link (spec-10 criterion 24) and every forward skip otherwise establishes a
floor the person cannot see.

Seek-to-start and seek-to-end (spec-10 §12.3's home and end) are ordinary seeks
under this rule, and seek-to-end is a restart.

A seek-restart is not a rendition failure. spec-10 §17.1's prohibition on silent
restart governs a delivery that failed, not one a person moved. What the person
sees while a restart produces its first segments is §17.1's *bytes not yet
arrived* row, which §5.11 adds.

### 4.5 Retention

Permitted on spec-01 §13.6's terms, off by default. With seeking client-side and
a restart on a seek beyond the produced range, a retained rendition buys little.
The bound is a registry value; eviction is observable as having run.

### 4.6 The session

One viewing occasion of one principal on one device, as §2 defines it.

**A session continues across whatever the principal's queue holds.** The queue
is one object per principal, shared between the interface and the OpenSubsonic
surface and forbidden to diverge (spec-10 §12.3, spec-07 §6.5), and it is what a
person actually assembled. Playing a release end to end is the case where the
queue is its arrangement order; shuffling one, queueing fourteen songs across
five releases, and crossing from the last episode of a season into the first of
the next are all one occasion and all one session.

Arrangement order alone is not the rule. It would make a shuffled album twelve
sessions from one grouping whose order is sitting right there, and spec-10 §8.3
puts two seasons in two whole-part orderings, which would split an evening in
half.

A holding played from outside the queue starts a new session.

A session ends on an explicit stop, on a principal switch, on inactivity beyond
the session inactivity period, or at the session ceiling, whichever comes first.
A principal switch ends it because spec-06 §4 admits no ambient session.

Both values are spec-08's own registry entries (§5.10). spec-10 §20's existing
`inactivity period` is not one of them: §20 scopes it to §14.2, "after which a
shared surface returns to the choice of principal", and a television that
forgets who is watching and a session that has ended are not the same event.

A session's `sequence` increases once per report within the session and is
shared with no other session on the same device. `playing` describes whether the
person has the session playing rather than whether bytes are moving, so it stays
true through a buffering stall and through a §4.4 restart, and becomes false
only on a pause or a stop.

### 4.7 The path

Direct play where the master is within the declared capability and the bitrate
is within the declared ceiling. Remux where the codecs are within capability and
the container is not. Transcode where a rendition within the declared capability
can be produced.

**Refuse where one cannot**, with its reason, and never substitute silently.
spec-10 §18.4's second format fact is what makes this branch non-empty: "A
rendition MUST carry an audio track the device can decode on its own speakers.
An audio codec the device can only pass through to a receiver is silence on a
television that has none." A device declaring no codec it can decode on its own
speakers is refused rather than served silence.

This is the branch spec-10 criterion 58 tests, and §5.9 restates it against a
producible rendition rather than against a decodable master.

The decision is made once per delivery and stated. Where a fallback selection
differs from the profile's preference, it is reported rather than errored
(spec-01 §8.6).

### 4.7a Subtitles

Where the client declares it can render a track's format, the track is delivered
beside the rendition and never burned in. Jellyfin's `SubtitleDeliveryMethod`
carries `External`, `Embed` and `Hls` for this.

Where it declares it cannot — a bitmap track, PGS or VOBSUB, on a client with no
bitmap renderer, which is the ordinary outcome of ripping a disc — burn-in is
offered only where the person asked for that track, and turning it off produces
a delivery without it. spec-10 §17.4 forbids burn-in "as its only presentation,
since that removes the ability to turn it off"; a second delivery on request is
the ability to turn it off, and the prohibition is satisfied by that rather than
by declining to show the track at all.

A bitmap track is labelled image-based on every surface (spec-10 §17.4) and
counts toward no conformance claim. It answers spec-10 §17.3's subtitle filter
yes, because the holding carries the affordance; what differs per surface is the
delivery method, not whether the affordance exists.

Subtitle selection, subtitle visibility and audio selection stay three settings
(spec-01 §8.6). Burn-in couples visibility to the delivery for one track on one
kind of client, and that coupling is stated rather than hidden: turning that
track off is a new delivery, and turning it on again is another.

### 4.7b What a request is

spec-01 §13.6 triggers transcoding on "an actual request for the content", and
criterion 33 tests that nothing exists for content never requested. A request is
a client opening a delivery through the decision endpoint, and nothing else.

Not a render of a page carrying the holding. Not arrival at a deep link, which
spec-10 §10.2 requires "not begin playback" and criterion 24 tests. Not an
automatic preview, which spec-10 §17.8 requires record no consumption event.
Not queueing a holding, and not spec-10 §12.4's next-member offer, which "MUST
carry a visible interval before it acts" and so has not acted.

### 4.8 Capacity

spec-03 §4.4 sets the obligation without a number: serve "the household's
realistic concurrency". The number is a registry value.

**The bound is on transcodes, and it is allocated per principal.** Direct play
and remux are byte serving and hold no encoder, so they are never refused for
capacity.

Each principal has its own allocation, and a principal is refused only by its
own transcodes. The sum of allocations does not exceed what the deployment
sustains, and unused allocation is not lent to another principal.

**This is what keeps a refusal from being a disclosure.** A household-wide bound
makes a refusal report a household-level total over everyone's current playback,
which spec-06 §6.3 forbids — it covers "every surface, not merely direct
queries", and names "Aggregates, including any household-level total". In a
household of two, being refused would say the other member is watching right
now. Under a per-principal allocation a refusal reports only the refused
principal's own transcodes, which that principal already knows about.

Lending the surplus would reintroduce it. A refusal that usually cannot happen
is aggregation used as a privacy mechanism, and spec-06 §6.3 says implementations
"MUST NOT rely on aggregation as a privacy mechanism at household scale."

The cost is stated: a household sized for three sustained transcodes and holding
three principals leaves two allocations idle when one person is home alone, and
does not lend them. Compute is local (spec-01 §13.6) and the allocation is a
registry value (§5.10), so the answer to wanting more at once is to raise it.

At the bound a delivery is refused with its reason, and is not queued.
`PlaybackErrorCode` carries `RateLimitExceeded` and carries nothing for a
delivery that will start later, and spec-10 §17.1 requires a failure be surfaced
rather than absorbed.

**An allocation counts transcodes a person is watching.** A §4.4 restart
replaces a transcode and does not add one, or a person would refuse themselves
for seeking in a film they are already watching. An abandoned delivery holds its
own principal's allocation until §6.2's rule tears it down — which, under this
allocation, locks out only the person who left the television on and never the
household.

### 4.8a Renegotiating mid-delivery

A client may re-attempt at a lower declared ceiling. That opens a new delivery,
which replaces the current one at the position last reported, and the old one
ends.

This is not a ladder. One rendition exists at a time and each was asked for, so
spec-01 §13.6 is untouched. Without it §4.1's bandwidth input is a property of
the first second of a delivery and of nothing after it, and a connection that
degrades mid-film leaves the person in spec-10 §17.1's *unreachable* row being
told something false — the deployment is reachable and is sending more bytes
than the link carries. §5.11's row is what that case renders as until the
re-attempt lands.

### 4.9 The television's credential

A television enrols through the OIDC device authorization grant [RFC8628],
which spec-06 §4 already says an input-constrained client SHOULD use. Support
for it does not wait on any particular provider.

The grant establishes the person. What the television then holds is a client
key in spec-07 §3.2's sense, minted by the deployment as the grant completes,
carrying the narrowed grant of spec-06 §4.2 and revocable per principal per
device.

The alternative — the television holding the provider's own access token, and
the deployment validating it on every request — is not taken. spec-06 §4.2
requires a credential's grant "MUST NOT be widened by the principal's role
changing afterwards". That is an invariant the deployment enforces over a
credential it minted; moved into provider scopes it becomes the provider's to
hold, where a role change widens a television's reach without the deployment
hearing of it.

Streaming therefore remains a grant checked on every request, whatever enrolled
the device.

**What this costs, stated rather than absorbed.** The deployment drives the
grant: it asks the provider's device-authorization endpoint, hands the user code
to the television to display, and polls the token endpoint until the person
approves. It therefore holds a client registration with the provider and makes
outbound calls to it, which it does not today.

That is narrower than it sounds and is not the thing spec-06 §3.2 rules out.
Forward authentication still establishes identity for every browser request, and
the deployment is not a relying party for those. The registration exists for
enrolling a device and for nothing else, and the token the provider returns is
read once, to learn which principal approved, and is not retained. spec-05 §6.3
already has the deployment making identified outbound provider calls, so the
outbound direction is not new; the client registration is.

**The second cost is switching.** spec-10 §14.2 requires switching principal be
reachable from every surface, never require "entering a credential on a surface
with no keyboard", and be "cheap enough that people actually do it", because
otherwise "one principal's history silently absorbs the household's".

spec-10 §20's `credential policy` registry decides whether a television holds one
credential or several. Under several, the grant runs once per device per person
and switching is a selection among stored credentials, which §14.2 permits and
spec-10 §21 costs in plaintext exposure. Under one, every switch of viewer is a
fresh grant — read a code, find a phone, sign in, approve, wait — which two
people sharing a sofa will do approximately never, and §14.2 is then not met.

Spec-08 is written against the several-credential policy. Under the one-credential
policy the enrolment cost is paid on every switch, and that is a tension with
§14.2 rather than a detail.

---

## 5. Upstream text spec-08 changes

Edited in place, in spec-08's own change.

### 5.1 spec-01 §13.6

"a transcode is per-session and the selected track (§8.6) is an input to it"
becomes per-delivery, in §2's sense. The sentence performs concurrency
accounting, which counts continuous productions of bytes rather than viewing
occasions.

### 5.2 spec-07 §6.2

`transcoding` and `transcodeOffset` join the advertised set. The clause holding
them back is removed.

### 5.3 spec-07 §6.7

`format`, `maxBitRate` and `estimateContentLength` change what is served. A
track of a release held in one file is served by cutting its extent.

### 5.4 spec-07 criterion 20

The clause answering error 0 for a track with no digital item of its own is
replaced by what spec-08 serves.

`download` is not among them. Its contract is the bytes as they arrived, and a
cut of a release's master is not those bytes, so a track of a release held in
one file continues to refuse `download` after spec-08.

### 5.5 spec-10 §18.4

The refusal of a holding outside declared capability becomes the rendition
spec-08 produces. The two format facts in that section stand unchanged.

### 5.6 spec-10 §18.3

Enrolment is the OIDC device authorization grant [RFC8628], which spec-06 §4
recommends for an input-constrained client. What it mints is the client key
§18.3 already describes, with the grant, the scoping and the revocability that
section already carries.

### 5.7 spec-07 §3.2, §3.4 and spec-06 §3.2

§3.4's television enrolment is the device authorization grant, and what it mints
is the client key §3.2 already specifies. spec-06 §4 recommends the grant for an
input-constrained client, so the three sections agree once §3.4 carries it.

The forward-authentication exemption reaches both surfaces a key is accepted on,
rather than the OpenSubsonic path alone. A surface whose client cannot follow a
browser through the provider's sign-in cannot be asked to, and §7.3 is what the
present wording costs.

### 5.8 spec-07 §1.2

Bytes are served as stored or as a rendition, as the negotiation decides.

### 5.9 spec-10 criterion 58

A holding for which no rendition within the client's declared capability can be
produced is refused with a statement of why, and is not silently substituted.

### 5.10 The registries

spec-10 §20 gains the retention bound (§4.5), the session inactivity period and
the session ceiling (§4.6), the per-principal transcode allocation (§4.8) and
the abandonment period (§6.2), and its `projected endpoints` row gains the
rendition endpoints. spec-10 §20's own rule is that a registry it names is
populated before the section depending on it is built.

### 5.11 spec-10 §17.1

The degradation table gains a row: **the deployment is reachable and the bytes
have not arrived yet** — a transcode producing its first segments after a §4.4
restart, a link too slow for the rendition being served (§4.8a), or a proxy
timeout (§7.6). It renders as that, named, and not as a spinner, not as
"something went wrong", and not as the deployment being unreachable, which is
false in all three cases.

It is rendered outside any live region, as §17.7 requires of a buffer state and
criterion 43 tests.

### 5.12 spec-10 §18.4, first format fact

Where a holding cannot be served to a client, the refusal names that client and
what it declared, at the moment of the attempt. The present wording — "one
holding may be served on one and refused on another, and the deployment MUST say
which" — reads as a statement about televisions the person is not standing in
front of, which §4.3 makes unknowable by forbidding stored capability.

### 5.13 spec-10 §12.1 and §12.2

§12.1's table gains the audiobook and podcast-episode categories spec-04 §6.9
places, with their primary surface, their honoured selectors and the
presentation assets they require, and §20's `category presentation` registry
gains the same. Without them a fourteen-hour reading falls to the music
recording row and is offered a waveform and a cover.

§12.2's track-of-a-release rule is scoped to the surfaces spec-10 governs.
Unmarked it binds a client in §2's sense, which would reach the OpenSubsonic
surface, where §3.14 cuts rather than range-limits. Criterion 40 is scoped with
it.

### 5.14 spec-10 §12.3

The transport gains playback speed. It is a property of the client's own
rendering on every path, changes no rendition, and reaches no server; spoken-word
audio is unusable without it and §12.3's table is where a transport control is
specified.

### 5.15 spec-07 §6.7

A `Range` header on a request `format` or `maxBitRate` has made a transcode is
answered with the whole stream rather than a range, and the response says so.

A byte offset into a rendition of unknown length addresses nothing (spec-01
§8.4), and clients predating the transcoding extension know only `stream` and a
range. They set a bitrate cap by default on a cellular connection, which §4.1
brings into scope, so the alternative is that the household's existing music
clients lose their scrub bar the day §5.3 lands.

### 5.16 Dependencies and references

spec-07 and spec-10 each depend on spec-08: their `Depends on:` headers and
their normative reference lists carry it, and spec-10's entry for it sits among
the normative references rather than the informative ones.

spec-10 §19's table gains a row for the rendition §18.4 needs, and §1.4 counts
what that table holds and states no outward dependency left unmet.

---

## 6. The remaining decisions

### 6.1 A ceiling below a lossless master

A declared ceiling below the master's rate produces a lossy rendition, and the
delivery states that it did.

spec-01 §13.3's prohibition on re-encoding lossy essence governs normalization,
and spec-03 §4.2 says so directly: "A lossy rendition made for a client to play
is not normalization at all." Nothing forbids the rendition. What the person is
owed is knowing they are not hearing the master, stated the way spec-01 §8.6
states a fallback selection — "implementations SHOULD indicate this
unobtrusively. This is a display concern, not an error."

### 6.2 Abandonment

A delivery is abandoned when nothing has been requested of it for longer than
the abandonment period, and it is torn down. For HLS that is segment requests;
for a progressive stream it is the connection.

The period must exceed the lead a delivery produces ahead of the playhead, or it
kills a client that is legitimately playing from its buffer — which is spec-10
§17.1's first row, "keep playing; show a persistent, non-modal notice". It is a
registry value (§5.10).

Without this an abandoned transcode holds its principal's allocation (§4.8)
indefinitely, and turning a television off at the wall locks that person out of
their own library until something notices.

### 6.3 One delivery per session at a time

A session holds one delivery. A prefetch of the next member of a grouping is
bytes nobody requested, which §4.7b excludes and spec-01 §13.6 forbids, and
spec-10 §12.4's next-member offer "MUST carry a visible interval before it acts"
so it has not acted.

Two sessions playing one res at once remains ordinary (spec-10 §13.3), each on
its own device with its own position.

### 6.4 What `bitRate`, `suffix` and `contentType` describe

What was served. spec-07 §6.7 already settles the shape for the untranscoded
case — "the response's content type says what was served" — and a rendition is
served no differently.

spec-07 §6.4 currently maps them to the probe of the manifestation's analysis
source, which describes the master. §5.15 carries the edit.

### 6.5 Which digital item a delivery reads

The one spec-10 §8.1 resolves, on every surface.

§8.1's ordering is spec-01 §8.6's — distance from the representative expression
under the requesting principal's profile — which is computable on any surface
and depends on the person rather than on acquisition order. spec-04 §8.1's
analysis source is analysis's designation and does not move playback: a member
naming a different source so a tool reads better bytes would otherwise silently
change what plays.

### 6.6 A holding recycled mid-delivery

spec-01 §14.3 makes recycling a catalog state that moves no byte, so a delivery
in flight can complete. Purge removes the bytes (spec-01 §14.3), and spec-05
§8.4's equations and spec-03 §8.3's duplicate resolutions both recycle whatever
is left holding nothing — so a res can be recycled by a decision nobody made
about playback. What a delivery does at each of those moments is not decided.

---

## 7. Deployment and security

Traefik terminates TLS and reverse-proxies to the container in production. In
local development the application is reached directly, with no proxy in front.

### 7.1 A playlist carries URLs

§4.2 delivers moving image as HLS, and an HLS playlist names its segments. The
application speaks plain HTTP on its own port behind the proxy, so a URI built
from the request's own scheme, host and port is not one a remote client can
reach.

**The external origin is configuration.** It is set per deployment from the
environment, and it is the origin spec-01 §9.3 already requires for a deep
link — "the primary identifier plus a reachable origin". Spec-08 introduces no
origin of its own and no second way of learning one.

The deployment already draws this distinction where it matters most. Identity's
issuer is a configured value and only the subject is read from a header, so the
half an attacker could move is the half that is checked and the half that cannot
be moved is the half that is trusted. An emitted origin is the same shape.

**An emitted URI MUST NOT be derived from a forwarded header.**
`X-Forwarded-Host` is set by whoever sent the request wherever the proxy does
not overwrite it, so a deployment building links from it can be made to emit
links pointing elsewhere. The configured value is known before any request
arrives and cannot be moved by one.

Segment URIs within a playlist MAY be relative, since they resolve against the
playlist's own URL and are therefore correct in development and in production
without consulting the origin at all.

### 7.2 A credential in a query string, multiplied

spec-07 §8: a key "travels in the query string, where the Subsonic protocol puts
it. Query strings reach access logs… a key found in a log is revoked, not
trusted."

A progressive audio delivery is one such request. An HLS delivery is a playlist
and every segment, so one film is hundreds of logged requests carrying one
credential. §4.2 creates that volume and this is its cost.

The rendition endpoints therefore accept the credential in `X-API-Key`, which
spec-07 §3.2 already prefers, and where a client can only put it in the query
string the proxy's access log for those paths drops the parameter rather than
recording it hundreds of times an evening.

### 7.3 The projected surface is not exempt, and HLS is on it

spec-07 §3.2 exempts one path: "The OpenSubsonic surface's path is exempt from
forward authentication at the proxy, since a key is its authentication; the
proxy MUST still assert that the request came through it." spec-06 §3.2 counts
it the same way — "One surface is exempt from forward authentication: the one
spec-07 §3.2 serves."

spec-07 §3.4 admits a client key on two surfaces, the OpenSubsonic one and the
projected one spec-10 §18 serves. Only the first is exempted from forward
authentication anywhere in the series.

§4.2 puts moving image on the projected surface as HLS, which is a playlist and
every segment. On the text as it stands each of those is a forward-authentication
round trip, on a surface whose client cannot follow a browser through the
provider's sign-in — which is why it holds a key at all.

This is a gap in spec-06 §3.2 and spec-07 §3.2 rather than a decision spec-08
makes, and §5.7 carries it.

### 7.4 Provenance is spec-06's

spec-06 §3.2 requires the implementation establish that a request came through
the proxy, names no mechanism for it, and requires the key-bearing surface have
come through "established the same way".

Spec-08 adds nothing here. Its rendition endpoints are covered by whichever
mechanism is in force for every other route, and never by a weaker one of their
own.

### 7.5 Development reaches no proxy

spec-06 §3.2 requires the implementation establish that a request came through
the proxy before reading an identity, and spec-07 §3.2 requires a request
without that assertion be refused **before any key is read**. A request made
directly to the application carries no such assertion.

Reaching the application directly in development therefore means either
configuring the secret and sending it, or being refused — which is the correct
behaviour rather than an obstacle, since it is the production rule running in
development too.

Spec-08's conformance tests exercise the rendition endpoints through that
assertion rather than around it, as the suite's existing helpers already do for
every other surface, so the refusal is tested rather than merely configured.

### 7.6 A proxy timeout is not a rendition failure

spec-10 §17.1 requires a mid-stream rendition failure be surfaced with its
reason and never silently restarted, and requires "the deployment is
unreachable" be distinguishable from a spinner. A proxy response or idle timeout
cutting a long delivery presents as neither: the rendition did not fail and the
deployment is reachable.

It is §5.11's row — reachable, bytes not arrived — which is the same row §4.4's
restart and §4.8a's degrading link render as.

### 7.7 Who can stream

spec-06 §6.1: "Who may use the deployment at all is the identity provider's
decision," and an admitted identity with no principal "becomes a Member
principal on its first request". A Member may read the catalog and stream.

With §4.1's reach and automatic provisioning, the boundary on who can stream the
household's holdings from outside the house is entirely the provider's
membership. That is the design rather than a defect.

### 7.8 A refusal carries no fact about another principal

A refusal states its reason, and a reason distinguishable from a fault is what
stops a person pressing play again. That requirement and spec-06 §6.3 are only
in tension where the reason is computed over the household.

§4.8's per-principal allocation is what removes the tension rather than wording
around it: every refusal spec-08 emits is about the refusing principal's own
capability declaration, its own bitrate ceiling, or its own transcodes. None is
derived from what anyone else is doing.

§3.9's rule — "A household of two makes almost any aggregate re-identifying" —
is the reason a household-wide bound could not have been reported honestly, and
§4.8 is where that was answered.
