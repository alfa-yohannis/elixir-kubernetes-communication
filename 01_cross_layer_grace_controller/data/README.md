# data/ — experiment results (real measurements only)

CSV outputs from `../code/harness/`. **Empty until experiments are run — no fabricated data.**

Naming convention (mirrors the reference project):
- `results_<baseline>_<metric>_runs_<load>.csv` — per-run raw samples
- `results_<baseline>_<metric>_summary_<load>.csv` — aggregated (mean, p50, p95, p99, stdev)

Where:
- `<baseline>` ∈ `static30`, `static300`, `prestop_sleep`, `m3`
- `<metric>`   ∈ `state_loss`, `rollout_duration`, `handoff_completion`, `premature_sigkill`, `grace_used`
- `<load>`     ∈ handoff-backlog sizes / rho settings (e.g. `h500`, `h2000`, `rho_low`)

Plus `*_summary.csv` cross-scenario tables consumed by `../code/analysis/` → `../figures/`.
