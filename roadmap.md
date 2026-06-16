# Roadmap — Elixir ⟷ Kubernetes Fault-Tolerance Coordination (Q1 paper)

_Forward plan. Current-state snapshot: [`PROJECT_STATUS.md`](PROJECT_STATUS.md).
Novelty conclusions: [`report/literature-review.tex`](report/literature-review.tex)._

## Goal
A Q1 journal paper that establishes and solves the **coordination gap between
language-runtime fault tolerance (OTP/BEAM) and orchestrator fault tolerance
(Kubernetes)** — two self-healing layers that today operate independently.

## Done (front matter)
- [x] Problem taxonomy — A–E communication categories (README)
- [x] OTP-vs-K8s overlap + 5 friction points + named scenarios + diagrams
- [x] Research questions RQ1–RQ5 (Q1-targeted)
- [x] 9 candidate mechanisms M1–M9 + sequence/activity diagrams (`diagrams/mechanisms/`)
- [x] Novelty pressure-test (24 sources, 15 confirmed claims; medium confidence)

## The contribution (decision)
**Thesis:** a *cross-layer coordination protocol* between the OTP supervisor and the
Kubernetes controller — two interacting closed loops with a defined ownership /
handoff contract.

**Recommended scope (from the novelty review):**
- Core artifact: **M3** (grace ↔ convergence controller) + **M7** (PDB ↔ quorum) +
  **M8** (adaptive restart-budget ↔ backoff) — the cleanest novel coordination
  contributions, no close prior art on any platform.
- Add **M4's BEAM-novel parts** (handoff-blocking termination + supervision-derived
  readiness) — but NOT the membership→readiness bridge (Akka already ships it).
- **Demote M5** (Akka `lease-majority` SBR exists) → fold into RQ5 generalization.
- **M1 / M9:** cite & differentiate from the Glasgow signal-based-monitoring paper.

**Open decisions (yours):**
- [ ] Ambition: full M3+M7+M8(+M4) bundle vs. one sharp mechanism (M3 alone is a
      credible minimum contribution).
- [ ] Target venue (sets the format + rigor bar) — see below.
- [ ] Evaluate by real k8s testbed vs. simulation/model.

## Phases

### Phase 0 — Novelty due diligence (small; do first)
- [ ] Re-verify the 3 abstained leads: Akka.NET `akkadotnet-healthcheck`, Beamlens,
      Akka Coordination-Lease CRD.
- [ ] Google Scholar / DBLP / IEEE Xplore pass (the web index missed full text).
- [ ] Confirm no published OTP↔K8s coordination protocol exists.
- **Exit:** novelty confidence raised medium → high for the chosen mechanisms.

### Phase 1 — Mechanism design (RQ4) ← natural next deliverable
- [ ] Formalize the coordination protocol: the ownership + handoff state machine.
- [ ] Define OTP↔K8s interfaces (what BEAM exposes; what the controller consumes).
- [ ] Specify the laws: M3 grace-period control law; M7 quorum→PDB mapping;
      M8 restart-budget ↔ backoff escalation function.
- [ ] (optional) lightweight formal model + safety invariants (no double recovery,
      no quorum break, no SIGKILL mid-handoff).
- **Output:** a design section + algorithms; refine the mechanism diagrams.
- **Exit:** design precise enough to implement.

### Phase 2 — Reference implementation + testbed
- [ ] Phoenix/Elixir app with libcluster + Horde (stateful processes).
- [ ] Coordination component: a Bonny-based operator + BEAM-side agent
      (health/membership/handoff signals; readiness gates; finalizers).
- [ ] k8s testbed on `kind`/minikube; Helm/manifests; metrics (PromEx/Prometheus).
- [ ] Baseline build (default probes/grace/PDB, no coordination) for comparison.
- **Exit:** both baseline and coordinated builds deploy and run.

### Phase 3 — Fault-injection evaluation (RQ2/RQ3)
- [ ] Experiment matrix: fault × injection tool × metric × build.
- [ ] Faults: rolling deploy, node drain, network partition, OOM, wedged subsystem,
      crash-loop (maps to the 5 friction points).
- [ ] Tools: Chaos Mesh / LitmusChaos; scripted `kubectl drain`.
- [ ] Metrics: MTTR, request/connection loss, state-loss rate, redundant restart
      count, coordination overhead.
- [ ] N repetitions + statistical analysis; baseline vs. coordinated.
- **Exit:** quantified trade-offs with significance.

### Phase 4 — Generalization (RQ5)
- [ ] Position vs. Akka (membership-readiness, lease-majority SBR) and Orleans.
- [ ] Argue the cross-platform asymmetry: Akka has the plumbing, BEAM doesn't, and
      nobody has the closed-loop coordination theory.
- [ ] (optional) small Akka replication for external validity.

### Phase 5 — Write-up & submission
- [ ] Paper outline / LaTeX skeleton.
- [ ] Related work (from `report/`).
- [ ] Threats to validity; artifact / reproducibility package.
- [ ] Submit.

## Target venues
- Empirical + design arc: **JSS, EMSE, FGCS, Software: Practice & Experience** (Q1 in Scopus).
- Mechanism-led / more theoretical: **IEEE TPDS, TCC, TDSC**.

## Risks & mitigations
- **Novelty (medium confidence)** → Phase 0 closes it.
- **Engineering lift (Phase 2)** → descope to one mechanism (M3) if time-bound.
- **Evaluation rigor** → fault injection + stats + baselines are non-negotiable for Q1.
- **"Niche" perception** → lean on the RQ5 cross-platform framing.

## Immediate queue
1. **Phase 0** re-verify (small) — or skip if already confident.
2. **Phase 1** mechanism design — the next real deliverable.
3. **Phase 3** experiment matrix — can be drafted in parallel with Phase 1.
