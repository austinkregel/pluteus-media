> **Non-normative.** Where this conflicts with
> [spec-01](../spec-01-catalog-data-model.md), the specification governs.
>
> **Superseded here:** the single-user premise. The content-based-only conclusion survives, but for a different reason: one household is still not a population. The `UserTasteProfile` critique describes a schema that will not be built.

# 07 — Analysis, Taste, and Playlists

The differentiating half of the system. Everything in
[02-protocol-landscape.md](02-protocol-landscape.md) is table stakes; this is why we build rather
than adopt.

---

## The feature vector

107 dimensions, fixed canonical order, assembled from:

| Group | Dims | Source |
|---|---|---|
| MFCC means / stds | 13 + 13 | `librosa.feature.mfcc` |
| Spectral contrast | 7 | `librosa.feature.spectral_contrast` |
| Chroma means / stds | 12 + 12 | `librosa.feature.chroma_cqt` |
| Frequency bands | 7 | derived from cached STFT |
| Dynamic arc coefficients | 4 | derived from RMS envelope |
| Scalars | remainder | tempo, tonality, loudness, spectral centroid/bandwidth/rolloff/flatness, onset, energy, crest, stereo, reverb, swing, syncopation, groove, chord change, entropy, consonance, sonic density, timbral variety, flux, intro/outro/section count |

**Semantic groups** (13, used for the radar chart and per-group weights): tempo, tonality, loudness,
timbre, spectral, onset, chroma, energy, production, rhythm, harmony, density, structure.

### Invariants to preserve

1. **Single-read.** One audio file read, all expensive transforms computed once into a
   `TransformCache`, every scalar and segment vector derived from those cached arrays. Never
   re-load audio or recompute an STFT/onset envelope already in the cache.
2. **Named, not positional, across the language boundary.** See
   [05-python-sidecar-contract.md](05-python-sidecar-contract.md).
3. **Raw vectors stay stored.** Unnormalized values persist alongside the normalized pgvector
   column, so re-normalization never requires re-reading audio.
4. **NaN/inf scrubbing before persistence.** pgvector rejects non-finite values.
5. **`extractor_version` on every row.** Numerical identity of the code that produced it.

### Normalization and weighting

Each dimension is min-max normalized to [0,1] then multiplied by a perceptual weight, so distance is
dominated by perceptually salient features (timbre/MFCC weighted high, structural metadata low).
This lives in **Elixir** post-migration — one module, the single owner of ordering and weights.

---

## Segments — the differentiator

Per-segment features, embeddings, and **likes recorded against segments rather than songs**.

Nothing in any protocol surveyed can address part of a track. This is simultaneously:

- the reason to build rather than run Navidrome + AudioMuse
- the strongest candidate for an upstream OpenSubsonic extension
- the input that makes several algorithms below strictly better than the published versions

Design note: keep segments addressable and stable across re-analysis where possible, because likes
reference them. If segmentation changes with `extractor_version`, likes need a migration story —
flag for the data spec.

---

## Taste modelling

### Current design, and its flaw

Inverse-variance weighting over liked segment vectors: features the user is *consistent* about (low
variance) get high weight; the centroid of liked vectors is the "ideal point". Requires 5 likes.
Weights normalized to sum to the dimension count.

**The flaw:** `UserTasteProfile.user_id` is `unique: true` — exactly one centroid. That models taste
as unimodal. If you like ambient techno and bluegrass, the centroid describes neither, and variance
is high on precisely the dimensions that distinguish them, so inverse-variance weighting actively
*suppresses* the features that define your real taste clusters.

### The change

Cluster liked segment vectors into **k components**; fit a centroid and inverse-variance weight
vector per component. `Scholar.Cluster.KMeans` or `GaussianMixture` does this directly on the GPU.

Consequences:

- Each component is a coherent region of taste — the basis for themed playlists below.
- The radar chart describes each component individually, which is a better UI story than one global
  profile.
- Schema change: drop the unique constraint, add a component index and a component weight.

---

## Themed playlists

### What actually makes them work

Spotify's stated attributes for a Daily Mix are **familiarity and coherency**. Both are computable
from a single library. The "pick one and drive 30 minutes without thinking" property is a *variance
constraint*, not recommendation accuracy.

YouTube Music feels disjointed because it optimizes per-track relevance with no set-level coherence
term. Each song is defensible; the sequence isn't.

**The current recommendation code has exactly this failure mode:** it pulls `limit × 7` candidates
by distance to the centroid, scores each independently by weighted distance, sorts, returns.
Nothing considers the set. Fixing that is the single largest quality gain available.

### Collaborative filtering is unavailable

Daily Mix runs on collaborative filtering over hundreds of millions of users. We have one. That
mechanism is permanently closed — say so up front so nobody chases it. For reference, the RecSys
2018 Challenge on the Spotify Million Playlist Dataset topped out at R-precision 0.2241, and those
approaches all depend on a user population.

Everything below is content-based and single-user by construction.

### Generation pipeline

```
1. SCOPE       pick a taste component (or an explicit seed//theme)
2. WEIGHT      apply a per-theme dimension weight override
3. RETRIEVE    pgvector nearest neighbours to the component centroid
4. CONSTRAIN   admit candidates only while set variance stays under threshold
5. BALANCE     enforce familiarity ratio (mostly known, some new)
6. FIT         select to a target duration
7. SEQUENCE    order the chosen set
8. NAME        label the result
```

#### 2 — A theme *is* a weight vector

The ISMIR/Spotify sequencing paper is explicit: the feature space is a concatenation of sub-vectors
where "each feature is optionally weighted according to the application (e.g. in dance playlist,
tempo coherence is important, thus tempo would have a large weight)."

Our per-dimension weights are currently a single global perceptual weighting. **Per-theme weight
overrides turn one distance metric into an unlimited family of them** — a driving mix weights
tempo/energy/groove and loosens timbre; a focus mix inverts that. No new features, models, or
storage required.

#### 4 — Coherence as an explicit constraint

This is the secret. Rather than top-N by distance, admit a candidate only if it does not push
within-set variance past a threshold — a maximal-marginal-relevance style trade of relevance
against set homogeneity. The threshold is the "tight mix vs. broad mix" knob and should be exposed.

AudioMuse solves the same problem at the clustering layer: its evolutionary search scores candidates
on seven metrics, including four label-aware ones that explicitly trade **diversity across
playlists against purity within playlists** (the structural three are silhouette, Davies-Bouldin,
and Calinski-Harabasz). Its final selection takes the three most-represented genres, contributes
each one's two farthest-apart centroids, then adds four more playlists maximizing minimum centroid
distance from those already chosen — a principled construction of "Daily Mix 1–6."

#### 5 — Familiarity requires play history

**We have no play or skip history.** Only likes. Half of what makes a Daily Mix work is not
computable today.

Fix: implement the OpenSubsonic `playbackReport` extension and `scrobble`, and add a listen-events
table. This also unlocks ListenBrainz submission (`/1/submit-listens`; submit at half the track or
4 minutes, whichever is lower) and Navidrome-style `.nsp` rules like `inTheLast`.

#### 6 — Duration targeting is an unserved primitive

Nobody offers "give me exactly 34 minutes that holds one mood" — not Spotify, not Plexamp, not
AudioMuse. We have durations and a coherence metric; it is a knapsack problem solvable exactly at
playlist scale. **Cheaper to build than transitions and more differentiated.** Build it early.

#### 7 — Sequencing

Model as shortest Hamiltonian path over a complete graph, edges weighted by Euclidean distance in
the weighted feature space (Bittner et al., ISMIR 2017, Spotify):

| Method | Behaviour |
|---|---|
| **HAM-1** | Greedy nearest unvisited from a seed. Seed stays first; poor pairings accumulate at the tail. |
| **HAM-2** | Greedy from either head or tail. Reliably lower total cost, but the seed no longer ends up first; artifacts at both ends. |
| **TSP cycle** | Shortest Hamiltonian cycle, polynomial 2-approximation. Higher cost, but no head/tail artifacts and it loops cleanly. |

Cost is dominated by building the weight matrix — quadratic in playlist length, irrelevant at 30
tracks.

**Honest effect size.** Professional curators compared sequenced vs. random on six 30-track
playlists. Abrupt pairs fell from 4.2 to 2.4 out of 29. Curators unanimously preferred the
sequenced version on three of six, split evenly on two, mixed on one. The gain concentrated in the
genre-diverse playlist (jazz/classical/house: 9.3 → 2.7); two indie playlists showed no preference.

**Conclusion:** worth building, matters most on broad mixes, does roughly nothing on tight ones.

Their feature space is also worth copying: acoustic embedding (R²⁰⁴⁸ → R⁸), key/mode mapped into R³
so circle-of-fifths neighbours and relative major/minor are equidistant, and tempo on a base-2
logarithmic scale (optionally octave-invariant, as a unit vector whose polar angle maps the tempo
octave).

#### Arc shaping

A complementary finding (PLOS One, feature arcs across track sequences): valence, arousal, and
loudness form a **U** across a sequence — high at both ends, depressed in the middle — while tempo
runs an **inverted U**, fastest in the middle. The authors liken it to the "man in a hole" narrative
arc.

We already extract four dynamic-arc coefficients per song, so shaping an arc across a playlist is
available rather than merely minimizing pairwise distance.

#### 8 — Naming

AudioMuse builds a grounded context per cluster (primary genre, mean mood and feature scores,
instrumentality, decisive lyric-axis labels), asks an LLM for a short concept name, sanitizes it for
length and consistency with recent naming history, and falls back to a deterministic tag-based name
like `Happy_Party_Fast`. `document-sorter` already has an `ml/llm_client.ex` to reuse.

---

## Segment-aware transitions

The same ISMIR paper restricts transition points to downbeats, **"heavily weighted to occur on
section boundaries, such as at the intersection of a verse and a chorus,"** and assumes "regions of
tracks that have similar timbre and pitch distributions will yield the smoothest transition." Only
quadruple meter is considered.

That is a description of our segment tables. Section boundaries with per-segment timbre and chroma
vectors are exactly the required input, and no open music server has them. Sequencing distance can
be **end-of-A to start-of-B** rather than centroid-to-centroid — strictly better than the published
method.

**Honest caveats:** 95% of Spotify users turn crossfade off, and the A/B test for DJ-style
transitions moved daily return rate by 1.4 percentage points. Small in general, plausibly larger for
the driving case specifically. Build it last.

---

## Exposing all this

No new specification work is needed to ship themed playlists:

- Generate → persist → `createPlaylist`. They appear as ordinary playlists in every Subsonic client,
  Music Assistant, and Android Auto. This is exactly what AudioMuse does.
- **`getSimilarSongs` / `getSimilarSongs2` first.** Music Assistant's "Don't Stop the Music" depends
  on it, and both Gonic and Navidrome require a **Last.fm API key** to answer it — meaning that
  feature is powered by scrobble co-occurrence, not audio. Answering it from acoustic content with
  no external dependency is a concrete, demonstrable win over every server on the list, available
  early.
- **`sonicSimilarity` second.** `getSonicSimilarTracks` maps directly onto existing similarity code.
  `findSonicPath` — a route between two songs through intermediate matches — is well served by
  segment vectors and is where we can be visibly better than track-level competitors.

**Blocking prerequisite:** there is no `Playlist` entity. OpenSubsonic requires
`createPlaylist` / `updatePlaylist` / `deletePlaylist` CRUD, and persistent playlists are needed for
generated mixes regardless. This is also one of the three original grievances, so it earns its place
independently.

**Also required:** `UserSegmentLike` has no protocol representation. Until sub-track addressing is
specified, expose a derived song-level projection for `star`, `unstar`, and `setRating`, keeping
segment data as the source of truth underneath.
