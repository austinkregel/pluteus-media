# Annex A — Design Language

**Companion to Specification 10**
**Status:** Draft
**Version:** 0.2
**Normative status:** Normative for the interface (spec-10 §4.2), at both of the
distances A.1.6 resolves it for.

## Scope

spec-10 specifies what must be presentable. This annex specifies what it looks
like: how tokens are defined and named, the colour, type, space, motion and
focus systems, the component bar, and the values of each.

One constraint shapes everything. The design must reach two surfaces drawn by
different technologies — a browser, and a television client with no cascade, no
stylesheet, no selectors and no inherited properties, where every colour and
size is a field on an individual node. A design expressed as CSS cannot reach
the second, so the token definition is format-neutral and both stylesheets are
artefacts of it.

Every value below is a starting value, maintained as spec-10 §20's registry.
A value is present so that a screen can be drawn; disagreeing with one is a
registry change, not a change to this annex.

---

## A.1 The token file

### A.1.1 Format

Tokens are defined in the Design Tokens Format Module 2025.10 [DTCG]. The file
MUST validate against the published schema for that version with no errors, and
that validation MUST run in continuous integration. The version is pinned
exactly: the format's only stated evolution mechanism is a superseding
specification.

Contexts are expressed with the Resolver Module 2025.10 [DTCG-RES] as modifiers
over a resolution order, not as separate files of separate names.

### A.1.2 What the format cannot hold

The `dimension` type admits only `px` and `rem`. It cannot express `clamp()`,
`%`, `em`, `ch`, `vw` or container units.

**The token file is the source of truth for values; the build is the source of
truth for expressions.** A fluid size is two endpoint tokens and a generated
`clamp()`. Nothing is smuggled into an extension to evade this.

### A.1.3 Units

Every dimension primitive that participates in the scale is expressed in `rem`.
The root font size is the anchor that scale resolves against and is in `px`.

Three further primitives are in `px`, and the set is closed: the hairline and the
component border width of A.4.3, which are a fixed thinness rather than a
proportion of the type size, and the pill radius, which A.1.2's admissible units
cannot express as a proportion. **A `px` dimension outside those four is an
error**, and the lint A.1.5 requires enforces the list rather than the unit.

The first reason is the reader: a `rem` honours the browser font-size
preference a person has set, and a `px` overrides it. The second is A.3.3: the
viewing-distance strategy is a change of root size, which composes with every
`rem` and with no `px`.

This is the most expensive decision here to reverse. A `px` primitive would
need a parallel token set per distance context — the combinatorial explosion
the resolver exists to prevent — and would break the reader's preference
silently.

### A.1.4 Tiers

| Tier | Prefix | Holds | May reference |
| --- | --- | --- | --- |
| Primitive | `base` | raw values carrying no meaning | nothing |
| Semantic | `sys` | roles; the only tier templates and components use | `base` |
| Component | `comp` | a component's genuine deviation | `sys` |

Only `sys` tokens may be referenced from templates, component code or component
styles, enforced by the lint rule A.1.5 requires. A component reaching into
`base` means the semantic layer is inadequate; the answer is to add a role.

### A.1.5 Naming

```
token-path = tier "." category "." concept *( "." modifier )
```

Four rules bind:

1. **A name MUST NOT contain a theme, density, distance, contrast level, motion
   preference, surface or category.** Those are *when* a value applies. They are
   resolver contexts and scopes.
2. A `sys` name MUST NOT exceed four segments. A fifth means it is a `comp`
   token.
3. Every segment is lower-kebab and contains no `.`, `{` or `}`.
4. `on` denotes polarity and is the segment immediately after the category:
   `sys.color.on.surface.strong`.

Rule 1 is what makes a new surface or category cost nothing: adding a context
adds one override file and renames nothing. A rename is a breaking change
across templates, code, generated CSS and documentation, and A.9.5 means a
token name must be a complete literal string for the CSS build to see it, so a
vocabulary that encodes context in names cannot be recovered later.

[DTCG] states that naming conventions are out of scope and that tools MUST NOT
infer meaning from grouping. The grammar is therefore enforced by a lint rule
of the deployment's own; no format tool enforces it.

### A.1.6 Contexts

| Modifier | Contexts | Changes |
| --- | --- | --- |
| `theme` | `dark` (default), `light` | colour only |
| `contrast` | `normal`, `more` | colour only |
| `distance` | `near` (default), `far` | root size, target minimums, focus-ring width, safe inset, optical size, focus-move duration, class-colour lightness |
| `density` | `comfortable` (default), `compact` | spacing and control height only |
| `motion` | `full`, `reduced` | durations |

**`distance` and `density` are different axes and MUST NOT be merged.** Density
is how tightly a layout packs at a given apparent size; distance is how large
everything must be to be legible at all. A compact television layout and a
comfortable desktop one are both coherent, and one axis cannot express them.

Density MUST NOT change text size, MUST NOT reduce a target below A.4.2's
floor, and MUST NOT change colour, border width, radius or elevation. It MUST
NOT apply to a surface reached by a remote, to a control that changes the mode
itself, or to a menu, dialog or validation message.

`distance: far` is the same interface rendered across a room (A.10.3), not a
separate artefact. The deployment ships no client of its own, so there is nowhere
else for it to go.

Neither may be inferred (spec-10 §4.4).

---

## A.2 Colour

### A.2.1 Authoring

Every colour is authored in OKLCH with an sRGB fallback written explicitly
rather than computed by the build. Two conformant tools may gamut-map
differently, so an unwritten fallback is not reproducible.

OKLCH earns its place by making lightness a contract: holding lightness
constant across hues holds measured contrast roughly constant, so one number
governs the contrast of every class colour and becomes a testable invariant.

Gamut mapping MUST reduce chroma at constant lightness and hue. Letting a
browser clip in RGB moves lightness and breaks the invariant. The maximum
in-gamut chroma varies substantially by hue — at the class lightness of A.2.6 it
is roughly twice as high at hue 320 as at hue 200, measured in this session —
so clipping is not hypothetical.

Wide-gamut values are gated on both a syntax check and a gamut media query. The
interface's own colours stay within sRGB: the content is photographs and film,
and chrome that out-saturates the artwork fights it.

### A.2.2 The neutral ramp

Twelve steps, each with a stated job. A role without a written purpose is not
added.

| Step | Role | OKLCH (dark) | sRGB |
| --- | --- | --- | --- |
| 01 | page background | `oklch(0.178 0.004 264)` | `#101113` |
| 02 | subtle background | `oklch(0.213 0.006 264)` | `#18191c` |
| 03 | component background | `oklch(0.252 0.008 264)` | `#202226` |
| 04 | component background, hovered | `oklch(0.279 0.009 264)` | `#26292d` |
| 05 | component background, active | `oklch(0.305 0.010 264)` | `#2c2f34` |
| 06 | subtle border and separator | `oklch(0.345 0.011 264)` | `#36393f` |
| 07 | component border | `oklch(0.400 0.012 264)` | `#44484e` |
| 08 | component border, hovered | `oklch(0.487 0.013 264)` | `#5c6067` |
| 09 | solid background | `oklch(0.545 0.014 264)` | `#6c7079` |
| 10 | solid background, hovered | `oklch(0.600 0.014 264)` | `#7c8089` |
| 11 | low-contrast text | `oklch(0.770 0.013 264)` | `#b0b4bd` |
| 12 | high-contrast text | `oklch(0.949 0.006 264)` | `#eceef2` |

The ramp is generated at even intervals of OKLCH lightness at one hue, with
chroma rising and then falling. Steps 01 to 05 are also the elevation scale
(A.6); steps 06 to 08 are the border scale. Two of the ramp's three jobs come
free.

**The focus ring is not a ramp step.** A.5 explains why.

Measured against step 02: step 11 is 8.46:1 and step 12 is 15.13:1 under the
WCAG 2 formula. Measured under the APCA implementation A.2.4 pins, step 11 is
Lc 60.5 and step 12 is Lc 95.5.

### A.2.3 The dark theme is the default

**Step 01 MUST NOT be pure black and step 12 MUST NOT be pure white.** Both are
concrete failures rather than taste. A black page leaves no room to express
elevation downward, and on an emissive panel it produces visible edge artefacts
against anything lit. Maximal light-on-dark contrast causes glyph bloom, worst
for the very common case of uncorrected astigmatism — so the pairing that
scores best under the WCAG 2 formula is not the most readable one.

The light theme is a separately tuned ramp, not an inversion of this one.

The scaffolded stylesheet the project currently ships makes light the default
theme; A.10 requires that be inverted.

### A.2.4 Two contrast instruments, and the one statement of them

Text MUST meet [WCAG22] §1.4.3, and interface components and meaningful
graphics MUST meet §1.4.11, under the WCAG 2 relative-luminance formula. That
is the conformance floor and the only instrument written against a standard.

In the dark theme the following additional floors apply, measured with the APCA
algorithm at the version A.2.5 pins, and checked in continuous integration:

| Use | Floor |
| --- | --- |
| body text | Lc 75 |
| large text, secondary text | Lc 60 |
| non-text needed to understand or operate | Lc 45 |
| disabled and placeholder text | Lc 30 |

The second instrument exists because the first is known to overstate contrast
between dark colours, and this interface is dark-first: a pairing can compute as
conformant and be hard to read.

**These four numbers are the deployment's own, informed by APCA, and are not a
conformance claim against it.** The algorithm is pinnable by version; its
published thresholds are not — they appear only in an undated document, and the
standards work intended to carry them does not yet contain numbers. The
algorithm is a measuring instrument here, not an authority.

### A.2.5 Pinned instruments

| Instrument | Pinned at |
| --- | --- |
| APCA algorithm | `0.0.98G-4g`, as implemented in the published `apca-w3` package at version `0.1.9` |
| Page-zoom ceiling for A.3.2 | 500%, as implemented in Chromium and Firefox at the versions the deployment tests against |

A.3.2's ratio is derived from the second, so it is pinned rather than assumed.

### A.2.6 Class colour, and what colour is for

**A glyph identifies a category. Colour groups it.** The two carriers answer two
different questions and neither is decoration.

Colour is preattentive and good at coarse grouping, and poor at carrying many
identities. A palette that gives every category its own hue must either place
them close enough to collide or spread them evenly around the wheel — and evenly
spaced hues at one lightness and equal chroma are the primary four-colour palette
every generic interface arrives at, which says nothing about a household's
collection and out-saturates its artwork besides. A glyph is the reverse: it
identifies precisely, survives monochrome and forced colours, and reads at three
metres, where a hue distinction does not.

So colour follows what the bytes already decide. spec-04 §5.3 records a broad
class per holding, and spec-04 §6.3's finer category — which bytes cannot decide
— is the glyph's (A.8.6).

| Class | OKLCH | sRGB | Hue family | Covers |
| --- | --- | --- | --- | --- |
| video | `oklch(0.72 0.146 275)` | `#8b9bff` | indigo | film, television episode, home video |
| audio | `oklch(0.72 0.150 75)` | `#da950b` | amber | music recording, audiobook, podcast episode |
| software | `oklch(0.72 0.170 138)` | `#6abd4b` | green | video game |
| image | `oklch(0.72 0.126 185)` | `#08beaf` | teal | photograph, scan |
| text, package | `oklch(0.72 0.160 12)` | `#f7758a` | rose | document, ebook, comic issue |

The hue families are borrowed from a widely used general-purpose palette; the
lightness is this system's own, so the invariant holds. All five span **6.58:1 to
7.53:1** against step 02, a spread of 0.95, which is one assertion in continuous
integration. Every pair is at least 134 rgb units apart.

**Six classes, five colours.** sRGB at this lightness has room for a fifth hue
and not a sixth. Measured across the whole wheel, the best available sixth falls
**95 rgb units** from its nearest neighbour while staying inside the band above — against a tightest existing pair of 134. Abandoning the
band buys 130 units at hue 328, at a chroma of 0.296 that out-saturates the
artwork A.2.1 keeps the interface clear of. The choice is therefore which two
classes share a hue, not whether any do.

**`package` takes text's rose**, because a comic issue is read a page at a time
on the reader spec-10 §12.1 adapts from the one a document and an ebook get: the
group is the one a person is already in, and A.8.6's glyph carries the difference.
`software` takes a hue of its own because nothing else in the catalog is run
rather than read, heard or watched, so it groups with nothing.

| Role | Value |
| --- | --- |
| `sys.color.class.<broad class>` | per class, above |
| `sys.color.on.class` | `#16181c` |

There is a token per class, and `sys.color.class.package` and
`sys.color.class.text` resolve to one `base` primitive. Both names exist, so a
release that finds a sixth hue worth spending gives package a value and touches
no template — which is the semantic tier doing the job A.1.4 describes.

`on.class` is a token rather than a constant because a solid's readable
foreground varies by hue. At one lightness it does not have to: one dark ink
reaches 6.66:1 on the least contrasting of the five. A class added at another
lightness is what the token absorbs.

A companion (spec-04 §4.6) carries no class colour, because a companion is never
presented as a holding (spec-10 §12.2).

Status roles, each with a solid and an `on` pair, and each requiring a non-colour
carrier as well (spec-10 §17.9):

`sys.color.status.error`, `.warning`, `.success`, `.info`. These and the class
colours are the only places saturation is spent.

### A.2.7 Forced colours

Under forced colours the semantic tier is rebound once to system colour
keywords, and every component follows with no per-component work. This is the
clearest practical argument for the tier: a codebase of literal colours cannot
do it at all.

System colours are used in their defined pairs. Three rules follow, each
addressing a silent failure:

- A focus indicator MUST be drawn with an outline, never a shadow alone.
  Shadows compute to `none`, so a shadow-only ring vanishes for exactly the
  people most likely to be in this mode.
- No affordance may depend on a gradient. Gradients compute to `none`.
- Every state carried by colour needs a second carrier that survives.

Semantic colour is assigned from element semantics, not from a declared role,
so a control built from a generic element with a role attribute receives no
mapping. Native elements are used for native controls, and a component that
does not **MUST fail the review of A.9.1**.

---

## A.3 Type

### A.3.1 The scale

One modular scale at a ratio of approximately 1.2 in the interface range,
authored to whole pixels at the base size and widening for display sizes. No
production system uses one constant ratio across the whole range.

| Token | px at `near` |
| --- | --- |
| `sys.type.caption` | 12 |
| `sys.type.body.sm` | 14 |
| `sys.type.body.md` | 16 |
| `sys.type.body.lg` | 18 |
| `sys.type.title.sm` | 20 |
| `sys.type.title.md` | 24 |
| `sys.type.title.lg` | 28 |
| `sys.type.display.sm` | 32 |
| `sys.type.display.md` | 40 |
| `sys.type.display.lg` | 48 |

The ratio is held constant across contexts. **Changing the ratio changes
hierarchy; changing the base changes apparent distance.** Only the base moves.

### A.3.2 The 2.5 rule

Where a size is fluid, **the maximum MUST NOT exceed 2.5 times the minimum**,
and that ratio MUST be checked in continuous integration over the token file.

This is arithmetic. [WCAG22] §1.4.4 requires text to remain usable at 200%
resize. A viewport-proportional term does not scale with page zoom — the layout
viewport shrinks as the zoom rises, so the term works against the reader. With
the zoom ceiling A.2.5 pins, reaching a doubling from a size already at its
fluid maximum requires the ramp's span to be no more than 2.5. A wider ramp
fails §1.4.4 before anyone inspects it.

Container-proportional units do not rescue this; they shrink under zoom the
same way.

### A.3.3 Distance is a root-size switch

A television is not the far end of a fluid ramp. A viewport cannot report
viewing distance, and a television at a given width is indistinguishable from a
desktop monitor at that width, so a fluid scale maps the television onto the
desktop end of its own ramp — the one place it must not.

`distance: far` therefore changes **the root font size** and nothing else about
the scale. Every `rem` token, every measure in `ch` and every computed space
moves together, and the scale's ratios are preserved exactly.

| Context | Root |
| --- | --- |
| `near` | 16 px |
| `far` | 32 px |

The factor is 2. Android TV and Fire TV both render a 1920-wide surface in a
2.0 density bucket, giving a 960-unit design canvas; Xbox's UWP guidance scales
XAML applications 200% and HTML applications 150% onto a 1280-unit canvas; and
BBC's published typography system selects between two scales on a touch class
rather than interpolating. Four independently shipped answers, all switches
rather than dials.

16 px on an ordinary panel at three metres subtends roughly 5 to 6 arcminutes
of x-height, computed in this session from measured font metrics. [LEGGE] puts
the critical print size — the size below which reading slows from its maximum —
typically between 0.15 and 0.3 degrees, which is 9 to 18 arcminutes. So 16 px
at that distance is at or below half the size at which fluent reading is
possible, and the doubled figure clears it.

The familiar "three times" rule does not hold as a constant: the equal-angle
multiplier computes to roughly 1.5 to 2.8 across ordinary panel sizes at three
metres, because a larger panel's coarser pixel pitch partly cancels the
distance. Three over-delivers on a small panel and oversizes a large one. The
value here comes from the angular requirement and from what the platforms ship.

### A.3.4 Measure

Long-form text is constrained by a measure in `ch`, adjustable by the reader.

| Token | Value |
| --- | --- |
| `sys.size.measure` | `55ch` |

`ch` is the advance of the zero glyph, which in a proportional face is wider
than the average lowercase letter, so a measure in `ch` yields more characters
than its number suggests: 55ch renders approximately 65 characters in the
shipped face. The character count is what matters and MUST be verified by
counting when the face changes.

[WCAG22] §1.4.8 requires that a mechanism be available for a width of no more
than 80 characters, for unjustified text and for generous line spacing. It is
Level AAA and it requires that the reader be *able* to obtain these, not that
content use them. The interface provides the mechanism.

Expressing measure in `ch` makes it survive A.3.3 automatically: at `far` the
column widens with the type instead of wrapping every few words.

### A.3.5 The face

The interface self-hosts its faces; there is no external font host.

A variable face costs about two static weights, and any real interface uses
more than two, so variability pays for itself. Subsetting matters more: the
difference between a Latin subset and an unsubset variable face measured
roughly sevenfold in this session, several times the saving from variability.

Because a media catalog's names are the worst case for subsetting — one title
in another script pulls a whole subset — the face is chosen for the coverage
the household holds, and the fallback chain is metric-adjusted so a late swap
does not move the layout.

Weight is set with the weight property, never with raw variation settings.
Variation settings have no per-axis cascade, so a utility setting one axis
silently resets the others.

**Optical size is set by apparent size, not rendered size.** At `far`, text at
twice the size is not display type seen closely; it is text seen from five
times the distance. Automatic optical sizing chooses a high-contrast,
fine-stroked cut for the case that needs a sturdy one, so at `far` the automatic
behaviour is disabled, the optical size pinned to the apparent size, and the
weight raised one step.

A face without an optical-size axis cannot honour that rule. Where the chosen
face has none, the limitation is recorded rather than ignored.

### A.3.6 Reading preferences

A reader MUST be able to set, per principal and persisted, the face, size, line
height, measure, letter and word spacing, alignment, hyphenation and theme of
long-form text.

| Token | Value |
| --- | --- |
| `sys.type.body.md` line height | 1.55 |
| `sys.type.display.*` line height | 1.15 |
| alignment default | start |
| hyphenation default | off |

Justification and hyphenation default off. Justification without hyphenation
produces rivers; hyphenation fragments words across lines, which harms
magnified reading.

A face marketed for dyslexia MAY be offered as one choice among several. It
MUST NOT be labelled an accessibility feature and MUST NOT be a default:
[DYSLEXIA-META] pools fifteen studies and 91 effect sizes over 688 readers and
finds no reliable effect on reading speed or accuracy. What the evidence
supports is a plain face at the reader's chosen size with generous spacing and a
short measure — the controls above.

---

## A.4 Space and size

### A.4.1 The scale

A 4-pixel base with an 8-pixel rhythm, linear, computed from one base value
rather than enumerated, so a density or distance change is one number.

| Token | Base multiples | px at `near` |
| --- | --- | --- |
| `base.space.025` | 0.5 | 2 |
| `base.space.050` | 1 | 4 |
| `base.space.100` | 2 | 8 |
| `base.space.150` | 3 | 12 |
| `base.space.200` | 4 | 16 |
| `base.space.300` | 6 | 24 |
| `base.space.400` | 8 | 32 |
| `base.space.600` | 12 | 48 |
| `base.space.800` | 16 | 64 |
| `base.space.1200` | 24 | 96 |

Every widely used system that declares an 8-pixel grid ships sub-8 steps in its
own token file — Carbon at 2 and 4, Atlassian at 2, 4 and 6, Material at 2, 4
and 6 — and none surveyed is purely 8. A 4-pixel base with most semantic steps
on even multiples gives the discipline of 8 with the escape hatch needed
anyway.

### A.4.2 Targets

Four floors, stated separately because conflating them ships 24-pixel buttons
described as conformant:

| Floor | Token | Value at `near` | Source |
| --- | --- | --- | --- |
| Conformance minimum, any pointer | `sys.size.target.min` | 1.5rem / 24 px | [WCAG22] §2.5.8 |
| Precise pointer | `sys.size.target.pointer` | 2.75rem / 44 px | platform convention |
| Touch | `sys.size.target.touch` | 3rem / 48 px | platform convention |
| Directional remote | `sys.size.target.remote` | 3.5rem / 56 px | derived here |

[WCAG22] §2.5.8's 24 pixels is below every platform recommendation and below
the physical size a fingertip requires. It is a legal floor, not a design
target.

Neither §2.5.8 nor its enhanced counterpart covers a directional remote: both
are scoped to pointer input, and **no television platform publishes a minimum
focusable size** — four vendors' design documentation was searched and none
states one. The remote value is therefore the deployment's own, derived from
A.3.3's angular requirement and from A.5's focus-scale headroom. Because it is
in `rem`, at `far` it is 112 px on a 1920-wide canvas.

Targets are sized for the coarsest pointer present, not the primary one. The
media features reporting pointer capability are unreliable in exactly the
hybrid cases that matter — a tablet with a mouse attached commonly fails to
report it — so a fine pointer may enable a denser mode by choice and MUST NOT
shrink anything by default.

### A.4.3 Radius and border width

| Token | Value | For |
| --- | --- | --- |
| `sys.shape.radius.sm` | 0.25rem / 4 px | an inline control, a chip |
| `sys.shape.radius.md` | 0.5rem / 8 px | a button, a tile, a card |
| `sys.shape.radius.lg` | 0.75rem / 12 px | a dialog, an overlay |
| `sys.shape.radius.full` | a pill | a facet chip, a status badge |
| `sys.border.width.hairline` | 1 px | a separator |
| `sys.border.width.component` | 1.5 px | a control's own edge |

Radii are modest throughout. Poster art, scans and pages are rectangular, and a
large radius crops the content it frames rather than framing it.

A border width is not in `rem`. A hairline is a hairline at every distance: it
exists to be the thinnest visible line, and doubling it at `far` would make it a
rule. A.6 explains why 1.5 px is the component value — it is what survives three
metres where a 1.10:1 tone step does not.

Neither radius nor border width changes under `density` (A.1.6).

### A.4.4 The safe inset

At `far`, nothing readable or interactive is placed within the inset:

| Edge | Value at 1920 × 1080 |
| --- | --- |
| left, right | 96 px |
| top, bottom | 60 px |

Roku publishes an action-safe rectangle of 1726 × 970 at offset (96, 53) and a
design guideline of a 90-pixel horizontal and 60-pixel vertical margin. The two
disagree; the stricter figure per edge is taken.

The justification is **not** overscan, which modern panels largely do not have
and which Google's current guidance says is no longer an issue. It is that
focus enlarges an item — published focus scale factors run to 1.1× — and the
outermost row or column must have room to grow into without crossing the edge.
That reason is checkable now and survives the disappearance of the historical
one.

---

## A.5 Focus

Focus is the cursor on a surface reached by a remote and is continuously visible
there. On a pointer surface it is shown when a person is navigating by key.

| Token | Value |
| --- | --- |
| `sys.color.focus.ring` | `oklch(0.62 0.012 264)` / `#82868e` |
| `sys.border.focus.width` at `near` | 0.125rem / 2 px |
| `sys.border.focus.width` at `far` | 0.125rem / 4 px |

**The ring is a role of its own and not a ramp step.** A.6 establishes that
adjacent ramp steps cannot reach 3:1, and the ring must clear 3:1 against every
surface it can sit on. Assigning it a step would make it fail the test A.5
imposes. The value above clears 3:1 against step 05 and more against the
darker steps.

In the light theme the constraint runs the other way. The ring is measured
against **the surface of least contrast with it** — the lightest in the dark
theme, the darkest in the light one — which then clears the rest by more.

- The indicator MUST be drawn with an outline, for A.2.7's reason.
- It MUST meet [WCAG22] §2.4.13: an area at least that of a two-pixel perimeter
  of the component, and a contrast ratio of at least 3:1 between the focused and
  unfocused states of the same pixels. That is a change-of-state measurement,
  which is the right property and is checkable.

Indication MAY combine an outline with a scale or an inversion. On a client with
a constrained renderer, an inversion and a border are cheaper than a scale, and
a scale must stay inside A.4.3's inset.

The interface MUST NOT rely on its framework to preserve focus across a
re-render; spec-10 §17.7 states the obligation and names its assertion point.

---

## A.6 Elevation

Elevation is a step of surface tone, not a shadow. On a dark surface a shadow
darkens nothing.

| Level | Step |
| --- | --- |
| base | 01 |
| raised | 03 |
| overlay | 05 |

**A tonal step alone cannot carry a boundary.** Step 03 on step 02 measures
1.10:1, far below the 3:1 [WCAG22] §1.4.11 requires of a boundary that must be
perceived.

**No border step reaches 3:1 against an elevation surface either.** Measured
against steps 01 to 05, step 06 spans 1.63:1 down to 1.16:1 and step 07 spans
2.05:1 down to 1.46:1; step 08, which is a hovered value rather than a resting
border, reaches 2.99:1 at its best. An elevated surface whose edge is functionally
significant MUST therefore carry `sys.color.border.strong`, which resolves to the
same primitive as the focus ring and clears 3:1 against every surface in the ramp
— 5.17:1 at step 01 falling to 3.68:1 at step 05.

It is a role of its own rather than a reference to `sys.color.focus.ring` because
A.2.7 rebinds the semantic tier to system colour keywords in their defined pairs:
a boundary binds to `ButtonBorder` and a focus indicator to `Highlight`, and one
name cannot be both. Steps 06 and 07 remain correct for a separator and for a
control's own edge, where the edge is not the sole carrier of anything.

This is the rule and not an exception, because in this ramp no border step and no
surface pair reach the ratio. A deployment that retunes the ramp measures again;
the obligation is the ratio, not the step.

A shadow MAY be added for depth and MUST NOT be the sole carrier of any
boundary, state or affordance: it does not survive forced colours and it does
not survive three metres.

---

## A.7 Motion

| Token | Value |
| --- | --- |
| `sys.motion.duration.state` | 200 ms |
| `sys.motion.duration.container` | 300 ms |
| `sys.motion.duration.full` | 500 ms |
| `sys.motion.easing.enter` | `cubic-bezier(0.05, 0.7, 0.1, 1)` |
| `sys.motion.easing.exit` | `cubic-bezier(0.3, 0, 0.8, 0.15)` |
| `sys.motion.easing.standard` | `cubic-bezier(0.2, 0, 0, 1)` |
| `sys.motion.duration.focus-move` at `near` | 150 ms |
| `sys.motion.duration.focus-move` at `far` | **provisional, pending measurement** |

The durations and easings are Material 3's published set, adopted whole because
they are versioned and numerically explicit.

`reduced` is a resolver context, not a media query sprinkled through
components. Under it, durations of transform and position resolve to zero while
short opacity transitions are retained — deliberately, because a change of
opacity is not motion animation, and zeroing everything makes state changes
instantaneous and harder to follow.

Focus movement is a `distance` override. On a surface driven by a remote, focus
moves repeatedly and in sequence, so per-move duration accumulates into felt
latency in a way a single tap does not; the far value is **shorter** than the
near one. **No television platform publishes a figure for this** — two
independent searches of Apple's and Google's documentation found none — so it is
measured on the household's own hardware and recorded, and is marked provisional
until it is.

---

## A.8 Iconography

### A.8.1 The base set

Icons come from **Heroicons 2.2.0**, vendored into the repository. No external
host, and no icon font.

The set ships four variants, each drawn on its own grid:

| Variant | viewBox | Paint | Count |
| --- | --- | --- | --- |
| `24/outline` | `0 0 24 24` | `fill=none`, `stroke-width=1.5` | 324 |
| `24/solid` | `0 0 24 24` | `fill=currentColor` | 324 |
| `20/solid` | `0 0 20 20` | `fill=currentColor` | 324 |
| `16/solid` | `0 0 16 16` | `fill=currentColor` | 316 |

The 20 and 16 variants are separate drawings, not the 24 scaled down. That is
what earns the choice: an optical-size programme of four discrete grids, which is
the requirement A.3.5 states for a face serving both 30 centimetres and three
metres.

The licence is MIT, Copyright (c) Tailwind Labs, Inc. It permits use,
modification and redistribution, commercial or not. **The copyright notice and
permission notice MUST travel with the vendored copies and with any glyph derived
from them**, which is the whole of the obligation. The notice lives beside the
vendored files and in the interface's third-party notices.

Icons are inline vectors taking their colour from the text colour, for A.2.7's
reason.

### A.8.2 The ladder

One variant per size band. A surface MUST NOT scale a variant outside its band:

| Rendered size | Variant |
| --- | --- |
| 16–19 px | `16/solid` |
| 20–23 px | `20/solid` |
| 24 px and above | `24/outline` |

Solid at the small sizes and outline at the large is the set's own programme, not
a preference: below about 20 px an outline's counters close and the glyph becomes
a grey lozenge, and the small grids are drawn to be read as filled shapes.

`24/solid` is reserved for a filled treatment at 24 px and above where the
surrounding design calls for one. It is not a state.

**The television takes 80 px minimum, 96 px preferred**, from `24/outline`. A
56 px icon on a 55″ panel at three metres subtends 41 arcminutes — optically a
22 px browser icon, and under the 0.7° threshold for identifying a shape. Ordered
by what the eye receives, the television sits with the *small* icons, so a rule
keyed to pixel count would hand the thinnest stroke to the hardest-to-identify
glyph.

### A.8.3 What carries selected state

Fill is unavailable: it is the resting form at 16 and 20 px. A surface MUST NOT
use fill, or its absence, to mean selected.

Ranked by what survives a dark field, forced colours, three metres, and a client
with no runtime axis control:

1. **A container behind the glyph** — pill, circle or rounded square on a raised
   surface. Survives forced colours as a background region, survives monochrome,
   and is far larger than any stroke, so it works at distance.
2. **A separate indicator** — a dot, bar or underline beside the glyph.
   Overloads no channel.
3. **A size step**, which is the television's own native focus idiom.

Tint alone is insufficient: colour is spent on class (A.2.6), and colour as the
only visual means fails at Level A.

### A.8.4 Drawing a glyph the base set lacks

A drawn glyph MUST match the base set's construction, which is four rules:

- **Radii sit on a 0.375 grid** at 24, and a 0.25 grid at 20 and 16 — an atom of
  about 1.5% of the box. Outer rects take 1.875 or 2.25; interior features 0.375
  to 0.75.
- **No vertex is sharp, and the arc is authored into the path**, not left to
  `stroke-linejoin`. A rounded join scales with the stroke; an authored arc is the
  same shape at every size. A triangle's apex takes 1.125, and its other corners
  are arced too.
- **A bar is a stadium**, a closed shape with its terminals in the geometry, not a
  line with a round cap.
- **A dot is a zero-length segment** — `h.008v.008h-.008Z` under
  `stroke-linecap="round"` renders as a dot exactly one stroke-width across. A
  small `<circle>` has its interior swallowed by its own stroke and closes up.

A drawn glyph MUST NOT set type. A numeral or letter in a glyph is drawn as
strokes, and a letterform that cannot be drawn as strokes at 16 disqualifies the
design rather than the size — see A.8.5.

### A.8.5 Reducing a drawing to 20 and 16

A drawn glyph MUST resolve at all three grids. Reduction is re-expression, not
thinning:

- **Repeats reduce in count and are respaced.** Six perforations a side at 24,
  four at 20, three at 16.
- **Relative radii hold or grow** as the icon shrinks. Tightening corners at small
  size is the wrong instinct.
- **A construction serving only a refinement is deleted**, not shrunk.
- **A feature too thin to survive is restated as a solid region.** A divider line
  becomes two knocked-out frames.
- **A line-figure's solid form is its stroke outlined into a ribbon** of 1.5
  units, not a second drawing.

Where no reduction preserves the meaning, the meaning changes and **the interface
MUST supply what the glyph drops**. The seek intervals are the case: a two-digit
numeral in a 16 box is about five units tall with two counters and cannot be
drawn, so below 24 px the numeral is absent and the interval appears in the label
and the accessible name. Direction alone then separates the two controls. This is
a stated loss, not a rendering fallback.

The constraint runs upward as well as downward. Where a mark cannot be drawn at
16, the 24 drawing is the thing that is wrong. An overdue integrity check is
marked with an **ellipsis** rather than a question mark for exactly this reason:
the shield leaves about four units for an interior mark, a question mark is a
bowl and a stem and a dot, and *pending* is in any case the more accurate word.

### A.8.6 The category glyphs

A.2.6 makes the glyph the carrier of category. One glyph per value of spec-04
§6.3's category registry:

| Category | Class | Glyph | Source |
| --- | --- | --- | --- |
| film | video | a film strip: a frame with sprocket columns down both edges | `film` |
| television episode | video | a screen on a stand | `tv` |
| home video | video | a camcorder: a body and a lens wedge | `video-camera` |
| music recording | audio | a disk: a centre hole and one groove | drawn |
| audiobook | audio | an open book with one sound arc rising clear of its outer edge | drawn |
| podcast episode | audio | a microphone: a capsule on a stem, on a base | `microphone` |
| photograph | image | a print: a frame with a horizon and a sun | `photo` |
| scan | image | a sheet with a folded corner, crossed by a scanner bar | drawn |
| document | text | a sheet with a folded corner and text lines | `document-text` |
| ebook | text | an open book: two facing pages | `book-open` |
| comic issue | package | a page of unequal panels: one wide above, two below | drawn |
| video game | software | a gamepad: a body with a directional cross and two buttons | drawn |

A companion kind is a value of that registry and takes no glyph, for A.2.6's
reason for giving it no colour: it is never presented as a holding (spec-10
§12.2), so nothing draws it.

*music recording* is drawn because the base set offers a notated pitch. The unit
a household holds is a recording, and a disk says that; a quaver says something
about notation.

**A glyph MUST be identifiable with no colour at all.** Under forced colours the
fills are overridden; a television client may draw a marker in one ink; and a
person with a colour vision deficiency gets the monochrome rendering whatever the
tokens say. Where two glyphs are distinguishable only when coloured, the glyphs
are wrong, not the palette.

The pair needing most care is *scan* against *document*, since both are a sheet
of paper. The scanner bar crossing **beyond** the sheet's edges is what separates
them, and it must still separate them at 16 px. The sheet keeps its folded corner
at every grid and loses its text lines, so the bar is the entire signal.

*audiobook* against *ebook* is the same problem and takes the same answer, since
both are an open book. The arc rising **clear of** the book's outer edge is the
separator, and at 16 the pages reduce to one knocked-out region and the arc to a
single stroke outside it — A.8.5's restatement of a thin feature as a solid one,
applied so that the signal is the part that sits outside the silhouette. These
two are also the pair where class colour helps least, because rose and amber are
the tightest pair in A.2.6 at 134 rgb units, which is a further reason the glyph
carries it.

*comic issue* against *photograph* needs less care than it looks to: both are a
frame, but a print carries a horizon and a sun inside one field while a comic
page is divided, and A.8.5's rule that a divider becomes two knocked-out frames
makes the division the shape rather than a line that could thin away.

A category the registry adds needs a glyph before it is presentable. It does not
need a colour: it takes its class's, and A.2.6 gives every class one.

### A.8.7 The drawn inventory

Fifteen glyphs are drawn because nothing in the base set's 324 serves them. Each
carries all three grids.

| Glyph | Why the base set does not serve it |
| --- | --- |
| music recording | `musical-note` is a notated pitch |
| audiobook | `book-open` is the ebook; nothing in the set is a book that is heard |
| comic issue | no panelled page; `squares-2x2` is a grid control and `rectangle-stack` a stack of cards |
| video game | no gamepad; `puzzle-piece` means an extension and `cpu-chip` means hardware |
| scan | no scanner mark |
| previous, next | `backward` and `forward` are scans; a step is a different command |
| back 10s, forward 30s | no seek-by-interval mark |
| shuffle | `arrows-right-left` means swap |
| repeat one | `arrow-path-rounded-square` is repeat-all; the numeral is absent |
| captions | no caption-track mark |
| audio description | no described-audio mark |
| face tag | `viewfinder-circle` frames a point, not a person |
| integrity overdue | `shield-check` and `shield-exclamation` exist; the state between them does not |

*captions* is `CC` because a C is the one letterform that survives 16: an open arc
with no counter. *audio description* cannot be letters at all — an A is two
diagonals and a crossbar, three strokes in three units — so it is a point inside
the picture frame with sound coming off it, the arcs reducing in count at 16.
Published comprehension-tested access symbols for both exist; substituting that
artwork is a separate decision and is not made here.

No *share* glyph ships on either surface.

### A.8.8 The absence markers

spec-10 §5.2's seven states are marked by a vocabulary of three channels, none of
which any icon set contains: contour (solid or dashed), field (outline or knocked
out), and one interior mark of 8×8 at 24. A broken contour means no person has
established this. A knocked-out field means settled, and will not change.

At 16 each interior mark reduces to a **single stroke** — a dot, a vertical bar, a
horizontal bar, a diagonal slash — for A.8.5's reason, and the four are chosen to
stay maximally distinct from one another rather than to resemble the marks they
replace.

*held* carries no marker, so a reader cannot distinguish *held* from *state never
computed*. That is why *not yet examined* has a mark of its own and why the state
may never be left unset. It is an invariant, not a convention.

On the television, render the state at 32 px or more, or as prose on the focused
row, and prefer the prose.

## A.9 Components

### A.9.1 What a component is

A user interface element is a component when all four hold:

1. It corresponds to a named pattern in [APG] or [OPEN-UI], or carries a written
   rationale for being novel.
2. Its states are enumerated.
3. Its keyboard **and** directional-remote interactions are defined.
4. Its populated, empty, error and loading renderings are defined, where it can
   hold content.

Condition 3 is where a media interface differs from a general design system:
the published inventories specify keyboard interaction and say nothing about a
remote. That column is written here.

### A.9.2 Empty and error are required

A household catalog is defined by its gaps. A fresh install is empty, a scan in
progress is partial, a moved file is an error, and a photograph with no date, a
letter with no transcript and a release with no cover art are the ordinary case.
Every one is a rendering the happy path never exercises and a demonstration
library never shows.

A component specified only in its populated state will be wrong in production on
the first day and stay wrong. The review criterion is that all four renderings
exist, not that the populated one looks right.

The empty rendering MUST distinguish spec-10 §5.2's states: "nothing here" and
"nothing here yet" are different components' worth of difference.

### A.9.3 The inventory

| Component | Pattern | Notes |
| --- | --- | --- |
| Tile | grid cell | the browse unit; carries name, category marker, absence state |
| Shelf | layout grid | a row of tiles; wrapping permitted (A.9.4) |
| Collection | layout grid or list | spec-10 §9.3's faceted surface |
| Facet group | listbox or group of toggles | never a form |
| Facet chip | button | one per active facet, independently removable |
| Entity page | — | spec-10 §8.4's seven bands |
| Member list | list | spec-10 §8.2 and §8.3; a list, never a grid |
| Transport | toolbar | spec-10 §12.3; the position slider sits outside it (A.9.4) |
| Position slider | slider | never inside a live region |
| Track picker | listbox | values, not actions |
| Queue | list | reorderable without dragging |
| Reader | — | spec-10 §12.1; carries A.3.6's preferences |
| Scan viewer | — | scan beside transcript; region correspondence |
| Correction question | button pair | spec-10 §15.2 tier one; one confirm |
| Correction field | input | tier two |
| Finding | — | spec-10 §16; what was attempted, what happened, what may be done |
| Identity indicator | — | spec-10 §14.1; always present |
| Principal chooser | listbox | spec-10 §14.2 |
| Absence statement | — | spec-10 §5.3; words, in the value's place |
| Dialog | dialog (modal) | native element, for focus containment that survives patching |
| Notice | status or alert | polite by default; alert for playback failure only |

### A.9.4 Three pattern constraints

From [APG]:

- **A seek control does not belong inside a transport toolbar.** A toolbar
  navigates with the arrow keys and a slider consumes them. [APG] says to avoid
  such a control in a toolbar and, where unavoidable, to make it the last
  element; here it sits outside the toolbar's single tab stop.
- **A list of actionable things is not a listbox.** [APG] states that a listbox
  cannot hold interactive elements and directs such a list to the grid pattern.
  A shelf of playable tiles is a grid; a track picker, where a row is a value,
  is a listbox.
- **A browse grid follows [APG]'s layout-grid keyboard model**, in which
  wrapping at a row's end is permitted, and not the data-grid model, in which it
  is not.

### A.9.5 Variants fail loudly, and names are literals

A component's variant set is enumerated and an unmapped variant raises rather
than falling back to a default. Compile-time checking covers only a literal, so
where a variant arrives as a value the component matches on it and raises on no
match.

A class name MUST be a complete literal string in the source. A name assembled
at run time is not detected by the CSS build and produces no rule, so a token
vocabulary requiring assembly does not merely read badly — it does not compile.
This is a further reason the semantic vocabulary is small, flat and enumerable.

---

## A.10 Generating the stylesheet

One token file, one stylesheet. Every context is in it, including the one that
renders across a room: A.10.3 establishes that `far` is this interface at a
distance rather than a theme handed to another program, so it needs no artefact of
its own.

### A.10.1 The interface

Three layers, in this order:

1. Primitives are declared in the theme layer, where they generate utilities.
2. Semantic and context values are declared **outside** the theme layer, on the
   root and on context scopes, so they can be rebound per context.
3. Semantic names are registered in the theme layer as references to those
   runtime variables.

**Layer 3 requires the `inline` keyword** — `@theme inline { --color-surface:
var(--sys-color-surface) }`. Without it the build copies the value at compile
time and the runtime rebinding in layer 2 silently has no effect. The failure
mode is that the context attribute does nothing, with no error.

The consequence is that one attribute on the document root reassigns the whole
spacing scale, the whole type scale and the whole palette with no rebuild.

**daisyUI is removed, and `core_components.ex` is rebuilt against `sys`
tokens.** This is not optional and it is not small. daisyUI has one flat
named-theme axis selected by a single attribute, which cannot express A.1.6's
five orthogonal modifiers without a named theme per combination — the
combinatorial explosion the resolver exists to prevent. Its component classes
also bind every shipped component to daisyUI's token names rather than `sys`,
which A.1.4 forbids, and its four-step surface scale cannot carry A.2.2's
twelve. Removing it rewrites the component layer.

Context attributes live on the document root, outside the region the server
patches, so they survive navigation. **Two attributes are recorded — the
resolved value and the person's intent** — so that "follow the system" is a
third state rather than a lost one. The scaffolded script the project currently
ships removes the resolved attribute for the system case, which discards
exactly the value A.10 requires be kept.

### A.10.2 Breakpoints

Breakpoints are literal and are not variables. A custom property is not a legal
value in a media query condition, and relative units in a media query resolve
against the user agent's initial font size rather than anything the page
declares — so **a root-size change cannot move a `rem` breakpoint under any
arrangement.**

That has a consequence A.3.3 must answer rather than inherit. Were `far` ever
emitted into a stylesheet with the interface's breakpoints, every `rem` would
double while every breakpoint stayed put, and a 1920-wide surface would render
a desktop column count at twice the type size.

| Context | Breakpoints |
| --- | --- |
| `near` | 40rem, 48rem, 64rem, 80rem |
| `far` | none; a single-column, shelf-based layout |

A single column at `far` is not a breakpoint set withheld; it is the layout a
shelf-based surface has at any width, because a person across a room scans one
row at a time.

### A.10.3 The interface across a room

`distance: far` is the deployment's **own interface rendered across a room**, not
a theme handed to another program. The deployment ships no client on any platform:
spec-10 §18.1's television contract is met by a community client already in a
platform's store, and such a client carries its own design language and takes
nothing from here.

So `far` needs no second artefact and no second carrier. It is a resolver context
like the other four (A.1.6), emitted into the same stylesheet, and it is carried by
the cascade and inheritance A.10.1's layers already rest on. What changes at `far`
is the root size (A.3.3), the focus ring's width (A.5), the target floors (A.4.2)
and the breakpoint set (A.10.2). The `sys` role names do not change, so no template
distinguishes the two distances.

**A Roku is not a surface this reaches**, and spec-10 §4.3 is unqualified about
why: it runs no browser, so no stylesheet arrives at it. What `far` serves is a
screen far from its reader that renders pages — a laptop or tablet across a room, a
desktop on a large panel, a television whose own browser the household chooses to
use. §4.4 makes that a declaration recorded against the device rather than
something the page detects, which is what keeps the two distances from being
guessed at.

A deployment that later shipped a client of its own would need these values in that
platform's form. The definition is format-neutral and nothing here forbids emitting
them, but this annex specifies no such artefact, because no such client exists to
consume one.

---

## A.11 Versioning

The design language is versioned semantically. Its public interface is the set
of `sys` token names, the component names, and each component's declared
attributes and their enumerated values.

Adding a role or a component is a minor change. Renaming, merging, splitting or
removing one is a breaking change, because every template binds to those names.
A token being removed is marked deprecated for one minor release first, using
the format's own deprecation field.

Three decisions are far more expensive to reverse than the rest, and each is
recorded with its reasoning where it is made: the unit of dimension primitives
(A.1.3), the exclusion of context from names (A.1.5), and the emphasis
vocabulary used across the colour roles — every system has one, they are
mutually incompatible, and changing it touches every colour token at once. The
vocabulary here is `subtle` / bare / `strong` / `solid`.

---

## A.12 References

### A.12.1 Normative

- **[DTCG]** Design Tokens Community Group, *Design Tokens Format Module
  2025.10*, Final Community Group Report, 28 October 2025, with its published
  JSON Schema.
- **[DTCG-RES]** Design Tokens Community Group, *Design Tokens Resolver Module
  2025.10*, Final Community Group Report, 28 October 2025.
- **[WCAG22]** as in spec-10 §23.1.
- **[APG]** W3C, *ARIA Authoring Practices Guide*, patterns, for A.9.1 and
  A.9.4.
- **[HEROICONS]** Tailwind Labs, *Heroicons* 2.2.0, MIT License. The base icon
  set (A.8.1). The version is normative: A.8.2's ladder depends on the four
  variants being separately drawn, and A.8.7's inventory depends on what the
  324 icons do and do not cover.
- **[spec-10]** *Presentation*, this system.

### A.12.2 Informative

- **[LEGGE]** Legge, G. E., Bigelow, C. A., *Does print size matter for
  reading? A review of findings from vision science and typography*, Journal of
  Vision, 2011. A.3.3's critical print size.
- **[DYSLEXIA-META]** *Does font improve reading in dyslexic children? A
  meta-analysis of dyslexia-friendly fonts and dyslexic children's reading
  performance*, Annals of Dyslexia, 2026. A.3.6's null result.
- **[OPEN-UI]** Open UI, component specifications, for A.9.1.
- **[APCA]** The Accessible Perceptual Contrast Algorithm, at the version A.2.5
  pins. Its threshold guidance is not published in a versioned normative
  document, which is why A.2.4 adopts values rather than claiming conformance.

Values marked as computed or measured in this annex — the ramp, the class-colour
contrast band and the hue-separation figures beside it, the angular figures in
A.3.3, the subsetting ratio in A.3.5, the chroma variation in A.2.1 — were
derived rather than cited, and are recorded so that they can be re-derived.
