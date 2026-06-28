# CONTEXT — paper 02 (M7)

Orientation for anyone (human or agent) picking up this paper. Companion to
[`../01_cross_layer_grace_controller`](../01_cross_layer_grace_controller) (M3).

## Where M7 sits in the agenda

The repository pursues one research gap: **OTP/BEAM runtime fault tolerance and Kubernetes
orchestrator fault tolerance overlap but do not coordinate.** The agenda enumerates
candidate coordination mechanisms M1–M9 (see [`../README.md`](../README.md) §RQ4 and
[`../report/`](../report/)). The cleanest novel "control-loop coupling" bets are **M3, M7,
M8**:

- **M3** — grace ↔ convergence controller → **paper 01** (done; under revision).
- **M7** — PDB / `maxUnavailable` ↔ BEAM quorum → **this paper (02)**.
- **M8** — adaptive restart-budget ↔ K8s backoff → future paper.

All three couple the same two control loops; M3 sizes *how long* a pod may take to leave,
M7 sizes *how many* may leave at once.

## Mechanism definition (from the report)

Source: [`../report/mechanisms.tex`](../report/mechanisms.tex) §M7, and the diagrams in
[`../diagrams/mechanisms/`](../diagrams/mechanisms/)
(`m7-pdb-quorum-coupling-{sequence,activity}.{puml,pdf,png}`).

> A controller derives the PodDisruptionBudget / `maxUnavailable` from the BEAM quorum
> requirement and handoff capacity, so voluntary disruptions never break quorum.
>
> `OnClusterChange`: `SetPDB(minAvailable = Quorum(), maxUnavailable = HandoffCap())`
> `OnEviction(pod)`: if `ViolatesQuorum(pod)` → `Deny()` else `Allow(); Handoff()`

## Novelty (from the literature review)

`../report/literature-review.tex` and `../PROJECT_STATUS.md`: **Novel.** Closest prior
art = PDB primitives themselves (`k8sPDB`) and Akka `lease-majority` SBR — but **no
quorum-aware PDB exists in BEAM tooling**, and no platform drives the K8s disruption
budget from the live runtime quorum. Phase-0 due diligence (2026-06-16) rated novelty
confidence **HIGH for M3/M7/M8**. A literature *absence* can't be proven, so Related Work
must still position carefully against SBR/Lease fencing (which *fences* split-brain rather
than *preventing* the disruption that causes it).

## Key references (already in `paper/references.bib`, seeded from 01)

- `k8sPDB` — Kubernetes Disruptions / PodDisruptionBudgets (the primitive M7 drives).
- `libcluster`, `horde` — BEAM clustering + distributed registry/handoff.
- `k8sgraceful`, `bonny` — graceful shutdown; Elixir operator toolkit.
- **Needed later (verify URL/DOI before adding):** a consensus/quorum reference (e.g.,
  Raft) and the Akka split-brain-resolver / Lease docs for Related Work.

## Constraints (inherited — do not violate)

1. **No fabricated or illustrative numbers.** The Evaluation is an *outline* until the
   harness runs. `\todo{}` marks every pending claim.
2. **Every reference real + accessible, with URL/DOI.** Verify on the web before adding.
3. **Language:** paper + top-level `README/OUTLINE/CONTEXT` in **English**; once `code/`
   exists, code comments + `code/` READMEs + `code_guide/` in **Bahasa Indonesia**
   (3rd-year-undergrad level), as in paper 01.
4. **Reader-facing prose:** describe the mechanism by name ("quorum-aware disruption
   budget"), not the internal tag "M7" (the `:m7`-style config atom, if any, is fine in
   code).
5. **Build:** `cd paper && latexmk -xelatex main.tex` (Wiley NJD v5 needs XeLaTeX).

## Reuse from the M3 artifact

When implementing `code/`, the following are expected to be shared/adapted from paper 01's
artifact: the **HTTP probe** scaffolding, the **`kubectl`-based operator** loop, the
**handoff-rate (`ρ`) estimator**, RBAC manifests, and the `kind` packaging. The new pieces
are the **quorum signal** (cluster size + declared `Q`) and the **PDB-patching** reconcile
(vs. M3's `terminationGracePeriodSeconds` patch).

## Current state (2026-06-29)

**Complete draft.** `paper/` builds (10 pp, RQ1–RQ7, 0 undefined refs). Working artifact
under `code/` (`quorum.ex`, `cluster.ex`, `quorum_probe.ex`, `pdb_operator.ex`,
`disruptor.ex`, `harness.ex`, HTTP + k8s manifests + Dockerfile). **Real measurements**
for all seven RQs in `data/*.csv`; five figures in `figures/`; `code_guide/` (Indonesian)
builds. Tests: 7 unit + 2 cluster pass. Headline results: static PDB breaks quorum on
every rollout (N=3–9) while the controller never does; quorum-aware maintenance is 2.9×
faster than conservative; budget compute is O(1) (~48 ns); on `kind`, the eviction API
denies the quorum-breaking evictions a static PDB admits.

Remaining integration: deploy the full BEAM-cluster image on `kind` and measure the
operator patching the PDB end-to-end (RQ7 currently validates the eviction-enforcement
path directly); wide-area membership-flap experiments; a joint M3+M7 evaluation.
