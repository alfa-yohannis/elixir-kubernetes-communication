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
  (`latexmk -xelatex main.tex`), currently **7 pages, 0 errors, 0 undefined**.
- **`paper/main.tex` prose written through the Design section:**
  - **Abstract** — conceptual, deliberately free of product/API names; quantitative results left as
    an explicit placeholder (no fabricated numbers).
  - **§1 Introduction** — full prose + 4 enumerated contributions.
  - **§2 Background & Motivation** — 3 subsections + **the problem figure** (`fig:problem`, the
    "grace gap": 30 s grace vs ~45 s handoff → ~150 procs killed). Marked illustrative.
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

### NOT done yet (next work)
1. **Build the artifact in `code/`** — Elixir app (Horde + libcluster + convergence probe), Bonny
   operator (computes grace, paces rollout), adaptive `preStop` hook, K8s manifests, experiment
   harness (load gen + fault injection), tests. See `code/README.md` for the planned layout.
2. **Run experiments → populate `data/` → generate `figures/`.** Baselines: static 30 s /
   over-provisioned 300 s / fixed preStop sleep / **adaptive (ours)**. Metrics: state loss, rollout
   duration, p99 handoff, premature SIGKILLs, actual grace vs invariant. **Real runs only — no
   fabricated data** (local kind/k3s on the i9/30 GB machine is sufficient).
3. **Write the remaining prose:** Evaluation, Discussion/Threats, full Related Work, Conclusion;
   then fill the abstract's results placeholder.
4. **Submission bits:** cover letter body, declarations, confirm SP&E reference style (.bst option)
   and whether blind review is required, Zenodo artifact archive.

---

## Figures (sources + how to regenerate)

All figure sources live in `figures/`; PDFs are embedded by `paper/main.tex`
(`\graphicspath` includes `figures/`). Titles are clean English with **no internal labels**
("Problem 4"/"M3") and **no scenario product names** — keep it that way.

| PDF (in paper)                         | Source                                  | Tool | Notes |
|----------------------------------------|-----------------------------------------|------|-------|
All three diagrams use the **standard PlantUML/UML theme** (default colours and shapes — no custom
skinparam palette, no coloured notes). Keep it that way.

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
