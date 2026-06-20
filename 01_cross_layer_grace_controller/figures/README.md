# figures/ — figures embedded by the paper

Two kinds. **Diagrams** are PlantUML (standard UML theme — no custom palette); regenerate with
`plantuml -tpdf <file>.puml`. **Plots** are matplotlib, rendered from `../data/*.csv` by
`~/venv/bin/python ../code/analysis/plot.py` (do not hand-edit the PDFs).

### Diagrams (PlantUML sources alongside)
- `grace-gap-problem.pdf` (`fig:problem`) — the addressed problem (grace gap).
- `grace-convergence-sequence.pdf` (`fig:seq`) — the cross-layer sequence.
- `grace-convergence-activity.pdf` (`fig:act`) — the controller's activity diagram.

### Plots (from `analysis/plot.py`)
- `eval_state_loss.pdf`, `eval_grace_budget.pdf` (`fig:eval`) — two-load loss & grace (RQ1/RQ2).
- `eval_sweep_loss.pdf`, `eval_sweep_grace.pdf` (`fig:sweep`) — load sweep (RQ1/RQ2).
- `eval_invariant.pdf` (`fig:invariant`) — granted grace vs the safety floor; over-provisioning (RQ1).
- `eval_rollout.pdf` (`fig:rollout`) — three-pod rolling-update time (RQ2).
- `eval_sensitivity.pdf` (`fig:sens`) — grace sensitivity to σ, g-bounds, ρ-error (RQ5).
- `eval_scale.pdf` (`fig:scale`) — per-node scalability: handoff/throughput/memory vs \|H\| (RQ6).
- `eval_netem.pdf` (`fig:netem`) — real inter-pod latency → RTT, ρ, grace (RQ7).
- `eval_presence.pdf` (`fig:presence`) — Phoenix.Presence convergence vs N; real T_c (RQ8).

Titles carry **no internal labels** ("M3"/"Problem 4") and **no scenario product names** — keep it so.
