# code/ — artifact & experiment harness

Reference implementation of the grace-convergence controller plus the harness that produces
`../data/` and `../figures/`. See `DESIGN.md` for analysis → requirements → design → validation, and
`app/README.md` / `k8s/README.md` for how to run everything.

## Layout (as built)
```
code/
├── app/                        # Elixir/OTP mix project `grace_convergence`
│   ├── lib/grace_convergence/  #   grace (policy), probe, workers, stateful_worker, handoff,
│   │                           #   shutdown (preStop), probe_http, operator (kubectl-based), harness
│   ├── harness/                #   run.exs, sweep.exs, repeats.exs (CIs), scale.exs (RQ6) + scripts/
│   ├── test/                   #   grace_test (6 unit), cluster_handoff_test (2, :peer 2-node)
│   └── config/                 #   config/test/prod (prod = libcluster Kubernetes strategy)
├── k8s/                        # rbac.yaml, app.yaml, operator.yaml + netem.sh (RQ7), faults.sh
├── analysis/plot.py            # data/*.csv -> figures/*.pdf (matplotlib, ~/venv)
└── Dockerfile                  # one multi-stage image; GRACE_ROLE switches app vs operator
```

## Experiment scenarios (baselines)
- (a) static 30 s, (b) over-provisioned 300 s, (c) preStop fixed sleep, (d) **adaptive controller** —
  swept over handoff backlog `|H|` and rate `ρ`.

## Status
- **Local BEAM:** unit 6/6 + 2-node cluster integration 2/2 pass; full suite (RQ1–RQ6) → real
  `../data/*.csv`.
- **Kubernetes (kind):** app + operator deployed; the operator patches
  `terminationGracePeriodSeconds` from runtime backlog; RQ7 (real `tc netem` latency) and the
  fail-safe injection run on the cluster.
- The coordinator is a **`kubectl`-based GenServer operator** (`lib/grace_convergence/operator.ex`),
  **not** Bonny.

## Reproduce
```bash
# BEAM experiments (from code/app), then figures:
MIX_ENV=test elixir --name primary@127.0.0.1 --cookie ck -S mix run harness/run.exs   # + sweep/repeats/scale
~/venv/bin/python analysis/plot.py
# Kubernetes: see k8s/README.md, then bash k8s/netem.sh and bash k8s/faults.sh
```
Toolchain: Elixir/Erlang/mix + Docker (linuxbrew); `kind` + `kubectl` in `~/.local/bin` — all present.
**Never `pkill -f '…@127.0.0.1'`** around the harnesses (it matches the running shell → exit 144).
