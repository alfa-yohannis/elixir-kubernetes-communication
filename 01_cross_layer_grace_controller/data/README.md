# data/ — experiment results (real measurements only)

CSV outputs from `../code/harness/` (BEAM experiments) and `../code/k8s/` (cluster experiments).
**Every row comes from a real run — no fabricated data.** Regenerate figures with
`~/venv/bin/python ../code/analysis/plot.py`.

| File | Produced by | Contents |
|---|---|---|
| `results_runs.csv` | `harness/run.exs` | two-load matrix (Table 1): policy, need, grace, drain, lost |
| `results_runs_ci.csv` | `harness/repeats.exs` | the two table loads × 4 policies × **10 repeats** (confidence intervals) |
| `results_sweep.csv` | `harness/sweep.exs` | load sweep, need ∈ {10,25,40}s × 4 policies × 3 repeats (RQ1/RQ2 curves) |
| `results_rollout.csv` | `harness/sweep.exs` | three-pod rolling-update time per policy (RQ2) |
| `results_rollout_ci.csv` | `harness/repeats.exs` | rolling-update time × 4 policies × **5 repeats** (reproducibility) |
| `results_overhead.csv` | `harness/sweep.exs` | controller overhead: probe latency, per-process memory, throughput (RQ4) |
| `results_sensitivity.csv` | `harness/sweep.exs` | grace sensitivity to σ, g-bounds, ρ-estimate error (RQ5) |
| `results_scale.csv` | `harness/scale.exs` | per-node scalability, \|H\| 1k→80k: start, mem, drain, throughput, lost (RQ6) |
| `results_netem.csv` | `k8s/netem.sh` | **real** inter-pod latency on kind: injected delay → RTT, ρ, grace (RQ7) |
| `results_presence.csv` | `harness/presence.exs` | Phoenix.Presence (Phoenix.Tracker) convergence vs N: add/re-converge (T_c) (RQ8) |

Columns are self-describing (header row in each file). The scalability ceiling is near \|H\|≈30–35k
(under a 600 s budget: 5,632/40,000 and 69,038/80,000 lost); netem shows ρ≈1/RTT collapsing and the
grace saturating g_max beyond ~100 ms RTT.
