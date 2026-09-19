# Wire Protocol

**Specification 07**
**Status:** Draft
**Version:** 0.1
**Depends on:** spec-01 (Catalog Data Model), spec-02 (Annotations and Derived
Data), spec-03 (Assets, Storage and Preservation), spec-04 (Ingest and
Normalization), spec-06 (Principals, Auth and Authorization)
**Obsoletes:** nothing

## Abstract

This document specifies how clients reach the deployment: a native API over the
catalog, change notification, and an OpenSubsonic surface through which
existing music clients read the library, stream it, and record what their
principal played. The native API is the architecture; the OpenSubsonic surface
is a projection of it into a model with artists, albums and songs, which loses
what that model cannot hold and adds nothing the native API cannot reach.

---

## 1. Introduction

### 1.1 Scope

- The native API: resources, representations, paging, writes, bytes, errors
- Change notification over a WebSocket, and reconciliation after a gap
- Client keys: how a client that cannot perform forward authentication proves
  which principal it acts for
- The OpenSubsonic surface: which endpoints and extensions, and how the catalog
  maps onto them

### 1.2 What this document does not specify

The transcode decision and transcoded streams (spec-08); until spec-08, bytes
are served as stored. Search ranking and similarity (spec-09); searching here
matches names and orders them alphabetically. Image scaling and client
presentation (spec-10). Metadata matching (spec-05).

---

## 2. Conventions

BCP 14 key words per spec-01 §2.

---

## 3. Identity on the wire

### 3.1 The native API

The native API, and its WebSocket, admit a request only through forward
authentication (spec-06 §3.2), as every other route does. A client key
(§3.2) is not accepted there.

### 3.2 Client keys

A music client on a phone cannot follow a browser through the identity
provider's sign-in. It authenticates with a client key: a credential a principal
mints for one device while signed in through the proxy, and which the device
presents on every request.

A client key is the credential of a device in spec-06 §4's sense. Minting one
binds a device to the minting principal, with a label naming it; the key is
that device's, and nothing it does is attributed to anyone else.

- A key MUST carry at least 256 bits from a cryptographically secure source,
  and MUST be shown to the principal once, at minting, and never again.
- A key MUST be stored only as a digest. Its entropy makes a fast digest
  sufficient; a key is not a password and is not stretched.
- A principal MAY list and revoke its own devices' keys. An Administrator MAY
  revoke any principal's, which spec-06 §6.6 audits.
- A revoked key, or a key whose principal is retired, MUST be refused.
- A key is accepted only on the OpenSubsonic surface (§6). It is never
  accepted where forward authentication is expected.

The OpenSubsonic surface's path is exempt from forward authentication at the
proxy, since a key is its authentication; the proxy MUST still assert that the
request came through it (spec-06 §3.2), and a request without that assertion
MUST be refused before any key is read.

### 3.3 Attribution

Every request authenticated by a key acts as the key's principal. Every catalog
write it makes is attributed to that principal (spec-06 §6.2), and every
consumption event it records belongs to that principal (spec-01 §11). The
device is recorded with the event where the event carries one, and never
accumulates history of its own (spec-06 §4).

---

## 4. The native API

### 4.1 Resources

Every res kind has a collection and an entity URI. The entity URIs are spec-01
§9.1's, and a deep link's selector is honoured on them as §9 specifies.

| Resource | URI |
| --- | --- |
| a res of a kind | `/{kind}/{id}` — `/works/…`, `/expressions/…`, `/manifestations/…`, `/items/…`, `/digital-items/…`, `/assets/…`, `/persons/…`, `/collective-agents/…`, `/places/…`, `/time-spans/…`, `/nomens/…`, `/addresses/…`, `/annotations/…` |
| every res of a kind | `/{kind}` |
| an asset's bytes | `/assets/{id}/content` |
| the change feed | `/changes` |
| the principal's own devices | `/devices`, `/devices/{id}` |
| findings | `/findings`, `/findings/{id}` |

A representation carries the res's identifier and kind, its preferred name
resolved under the requesting principal's resolution profile (spec-01 §7.4),
every nomen it carries, the identifiers of the res it is related to by each
relationship, and its lifecycle state (spec-01 §14). A client MAY name another
profile with `profile`.

A representation MUST NOT embed another res's representation. It names related
res by identifier, and a client asks for what it needs: embedding would let one
resource's representation carry another's recycled or purged state stale.

### 4.2 Paging

A collection is paged by keyset on the primary identifier, which is time-ordered
(spec-01 §4.1). A request carries `limit` and, after the first page, `after`,
the last identifier of the page before. The response carries the identifier to
pass as `after` for the next page, or none on the last.

Offset paging MUST NOT be offered. Rows created or recycled between two requests
shift every later offset, and a client paging by offset skips or repeats what it
was shown; a keyset does neither.

### 4.3 Writes

The native API writes through the same operations the deployment's own code
uses, and adds none. Each is a request on the resource it changes:

| Operation | Request |
| --- | --- |
| add or correct a name (spec-01 §7) | `POST /nomens` |
| categorize (spec-01 §7.5) | `POST /{kind}/{id}/categories` |
| annotate (spec-02) | `POST /annotations` |
| decide a duplicate candidate (spec-03 §8.3) | `POST /duplicate-candidates/{id}/decision` |
| recycle, restore, empty (spec-01 §14) | `DELETE /{kind}/{id}`, `POST /recyclings/{id}/restoration`, `DELETE /recyclings/{id}` |
| clear a finding (spec-04 §9) | `POST /findings/{id}/clearing` |
| mint and revoke a client key (§3.2) | `POST /devices`, `DELETE /devices/{id}` |

A write a catalog constraint refuses is answered with problem details naming the
constraint. A write that raises is answered 500 and is not retried by the
server.

### 4.4 Bytes

`/assets/{id}/content` serves an asset's stored bytes. It MUST honour byte range
requests [RFC9110] §14, since a player seeks by range, and MUST answer with the
asset's identified format as its media type where the format registry maps one,
and `application/octet-stream` where it does not.

It serves the bytes as they are stored. It MUST NOT transform them: a transcode
is spec-08's, produced on demand and never stored as the asset (spec-01 §13.6).

### 4.5 Errors

Every error is problem details [RFC9457] with a type this system defines.

| Condition | Status | Type |
| --- | --- | --- |
| no res carries the identifier | 404 | `not-found` |
| a res of another kind carries it | 404 | `not-found` |
| the res is recycled | 410 | `recycled`, with when it can be restored until |
| the res is purged | 410 | `purged` |
| the request is malformed, or a selector invalid at the level (spec-01 §8.5) | 400 | `invalid-request` |
| a constraint refuses the write | 422 | `constraint`, naming it |
| a consumption datum of another principal | 404 | `not-found` |

The last row is deliberate. Answering 403 would confirm that another principal's
datum exists, which is itself consumption data (spec-06 §6.3).

---

## 5. Change notification

### 5.1 The feed

spec-01 §12.2 makes propagation a notification that something changed, never a
delta. The feed is the record of catalog writes spec-06 §6.2 already keeps: every
write is numbered in the order it was recorded, and names the res it touched.

`GET /changes?after={n}` returns, in order, each recorded write after `n`: its
number, the operation, and the identifiers of every res in the row it wrote. A
client reconciles by fetching those res again. Several writes to one res are
several entries, and a client MAY fetch it once.

A write MUST NOT appear in the feed before every write numbered below it has
either committed or failed. Numbers are assigned as rows are written and
transactions commit in their own order, so a feed that released a committed
write while a lower-numbered one was still in flight would let a client read
past a write it had not yet seen, and never see it.

### 5.2 The socket

A client MAY hold a WebSocket open at `/socket`. On it the server pushes, on the
topic `catalog`, the number of the newest write released to the feed, whenever
it advances. It pushes no rows: the client fetches `/changes` from the last
number it reconciled. Pushes MAY be coalesced; one push MAY stand for many
writes.

On the topic `principal:{id}`, joinable only by that principal, the server
pushes a notice that the principal's own consumption data changed — its events,
play queue, bookmarks, stars and ratings — so that another of the same person's
devices can refresh. No principal can join another's topic, and no notice of one
principal's consumption is ever pushed where another can receive it (spec-06
§6.3).

A socket carries nothing a client cannot recover without it. A client that was
disconnected reconciles from `/changes` and loses nothing.

---

## 6. The OpenSubsonic surface

### 6.1 Protocol

The surface is served at `/rest/{endpoint}`, and at `/rest/{endpoint}.view` for
clients that append it. It speaks the Subsonic API at version 1.16.1 with the
OpenSubsonic additions [OPENSUBSONIC]: every response carries `status`,
`version`, `type`, `serverVersion` and `openSubsonic: true`, in XML by default
and in JSON when `f=json` is asked for.

Authentication is by client key only (§3.2), as `apiKey`. A request carrying
`u` together with `apiKey` MUST be refused with error 43. A request
authenticating by password or by salted token MUST be refused with error 42:
the deployment holds no password to check a token against, and will not keep
one.

### 6.2 Extensions

`getOpenSubsonicExtensions` advertises exactly these:

| Extension | Version | Serves |
| --- | --- | --- |
| `apiKeyAuthentication` | 1 | §6.1, and `tokenInfo` |
| `formPost` | 1 | every endpoint by `application/x-www-form-urlencoded` POST |
| `songLyrics` | 1 | `getLyricsBySongId`, from lyrics companions (spec-04 §4.6) |
| `indexBasedQueue` | 1 | `getPlayQueueByIndex`, `savePlayQueueByIndex` |

An extension not listed MUST NOT be advertised. `transcoding` and
`transcodeOffset` wait for spec-08, `sonicSimilarity` for spec-09.

### 6.3 Endpoints

| Group | Endpoints |
| --- | --- |
| System | `ping`, `getLicense`, `getOpenSubsonicExtensions`, `tokenInfo` |
| Browsing | `getMusicFolders`, `getIndexes`, `getMusicDirectory`, `getGenres`, `getArtists`, `getArtist`, `getAlbum`, `getSong`, `getArtistInfo2`, `getAlbumInfo2`, `getCoverArt` |
| Lists | `getAlbumList`, `getAlbumList2`, `getRandomSongs`, `getSongsByGenre`, `getNowPlaying`, `getStarred`, `getStarred2` |
| Searching | `search2`, `search3` |
| Retrieval | `stream`, `download` |
| Annotation | `star`, `unstar`, `setRating`, `scrobble`, `getLyricsBySongId` |
| Playlists | `getPlaylists`, `getPlaylist`, `createPlaylist`, `updatePlaylist`, `deletePlaylist` |
| Play queue | `getPlayQueue`, `savePlayQueue`, `getPlayQueueByIndex`, `savePlayQueueByIndex` |
| Bookmarks | `getBookmarks`, `createBookmark`, `deleteBookmark` |
| Users | `getUser`, for the requesting principal only |

Any other endpoint MUST answer error 0 naming the endpoint as not provided, and
MUST NOT answer with an empty success. A client that asked for podcasts told
there are none is misled; one told the endpoint is not provided can say so.

### 6.4 The mapping

| Subsonic | Catalog |
| --- | --- |
| music folder | one, the household's |
| artist | the agent a track's or release's credit resolved to (spec-04 §6.4); for a credit that names no agent, the credit's name, one artist per name |
| album | a release manifestation (spec-04 §6.4) |
| song | a track manifestation |
| genre, year, duration, bit rate, suffix, content type | the current probe annotation of the manifestation's analysis source (spec-04 §5.1, §8.1) |
| cover art | the cover-art companion linked to the release (spec-04 §4.6), or the picture embedded in the track's master |
| lyrics | the lyrics companion linked to the track |
| star, rating, playlist, play queue, bookmark, now playing | the requesting principal's own consumption data |

Every name is the preferred nomen under the principal's resolution profile. Every
identifier is the res's primary identifier, as a string.

`getIndexes` and `getMusicDirectory` present the same catalog as directories:
artists at the top, an artist's albums within it, an album's songs within that.
The directories are a presentation of the catalog, and name nothing the
filesystem holds; storage has no directories that mean anything (spec-04 §4.5).

### 6.5 Consumption

Stars, ratings, playlists, the play queue, bookmarks, and what is playing now
are consumption data, and each principal's are its own (spec-06 §6.3):

- `getNowPlaying` returns only the requesting principal's own sessions.
- `getStarred`, `getStarred2` and the `starred`, `highest`, `frequent` and
  `recent` album lists read only the requesting principal's own data.
- `scrobble` with `submission=true` records a playback event of the requesting
  principal (spec-01 §11); with `submission=false` it records what that
  principal is playing now, which is not kept as an event.
- A play queue and a bookmark belong to their principal, and the bookmark is the
  principal's resume position (spec-01 §11).

No response on this surface reveals another principal's consumption, whether
directly, as a count, or as an ordering.

### 6.6 Playlists

A playlist is its principal's, like a star or a rating: an ordered list of songs
that says what one person chose to hear, and so consumption data rather than
catalog content (spec-06 §6.3). It lives with the principal's other consumption
data, not in the catalog, and references songs by identifier.

`getPlaylists` returns only the requesting principal's playlists, and every
playlist is reported with `public: false` and the requesting principal as its
`owner`. A request naming another principal's playlist, to read, change or
delete it, answers error 70, as if it did not exist. A request to create or
update one as public is refused with error 50: nothing on this surface can make
one principal's consumption visible to another.

A song a playlist names that is later recycled or purged stays in the playlist
and is left out of what `getPlaylist` returns, so restoring the song restores
it to the playlist.

### 6.7 Retrieval

`stream` serves the song's normalized master as stored, honouring byte ranges.
Until spec-08, `format`, `maxBitRate` and `estimateContentLength` do not change
what is served, and a request that names a format other than the master's is
still served the master; the response's content type says what was served.

A song whose track manifestation has no digital item of its own — a track of a
release held in one file (spec-04 §6.4) — is served by cutting its extent from
the release's master, which is a transcode, and waits for spec-08. Until then
`stream` answers error 0 for it, and says why.

`download` serves the song's acquired original, the bytes as they arrived.

`getCoverArt` serves the cover image as stored; `size` waits for spec-10.

### 6.8 Errors

| Condition | Subsonic error |
| --- | --- |
| a required parameter missing | 10 |
| a client asking for a newer protocol version than 1.16.1 | 30 |
| an unknown, revoked or retired key | 44 |
| a password or token given | 42 |
| `u` given with `apiKey` | 43 |
| the requesting principal may not | 50 |
| no res carries the identifier, or it is recycled or purged, or it is another principal's consumption datum | 70 |
| anything else | 0, with a message |

A recycled entity answers 70 like an absent one: the Subsonic model has no way to
say "gone but restorable", and a client offered nothing better treats both as
missing. The native API (§4.5) is where the difference is told.

---

## 7. Conformance

1. The native API and its socket refuse a request that did not come through
   forward authentication, and refuse a client key.
2. A client key is shown once, stored only as a digest, bound to one device of
   one principal, and refused once revoked or once its principal is retired.
3. The OpenSubsonic surface refuses a request that did not come through the
   proxy before reading its key.
4. A password or token is refused with error 42; `u` with `apiKey` with error
   43; an unknown or revoked key, or one whose principal is retired, with error
   44.
5. Every catalog write and every consumption event made through a key is
   attributed to the key's principal.
6. A representation names related res by identifier and embeds none.
7. Paging by keyset neither skips nor repeats a row created or recycled between
   two pages.
8. Asset content honours byte ranges and is served as stored.
9. A recycled res answers 410 with the recycled type and when it can be
   restored until; a purged one 410 with the purged type; an absent one 404.
10. Another principal's consumption datum answers 404 on the native API and 70
    on the OpenSubsonic surface.
11. The change feed returns every catalog write after a number, in order, and
    never releases a write before every lower-numbered one has committed or
    failed.
12. The socket pushes feed numbers and no rows; a client that reconciles from
    the feed after a disconnection has lost nothing.
13. No principal can join another's topic or receive a notice of another's
    consumption.
14. Every OpenSubsonic response carries `openSubsonic: true`, its `type` and
    `serverVersion`, in XML by default and JSON on `f=json`.
15. `getOpenSubsonicExtensions` advertises exactly the extensions of §6.2.
16. An endpoint not provided answers error 0 naming it, never an empty success.
17. An album is a release, a song a track, and an artist the agent a credit
    resolved to, or for a credit naming no agent, one artist per credited name;
    every name is the preferred nomen under the principal's profile.
18. Stars, ratings, playlists, the play queue, bookmarks and now-playing are per
    principal, and no list or count on the surface reflects another principal's.
19. Another principal's playlist answers error 70 whether read, changed or
    deleted, and a playlist cannot be made public.
20. `stream` serves the normalized master and `download` the acquired original,
    as stored and with byte ranges; a track with no digital item of its own
    answers error 0 until spec-08.
21. A recycled or purged entity answers error 70.

---

## 8. Security considerations

The OpenSubsonic surface is exempt from forward authentication, and so is the one
path where a credential the deployment issued is the whole of a request's
authentication. The proxy's assertion (spec-06 §3.2) still stands in front of
it, which confines the surface to clients that can reach the proxy; a key alone
reaches nothing.

A key travels in the query string, where the Subsonic protocol puts it. Query
strings reach access logs. A deployment SHOULD keep `apiKey` out of the logs of
the proxy and of the application, and a key found in a log is revoked, not
trusted.

A key grants everything its principal may do on the surface. It does not grant
administration, identity mapping, or anything on the native API, which a
stolen phone's key therefore cannot reach.

The change feed names identifiers the household can already read. It carries no
consumption data, which travels only on a principal's own topic.

---

## 9. References

### 9.1 Normative

- **[spec-01]** through **[spec-06]**, this system.
- **[OPENSUBSONIC]** OpenSubsonic API, <https://opensubsonic.netlify.app/>: the
  `subsonic-response` fields, the endpoints of §6.3, and the extensions
  `apiKeyAuthentication`, `formPost`, `songLyrics` and `indexBasedQueue`.
- **[RFC9110]** HTTP Semantics, §14 (range requests).
- **[RFC9457]** Problem Details for HTTP APIs.
- **[RFC2119]**, **[RFC8174]** as in spec-01 §18.1.

### 9.2 Informative

- **[notes-02]** [Protocol landscape](notes/02-protocol-landscape.md): the
  survey this surface was chosen from, and the clients it serves.
