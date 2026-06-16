# Project Status & Handoff — Elixir-Kubernetes Communication

_Snapshot: 2026-06-15 ~17:25. Written for session resumption (quota-limited handoff)._

## What this project is
Research toward a **Q1 journal paper** on the *interaction between language-runtime
fault tolerance (Elixir / OTP / BEAM) and container-orchestrator fault tolerance
(Kubernetes)*. Thesis: both layers self-heal independently; the **unstudied gap is
their coordination**. `README.md` is the canonical living document.

## Deliverables on disk
- **README.md** — canonical. Contains: A–E communication taxonomy; OTP-vs-K8s
  overlap table; 5 friction points + illustrative scenarios (PayGate, SensorHub,
  ArenaServer, CoEdit, TopScore); Research Questions RQ1–RQ5 (Q1-targeted); RQ4
  candidate mechanisms **M1–M9**; preliminary literature-review verdict table.
- **diagrams/** — 10 PlantUML files (sequence + activity for each of the 5
  problems) at `skinparam dpi 300`, named diagrams, + rendered 300-DPI PNGs +
  `diagrams/README.md` (render instructions, PDF/Batik gotcha). All parse OK.
- **report/literature-review.tex** — academic /
  cross-layer **sub-review** with M1–M9 verdicts + citations (NOT yet the final
  merged report — see below).

## Background research — COMPLETED & SYNTHESIZED 2026-06-15

> The 106-agent run finished (24 sources, 118 claims → 25 verified → 15 confirmed).
> Its automatic synthesis hit the session limit, so the merged final report was
> written by hand: **`report/literature-review.tex`** (raw claims in
> `raw-confirmed-claims-wjm1rgd8u.md`; academic sub-review in
> `cross-layer-coordinated-fault-tolerance.md`). README verdict table + safest-bets
> are finalized. Net: the *coordination* gap holds; **M5 confirmed to exist on Akka**
> (`lease-majority` SBR), **M4's membership-bridge covered on Akka**
> (`ClusterMembershipCheck`); cleanest novel bets are **M3 / M7 / M8** plus M4's
> handoff-blocking + supervision parts.
>
> **Phase 0 — novelty due diligence (DONE 2026-06-16):** the 3 abstained leads were
> re-verified. `akkadotnet-healthcheck` **CONFIRMED** (membership→probe bridge exists on
> .NET too); **Beamlens has NO Kubernetes integration** (LLM diagnostics inside the
> supervision tree only); Akka Coordination-Lease **CONFIRMED** (CRD `akka.io/v1 Lease` on
> etcd via optimistic-concurrency CAS). Scholar/DBLP/IEEE-Xplore pass found **no published
> OTP↔K8s coordination protocol → gap confirmed; novelty confidence raised medium → HIGH
> for the core (M3/M7/M8).** Notable related work surfaced: Roberts SCM (arXiv:2507.02158);
> **Nefele** (arXiv:2006.07163) — an OTP-inspired orchestrator that *replaces* Kubernetes
> rather than coordinating with it.
- deep-research Workflow. **Run ID:** `wf_2e167589-1b8`. **Task ID:** `wjm1rgd8u`.
- Script: `/home/alfa/.claude/projects/-home-alfa-projects-elixir-kubernetes-communication/4a68298a-7dab-4409-bef8-6fa2e41b6137/workflows/scripts/deep-research-wf_2e167589-1b8.js`
- Agents/transcript: `…/subagents/workflows/wf_2e167589-1b8/`
- Scope: novelty of M1–M9 + adjacent lit (Akka/Orleans, MAPE-K, chaos eng, KEDA).
- **On completion it should save the FINAL synthesized report to `report/`.**
  If only the sub-review is present after it finishes, retrieve the final report
  from the workflow transcript dir, or resume:
  `Workflow({scriptPath: "<script above>", resumeFromRunId: "wf_2e167589-1b8"})`
  (cached agents return instantly).
- **TODO on resume:** read the final report; replace the *preliminary* verdicts in
  README with the final ones; commit `report/`.

## Literature-review verdicts (preliminary, medium confidence)
| Mech | Verdict | Closest prior art |
|---|---|---|
| M1 probe semantics from supervision tree | Partially covered | Glasgow "Signalling Health…" arXiv:2507.02158 (2025) |
| M2 failure-ownership delegation | Novel as a layer-ownership model | Rollback-recovery survey (ACM CSUR 2002); UCC'23 |
| M3 grace↔convergence↔probe feedback controller | Novel | K8s drain primitives; Akka SBR↔rolling-update issue #32801 |
| M4 BEAM-aware operator + readiness bridge | Novel for BEAM (exists on Akka/JVM) | Akka Lease + SBR + bootstrap |
| M5 etcd/Lease arbiter for split-brain | **Weakest** — exists on Akka (K8s Lease SBR) | Akka Kubernetes Lease |
| M6 one spec → OTP + K8s manifests | Novel | UCC'23 formal deployment model |
| M7 PDB/maxUnavailable ↔ BEAM quorum | Novel | PDB primitives; no quorum-aware PDB in BEAM |
| M8 adaptive restart-budget ↔ K8s backoff | Novel | MAPE-K self-healing (generic) |
| M9 composite BEAM liveness signal | Partially covered | Glasgow "Signalling Health…" preprint |

- **Defensible gap = coordination between the two recovery authorities** (OTP
  supervision ⟷ K8s controller as two interacting closed loops with an ownership /
  handoff protocol), NOT the individual primitives (all already exist).
- **Safest Q1 bets:** **M3 + M7 + M4** bundle; then **M8**; then **M2 + M6**.
- **Reframe M5** as BEAM-specific (fold into RQ5). **M1/M9 must cite & differentiate
  from** the Glasgow preprint (arXiv:2507.02158).

## Q1 assessment (from earlier analysis)
- Descriptive "when do they communicate" only ≈ **3/10** for Q1.
- Full arc (characterize → quantify → build mechanism → evaluate → generalize)
  ≈ **6.5/10** potential; reaching ~8 requires a genuinely novel, built-and-evaluated
  coordination mechanism + rigorous fault injection + generalization beyond Elixir.
- Minimum Q1 spine = RQ2 + RQ3 + RQ4. Venues: JSS / EMSE / FGCS / SP&E (Q1 in
  Scopus); TPDS / TCC / TDSC only if the mechanism is theoretically substantial.

## Tooling fixes applied this session
- VS Code PlantUML PDF export: deps (Batik/FOP) were **already installed**; real fix
  was pointing jebbs.plantuml at the system jar — added
  `"plantuml.jar": "/usr/share/plantuml/plantuml.jar"` to
  `~/.config/Code/User/settings.json`. Extension exports land in `out/`
  (jebbs `exportOutDir` default); `.cmapx` files come from `exportMapFile: true`.

## Next steps (prioritized)

> Full phased plan now lives in [`roadmap.md`](roadmap.md); the list below is the near-term queue.
1. **When research completes:** fold FINAL verdicts into README; commit `report/`.
2. Pressure-test the top mechanism bundle (M3+M7+M4) design vs. Akka issue #32801
   to confirm the coordination gap is real and unsolved even on the JVM stack.
3. Build the RQ2/RQ3 **fault-injection experiment matrix** (fault → injection tool
   → metric → expected vs. observed); metrics: MTTR, request/connection loss,
   state-loss rate, redundant restart count.
4. Pick target venue and draft the paper outline.
5. Add `.gitignore` entries for `out/` and `diagrams/*.png` (build artifacts) before
   committing; then commit README + diagrams sources + literature_review.

## Open offers (not yet done)
- Convert README into a LaTeX section skeleton.
- Build a runnable reference app (Phoenix + libcluster + Horde + probes + graceful
  SIGTERM) to anchor friction points #1–#5 empirically.
