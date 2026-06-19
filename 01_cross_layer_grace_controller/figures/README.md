# figures/ — generated PDF figures

Produced by `../code/analysis/` from `../data/`. Do not hand-edit; regenerate via `make figures`
(to be added). Planned figures:

- `state_loss_vs_grace.pdf` — lost stateful processes vs grace strategy, across load.
- `rollout_duration.pdf` — total rolling-update time: static30 / static300 / prestop_sleep / m3.
- `handoff_completion_cdf.pdf` — CDF / p99 of handoff completion time.
- `grace_actual_vs_invariant.pdf` — grace chosen by M3 vs the safety lower bound.
- `adaptivity_timeline.pdf` — M3 tracking a load change (rho drop / backlog spike) over time.
