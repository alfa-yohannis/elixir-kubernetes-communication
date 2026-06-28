# 02 — Closing the Quorum Gap (M7: quorum-aware PodDisruptionBudget)

**Target:** *Software: Practice and Experience* (Wiley), Q2. **Status: complete draft** —
design, model, safety, a working artifact, and an evaluation with **real measurements**
for RQ1–RQ7. Every number in the paper comes from a real run; no fabricated figures.

This is paper **02** of the cross-layer agenda. Paper
[01](../01_cross_layer_grace_controller) is **M3** (the grace-convergence controller —
*how long* a pod may take to leave). This paper is **M7**: a controller that sizes *how
many* pods may leave at once, coupling the Kubernetes disruption budget to the BEAM
cluster's quorum.

## The gap

Kubernetes limits **voluntary disruptions** (rolling updates, `kubectl drain`,
scale-down) with a **PodDisruptionBudget** (PDB) / `maxUnavailable`. That budget is fixed
by an operator and expressed in pod counts — it is **unaware of the BEAM cluster's
quorum**. A budget that is safe at the pod level can still evict enough members to break
`:global`/Horde/consensus quorum (split-brain, lost authoritative state) while every
pod's probe stays green.

## The mechanism (M7)

A **quorum controller** reads, from the live BEAM cluster, the cluster size `N` and the
declared **quorum threshold** `Q` (majority `⌊N/2⌋+1`, or an operator floor), and
continuously sets the PDB:

```
minAvailable  = max(Q, Q_min)                  # enforces the quorum invariant A ≥ Q
maxUnavailable = min(N − minAvailable, cap)     # headroom above quorum (cap = handoff capacity)
```

On eviction/drain, the Kubernetes eviction API **denies** requests that would take the
live membership below `Q`. **Safety (Proposition 1):** if `minAvailable = Q* ≥ Q`, then
under any PDB-respecting voluntary disruption the available members never drop below `Q`.

## Results (all measured — `data/*.csv`)

| RQ | Question | Result |
|----|----------|--------|
| **RQ1** safety | static vs quorum-aware under rollout | static PDB broke quorum at **every** N∈{3,5,7,9} (min avail 1/2/3/4 < Q 2/3/4/5); quorum-aware held min avail = Q, **zero** violations |
| **RQ2** efficiency | maintenance time (N=9) | conservative (1-at-a-time) **3.49 s** vs quorum-aware **1.21 s** → **2.9× faster**, both safe |
| **RQ3** adaptivity | minAvailable vs N | tracks majority `⌊N/2⌋+1` exactly (N=3…10001) |
| **RQ4** overhead | budget compute | **48 ns/call** (median of 5×200k) |
| **RQ5** robustness | sensitivity to `q` estimate | under-estimating Q grants an unsafe budget → bias estimate **up** |
| **RQ6** scalability | compute vs N | flat ~46–49 ns → **O(1)** in cluster size |
| **RQ7** real cluster | eviction API on `kind` | quorum-derived PDB (minAvailable=Q=3) **denied** quorum-breaking evictions (held avail=3); quorum-unaware PDB let avail fall to 1 < Q |
| **RQ8** realistic workload | quorum-gated workload under rollout | static budget blocks **⌊N/2⌋** surviving members (Ready but can't commit); quorum-aware **0** |
| **RQ9** vs reactive baseline | model-free budget that tightens after each break | reactive breaks quorum **4×** before converging; model-based **0** (correct from first probe) |
| **RQ10** membership flapping | live-size vs desired-size anchoring | naive (live) = **28 PDB patches + 14 unsafe** samples/100; ours (desired) = **0/0** |

## Layout

```
02_quorum_aware_disruption_budget/
├── paper/              # Wiley NJD v5 — builds with XeLaTeX (10 pp, RQ1–RQ7)
├── code/
│   ├── app/            # Elixir/OTP artifact (~0.5 KLOC)
│   │   ├── lib/quorum_budget/   quorum.ex, cluster.ex, quorum_probe.ex,
│   │   │                        pdb_operator.ex, disruptor.ex, harness.ex, ...
│   │   ├── harness/    run.exs (RQ1/2), policy.exs (RQ3–6)
│   │   └── test/       quorum_test.exs, cluster_test.exs
│   ├── k8s/            rbac.yaml, app.yaml, operator.yaml, rq7_eviction.sh
│   ├── analysis/plot.py
│   └── Dockerfile
├── code_guide/         # Indonesian LaTeX walkthrough of the code
├── data/               # results_*.csv (real measurements)
├── figures/            # eval_*.pdf (rendered by plot.py)
├── README.md  OUTLINE.md  CONTEXT.md  Makefile
```

## Build & reproduce

```sh
make -C ..                      # see Makefile targets
# or directly:
cd code/app && MIX_ENV=test mix test                         # unit tests
cd code/app && MIX_ENV=test elixir --name primary@127.0.0.1 --cookie ck -S mix run harness/run.exs
cd code/app && MIX_ENV=test mix run harness/policy.exs
~/venv/bin/python code/analysis/plot.py                       # figures
bash code/k8s/rq7_eviction.sh                                 # RQ7 (needs a kind cluster)
cd paper && latexmk -xelatex main.tex                         # paper
```

## Constraints (inherited from paper 01)

- **No fabricated numbers** — every reported figure is from a real run.
- **All references real + URL/DOI.**
- **Code comments + `code/` READMEs + `code_guide/` in Bahasa Indonesia**; the **paper is
  in English**.
- Describe the mechanism by name ("quorum-aware disruption budget"), not the internal tag
  "M7", in reader-facing prose.

## Next steps

- Deploy the full BEAM-cluster artifact on `kind` (image + Deployment + operator) and
  measure the operator patching the PDB end-to-end (RQ7 currently validates the eviction
  enforcement directly on a real cluster; the operator-driven patch is the remaining
  integration step).
- Wide-area / multi-node membership-flap experiments to stress the estimator's hysteresis.
- Bundle with the M3 grace controller in a joint evaluation (size *how long* and *how
  many* together).
