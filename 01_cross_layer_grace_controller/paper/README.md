# paper/ — manuscript (Wiley NJD v5, SP&E target)

Target venue: **Software: Practice and Experience** (Wiley), Q2, hybrid (free via the
subscription route). `main.tex` uses the **Wiley New Journal Design v5** class (`WileyNJDv5.cls`),
the current Wiley template.

## Build

**Compile with XeLaTeX** (the Wiley v5 class requires it for its fonts):

```bash
latexmk -xelatex main.tex
# or:
xelatex main.tex && bibtex main && xelatex main.tex && xelatex main.tex
```

Verified compiling on TeX Live 2023 (Debian). The template officially recommends TeX Live 2022;
2023 works here (fonts substituted), but if you hit font issues, install TeX Live 2022.

## Template files (already in this folder)

Extracted from `Wiley_New_Journal_Design_version_5__NJD_v5_.zip`:
- `WileyNJDv5.cls` — the class.
- `wileyNJD-*.bst` — all citation styles (AMA, APA, Vancouver, Harvard, …).
- `lettersp.sty`, `NJDnatbib.sty`, `NJDapacite.sty`, `mla.sty` — Wiley-specific support packages.
- `empty.pdf`, `empty.eps`, `rhlogo.jpg` — template assets.

### Three fixes applied (so it compiles on Linux/TeX Live 2023) — DO NOT REGRESS
1. The zip ships `LETTERSP.STY` (uppercase) but the class loads `lettersp.sty` — we added a
   lowercase copy (Linux is case-sensitive). **Keep `lettersp.sty`.**
2. Removed the zip's bundled generic styles (`listings.sty`, `natbib.sty`, `algorithm.sty`,
   `algorithmicx.sty`, `amssymb.sty`, `appendix.sty`) — they were old pinned versions that
   clashed with TeX Live 2023 ("requires listings.sty version 1.9 … serious problem").
   **Do NOT copy these back from the zip**; the TeX Live system versions are used instead.
3. The class emits `\bibstyle{WileyNJD-AMA}` (capital `W`) but the zip's file is
   `wileyNJD-AMA.bst` (lowercase `w`). We added capital-`W` copies `WileyNJD-*.bst` so bibtex
   resolves the style on any case-sensitive setup. **Keep both cases.**

### Build status
Verified: `xelatex → bibtex → xelatex → xelatex` exits 0, 0 undefined citations/refs, `main.pdf`
builds (~9 pages). Prose is written through the Design section (Abstract, Introduction, Background
incl. the problem figure and a "why current approaches fall short" subsection, System Model, and the
full Design); Evaluation, Discussion, the prose body of Related Work, and Conclusion are still
skeleton (guidance comments). See the top-level `README.md` for the done/not-done snapshot.

> **Always build with XeLaTeX, never pdfLaTeX** (the v5 class needs XeLaTeX fonts).

## Citation style

Selected via the `\documentclass` option, **not** `\bibliographystyle` (the class sets it).
`main.tex` currently uses `[AMA,Times1COL]` (AMA = numeric, single column).
**Confirm SP&E's required style** and switch the option if needed:
`AMA | APA | APS | AMS | Chicago | Harvard | MLA | MPS | Vancouver | WCMS`.

Bibliography source: `references.bib` (verify all DOIs/years before submission).
