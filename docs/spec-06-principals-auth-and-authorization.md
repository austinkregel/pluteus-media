# Principals, Authentication and Authorization

**Specification 06**
**Status:** Draft
**Version:** 0.1
**Depends on:** spec-01 (Catalog Data Model)
**Obsoletes:** nothing

## Abstract

spec-01 §10 establishes that a principal is an identity that uses the system,
separate from LRM's agents, and §11.2 requires consumption events to be scoped
to a principal and never exposed across them. This document specifies how
principals are identified, how devices are bound to them, what the household is
in relation to both, and what a principal is permitted to do.

---

## 1. Introduction

### 1.1 Scope

- Principal identity and its mapping to external identities
- Device binding
- The household: its two natures and how they avoid drift
- Authorization: what principals may do
- Enforcement of consumption privacy

### 1.2 What this document does not specify

The authentication handshake as it appears on the wire, and session
representation (spec-07). Network exposure of the deployment, which spec-01 §16
explicitly does not address and this document does not either.

---

## 2. Conventions

BCP 14 key words per spec-01 §2.

---

## 3. Principals

### 3.1 Local identity

A principal MUST be minted locally with a primary identifier per spec-01 §4.1,
and MUST be mapped to external identities rather than keyed on them.

Every downstream reference — an event, an authored annotation, a device, a
preference — MUST reference the local identifier. Nothing MUST reference the
external identity directly.

This is what makes §3.3 survivable.

### 3.2 The external identity key

The identity key from an OIDC provider is the `(iss, sub)` composite. `sub` is
unique only within an issuer, so `sub` alone MUST NOT be used as a key.

A principal MAY hold more than one external identity mapping, which is the
mechanism by which §3.3 is repaired.

### 3.3 Issuer change

spec-01 §10.1 records the exposure: if the issuer URL changes through provider
migration, realm rename, or a move off a hosted provider, the composite changes
and prior history no longer resolves through it.

Because every reference is to the local identifier (§3.1), an issuer change is a
re-mapping and not a loss. An implementation MUST support adding a new
`(iss, sub)` mapping to an existing principal, and MUST NOT require creating a
new principal to do so. Conformance criterion 21 of spec-01 — that changing the
issuer preserves the principal's events — is satisfied by this and by nothing
else.

Adding a mapping is a privileged operation: it grants whoever holds the new
external identity the full history of that principal.

### 3.4 Principals and LRM agents

A principal MAY link to the LRM person it corresponds to.

A person who appears in household media, or who assigns names to things, but who
holds no login, is an agent and not a principal. Implementations MUST support
this. The author of a scanned letter and a relative identified in a photograph
are the ordinary cases, and neither will ever authenticate.

The link is optional and MUST NOT be required to create either side.

---

## 4. Devices

Devices are scoped to a principal at authentication time.

Input-constrained clients — televisions, set-top boxes, anything without a
usable keyboard — SHOULD use the OIDC device authorization grant [RFC8628].

**There is no shared or ambient session.** Every playback MUST be attributable
to a principal. A device is not an identity and MUST NOT accumulate consumption
history of its own.

This is a substantive constraint on the living-room case, where a single
television is used by everyone. The television is bound to whoever authenticated
it, and switching viewer is switching principal, not switching profile within a
device. An implementation MUST make that switch cheap enough that people
actually do it, because the alternative is that one principal's history silently
absorbs the household's.

---

## 5. The household

### 5.1 Two natures

spec-01 §10.2 states that the household is both an LRM collective agent and an
application concept, and is not one or the other:

- As a **collective agent** it is a res — nameable, creditable as the creator of
  a work, able to assign nomens. LRM-E8 names families explicitly. Home video
  (Annex A §A.7) is created by it.
- As an **application concept** it is the deployment and the trust boundary,
  which LRM §2.1 places outside the model.

### 5.2 Drift is avoided by partition, not by reconciliation

The two are not reconciled, because nothing is duplicated between them. Drift is
only possible where both sides hold the same attribute, and neither does.

| Held by the collective agent | Held by the trust boundary |
| --- | --- |
| Names, via nomens (spec-01 §7) | Principal membership |
| Creation and assignment relations | Authorization policy |
| Place and time-span associations | Device bindings |

The trust boundary MUST NOT carry a name of its own. Where the household's name
is displayed, it MUST be resolved from the collective agent's nomens through
spec-01 §7.4, like any other res. Renaming the household is therefore a naming
operation with no second write.

The collective agent MUST NOT carry a membership list. Membership is not a
catalog fact and changes for reasons — someone moves out — that must not alter
the creditability of work the household produced while they were part of it.

Exactly one link exists between the two. An implementation MUST NOT duplicate
any attribute across it.

### 5.3 Consequences

A collective agent continues to exist and remain creditable after every member
has left, which is correct: the home video it created does not become
authorless.

Conversely a deployment may exist before its collective agent is named, and
naming it later is an ordinary nomen creation.

---

## 6. Authorization

### 6.1 Principal classes

| Class | May |
| --- | --- |
| **Member** | Read and write the catalog; read and write their own consumption data; manage their own devices |
| **Guest** | Read what they have been granted; accumulate their own consumption data; write nothing to the catalog |

Guests exist because spec-01 §9.3 anticipates a deep link shared with a relative
given access. A guest is a principal — their playback is attributable and their
events are scoped like anyone's — but they are not part of the household in the
sense of §5.

**OPEN:** whether guest grants are per-entity, per-collection, or
time-bounded. The mechanism is a spec-07 concern; that it must exist is settled
here.

### 6.2 Members are peers over the catalog

Members are not further distinguished. There is no owner, no administrator over
catalog content, and no per-entity ownership.

The justification is the trust boundary itself: a household of a few people who
already share physical access to the storage does not benefit from modelling
internal distrust, and the recycle bin (spec-01 §14) is the safety net against
mistakes rather than a permission system.

This is a deliberate simplification and is reversible: adding distinctions later
is additive, since every write already records the principal that made it.

### 6.3 Consumption data is not shared

**No principal may observe another's consumption data.** This is spec-01 §11.2
and it is not subject to the peer rule in §6.2.

The prohibition covers every surface, not merely direct queries:

- Resumption and continue-watching lists
- Play counts and any metric derived from events
- Recommendation output, which derives from events by construction
- Aggregates, including any household-level total
- "Recently played", "popular in your library", and similar

spec-01 §16 identifies aggregate and recommendation surfaces as the likely leak
path precisely because they are built from events across the household. An
implementation MUST evaluate each such surface against this rule rather than
assuming that an aggregate anonymizes.

A household of two makes almost any aggregate re-identifying. Implementations
MUST NOT rely on aggregation as a privacy mechanism at household scale.

### 6.4 Authored annotations are not settled here

spec-02 §10 records that authored annotations sit between spec-01 §7.3, which
makes household naming shared by construction, and §11.2, which makes
consumption private. That question is open in spec-02 and is not resolved by
this document; §6.3 governs events, not annotations.

---

## 7. Conformance

1. Every event, authored annotation, and device references a principal by its
   local identifier and not by an external identity.
2. A principal accepts an additional `(iss, sub)` mapping, and after the change
   their prior events remain reachable.
3. `sub` alone is never accepted as an identity key.
4. An agent with no principal can be recorded as the creator of a work and as
   the assigner of a nomen.
5. A principal with no linked agent is fully functional.
6. No playback is recorded without an attributable principal.
7. The trust boundary carries no name; the household's displayed name resolves
   from the collective agent's nomens.
8. Removing every member from the trust boundary leaves the collective agent
   creditable as the creator of the works it created.
9. A guest can read granted content and accumulate their own events, and cannot
   write to the catalog.
10. Principal A cannot observe principal B's events through any endpoint,
    including resumption lists, play counts, recommendations, and household
    aggregates.

---

## 8. Security considerations

§3.3's re-mapping operation grants full historical access to whoever controls
the new external identity. It is the highest-value operation in this
specification and MUST be treated as such.

The device authorization grant (§4) issues credentials to a device on the basis
of a code displayed on it. A device that leaves the household — sold, lent,
returned — retains its binding until revoked. Implementations MUST provide
revocation and SHOULD surface bound devices to their principal.

§6.2's peer model means any member can delete any catalog entity. The recycle
bin (spec-01 §14) bounds the damage to thirty days; it does not prevent it. A
household that wants this prevented needs a distinction §6.2 does not provide.

---

## 9. References

### 9.1 Normative

- **[spec-01]** *Catalog Data Model*, this system.
- **[RFC8628]** Denniss, W., et al., *OAuth 2.0 Device Authorization Grant*.
- **[RFC2119]**, **[RFC8174]** as in spec-01 §18.1.

### 9.2 Informative

- **[spec-02]** *Annotations and Derived Data*, this system. §6.4.
- **[OIDC-CORE]** OpenID Connect Core 1.0, for the `(iss, sub)` composite.
