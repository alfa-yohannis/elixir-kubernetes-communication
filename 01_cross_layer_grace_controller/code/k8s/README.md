# k8s/ — Kubernetes deployment (M-d)

The actual Kubernetes integration of the controller. (The M-a–M-c validation runs on a bare BEAM
cluster with **no** Kubernetes — it validates the grace/handoff/probe logic cheaply. These manifests
put the controller on a real cluster; running them is **V3**, which needs a local cluster.)

## What's here
- `rbac.yaml` — ServiceAccounts + Roles: the app lists pods/endpoints (libcluster discovery); the
  operator reads pods and **patches the app Deployment's `terminationGracePeriodSeconds`**.
- `app.yaml` — headless `Service` (BEAM distribution discovery), the stateful `Deployment`
  (readiness/liveness on `/healthz`; an adaptive `preStop` hook that `POST`s `/drain` so termination
  **blocks until handoff completes**), a distribution cookie `Secret`, and a `PodDisruptionBudget`.
- `operator.yaml` — the cross-layer coordinator `Deployment` (same image, `GRACE_ROLE=operator`;
  `GraceConvergence.Operator` reads each pod's `/probe`, computes the grace via `Grace.compute/2`,
  and patches the Deployment). The operator is a plain GenServer calling `kubectl` (System.cmd) —
  **not** Bonny.
- `netem.sh` — **RQ7 (real network latency).** Injects `tc netem` delay on survivor pods' egress
  (nsenter into the pod netns from the kind node) and measures, via release `rpc`, the inter-pod RTT,
  the achievable handoff rate ρ≈1/RTT, and the resulting grace → `../../data/results_netem.csv`.
  **Pauses the operator first** (else the backlog it creates triggers a rollout that kills the leaver).
- `faults.sh` — **fail-safe validation.** Injects three faults (operator crash, unusable probe,
  revoked patch RBAC) and shows the conservative response (recovery / g_max fallback / no crash).
- `../Dockerfile` — one image for both roles (`GRACE_ROLE` switches app vs operator; runtime is
  `elixir:1.16-alpine` to match the builder's OpenSSL — a mismatch caused a crypto-NIF CrashLoopBackOff).

## How the cross-layer loop maps to the paper
- **Convergence probe** → `/probe` on each app pod (`GraceConvergence.Probe`).
- **Adaptive termination hook** → `preStop` → `POST /drain` → `GraceConvergence.Shutdown` (blocks
  until `GraceConvergence.Handoff` drains the backlog, bounded by `g_max`).
- **Coordinator** → `GraceConvergence.Operator` patches `terminationGracePeriodSeconds`.
- **Membership layer** → libcluster Kubernetes strategy (`config/prod.exs`) via the headless service.

## Run it (V3) — `kind` + `kubectl` are installed (`~/.local/bin`); `docker` present
```bash
kind create cluster --name grace
docker build -t grace:dev code/             # build the image
kind load docker-image grace:dev --name grace
kubectl apply -f code/k8s/rbac.yaml -f code/k8s/app.yaml -f code/k8s/operator.yaml
kubectl rollout status deploy/grace
kubectl logs deploy/grace-operator          # "operator: pods=N grace=Ms"
bash code/k8s/netem.sh                       # RQ7: real latency -> rate/grace
bash code/k8s/faults.sh                       # fail-safe validation (Table in paper)
kind delete cluster --name grace             # tear down
```

> Status: **V3 executed on a `kind` cluster.** The 3-replica Deployment formed a BEAM cluster via the
> libcluster Kubernetes strategy, and the operator patched the Deployment's
> `terminationGracePeriodSeconds` from 6 s (idle) to 26 s once ~190 stateful processes/pod accumulated
> at a 10/s handoff rate — the cross-layer loop confirmed on a real orchestrator. The quantitative
> loss/efficiency numbers in the paper come from the controlled BEAM-cluster experiment (M-c); this
> deployment validates the manifests and the operator's control loop. The cluster was also scaled to
> **6 replicas** (operator handled all six probes), and both the **real-latency** experiment
> (`netem.sh`, RQ7) and the **fail-safe** injection (`faults.sh`) ran on it. Tear down with
> `kind delete cluster --name grace`.
