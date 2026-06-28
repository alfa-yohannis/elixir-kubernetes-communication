# OUTLINE — Closing the Quorum Gap (M7)

Working plan for paper 02. Mirrors the structure of
[`../01_cross_layer_grace_controller/OUTLINE.md`](../01_cross_layer_grace_controller/OUTLINE.md).
Status of each part: **[done]** written in the skeleton, **[todo]** pending.

## Thesis (one sentence)

The safe number of simultaneous voluntary disruptions is not a constant but a function of
the live BEAM cluster size, the declared quorum threshold, and handoff capacity; a
controller that derives the PodDisruptionBudget from those runtime signals preserves
quorum without over-blocking maintenance.

## Section plan

1. **Introduction** — [done] the quorum gap; contribution list; RQ preview.
2. **Background & Motivation**
   - Voluntary disruptions & PDB / `maxUnavailable` — [done]
   - Quorum in BEAM clusters (`:global`, Horde, consensus) — [done]
   - The quorum gap — [todo] worked example (adapt CoEdit/TopScore scenarios from the
     repo README): static PDB safe at pod level still breaks quorum.
   - Why current approaches fall short — [todo] conservative static `minAvailable`;
     membership→readiness bridges; `:global`/SBR (recovers after split); Akka
     `lease-majority` (fences, doesn't drive the budget).
3. **System Model & Problem Definition**
   - Model: `N`, `Q`, `A`, `ρ` — [done]
   - Quorum-safety invariant `A ≥ Q` ⇔ `minAvailable ≥ Q` — [done], Eq. (1)
   - Why a static PDB fails (`Q` tracks live size) — [done]
4. **Design**
   - Overview + reused M7 sequence figure — [done]
   - Quorum probe — [todo] reads size, `Q`, `ρ`
   - Controller & budget computation (Eq. 2) — [done formula], [todo] cadence/hysteresis
   - Eviction admission: native PDB vs. validating webhook — [todo]
   - Fail-safes & scope (bias `minAvailable` up on uncertainty) — [todo]
   - Safety guarantee: **Proposition 1** — [done]
5. **Implementation** — [todo] quorum probe (GenServer + HTTP), `kubectl`-based operator
   patching the PDB, RBAC, `kind` packaging; note code shared with M3.
6. **Evaluation** — [todo] outline only; see matrix below.
7. **Discussion & Threats** — [todo] single-host emulation; "quorum" across
   `:global`/CRDT/consensus; PDB granularity; webhook trade-off; generality (size,`Q`,`ρ`
   interface → Akka/Orleans).
8. **Related Work** — [todo] PDB primitives; SBR / `lease-majority`; readiness bridges;
   companion M3; quorum/consensus background. Claim: none couples budget to live quorum.
9. **Conclusion** — [todo].
10. **Appendix**: reproduction — [todo].

## Quorum-safety invariant

- Cluster of `N` pods; application declares quorum threshold `Q` (majority `⌊N/2⌋+1`, or
  an operator floor).
- A voluntary disruption leaves `A` members available; **invariant: `A ≥ Q` at every
  instant.**
- A PDB with `minAvailable = m` guarantees `A ≥ m` against voluntary evictions ⇒ the
  invariant holds iff `m ≥ Q`.
- `maxUnavailable ≤ ⌊handoff capacity⌋` additionally ensures leaving members' state
  migrates in time (the M3 coupling).

## Experiment matrix (DONE — real measurements in `data/*.csv`)

| RQ | Method | Result (measured) |
|----|--------|-------------------|
| RQ1 safety | real peer cluster, rolling update, static $\lceil N/2\rceil$ vs quorum-aware | static breaks quorum at **every** $N\in\{3,5,7,9\}$ (min avail $1/2/3/4<Q$); quorum-aware holds min avail $=Q$, **0** violations |
| RQ2 efficiency | $N=9$ rollout, 5 repeats | conservative **3.49 s** vs quorum-aware **1.21 s** → **2.9×**, both safe |
| RQ3 adaptivity | $N=3\ldots10001$ | `minAvailable` tracks $\lfloor N/2\rfloor+1$ exactly |
| RQ4 overhead | $5\times200$k calls | **48 ns/call** (median) |
| RQ5 robustness | $q=1\ldots N$, $N=9$ | `maxUnavailable`$=N-q$ linear; under-estimate $Q$ unsafe → bias up |
| RQ6 scalability | $N=3\ldots10001$ | compute flat ~46–49 ns → **O(1)** |
| RQ7 real cluster | `kind`, eviction API | quorum-derived PDB **denied** quorum-breaking evictions (held avail$=Q=3$); static let avail fall to 1 |

**Testbed:** real peer BEAM cluster (`harness/run.exs`) + pure-policy eval
(`harness/policy.exs`) + live `kind` eviction test (`k8s/rq7_eviction.sh`). Every number
from a real run.

## Open decisions

- [ ] Quorum semantics to target first: majority consensus (`:ra`?), `:global` floor, or
      Horde membership floor. (Affects how `Q` is declared and what "violation" means.)
- [ ] Enforcement: native PDB only, or add a validating admission webhook for exact
      per-eviction quorum checks?
- [ ] How much code to share vs. fork from the M3 artifact (probe, operator, estimator).
- [ ] Bundle with M3 in one evaluation, or keep papers separate (cite across)?
