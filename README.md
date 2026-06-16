# Elixir-Kubernetes Communication

When is communication between Kubernetes and an Elixir/BEAM application actually
*necessary*? Both layers have built-in failover — OTP supervision inside the VM,
self-healing controllers in the cluster — so they overlap. This document
categorizes the cases where the two layers genuinely need to talk, with concrete
instances for each.

## Framing: direction and layer

"Communication between Kubernetes and Elixir" means traffic across the boundary
between the **Kubernetes control plane** and the **BEAM runtime inside the pod**.
It flows in three directions, and each category below is annotated with which one
applies:

- **K8s → Elixir** — the control plane signals or configures the app
- **Elixir → K8s API** — the app queries or controls the cluster
- **Elixir ↔ Elixir, mediated by K8s** — pods discover each other to form a BEAM cluster

Key insight: a *simple stateless* app needs almost none of this. The BEAM runs,
OTP supervisors restart crashed processes, K8s restarts the pod if the whole VM
dies, and the two layers never talk. **Necessity arises in the specific
situations isolated below.**

## A. Cluster formation & peer discovery — *Elixir ↔ Elixir via K8s*

The foundational case. BEAM distribution (`Node.connect/1`) needs the addresses
of peer nodes, but pods are ephemeral with dynamic IPs, so discovery **must** come
from Kubernetes.

**Mechanism** — `libcluster` strategies:

- `Cluster.Strategy.Kubernetes` — polls the K8s API (endpoints or pods, by label
  selector). Needs an RBAC `ServiceAccount` that can list endpoints/pods.
- `Cluster.Strategy.Kubernetes.DNS` / `.DNSSRV` — uses a **headless Service**'s
  DNS records instead of the API (less coupling; `.DNSSRV` pairs with StatefulSets).

**Instances that require clustering** (and therefore this discovery):

- `Phoenix.PubSub` (`:pg` adapter) broadcasting across pods
- `Phoenix.Presence` / LiveView presence (CRDT synced across the cluster)
- `Horde.DynamicSupervisor` / `Horde.Registry` — distributed process registry with handoff
- Distributed singletons (a global `GenServer` via `:global` or Horde)
- Distributed cache (`Nebulex`, `Cachex` distributed), Mnesia clustering
- Cross-node work distribution (`Task.Supervisor`, `:rpc`)

## B. Pod lifecycle & health signaling — *K8s → Elixir*

Kubernetes owns the pod lifecycle; the app must participate, or K8s makes wrong
decisions.

- **Liveness probe** — app exposes `/healthz` (HTTP/TCP/exec); K8s restarts the
  container on failure.
- **Readiness probe** — `/readyz`; app reports *not ready* until the cluster is
  formed / migrations are done / dependencies are reachable. Controls Service
  endpoint membership. Especially important for Elixir because forming the cluster
  and warming up takes time.
- **Startup probe** — for slow boots (large releases, migrations).
- **Graceful shutdown (SIGTERM)** — on rolling deploy, scale-in, eviction, or node
  drain, K8s sends `SIGTERM`. Elixir must trap it and drain: stop accepting
  connections (`Plug.Cowboy.Drainer` / Bandit shutdown), **hand off stateful
  processes** (Horde), deregister from the cluster, finish in-flight work, then
  `System.stop()`. Must complete within `terminationGracePeriodSeconds`.
- **preStop hook** — K8s runs a command/HTTP before SIGTERM (e.g., deregister,
  sleep for endpoint propagation).

## C. Configuration & identity injection — *K8s → Elixir*

- **ConfigMap** → env vars / mounted files → read in `runtime.exs`.
- **Secret** → DB credentials, API keys, and critically the **Erlang distribution
  cookie** (must be identical across all pods or distribution silently fails).
- **Downward API** → `POD_IP`, `POD_NAME`, `POD_NAMESPACE` injected as env, used to
  build `RELEASE_NODE` (e.g. `app@<pod-name>.<headless-svc>.<ns>.svc.cluster.local`)
  and for telemetry labels.
- **ServiceAccount token** mounted for API access (consumed by categories A and E).

## D. Observability & autoscaling signals — *Elixir → K8s ecosystem* (indirect)

The app emits; the K8s ecosystem consumes and acts.

- Prometheus metrics via `PromEx` / `TelemetryMetricsPrometheus`, scraped via a
  `ServiceMonitor`.
- These feed the **HPA** (custom/external metrics) or **KEDA** → K8s scales the
  Deployment. Example scalers: BEAM run-queue length, GenServer message-queue
  depth, **Oban** queue backlog, active LiveView connections.
- The loop: scaling changes the pod count, which re-triggers category A
  (discovery) and category B (lifecycle).

## E. Active cluster control — *Elixir → K8s API* (the operator pattern)

Here the app's *job* is to drive Kubernetes.

- **`Bonny`** — write K8s Operators in Elixir: watch CRDs, reconcile, manage resources.
- **`k8s`** (hex) — general CRUD against the API.
- Use cases: an operator managing CRDs (tenant/DB provisioning), an app that
  dynamically creates K8s **Jobs/Pods** for batch work, a custom controller, or
  **leader election via K8s `Lease`** objects (an alternative to `:global` for a
  "single active instance").

## Overlap & division of labor

Since both layers do failover, the real question is *where they meet*. They operate
at **different granularities and are complementary, not redundant**:

| | OTP supervision | Kubernetes |
|---|---|---|
| Granularity | Process (intra-VM) | Container / pod / node |
| Recovers from | Logic bugs, transient faults | OOM, node death, bad image, infra |
| Speed | µs–ms | seconds–minutes |
| State | Rebuilt per restart strategy | Pod replaced wholesale |

They don't talk by default. **Communication becomes necessary precisely when:**

1. You need cross-pod BEAM distribution → **A**
2. Stateful processes need graceful handoff on termination → **B** + **A**
3. You want K8s to make accurate restart/traffic decisions from app-internal
   health → **B**
4. The app manages K8s → **E**

### Friction points (where the two failover systems conflict)

- **Liveness granularity mismatch** — the BEAM VM stays alive while a critical
  subsystem is wedged, so a naive TCP liveness probe passes on a broken app;
  conversely, an over-aggressive probe kills a VM that OTP would have recovered.
- **Double recovery / "who owns the failure"** — OTP restarting a crash-looping
  process vs. K8s restarting the pod. Often resolved by deliberately letting
  `max_restarts` exhaustion crash the VM as an *escalation* to K8s.
- **Readiness vs. cluster formation** — a pod marked ready before it joins the BEAM
  cluster receives traffic it can't fully serve (e.g., can't reach a global singleton).
- **Rolling-deploy churn** — libcluster + Horde convergence and SIGTERM handoff must
  finish within `terminationGracePeriodSeconds`, or distributed state is lost.
- **Split-brain** — a network partition makes the BEAM see disconnected nodes
  (`:global` conflicts, netsplit) while K8s still sees healthy pods; the two layers
  disagree on cluster membership.

### Illustrative scenarios

Each scenario maps 1:1 to a friction point above and is concrete enough to serve as
a motivating example or a fault-injection test case.

**1. Liveness granularity mismatch — `PayGate`, a payment-webhook service.**
PayGate runs Phoenix on port 4000 and scores each charge against an external fraud
API through a Finch connection pool. The fraud API hangs (half-open TCP, no
timeout), so every pooled worker blocks and all payment requests stall. But Cowboy
still accepts sockets instantly, so the `tcpSocket: 4000` liveness probe passes —
K8s sees a healthy pod and never restarts it while 100% of payments fail.
*Inverse (over-aggressive):* the probe instead hits `/healthz`, which synchronously
pings Postgres, with `periodSeconds: 5, failureThreshold: 1`. A 3-second DB
failover returns one 503 → K8s kills the pod, dropping every in-flight LiveView
session and warm cache — even though Ecto's pool would have reconnected in 2s. If
all pods blip together, the whole Deployment cycles. The fault was survivable; the
probe wasn't.

**2. Double recovery — `SensorHub`, an IoT telemetry ingester.**
One `GenServer` per device decodes a vendor binary protocol. A firmware bug emits a
malformed frame that triggers a `MatchError`; the `:one_for_one` supervisor restarts
the decoder, the device resends the same frame, and it crashes again. Configured too
permissively (`max_restarts: 1000`), the process crash-loops thousands of times a
minute — logs flood, a core pegs — but the VM stays up, so K8s sees green and does
nothing. *Deliberate escalation:* with a sane `max_restarts: 3 in 5s`, exhaustion
propagates up, the top supervisor terminates, the BEAM exits non-zero, and K8s
restarts the pod under CrashLoopBackOff. The runtime says "I can't fix this locally"
and hands the failure to the orchestrator, whose slower restart-with-backoff breaks
the tight loop and surfaces it on pod-restart dashboards.

**3. Readiness vs. cluster formation — `ArenaServer`, a multiplayer game backend.**
Each live match is a global singleton `GenServer` placed via `Horde.Registry`. A
rolling deploy starts pod-7; Cowboy binds 4000 and the `tcpSocket` readiness probe
passes in ~1s, so K8s adds pod-7 to the Service and routes players to it. But
libcluster's 5s poll hasn't discovered peers yet and Horde hasn't synced, so pod-7's
registry is empty. A player rejoining match `abc` (whose singleton lives on pod-3)
either gets "match not found" or — worse — pod-7 spawns a *second* `abc` process
locally, splitting the match across two pods. Fix: gate readiness on "cluster joined
AND Horde converged," not "port open."

**4. Rolling-deploy churn — `CoEdit`, a LiveView collaborative editor.**
Every open document is a stateful `GenServer` holding an in-memory CRDT, distributed
via Horde. A rolling deploy SIGTERMs pod-2, which owns 400 document processes, with
`terminationGracePeriodSeconds: 30`. On SIGTERM the app drains the endpoint and asks
Horde to hand off all 400 processes (each serializes and transfers CRDT state) — but
under load the handoff takes ~45s. At 30s K8s sends SIGKILL; the ~150 not-yet-moved
documents die with their unsynced edits, and users lose recent changes. Compounding
it, if the rollout replaces pods faster than libcluster's poll interval, the handoff
*target* may itself be terminating. Fix: align the grace period with measured
handoff time, cap `maxUnavailable`, and checkpoint CRDTs more aggressively.

**5. Split-brain — `TopScore`, a distributed leaderboard.**
The running tally is a single global counter registered with `:global` across 4
pods. An AZ network blip partitions the cluster into {pod-1, pod-2} | {pod-3, pod-4};
each side sees the other as `nodedown` and may re-register its own leaderboard
singleton, creating duplicates. When the partition heals, `:global`'s name-clash
resolver kills one duplicate — discarding the scores it accumulated during the split.
Throughout, every pod's local liveness/readiness probe passes, so K8s reports 4
healthy pods and takes no action: the orchestrator's health model says "all green"
while the runtime's membership model says "split," and data is silently lost on heal.

## Research questions (Q1 target)

The descriptive "when do they communicate" angle alone is contribution-light. The
Q1-worthy gap is the **under-studied interaction between two overlapping
fault-tolerance layers**: OTP supervision at the *runtime* layer and Kubernetes
self-healing at the *orchestration* layer. The literature treats each in isolation.

> **Gap.** Cloud-native Elixir/BEAM systems embed two independent, overlapping
> fault-tolerance mechanisms — OTP supervision and Kubernetes self-healing — yet
> their coordination is ad hoc and prone to conflict. The interaction between
> *language-runtime* and *orchestrator* fault tolerance is largely unstudied.

**Main RQ.** *How should runtime-level (OTP/BEAM) and orchestrator-level
(Kubernetes) fault-tolerance mechanisms be coordinated to maximize dependability
while minimizing redundant recovery and state loss in cloud-native Elixir systems?*

### Sub-questions

**RQ1 — Characterization.** *What forms of communication between Elixir
applications and Kubernetes are necessary, and how are they realized in practice?*
- **Method:** systematic literature review + mining open-source repositories
  (libcluster usage, Helm charts, probe configs) + grey literature.
- **Contribution:** an empirically grounded taxonomy (validates categories A–E
  above) with prevalence data.

**RQ2 — Interaction failure modes.** *How do OTP-level and Kubernetes-level fault
tolerance interact, and what anti-patterns emerge from their overlap?*
- **Method:** fault injection / chaos engineering (Chaos Mesh, LitmusChaos) on
  representative workloads; catalog conflict modes — double recovery,
  liveness/health-granularity mismatch, split-brain, handoff-vs-grace-period races.
- **Contribution:** an empirically derived catalog of layered-FT failure modes
  (formalizes the friction points above).

**RQ3 — Quantification.** *What is the impact of layered fault tolerance on recovery
time, availability, and state consistency versus single-layer configurations, and
at what overhead?*
- **Method:** controlled experiments; metrics: MTTR, request/connection loss,
  state-loss rate, redundant restart count; statistical analysis across fault
  scenarios.
- **Contribution:** quantified trade-offs — the evidence base.

**RQ4 — Design (systems contribution).** *Can an explicit coordination mechanism
between the BEAM runtime and the Kubernetes control plane improve dependability
over default/ad-hoc configurations?*
- **Method:** design a coordination layer (e.g., readiness/liveness semantics
  driven by cluster-formation + supervision health; orchestrated `SIGTERM`↔Horde
  handoff; escalation policy mapping `max_restarts` exhaustion to pod restart);
  implement and evaluate against the RQ3 baselines.
- **Contribution:** a reusable coordination artifact + evaluation. Lifts the paper
  from "study" to Q1.
- **Candidate mechanisms (the novelty lever — `report/` validates each against prior art):**
  1. probe/readiness semantics derived *automatically from the supervision tree*
     (a wedged or over-restarting subtree drives liveness/readiness, instead of a
     hand-written `/healthz`);
  2. a *principled failure-ownership delegation model* — a policy deciding which
     layer (OTP vs. Kubernetes) recovers a given fault class, rather than both
     reacting independently;
  3. a *feedback controller* coordinating the two layers (coupling
     `terminationGracePeriodSeconds`, libcluster/Horde convergence, and probe state);
  4. a *BEAM-cluster-aware Kubernetes operator* + bidirectional health bridge that
     reflects Erlang-distribution / Horde membership into pod readiness (via
     readiness gates) and blocks pod termination until handoff completes;
  5. using the *Kubernetes control plane (etcd / Lease) as an external arbiter /
     fencing authority* to resolve BEAM network partitions, instead of `:global`
     last-writer-wins;
  6. a *single declarative fault-tolerance spec* compiled to BOTH OTP supervision
     specs AND K8s manifests (probes, PDBs, grace periods, anti-affinity) — one
     source of truth for cross-layer recovery policy;
  7. *coupling PodDisruptionBudgets / `maxUnavailable` to BEAM quorum and handoff
     capacity*, so voluntary disruptions never break `:global`/Horde quorum;
  8. *adaptive restart-budget escalation* — dynamically tuning OTP
     `max_restarts`/`max_seconds` and mapping the escalation threshold to K8s
     restart/backoff (a control-theoretic boundary between the layers);
  9. a *composite BEAM liveness signal* (scheduler utilisation, run-queue length,
     message-queue backpressure, restart intensity) replacing TCP/HTTP probes to
     eliminate the "VM alive but wedged" false negative.

  The bare "tune the probes / align the grace period" version is best-practice
  engineering, not a research contribution; these are the research-grade alternatives,
  to be pruned to the genuinely novel ones by the literature review.

#### Literature-review verdicts (preliminary)

> **Research status (2026-06-15, synthesis complete):** the deep-research run
> (106 agents, 24 sources, 118 claims → 25 verified → **15 confirmed**) finished; its
> automatic synthesis hit the session limit, so the merged report was written by hand:
> [`report/literature-review.tex`](report/literature-review.tex)
> (raw claims: [`raw-confirmed-claims-wjm1rgd8u.md`](report/literature-review.tex)).
> Key shift from the evidence: **Akka already bridges cluster membership into K8s
> readiness** (`ClusterMembershipCheck`) and **fences split-brain with a K8s Lease**
> (`lease-majority` SBR) — so **M5 clearly exists on the JVM** and **M4's
> membership→readiness bridge is covered there**. The BEAM-novel surface narrows to
> *supervision-tree-derived* probes (M1), *handoff-blocking* termination (M3/M4), and
> the control-loop couplings (M7/M8). The Glasgow *signal-based monitoring* paper
> (arXiv:2507.02158) is the closest prior art to M1/M9.

Prior-art pressure-test of M1–M9 (full cited report:
[`report/literature-review.tex`](report/literature-review.tex);
medium confidence — a literature *absence* cannot be proven):

| Mech | Verdict | Closest prior art |
|---|---|---|
| M1 | Partially covered | Glasgow "Signalling Health…" preprint (arXiv:2507.02158) |
| M2 | Novel as a layer-ownership model | Rollback-recovery survey (ACM CSUR 2002); UCC'23 |
| M3 | Novel | K8s drain/grace primitives; Akka SBR↔rolling-update issue |
| M4 | Novel for BEAM (exists on Akka/JVM) | Akka Lease + SBR + bootstrap |
| M5 | **Weakest** — already a pattern on Akka (K8s Lease SBR); novel only as BEAM-specific | Akka Kubernetes Lease |
| M6 | Novel | UCC'23 formal cloud-native deployment model |
| M7 | Novel | PDB primitives; no quorum-aware PDB in BEAM tooling |
| M8 | Novel | MAPE-K self-healing loops (generic) |
| M9 | Partially covered | Glasgow "Signalling Health…" preprint |

- **The defensible gap is the *coordination between the two recovery authorities*** —
  OTP supervision ⟷ Kubernetes controller as two interacting closed loops with a
  defined ownership/handoff protocol — **not** the individual primitives (probes,
  PDBs, grace periods, SBR, Lease fencing, supervision trees all already exist).
- **Safest Q1 bets (refined post-research):** **M3 + M7 + M8** — the control-loop
  couplings (grace↔convergence, PDB↔quorum, restart-budget↔backoff) with no close
  prior art on *any* platform; then **M4's BEAM-specific parts** (handoff-blocking
  termination + supervision-derived readiness — *not* the membership→readiness bridge,
  which Akka's `ClusterMembershipCheck` already does); then **M2 + M6** vs. the
  infra-only UCC'23 baseline. **M5 is weakest** (Akka `lease-majority` SBR is the same
  K8s-Lease fencing pattern).
- **Reframe M5** as BEAM-specific and fold into RQ5 (Akka already does Lease fencing);
  **M1 / M9 must cite and differentiate from** the Glasgow health-signalling preprint.
- **Phase 0 novelty due diligence — DONE (2026-06-16):** the 3 abstained leads were
  re-verified — `akkadotnet-healthcheck` CONFIRMED (membership→probe bridge on .NET too),
  Beamlens has NO K8s integration (LLM diagnostics only), Akka Coordination-Lease CONFIRMED
  (CRD `akka.io/v1 Lease` on etcd). Scholar/DBLP/IEEE-Xplore: **no published OTP↔K8s
  coordination protocol → gap confirmed; novelty confidence medium → HIGH for M3/M7/M8.**
  Related: Nefele (arXiv:2006.07163) *replaces* K8s rather than coordinating with it.

**RQ5 — Generalization.** *When should recovery be owned by the runtime vs. the
orchestrator, and do the findings generalize beyond Elixir (e.g., Akka/JVM,
Orleans/.NET)?*
- **Method:** derive a decision model/guidelines; small replication on another
  actor/runtime platform for external validity.
- **Contribution:** a generalizable model — impact beyond one ecosystem.

### Framing & venues

- **Empirical + design arc (RQ1–RQ5):** *Journal of Systems and Software*,
  *Empirical Software Engineering*, *Future Generation Computer Systems*,
  *Software: Practice and Experience*.
- **Lead with the mechanism (RQ4):** *IEEE Transactions on Cloud Computing*,
  *IEEE TPDS*, *IEEE TDSC*.
- **Survey-only (RQ1 + taxonomy):** realistically only *ACM Computing Surveys*
  reaches Q1, and only if exhaustive.

**Minimum credible Q1 spine:** RQ2 + RQ3 + RQ4 (characterize → quantify → solve →
evaluate). RQ1 alone is an SLR/workshop paper, not Q1.
