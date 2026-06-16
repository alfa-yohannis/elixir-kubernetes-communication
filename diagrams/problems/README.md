# Diagrams

PlantUML (`.puml`) **sequence** and **activity** diagrams illustrating the five
runtime-vs-orchestrator friction points from the root
[README](../README.md#illustrative-scenarios).

Each problem has two views:

- **sequence** — the message exchange / timing across Kubernetes and BEAM components
- **activity** — the control/decision flow and where it branches into failure

| # | Problem | App | Sequence | Activity |
|---|---------|-----|----------|----------|
| 1 | Liveness granularity mismatch | PayGate | [01-liveness-mismatch-sequence.puml](01-liveness-mismatch-sequence.puml) | [01-liveness-mismatch-activity.puml](01-liveness-mismatch-activity.puml) |
| 2 | Double recovery / who owns the failure | SensorHub | [02-double-recovery-sequence.puml](02-double-recovery-sequence.puml) | [02-double-recovery-activity.puml](02-double-recovery-activity.puml) |
| 3 | Readiness vs. cluster formation | ArenaServer | [03-readiness-cluster-sequence.puml](03-readiness-cluster-sequence.puml) | [03-readiness-cluster-activity.puml](03-readiness-cluster-activity.puml) |
| 4 | Rolling-deploy churn / handoff vs. grace | CoEdit | [04-rolling-deploy-sequence.puml](04-rolling-deploy-sequence.puml) | [04-rolling-deploy-activity.puml](04-rolling-deploy-activity.puml) |
| 5 | Split-brain (BEAM vs. K8s membership) | TopScore | [05-split-brain-sequence.puml](05-split-brain-sequence.puml) | [05-split-brain-activity.puml](05-split-brain-activity.puml) |

## Rendering (300 DPI)

All diagrams set `skinparam dpi 300`, so PNG output is rendered at print resolution
(pixel dimensions ~4× the 72-DPI default).

- **CLI (PNG):** `plantuml -tpng diagrams/*.puml`
- **Stamp the DPI tag:** PlantUML scales the pixels but leaves the PNG metadata at
  72. Fix it (set units *before* density, or it stores per-cm):
  `mogrify -units PixelsPerInch -density 300 diagrams/*.png`.
  PNG stores resolution as pixels-per-metre (`pHYs = 11811`), which is exactly
  300 DPI — `identify` shows `118.11 px/cm`, the same value in metric.
- **LaTeX (recommended):** use vector output instead — resolution-independent and
  sharper in print: `plantuml -tsvg diagrams/*.puml` (include via the `svg` package)
  or `plantuml -teps diagrams/*.puml`.
- **VS Code:** *PlantUML* extension (`jebbs.plantuml`), `Alt+D` to preview. Set
  `plantuml.exportFormat` to `png` or `svg` — **not `pdf`**: PDF export needs the
  Apache Batik library and otherwise throws
  `ClassNotFoundException: org.apache.batik.apps.rasterizer.SVGConverter`.
- **Online:** paste into <https://www.plantuml.com/plantuml>.

Red notes/blocks mark the failure path; green marks the desired/escalation path.
