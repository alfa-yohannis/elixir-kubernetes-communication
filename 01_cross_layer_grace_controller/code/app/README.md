# grace_convergence (app)

Reference implementation of the grace-convergence controller described in the paper. See
`../DESIGN.md` for analysis, requirements, design, and the validation plan.

## Modules
- `GraceConvergence.Grace` — the grace-period policy `g = clamp(T_d + B/ρ + T_c + σ, g_min, g_max)`.
- `GraceConvergence.Probe` — convergence probe: backlog, EWMA handoff rate, `T_c` estimate.
- `GraceConvergence.StatefulWorker` / `GraceConvergence.Workers` — Horde-distributed stateful processes.
- `GraceConvergence.Handoff` — drains local workers by transferring state to surviving nodes (throttled).
- `GraceConvergence.Shutdown` — adaptive termination hook; picks the grace per the configured policy.
- `GraceConvergence.ProbeHTTP` — `/probe` (reading), `/healthz`, and `POST /drain` (preStop hook).
- `GraceConvergence.Operator` — Kubernetes coordinator: reconcile loop (`kubectl` get pods → `/probe`
  → `Grace.compute` → `kubectl patch` TGPS). Runs only in the operator role (`GRACE_ROLE=operator`).
- `GraceConvergence.Harness` — experiment driver: `run/2`, `run_sweep/3`, `rollout/4`, `overhead/1`,
  `scale/1`.
- `GraceConvergence.Presence` — `Phoenix.Tracker` presence (the CRDT engine behind Phoenix.Presence),
  a realistic distributed workload used to measure real convergence time `T_c` (RQ8).

## Running the tests & experiments

### 1. Unit tests (fast, no cluster) — validates the grace policy
```bash
mix deps.get
mix compile
mix test                 # 6 Grace-policy tests; the :cluster suite is excluded by default
```

### 2. Multi-node integration test (V1) — a real 2-node BEAM cluster
The primary must be a distributed node, so launch it explicitly (it spawns a peer "survivor"
internally via `:peer`):
```bash
MIX_ENV=test elixir --name primary@127.0.0.1 --cookie ck -S mix test --only cluster
```
Asserts (a) a graceful drain hands off **all** local workers to the survivor with **state
preserved**, and (b) a too-short grace **truncates** the handoff (`{:timeout, remaining>0}` — the
RQ1 loss case). `epmd` is started automatically by the BEAM.

### 3. Manual 2-node probe (watch a handoff live)
```bash
MIX_ENV=test elixir --name primary@127.0.0.1 --cookie ck -S mix run scripts/cluster_probe.exs
```
Prints BEFORE/AFTER worker placement and the drain result, e.g.
`BEFORE local_primary=20 local_peer=20 … drain result=:ok … AFTER local_primary=0 local_peer=40`.

### 4. Single-node REPL (poke the API)
```bash
iex -S mix
iex> GraceConvergence.start_many(500)    # create 500 stateful workers
iex> GraceConvergence.reading()          # probe reading (backlog, rate, T_c)
iex> GraceConvergence.drain_and_await()  # run the adaptive drain
```

### 5. Full experiment suite (real data → `../../data/`, figures via `analysis/plot.py`)
All driven with a distributed primary (spawns a survivor peer); **never `pkill -f '…@127.0.0.1'`** —
that pattern matches the running shell and kills it (exit 144). Kill orphan beams by PID.
```bash
P="MIX_ENV=test elixir --name primary@127.0.0.1 --cookie ck -S mix run"
$P harness/run.exs        # two-load table (RQ1/RQ2)        -> results_runs.csv
$P harness/sweep.exs      # sweep + rollout + overhead + sensitivity (RQ1/2/4/5)
$P harness/repeats.exs    # N=10 table + N=5 rollout (CIs)   -> results_runs_ci.csv, results_rollout_ci.csv
$P harness/scale.exs      # |H| 1k->40k scalability (RQ6)    -> results_scale.csv
$P harness/presence.exs   # Phoenix.Presence convergence (RQ8) -> results_presence.csv
~/venv/bin/python ../analysis/plot.py   # render all figures
```
Kubernetes experiments (RQ7 + fail-safe) live in `../k8s/`: `bash ../k8s/netem.sh` (real latency) and
`bash ../k8s/faults.sh` (operator crash / probe fallback / revoked RBAC). See `../k8s/README.md`.

**Status: unit 6/6 pass; cluster integration 2/2 pass; full suite + K8s (RQ1–RQ7) run on real data.**

## Termination policy (config `:grace_policy`, FR6)
`:m3` (adaptive, default) · `:prestop_sleep` (fixed `:static_grace`) · `:static30` · `:static300`.
Switch per run, e.g. `config :grace_convergence, grace_policy: :static30`. The harness (M-c) will
sweep all four to produce the comparison in `../data/` → `../figures/`.

> Kubernetes deployment (operator + manifests) is M-d; `config/prod.exs` already selects the
> libcluster Kubernetes strategy.
