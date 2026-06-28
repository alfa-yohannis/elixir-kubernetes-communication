# 01 — Cross-Layer Grace-Convergence Controller (Mechanism M3)

Research artifact + manuscript for **Mechanism M3** of the parent project
(`../report/` — *Koordinasi Fault-Tolerance Lintas-Lapis BEAM ↔ Kubernetes*).

**Paper (working title):** *Closing the Grace Gap: An Adaptive Termination-Grace Controller Coupling
Kubernetes Pod Termination with BEAM Cluster Convergence for Zero-Loss Rolling Updates.*

**Target venue:** Software: Practice and Experience (Wiley), Q2, IF 3.77, hybrid (free via the
subscription route). Backups: CCPE → The Journal of Supercomputing → SN Computer Science. (JISA was
considered but **dropped — journal closed**.)

> **READ THIS FIRST when continuing.** Also read `CONTEXT.md` (conventions — DO NOT REGRESS) and
> `paper/README.md` (template build + the three fixes). Authoring decisions and gotchas live there.

---

## Current status (snapshot)

### Done
- **Project scaffold** mirroring the reference paper layout: `code/ data/ figures/ paper/
  cover_letter/ declarations/ upload/ zenodo/` + `OUTLINE.md`, `CONTEXT.md`.
- **Wiley NJD v5 template installed** in `paper/` (`WileyNJDv5.cls`, all `wileyNJD-*.bst` +
  capital-`W` copies, `lettersp.sty`, `NJD*.sty`, `mla.sty`, assets). **Compiles clean with XeLaTeX**
  (`latexmk -xelatex main.tex`), currently **20 pages, 0 errors, 0 undefined**.
- **`paper/main.tex` prose written through the Design section:**
  - **Abstract** — conceptual, deliberately free of product/API names; quantitative results left as
    an explicit placeholder (no fabricated numbers).
  - **§1 Introduction** — full prose + 4 enumerated contributions.
  - **§2 Background & Motivation** — 3 subsections + **the problem figure** (`fig:problem`, the
    "grace gap": 30 s grace vs ~45 s handoff → ~150 procs killed, illustrative) + a
    **"Why current approaches fall short"** subsection explaining, per approach (with citations),
    why existing fixes can't close the gap (summary table `tab:existing`).
  - **§3 System Model & Problem Definition** — grace-safety invariant (`eq:invariant`) and the
    optimal grace `eq:objective`; why static/over-provisioned both fail.
  - **§4 Design** — overview + **Role→Component table** (`tab:roles`) + **sequence figure**
    (`fig:seq`, full width) + 3 role subsections + **Algorithm 1** (`alg:grace`) + **activity
    diagram** (`fig:act`, vertical, centered float) + fail-safes/scope.
- **§Related Work** — has the *"Graceful shutdown in other actor runtimes"* subsection +
  comparison table (`tab:actor-compare`, Akka/Orleans/ours). Rest of related work is a stub.
- **Authors filled:** Alfa Yohannis (Universitas Pradita, **corresponding**,
  alfa.ryano@pradita.ac.id) and Alexander Waworuntu (Universitas Multimedia Nusantara,
  alex.wawo@umn.ac.id); both Department of Informatics, Tangerang, Indonesia. (Co-author email is in
  `declarations/README.md`; Wiley title page shows only the corresponding email.)
- **Styling:** all hyperlinks **navy blue** (`\hypersetup{colorlinks=true,allcolors=navyblue}`;
  hyperref/xcolor are loaded by the class — do not re-load them).

### Prototype progress (`code/`, see `code/DESIGN.md` for analysis→requirements→design→validation)
- **M-a — DONE:** `code/app/` Elixir project (`grace_convergence`): `Grace` policy, `Probe`,
  `StatefulWorker`+`Workers` (Horde), `Handoff`, adaptive `Shutdown`, `ProbeHTTP`, libcluster wiring.
  **Compiles clean; 6/6 `Grace` unit tests pass** (`mix deps.get && mix compile && mix test`).
  Termination policy switch implemented (FR6): `:m3 | :prestop_sleep | :static30 | :static300`.
- **M-b — DONE:** real 2-node BEAM cluster integration test (V1). **2/2 pass:** a graceful drain
  hands off all local workers to the survivor with **state preserved**; a too-short grace
  **truncates** the handoff (`{:timeout, remaining>0}` — RQ1 loss). Run with:
  `MIX_ENV=test elixir --name primary@127.0.0.1 --cookie ck -S mix test --only cluster`
  (see `code/app/README.md` → "Running the tests & experiments"). Implementation note: workers use
  a local `DynamicSupervisor` for hosting + `Horde.Registry` for cluster-wide identity, so the
  controller places handed-off state on a chosen survivor (Horde's ring would otherwise restart it
  on the leaving node).
- **M-c — DONE:** `code/app/harness/run.exs` drives the 4 policies under two loads on the 2-node
  cluster and writes **real** measurements to `data/results_runs.csv`; `code/analysis/plot.py`
  (matplotlib, `~/venv`) renders `figures/eval_state_loss.pdf` + `figures/eval_grace_budget.pdf`.
  **Result:** fixed 30 s loses 40/160 processes once need>grace; adaptive loses 0 and sizes grace to
  need (16→46 s) vs a fixed 300 s. These numbers are written into the paper (Evaluation/Conclusion/abstract).
- **M-c+ — extended evaluation (Q2 rigor), DONE:** `code/app/harness/sweep.exs` adds **(A)** end-to-end
  rolling-update time, **(B)** overhead (probe ~4 µs, ~6 KB/process, ~8k handoffs/s; operator
  ~73 MiB & ~74 ms reconcile/5 s on kind), **(C)** a load sweep (need {10,25,40} s × 4 policies × 3
  repeats → curves with std), and **(D)** sensitivity (σ, g-bounds, ρ-estimate error). Real data in
  `data/results_{sweep,rollout,overhead,sensitivity}.csv`; figures via `analysis/plot.py`. Paper
  Evaluation now has RQ1–RQ5 + 4 new figures (13 pages).
- **M-c++ — scalability-to-limit (RQ6), DONE:** `code/app/harness/scale.exs` sweeps a single draining
  node's backlog **|H| = 1k → 80k** (streams each size to `data/results_scale.csv`; figure
  `figures/eval_scale.pdf` via `analysis/plot.py`). **Result:** memory scales linearly & cheaply
  (5→317 MiB, ~4 KB/proc) but effective handoff throughput **collapses super-linearly** (3367→152→57→18 proc/s) as
  the Horde delta-CRDT registry fills. **Per-node ceiling ≈30–35k:** under a 600 s budget the node
  abandons **5,632/40,000** and **69,038/80,000** (≤20k still drains in 132 s, zero loss). The limit lives in
  the handoff *substrate* (registry), not the constant-time controller — motivating horizontal scaling
  (bound per-pod |H|) and a sharded registry as future work. Paper now **RQ1–RQ6 + 5 figures, 14 pages**.
  NOTE for re-runs: drive with a distributed primary
  (`MIX_ENV=test elixir --name primary@127.0.0.1 --cookie ck -S mix run harness/scale.exs`) and **never
  `pkill -f '…@127.0.0.1'`** — that pattern matches the running shell's own command line and kills it
  (exit 144, no output). Kill orphan beams by PID instead.
- **Q2-hardening — DONE (all four the user picked + a light safety proof + Phoenix case study):**
  Paper now **20 pages, RQ1–RQ8 + Proposition 1**. Added:
  - **Safety proof** — `Proposition 1` (Design §Safety guarantee): the policy provably satisfies the
    grace-safety invariant under a conservative rate estimate (hypotheses map to RQ5/RQ7 and the RQ6
    ceiling). SP&E does **not** want heavy formal methods — this light lemma is the right dose.
  - **Statistical rigor** — `harness/repeats.exs` (N=10 table + N=5 rollout) → `results_runs_ci.csv`,
    `results_rollout_ci.csv`. Loss/grace exactly reproducible (CI=0), drain ±0.005 s (CI95). Turned
    the "single-run" threat into a determinism result.
  - **Invariant figure (RQ1)** — `eval_invariant.pdf` (grace vs need + safety floor); doubles as the
    over-provisioning visual (fixed-300 off-chart).
  - **Real network latency (RQ7)** — `k8s/netem.sh` injects `tc netem` on survivor pods (nsenter into
    pod netns from the kind node; **pause the operator first** or its rollout kills the leaver).
    Measured RTT tracks injection; ρ≈1/RTT collapses (21 700→6.7/s); grace rises to the g_max cap →
    `eval_netem.pdf`. Directly rebuts the single-host threat.
  - **Fail-safe validation** — `k8s/faults.sh`: operator crash→recovery (idempotent), unusable
    probe→g_max fallback, revoked RBAC→no crash. → `tab:faults`.
  - **Wrote §Implementation** (was a stub) with Elixir+YAML listings, **Appendix A** (reproduction)
    + **Appendix B** (manifests/drain listing), and a **Practitioner-guidance** subsection.
  - **Review pass:** every figure/table/algorithm/listing referenced+discussed (0 undefined); all 18
    refs have URLs (7 + DOI); tone audited — no novelty/"first" overclaims, all "eliminate/guarantee"
    qualified to experiment or Proposition. Build clean, 20 pp.
  - **Realistic workload (RQ8)** — `harness/presence.exs` exercises **Phoenix.Tracker** (the CRDT
    engine behind Phoenix.Presence; added `phoenix_pubsub` dep + `GraceConvergence.Presence`, wired
    into the app supervision tree). Measured real re-convergence **T_c ≈ 1.5 s, ~constant in N**
    (100→2000), ~30× the naive 50 ms heuristic (σ=5 s absorbs it) → `eval_presence.pdf`. Honest gap
    surfaced: feed a measured convergence signal in production. (Fix: start PubSub/Presence via the
    app supervisor, **not** `Supervisor.start_link` over rpc — the latter links to the transient rpc
    proc and dies instantly, so the peer never replicated.)
  - Real data: `data/results_{scale,netem,runs_ci,rollout_ci,presence}.csv`. Figures via `analysis/plot.py`.
- **M-d — DONE (incl. V3 on a live cluster):** Kubernetes source — `GraceConvergence.Operator`
  (reads `/probe`, patches `terminationGracePeriodSeconds`), `code/k8s/` (`rbac.yaml`, `app.yaml`
  with the `preStop`→`/drain` hook + PDB + headless service, `operator.yaml`), `code/Dockerfile`.
  **V3 executed on a `kind` cluster:** 3-replica Deployment forms a BEAM cluster via the libcluster
  Kubernetes strategy; the operator reads each pod's probe and **patched the Deployment's
  `terminationGracePeriodSeconds` from 6 s (idle) to 26 s** once ~190 stateful processes/pod
  accumulated at 10/s — the cross-layer loop confirmed on a real orchestrator. (Tools `kind`+`kubectl`
  were installed to `~/.local/bin`; `docker` present. Tear down: `kind delete cluster --name grace`.)

### Remaining (paper)
- **Write the remaining prose:** Evaluation, Discussion/Threats, full Related Work, Conclusion;
  then fill the abstract's results placeholder.
- **Submission bits:** cover letter body, declarations, confirm SP&E reference style (`.bst` option),
  whether blind review is required, Zenodo artifact archive.

---

## Figures (sources + how to regenerate)

All figure sources live in `figures/`; PDFs are embedded by `paper/main.tex`
(`\graphicspath` includes `figures/`). Titles are clean English with **no internal labels**
("Problem 4"/"M3") and **no scenario product names** — keep it that way.
All three diagrams use the **standard PlantUML/UML theme** (default colours and shapes — no custom
skinparam palette, no coloured notes).

| PDF (in paper)                         | Source                                  | Tool | Notes |
|----------------------------------------|-----------------------------------------|------|-------|
| `grace-gap-problem.pdf` (`fig:problem`)| `grace-gap-problem.puml`                | PlantUML | the addressed problem; full-width float |
| `grace-convergence-sequence.pdf` (`fig:seq`) | `grace-convergence-sequence.puml`  | PlantUML | full-width float (font must stay readable) |
| `grace-convergence-activity.pdf` (`fig:act`) | `grace-convergence-activity.puml`  | PlantUML | genuine **activity diagram** (`start`/`stop`/`repeat`); vertical/tall — **normal centered float** at `width=0.40\linewidth` |

Regenerate: `cd figures && plantuml -tpdf <file>.puml`  (PlantUML + Java + Graphviz `dot` installed).

**Why the activity figure is NOT a `wrapfigure`** (don't reintroduce one): a PlantUML activity
diagram is vertical/tall by design and cannot be a horizontal "snake" (that earlier experiment used
component rectangles, not an activity diagram). A tall `wrapfigure` placed next to a short paragraph
or just before a `\subsection` heading prevents `wrapfig` from closing the wrapped column, so the
body text never returns to full width. We therefore use a **normal float** — text stays single-column
above/below it. (`wrapfig` has been removed from the preamble.)

---

## Build

```bash
cd paper
latexmk -xelatex main.tex      # XeLaTeX is REQUIRED (Wiley v5 fonts); pdflatex fails
# or: xelatex main && bibtex main && xelatex main && xelatex main
```
If it fails to find `lettersp.sty` / a `.bst` / clashes on `listings.sty`, re-read
`paper/README.md` → the three fixes (case copies, removed bundled generic styles). Do not undo them.

---

## Key decisions / conventions (full list in `CONTEXT.md`)
- Mechanism = **M3** (grace ↔ convergence ↔ probe). Internal labels **M3/M7 never appear in
  reader-facing text** — only in comments. Verify with:
  `grep -n 'M3\|M7' paper/main.tex | awk -F: '{l=$0;sub(/^[0-9]+:/,"",l); if(l!~/^[[:space:]]*%/)print}'`
- **Role vocabulary** in design (membership layer=libcluster, registry/handoff=Horde,
  coordinator=Bonny operator, …); bind role→component in Implementation. Keep standard terms
  (SIGTERM, grace period, rolling update) as-is.
- **Experiments: BEAM-only.** Akka/Orleans are qualitative comparison only (future work). **Never
  fabricate results.**
- Reference: `../report/mechanisms.tex` §M3 and `../report/problems.tex` Masalah 4 (source material).
