# CONTEXT — working notes

## Target
- **Venue:** Software: Practice and Experience (Wiley), Q2, IF 3.77, hybrid (free via subscription).
- **Backups:** CCPE (Wiley, Q2, free via subscription) → The Journal of Supercomputing (Springer,
  Q2, free, easiest) → SN Computer Science (Springer, Q2, free, high acceptance).
- JISA was considered but **dropped (journal closed)**.

## Mechanism
- **M3 — Grace ↔ Convergence ↔ Probe feedback controller.** See `../report/mechanisms.tex` §M3 and
  `../report/problems.tex` Masalah 4. Diagrams: `../diagrams/mechanisms/m3-*`.

## Why this fits SP&E
- SP&E values *artifact + real-world experience*. M3 is an engineering artifact (a controller) that
  must be built, operated, and measured — a natural "practice and experience" paper.
- Consequence: **Implementation (§5) and Evaluation (§6) must dominate**; emphasize lessons learned.

## Hard requirement
- The empirical evaluation must use **real measurements** from real experiment runs (kind/k3s on the
  local i9 / 30 GB machine is sufficient). No illustrative/fabricated numbers.

## Validity note (state explicitly in the paper)
- Single-host emulated cluster (kind) — declare as a threat to validity; optional single cloud
  confirmation run.

## Conventions — DO NOT REGRESS (for future me / other agents)

### Manuscript template
- **Wiley New Journal Design v5** (`paper/WileyNJDv5.cls`), NOT v2. v5 is the current Wiley template.
- **Compile with XeLaTeX only**: `latexmk -xelatex main.tex` (or xelatex→bibtex→xelatex→xelatex).
  pdfLaTeX will fail (v5 fonts). See `paper/README.md` for the three case/version fixes already
  applied — do not undo them.
- Citation style is chosen via the `\documentclass` option (currently `[AMA,Times1COL]`),
  **not** `\bibliographystyle`. Confirm the style SP&E mandates.

### Terminology (writing convention)
- Describe the mechanism by **role** (runtime-agnostic) in concept/design; **bind role→concrete
  component in the Implementation section**. See `\ref{tab:roles}` in `paper/main.tex`.
- Roles: membership layer (=libcluster), registry & handoff layer (=Horde), coordinator/operator
  (=a **`kubectl`-based GenServer operator**, `GraceConvergence.Operator` — NOT Bonny, despite the dep
  being present), convergence probe, adaptive termination hook, grace-convergence controller (=our new bit).
- **Keep standard OS/orchestrator terms as-is** (SIGTERM, grace period, rolling update, readiness
  probe) — do NOT rename them to invented generic names; gloss once at first use. Over-abstraction
  hurts clarity/reproducibility.

### Experiment scope
- **Core experiments: BEAM only** (Elixir + Horde + libcluster + Kubernetes). Deep & rigorous on
  one platform.
- **Akka / Orleans: qualitative comparison only** (see `\ref{tab:actor-compare}`); they have partial
  shutdown mechanisms but no convergence-derived grace. **Do NOT implement/benchmark them** — a
  multi-runtime study is a different, larger paper. Note it as future work.
- **No fabricated/illustrative numbers.** Every result in `data/`/`figures/` comes from real runs
  (kind/k3s on the local i9/30 GB machine — confirmed sufficient).

### References — must be real + must carry a URL (DO NOT hallucinate)
- Every citation in `references.bib` must be a **real, accessible** work — verify the exact
  arXiv ID / DOI / URL (e.g., via web search) before adding it. No invented papers, IDs, or DOIs.
- **Every entry must carry a resolvable `url` (and `doi` where applicable)** — DOI, arXiv, or
  official-doc link. All current entries are verified and URL-bearing; the WileyNJD-AMA style
  renders them (DOIs via `\doibase`, docs via `\url`). Keep this when adding references.
- Verified so far: `roberts2025` (arXiv:2507.02158, Glasgow SCM), `ucc23` (DOI 10.1145/3603166.3632139,
  UCC'23), plus official docs (`k8sgraceful`, `k8sPDB`, `akkacoordinated`, `akkaHealth`, `akkaLease`,
  `akkaSBR`, `orleans`) and classic papers (`kephart2003`, `elnozahy2002`). The venue-research-sourced
  entries (`souza2024dependable`, `singh2025istio`, `gustafsson2025rtilience`, `meliani2025proactive`)
  should be re-checked against the publisher before submission.

### Experiment gotchas (DO NOT REGRESS)
- **Never `pkill -f '…@127.0.0.1'`** around the BEAM harnesses: the pattern matches the running
  shell's own command line and kills it (exit 144, no output). Kill orphan beams by **PID**.
- **`k8s/netem.sh`: pause the operator first** (`kubectl scale deploy/grace-operator --replicas=0`).
  Otherwise the backlog the experiment creates makes the operator patch the grace → triggers a rolling
  update → the leaver pod is killed mid-measurement (exit 137). The script does this + restores on exit.
- Inject real latency by `nsenter`-ing into the pod netns from the kind node (`docker exec` → `crictl`
  → `nsenter -t <pid> -n tc netem`); delay **survivor egress**, not the leaver (delaying the leaver
  breaks the `rpc` helper's distribution connection).
- Paper now **20 pages, RQ1–RQ7 + Proposition 1**; build clean, 0 undefined; all floats referenced.

## Open decisions
- Confirm SP&E reference style: AMA (numeric) chosen as default; capital- and lowercase `.bst`
  copies are present. Switch the `\documentclass` option if SP&E requires Vancouver/Harvard/etc.
- Blind review required? (affects whether author/affiliation blocks are anonymized).
- Workload choice for evaluation (synthetic Horde registry vs a realistic stateful app).
