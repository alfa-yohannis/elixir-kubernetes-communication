# Prototype: Analysis → Requirements → Design → Validation

Reference implementation of the **grace-convergence controller** from the paper. This
document is the engineering basis for the code under `code/`. Build order is bottom-up and
**locally validatable first** (multi-node BEAM on one host, no Kubernetes), then Kubernetes.

---

## 1. Analysis

**Problem (from the paper).** During a rolling update or node drain, a terminating pod must
*drain*, *hand off* its stateful processes, and let the cluster *re-converge* within a fixed
`terminationGracePeriodSeconds`. If the fixed grace is shorter than the (load-dependent) time
actually needed, `SIGKILL` truncates the handoff and state is lost; if it is set defensively high,
every rollout is slow. The information that should size the deadline lives in the runtime; the
control that enforces it lives in the orchestrator; nothing connects them.

**What the prototype must demonstrate (maps to paper RQ1–RQ7).**
- **RQ1 (correctness):** a fixed 30 s grace truncates handoff and loses state under load; the
  controller eliminates that loss.
- **RQ2 (efficiency):** the controller's grace/rollout time is far below an over-provisioned 300 s grace.
- **RQ3 (adaptivity):** the controller tracks load changes (backlog spike, rate drop) without
  deadlock or zombie pods.
- **RQ4 (overhead):** probe latency, per-process memory, handoff throughput, operator footprint.
- **RQ5 (robustness):** grace sensitivity to σ, the g-bounds, and ρ-estimate error.
- **RQ6 (scalability):** how handoff cost scales with per-node \|H\|, and where the per-node ceiling is.
- **RQ7 (network realism):** under real inter-pod latency, does ρ (and the grace) track the degraded
  handoff throughput? Backed by `Proposition 1`: the policy provably satisfies the grace-safety
  invariant under a conservative rate estimate.
- **RQ8 (realistic workload):** does the mechanism hold on an unmodified Phoenix distributed feature
  (Phoenix.Presence / Phoenix.Tracker), and what real convergence time `T_c` must the grace cover?

**Measurable quantities we must produce (real data → `../data/`):** lost stateful processes,
total rolling-update duration, p50/p99 handoff-completion time, count of premature `SIGKILL`s,
grace actually used vs. the safety lower bound.

**Environment reality.** Elixir/Erlang/Docker present; `kind`/`kubectl`/`helm` not yet installed
(see top-level README). Core handoff/convergence/grace logic can be validated on a **local
multi-node BEAM cluster** (several `iex`/release nodes on one host via EPMD) before any Kubernetes
is involved — this de-risks the hardest logic early.

---

## 2. Requirements

### Functional
- **FR1 — Stateful workload.** A horde-distributed registry of stateful processes (`StatefulWorker`)
  whose in-memory state must survive a node leaving via Horde handoff. Configurable count `|H|`.
- **FR2 — Convergence probe.** A read-only endpoint exposing, per node: handoff backlog `B`
  (processes still to move), observed handoff rate `ρ` (EWMA), membership/convergence state, and an
  estimate of convergence time `T_c`. (HTTP + an in-VM API.)
- **FR3 — Grace computation.** Given probe values, compute
  `g = clamp(T_d + B/ρ + T_c + σ, g_min, g_max)` (paper Eq. 2 with margin σ and bounds).
- **FR4 — Adaptive termination.** On `SIGTERM`, drain, then **block until handoff backlog is empty**
  (not a fixed sleep), bounded by `g_max`; report completion.
- **FR5 — Coordinator/operator.** Sets per-pod `terminationGracePeriodSeconds = g` and paces the
  rollout (admit next pod only when the current reports handoff complete or `g` elapsed).
- **FR6 — Baselines.** Selectable termination policy: `static30`, `static300`, `prestop_sleep`,
  `m3` (adaptive) — so the harness can compare all four.
- **FR7 — Harness.** Drive a rolling update / repeated drain, inject faults (kill node, throttle CPU
  to lower ρ, spike `|H|`), and collect the metrics of §1 into CSV under `../data/`.

### Non-functional
- **NFR1 — Fail-safe:** unavailable/implausible probe ⇒ fall back to a configured conservative grace
  (default-safe). `g_min`/`g_max` bound both directions; assignment is idempotent.
- **NFR2 — Low overhead:** probe is side-effect-free; rate smoothing is O(1).
- **NFR3 — Reproducibility:** `make reproduce` regenerates all CSVs and figures; pinned deps.
- **NFR4 — Runs on the dev machine:** kind/k3s single host (i9, 30 GB) is sufficient.
- **NFR5 — No fabricated data:** every CSV row comes from a real run.

---

## 3. Design

### Roles → components (matches paper Table `tab:roles`)
| Role | Component (module / artifact) |
|---|---|
| Membership layer | `libcluster` topology (`Cluster.Strategy.Kubernetes` in-cluster; `Epmd`/`Gossip` locally) |
| Registry & handoff layer | `Horde.Registry` + `Horde.DynamicSupervisor` holding `StatefulWorker`s |
| Convergence probe | `GraceConvergence.Probe` (+ `GraceConvergence.ProbeHTTP` Plug/Bandit endpoint) |
| Adaptive termination hook | `GraceConvergence.Shutdown` (traps shutdown, blocks until backlog drains) |
| Coordinator (operator) | `GraceConvergence.Operator` — a GenServer reconcile loop calling `kubectl` (System.cmd) to read pods and patch TGPS (**not** Bonny) |
| Grace-convergence controller | `GraceConvergence.Grace` (the `g = clamp(...)` policy) |

### Key data structures / interfaces
- **Probe reading** (JSON + struct): `{node, backlog, rate_eps, converged?, t_c_ms, in_flight}`.
- **Grace policy:** `Grace.compute(reading, %{sigma, g_min, g_max, t_d}) -> g_seconds`.
- **Shutdown protocol:** on `:terminate`/SIGTERM → `Shutdown.drain()` then
  `Shutdown.await_handoff(timeout: g_max)` looping on `Probe.backlog/0` until 0.
- **Policy switch (FR6):** `:grace_policy` config = `:static30 | :static300 | :prestop_sleep | :m3`.

### Local-first cluster formation
- Locally: `libcluster` Epmd/Gossip strategy forms a cluster of `n` named nodes on one host; Horde
  spreads `StatefulWorker`s; killing a node triggers handoff — lets us measure `ρ`, `B`, `T_c`
  **without Kubernetes**.
- In Kubernetes: swap libcluster to the Kubernetes strategy; the operator patches TGPS and paces.

### Grace formula (single source of truth)
```
g* = T_d + B/ρ + T_c + σ
g  = min(g_max, max(g_min, g*))
```
`T_d` measured at drain start; `B`,`ρ`,`T_c` from the probe; `σ` safety margin.

---

## 4. Validation plan (validate the design before/with development)

- **V1 — Logic, local, no k8s:** unit tests for `Grace.compute` (bounds, fallback) and an
  integration test that starts `n` local BEAM nodes, registers `|H|` workers, kills one node, and
  asserts (a) Horde hands off all workers, (b) `Probe.backlog` returns to 0, (c) `await_handoff`
  returns before `g_max`. This validates the core invariant cheaply.
- **V2 — Policy comparison harness, local:** run the four policies (FR6) against a scripted
  kill/handoff with varied `|H|` and throttled `ρ`; emit CSV; confirm `static30` loses state when
  `B/ρ > 30 s` while `m3` does not — the central claim.
- **V3 — Kubernetes:** deploy app + operator on `kind`, run a rolling update, and reproduce V2 on a
  real cluster (declared single-host emulated — a threat to validity). **DONE** (incl. 6-replica scale).
- **V4 — Statistical rigor:** repeat the headline scenarios (N=10 table, N=5 rollout, `repeats.exs`)
  and report mean ± 95% CI. **DONE** — loss/grace exactly reproducible (CI=0), drain ±0.003 s.
- **V5 — Real network latency (RQ7):** inject `tc netem` on kind pods (`k8s/netem.sh`) and confirm the
  measured RTT drives ρ and the grace. **DONE** — ρ≈1/RTT collapses, grace saturates g_max past ~100 ms.
- **V6 — Fail-safe injection:** crash the operator, feed an unusable probe, revoke API RBAC
  (`k8s/faults.sh`); confirm conservative degradation. **DONE** — recovery / g_max fallback / no crash.
- **V7 — Realistic workload (Phoenix.Presence):** track N presences on `Phoenix.Tracker`, drain a
  node, measure real re-convergence T_c (`harness/presence.exs`). **DONE** — T_c ≈ 1.5 s, ~constant in
  N (set by the CRDT broadcast period); ~30× the naive 50 ms heuristic, covered by σ.
- **Exit criteria:** V1 green; V2 shows the predicted state-loss/rollout-time separation on real
  measurements; V3 reproduces the trend; V4–V6 confirm determinism, latency-tracking, and fail-safety.
  **All met.**

---

## 5. Build milestones (this prototype)
1. **M-a — DONE:** `app/` mix project — Horde + libcluster + `StatefulWorker` + `Probe` + `Grace`
   + `Shutdown` + HTTP probe; `Grace` unit tests (6/6). *(local-validatable core)*
2. **M-b — DONE:** local 2-node integration test (V1, 2/2 pass) + policy switch (FR6). V1 exit
   criteria met: graceful handoff completes with state preserved; a too-short grace truncates (RQ1).
   Hosting uses a local `DynamicSupervisor` + `Horde.Registry` (controlled survivor placement).
3. **M-c — DONE:** `harness/run.exs` → real `data/results_runs.csv`; `analysis/plot.py` → figures.
   V2 confirmed: fixed 30 s loses 40/160 once need>grace; adaptive loses 0, grace 16→46 s vs fixed 300 s.
4. **M-d — DONE (incl. V3):** `GraceConvergence.Operator` (patches `terminationGracePeriodSeconds`
   from `/probe`), `k8s/` manifests (preStop→`/drain`, PDB, headless service, RBAC), `Dockerfile`.
   V3 run on a `kind` cluster: 3-replica BEAM cluster via libcluster; operator patched grace 6→26 s
   from runtime backlog. (Quantitative numbers remain from M-c; V3 validates the deployment + loop.)
5. **M-c++ — DONE:** extended evaluation for RQ4/RQ5 — `harness/sweep.exs` adds overhead (probe ~7 µs,
   ~6.7 KB/process, ~8.3k handoffs/s), the load sweep with repeats, and grace sensitivity.
6. **M-e — DONE:** scalability (RQ6) — `harness/scale.exs` sweeps \|H\| 1k→40k → `results_scale.csv`;
   per-node ceiling at 40k (handoff can't finish in 600 s → 19,392 lost); memory linear.
7. **M-f — DONE (Q2 hardening):** statistical rigor (V4, `repeats.exs`), real network latency (V5/RQ7,
   `k8s/netem.sh`), fail-safe injection (V6, `k8s/faults.sh`), realistic Phoenix.Presence workload
   (V7/RQ8, `harness/presence.exs`), and `Proposition 1` (safety proof). Paper gained §Implementation
   (with code listings), Appendix A/B, and a Practitioner-guidance subsection; now **20 pages, RQ1–RQ8**,
   0 undefined refs, all floats referenced.

> Status is tracked in the top-level `README.md`. Keep deps pinned in `app/mix.exs`.
> **Gotcha:** never `pkill -f '…@127.0.0.1'` around the harnesses — the pattern matches the running
> shell itself (exit 144, no output). Kill orphan beams by PID. For `netem.sh`, pause the operator
> first (its rollout would kill the leaver mid-measurement).
