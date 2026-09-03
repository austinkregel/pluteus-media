> **Non-normative.** Where this conflicts with
> [spec-01](../spec-01-catalog-data-model.md), the specification governs.
>
> **Superseded here:** nothing structural. The protocol survey stands. Note that OpenSubsonic is now a compatibility surface rather than the architecture, and the five ranked specification gaps are inputs to the wire-protocol spec.

# 02 — Protocol Landscape

Playback is four independent problems that ship together in Plex. They standardize very
differently, and each can be adopted separately. This is what makes a swappable-backend design
possible at all.

**Our position:** implement Layer 1, consume Layers 2 and 3, adopt Layer 4.

---

## Layer 1 — Library and serving

A client asks a server what music exists and receives bytes. The only layer with a genuine,
actively maintained open specification.

| Protocol | Status | Notes |
|---|---|---|
| **OpenSubsonic** | Open spec | The de facto standard. ~75 endpoints. Explicitly backwards-compatible with Subsonic, explicitly optional piecewise, runtime capability negotiation. **Publishes an OpenAPI schema** — the surface is largely codegen. |
| Subsonic (original) | Frozen | Closed and stagnant; OpenSubsonic exists because of it. |
| Jellyfin / Emby | Published | Open and usable (`/Audio/{itemId}/universal`) but thinly documented in practice. |
| Plex | Unofficial | No published contract, thoroughly mapped (`python-plexapi`). |
| UPnP / DLNA | Published | Ancient SOAP/XML; the widest hardware footprint in existence. |
| OpenHome | Published | UPnP extension: the queue lives on the *renderer*, so control points can disconnect. |
| DAAP | Reverse-engineered | Apple's old iTunes sharing protocol. Niche; Owntone keeps it alive. |
| ActivityPub | Open spec | Federation, not playback. Funkwhale layers it over a custom Library object and still exposes Subsonic for actual clients. |

### OpenSubsonic detail

**Endpoint groups.** Browsing (20), Lists (7), Playlists (5), Media retrieval (8), Media
annotation (5), Searching (3), Podcast (7), Sharing (4), User management (6), System (4),
Internet radio (4), Jukebox (1), Chat (2).

**Authentication.** Legacy scheme is `u` + `s` (salt, ≥10 chars) + `t` where
`t = md5(password + salt)`. The **API Key Authentication** extension supersedes this with
`apiKey=` and no `u` parameter, and recommends servers implementing it drop salt/token entirely.
Implement API key auth; support legacy only for client compatibility.

**Extensions** (advertised via `getOpenSubsonicExtensions`, individually versioned):

| Extension | Adds |
|---|---|
| `apiKeyAuth` | API-key authentication |
| `formPost` | `application/x-www-form-urlencoded` POST |
| `indexBasedQueue` | Play queue specified and queried by index |
| `playbackReport` | Client playback timeline reporting (`reportPlayback`) |
| `songLyrics` | Synchronized lyrics, multiple languages, retrieval by song ID |
| `sonicSimilarity` | `getSonicSimilarTracks`, `findSonicPath` |
| `transcodeOffset` | Start offset for transcoding |
| `transcoding` | `getTranscodeDecision`, `getTranscodeStream` — client-driven transcode decisions |
| `getPodcastEpisode` | Individual episode metadata |

**`sonicSimilarity` matters most to us.** Extension key `sonicSimilarity`, version 1. Both
endpoints return `sonicMatch` entries of `{Child, normalized score}`. Navidrome implements it as a
*plugin capability* — advertised only when a provider is present, otherwise the endpoints 404.
AudioMuse-AI is the existing provider implementation. `findSonicPath` (a route between two songs
through intermediate matches) is the spec's version of Plexamp's Sonic Adventure.

**Servers implementing it:** Navidrome (0.51.1+), Gonic (0.21.0+), LMS, Ampache, Melodee,
Airsonic-Advanced.

**Clients we inherit by implementing it:** Symfonium, Substreamer, Tempo, Amperfy, play:Sub, DSub,
Feishin, Sonixd, Supersonic, and Music Assistant.

---

## Layer 2 — Transport and output

Getting audio to a speaker. Fragmented, largely vendor-owned, **and already solved by others.**

| Protocol | Openness | Notes |
|---|---|---|
| Google Cast | Documented SDK | Registered app IDs; mature tooling. Most reliable non-Apple target. |
| AirPlay / AirPlay 2 | Reverse-engineered | Never published by Apple. Cracked 2019. shairport-sync (receiver), pyatv / Owntone (sender). |
| Snapcast | Open source | Time-synchronized multiroom — the open answer to Sonos. Not a player; an extension that syncs existing players. |
| SlimProto | Documented | Squeezebox protocol, TCP 3483, Lyrion + squeezelite. Gapless, client sync, up to 384 kHz. The most capable open audio transport, and underrated. |
| Sonos | Vendor | Local control API plus SMAPI; SMAPI requires partner onboarding. |
| HEOS, MusicCast, Bluesound, SoundTouch, WiiM, AmpliPi | Vendor | Individually small, collectively most of the hardware people own. |
| Matter Casting | Open, royalty-free | No certification or royalty fee. Adoption near-nil and video-first (Prime Video, Echo Show 15, Fire TV). Track, don't build on. |

**Music Assistant implements roughly all of this** — AirPlay, Sonos, Google Cast, DLNA, Snapcast,
MPD, MusicCast, HEOS, Bluesound, Bose SoundTouch, Samsung WAM, WiiM, Squeezelite, AmpliPi, Roku,
Yandex, Fully Kiosk, plus a Home Assistant fallback for anything else.

Its OpenSubsonic music provider is tested against Gonic and Navidrome and documented to work with
any conforming implementation. **So implementing Layer 1 gets us all of Layer 2 for free.**

Two caveats from MA's own documentation:

- Some files may not play over a Subsonic connection — most often m4a, opus, and variable-bitrate
  encodes, because those can carry information mid-file rather than in the header.
- Multi-artist tracks/albums render badly unless the server assigns an artist ID to *every*
  contributing artist. A data-model requirement, not a bug to work around later.
- MA requires layer-2 network access (host or macvlan networking) to discover and stream to players.

**We can also do some of this natively.** Pure-Elixir `airplay` (RAOP sender) and `snapcast`
(server, owns the audio clock) exist — see
[04-elixir-package-reference.md](04-elixir-package-reference.md). Both GPL-3.0, both pre-1.0,
single maintainer. Viable for direct output without MA, worth knowing the bus factor.

---

## Layer 3 — Control surfaces

Where "generic UI, swappable backend" is a **platform mandate**, not an app pattern.

### Android Auto / Automotive OS

The app draws nothing. You implement a `MediaLibraryService` (or legacy `MediaBrowserService`)
plus a `MediaSession`, expose a content tree of nodes flagged `FLAG_BROWSABLE` or `FLAG_PLAYABLE`,
and the platform renders it with Google's driver-safe templates.

Constraints that determine whether the result is good:

- **Root children are effectively capped at four.** Only browsable items become tabs. Not all AAOS
  versions send the root hints that state the real limit, so assume four.
- Content styling is negotiated through extras in the root bundle.
- Browsable search results and voice actions are **required**, not optional.
- Google gates Play Store listing on a driver-distraction review.
- In-app media playback while driving is not permitted for video.

**Implication:** Plex's bad Android Auto app is a badly shaped browse tree, not a platform ceiling.
Anyone can beat it on the same API — and Symfonium already has.

### CarPlay

Substantially harder. You cannot build a CarPlay app at all until Apple grants the entitlement,
which requires signing the CarPlay APIs Addendum and naming a Team ID. The entitlement **locks you
to a single category** (Audio, for us) and only that category's templates. Plan for a months-long
approval or plan to skip iOS-in-car.

### Everything else

- **MPRIS v2.2** — `org.mpris.MediaPlayer2` over D-Bus, state via `PropertiesChanged`. Covers every
  Linux desktop; `playerctl` and every applet speak it.
- **MPD protocol** — plaintext line protocol, dozens of mature clients.
- **Media Session API** — `navigator.mediaSession`, gets OS lock-screen and media-key controls for
  the web UI essentially free.

---

## Layer 4 — Semantics and portability

| Standard | Status | Notes |
|---|---|---|
| MusicBrainz MBIDs | Open | The universal identity layer. Everything below depends on it. |
| AcoustID / Chromaprint | Open | Fingerprint → MBID resolution. We already compute fingerprints; the lookup is one step away. |
| ListenBrainz | Open | `/1/submit-listens`; submit at half the track or 4 minutes, whichever is lower. Also a recommendation API exposing collaborative-filtered recording IDs. |
| XSPF / JSPF | Open | The only real playlist interchange formats. JSPF is the JSON serialization; MusicBrainz defines an extension profile adding collaborators, timestamps, per-track attribution, MBIDs. |
| Troi | Open source | MetaBrainz's recommendation engine — powers ListenBrainz weekly jams and LB Radio, emits JSPF. Pipeline architecture of composable elements (sources → filters/operations → rankers/sorts). Worth studying as an architecture. |
| Navidrome `.nsp` | De facto, single-vendor | Smart playlists as JSON rule objects: `all`/`any` trees with operators like `inTheLast`, plus `sort`, `order`, `limit`. Well designed, one implementation. |
| ReplayGain, `.lrc`, `.nfo` | Conventional | Sidecar conventions everything reads. Cheap to support; their absence causes "why does this sound wrong / show no lyrics". |

**Store MBIDs.** It is the cheapest single thing that makes the library interoperable with every
tool in this table, and it makes any future spec proposal far easier to argue.

---

## Genuine gaps — where new specification work is warranted

Ranked by how well-founded the gap is and how well-placed we are to fill it.

### 1. Sub-track addressing — *strongest case*

Nothing in any protocol here can refer to **part of a song**. Subsonic bookmarks store a playback
position, which is a cursor, not an identity. There is no way to name a segment, attach features
to it, express a preference for it, or return it as a search result.

Our schema already does all four. This is an unusual design decision sitting exactly on the largest
hole in the ecosystem. Well-scoped, obviously useful beyond us, and backed by a working
implementation — which is how OpenSubsonic extensions get accepted.

### 2. Similarity with a reason attached — *extension, not new spec*

`sonicMatch` is a track and a score. No way to express *why* two tracks match, query by vector
rather than by example, constrain a match to particular dimensions, or ask for similarity to a
*region* of a track. Our named perceptual feature groups are the missing vocabulary.

### 3. Portable smart-playlist rules

`.nsp` is the only serious rule format and it is single-vendor. Move servers and your smart
playlists don't come with you. Adopt its shape first, propose the delta second.

### 4. Taste-profile portability

ListenBrainz standardizes *listens* and serves recommendations, but there is no interchange format
for a learned user model. Real but early — hard to standardize before more than one system computes
something comparable. Design storage so it *could* be exported.

### 5. Cross-device queue handoff

`savePlayQueue` and `indexBasedQueue` cover a queue within one server's world. Spotify-Connect-style
handoff has no open equivalent. Interesting, but belongs at Layer 2/3 where we should be a consumer.
Phoenix PubSub makes our *internal* version of this cheap regardless.
