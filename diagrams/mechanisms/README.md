# Mechanism diagrams (RQ4 candidate mechanisms M1–M9)

PlantUML **sequence** + **activity** diagrams for the nine candidate coordination
mechanisms from the root [README](../../README.md) (RQ4) and
[`literature_review/00-novelty-synthesis.md`](../../report/literature-review.tex).

These depict the **proposed mechanism** (the coordinated/desired flow), so green
marks the beneficial coordinated outcome. They complement the *problem* diagrams in
[`../`](../) (the 5 friction points).

| # | Mechanism | Novelty verdict | Sequence | Activity |
|---|-----------|-----------------|----------|----------|
| M1 | Supervision-tree-derived probe semantics | Partially covered | [seq](m1-supervision-derived-probes-sequence.puml) | [act](m1-supervision-derived-probes-activity.puml) |
| M2 | Failure-ownership delegation | Novel (model) | [seq](m2-failure-ownership-delegation-sequence.puml) | [act](m2-failure-ownership-delegation-activity.puml) |
| M3 | Grace ↔ convergence ↔ probe controller | **Novel** | [seq](m3-grace-convergence-controller-sequence.puml) | [act](m3-grace-convergence-controller-activity.puml) |
| M4 | BEAM-aware operator + health bridge | Split (Akka has membership-bridge) | [seq](m4-cluster-aware-operator-sequence.puml) | [act](m4-cluster-aware-operator-activity.puml) |
| M5 | Lease/etcd split-brain arbiter | Already exists on Akka (weakest) | [seq](m5-lease-fencing-arbiter-sequence.puml) | [act](m5-lease-fencing-arbiter-activity.puml) |
| M6 | One spec → OTP + K8s manifests | Novel | [seq](m6-declarative-spec-compiler-sequence.puml) | [act](m6-declarative-spec-compiler-activity.puml) |
| M7 | PDB/maxUnavailable ↔ BEAM quorum | **Novel** | [seq](m7-pdb-quorum-coupling-sequence.puml) | [act](m7-pdb-quorum-coupling-activity.puml) |
| M8 | Adaptive restart-budget ↔ K8s backoff | **Novel** | [seq](m8-adaptive-restart-budget-sequence.puml) | [act](m8-adaptive-restart-budget-activity.puml) |
| M9 | Composite BEAM liveness signal | Partially covered | [seq](m9-composite-liveness-signal-sequence.puml) | [act](m9-composite-liveness-signal-activity.puml) |

Cleanest novelty bets (post-research): **M3 + M7 + M8**, plus M4's handoff-blocking /
supervision-derived parts. Rendering instructions: see [`../README.md`](../README.md).
