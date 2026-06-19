# code/ — artifact & experiment harness

Reference implementation of **M3** plus the harness that produces `../data/`.

## Planned components (not yet implemented)

```
code/
├── app/            # Elixir/OTP stateful service: Horde registry+supervisor, libcluster,
│                   # convergence probe endpoint (handoff_backlog, observed rho, conv. state)
├── operator/       # Bonny operator: computes g = max(|H|/rho, T_c, g_min), patches per-pod
│                   # terminationGracePeriodSeconds, paces maxUnavailable
├── prestop/        # adaptive preStop hook: drain, then block until HandoffPending() drains
├── k8s/            # manifests: Deployment, readiness gate, RBAC, PDB (baseline vs M3)
├── harness/        # load generator + fault injection (repeated drain, node kill, CPU throttle)
│                   # + metrics collection -> CSV in ../data/
├── analysis/       # scripts that turn ../data/*.csv into ../figures/*.pdf
└── tests/          # unit/integration tests
```

## Experiment scenarios (baselines)
- (a) static grace 30 s, (b) over-provisioned 300 s, (c) preStop fixed sleep, (d) **M3 adaptive** —
  each swept over handoff backlog / handoff rate (rho).

## Target environment
- Local: `kind` or `k3s` on the dev machine (i9-11900H, 30 GB RAM) — sufficient.
- Reproduce: `make reproduce` (to be added) → regenerates all CSVs and figures.

## Toolchain (install when execution starts; not installed yet)
- `kind` (or `k3d`/`k3s`), `kubectl`, `helm` — currently MISSING on this machine.
- Elixir/Erlang/mix — present (linuxbrew). Docker — present.
