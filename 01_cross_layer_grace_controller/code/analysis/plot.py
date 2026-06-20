#!/usr/bin/env python3
"""Generate evaluation figures from data/*.csv into figures/.
Run:  ~/venv/bin/python code/analysis/plot.py   (paths resolved relative to this file)
Generates whatever it has data for (skips missing CSVs)."""
import csv
import os
import statistics as st

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
DATA = os.path.join(ROOT, "data")
FIGS = os.path.join(ROOT, "figures")

POLICIES = ["static30", "static300", "prestop_sleep", "m3"]
LABELS = {"static30": "fixed 30 s", "static300": "fixed 300 s",
          "prestop_sleep": "preStop 30 s", "m3": "adaptive (ours)"}
COLORS = {"static30": "#C0504D", "static300": "#9BBB59",
          "prestop_sleep": "#E8A33D", "m3": "#1F3B73"}
MARK = {"static30": "o", "static300": "s", "prestop_sleep": "^", "m3": "D"}


def rows(name):
    p = os.path.join(DATA, name)
    if not os.path.exists(p):
        return None
    with open(p) as f:
        return list(csv.DictReader(f))


def save(fig, name):
    os.makedirs(FIGS, exist_ok=True)
    fig.savefig(os.path.join(FIGS, name))
    plt.close(fig)
    print("wrote", os.path.join(FIGS, name))


def agg(rs, pol, xkey, ykey):
    """mean,std of ykey grouped by xkey for one policy (over repeats)."""
    xs = sorted({float(r[xkey]) for r in rs if r["policy"] == pol})
    means, stds = [], []
    for x in xs:
        vals = [float(r[ykey]) for r in rs if r["policy"] == pol and float(r[xkey]) == x]
        means.append(st.mean(vals))
        stds.append(st.pstdev(vals) if len(vals) > 1 else 0.0)
    return xs, means, stds


def sweep_curves(rs):
    for ykey, ylabel, title, fname, log in [
        ("lost", "stateful processes lost", "State loss vs. handoff need (RQ1)", "eval_sweep_loss.pdf", False),
        ("grace_s", "grace granted (s)", "Grace granted vs. handoff need (RQ2)", "eval_sweep_grace.pdf", True),
    ]:
        fig, ax = plt.subplots(figsize=(6.0, 3.6))
        for pol in POLICIES:
            xs, m, s = agg(rs, pol, "need_target", ykey)
            if xs:
                ax.errorbar(xs, m, yerr=s, marker=MARK[pol], color=COLORS[pol],
                            label=LABELS[pol], capsize=3, linewidth=1.6)
        ax.axvline(30, ls=":", color="gray", lw=1)
        ax.text(30, ax.get_ylim()[1] * 0.5, " fixed 30 s", color="gray", fontsize=8)
        ax.set_xlabel("handoff need  $|H|/\\rho$  (s)")
        ax.set_ylabel(ylabel)
        ax.set_title(title)
        if log:
            ax.set_yscale("log")
        ax.legend(fontsize=8)
        ax.grid(alpha=0.3)
        fig.tight_layout()
        save(fig, fname)


def rollout_fig(rs):
    pols = [r["policy"] for r in rs]
    secs = [float(r["rollout_ms"]) / 1000 for r in rs]
    lost = [int(float(r["lost"])) for r in rs]
    fig, ax = plt.subplots(figsize=(5.2, 3.4))
    bars = ax.bar([LABELS.get(p, p) for p in pols], secs,
                  color=[COLORS.get(p, "#888") for p in pols])
    for b, l in zip(bars, lost):
        tag = f"lost {l}" if l else "lost 0"
        ax.text(b.get_x() + b.get_width() / 2, b.get_height(), tag,
                ha="center", va="bottom", fontsize=8,
                color=("#C0504D" if l else "#1F3B73"))
    ax.set_ylabel("end-to-end rollout time (s)")
    ax.set_title("Rolling-update time, 3 pods (A)")
    ax.grid(axis="y", alpha=0.3)
    fig.tight_layout()
    save(fig, "eval_rollout.pdf")


def sensitivity_fig(rs):
    kinds = [("sigma", "safety margin $\\sigma$ (s)"),
             ("g_max", "upper bound $g_{max}$ (s)"),
             ("rho_error", "rate estimate factor ($\\hat\\rho/\\rho$)")]
    fig, axes = plt.subplots(1, 3, figsize=(8.2, 2.8))
    for ax, (kind, xlab) in zip(axes, kinds):
        pts = sorted([(float(r["x"]), float(r["grace_s"])) for r in rs if r["kind"] == kind])
        if pts:
            ax.plot([p[0] for p in pts], [p[1] for p in pts], marker="o", color="#1F3B73")
        ax.set_xlabel(xlab, fontsize=9)
        ax.set_ylabel("grace (s)", fontsize=9)
        ax.grid(alpha=0.3)
    fig.suptitle("Grace sensitivity (D)", fontsize=11)
    fig.tight_layout()
    save(fig, "eval_sensitivity.pdf")


def invariant_fig(rs):
    """Grace granted vs. handoff need, with the safety floor g=need. Points above the floor are
    safe (grace covers handoff); a fixed grace dips below once need exceeds it (loss = red ring)."""
    fig, ax = plt.subplots(figsize=(6.2, 3.8))
    needs = sorted({float(r["need_target"]) for r in rs})
    hi = max(needs)
    ax.plot([0, hi * 1.12], [0, hi * 1.12], ls="--", color="gray", lw=1.3,
            label="safety floor $g=|H|/\\rho$", zorder=1)
    ax.fill_between([0, hi * 1.12], [0, hi * 1.12], 0, color="#C0504D", alpha=0.06)
    ax.text(hi * 0.62, hi * 0.30, "unsafe\n(handoff truncated)", color="#C0504D",
            fontsize=8, ha="center")
    for pol in POLICIES:
        if pol == "static300":
            continue  # off-chart at 300 s; annotated separately
        xs, m, _ = agg(rs, pol, "need_target", "grace_s")
        if not xs:
            continue
        ax.plot(xs, m, marker=MARK[pol], color=COLORS[pol], label=LABELS[pol], lw=1.7, zorder=3)
        for x, g in zip(xs, m):
            lossy = any(float(r["lost"]) > 0 for r in rs
                        if r["policy"] == pol and float(r["need_target"]) == x)
            if lossy:
                ax.scatter([x], [g], s=140, facecolors="none", edgecolors="#C0504D",
                           linewidths=2.2, zorder=5)
    ax.annotate("fixed 300 s: safe but $\\approx$6--7$\\times$ over-provisioned (off-chart)",
                xy=(hi, hi * 1.05), xytext=(hi * 0.30, hi * 1.02), fontsize=8, color="#5F7530",
                arrowprops=dict(arrowstyle="->", color="#5F7530"))
    ax.set_xlim(0, hi * 1.12)
    ax.set_ylim(0, hi * 1.18)
    ax.set_xlabel("handoff need  $|H|/\\rho$  (s)")
    ax.set_ylabel("granted grace  $g$  (s)")
    ax.set_title("Invariant validation: grace vs. required handoff (RQ1)")
    ax.legend(fontsize=8, loc="upper left")
    ax.grid(alpha=0.3)
    fig.tight_layout()
    save(fig, "eval_invariant.pdf")


def presence_fig(rs):
    """Phoenix.Tracker (Presence) convergence vs tracked-presence count: a realistic Phoenix workload.
    Shows the real T_c (re-convergence after a node departs) against the naive 50 ms estimate."""
    n = [int(float(r["n"])) for r in rs]
    add = [float(r["add_ms"]) / 1000 for r in rs]
    rec = [float(r["reconverge_ms"]) / 1000 for r in rs]
    fig, ax = plt.subplots(figsize=(6.0, 3.6))
    ax.plot(n, add, marker="o", color="#3C7D3C", label="add-convergence")
    ax.plot(n, rec, marker="D", color="#1F3B73",
            label="re-convergence after departure ($T_c$)")
    ax.axhline(0.05, ls=":", color="#C0504D", lw=1.2)
    ax.text(n[0], 0.075, "naive estimate (50 ms)", color="#C0504D", fontsize=8)
    ax.set_xlabel("tracked presences $N$")
    ax.set_ylabel("convergence time (s)")
    ax.set_title("Phoenix.Presence convergence (realistic workload)")
    ax.legend(fontsize=8)
    ax.grid(alpha=0.3)
    fig.tight_layout()
    save(fig, "eval_presence.pdf")


def netem_fig(rs):
    """Real inter-pod latency (tc netem on kind): injected delay vs measured RTT, and how the
    achievable handoff rate (~1/RTT) and the resulting grace respond."""
    d = [float(r["delay_ms"]) for r in rs]
    rtt = [float(r["rtt_ms"]) for r in rs]
    rate = [float(r["rate_eps"]) for r in rs]
    grace = [float(r["grace_s"]) for r in rs]
    fig, (a1, a2) = plt.subplots(1, 2, figsize=(8.4, 3.3))
    a1.plot(d, rtt, marker="o", color="#1F3B73")
    a1.plot([0, max(d)], [0, max(d)], ls="--", color="gray", lw=1, label="$y=x$")
    a1.set_xlabel("injected one-way delay (ms)")
    a1.set_ylabel("measured inter-pod RTT (ms)")
    a1.set_title("Latency injection is real")
    a1.legend(fontsize=8)
    a1.grid(alpha=0.3)
    a2.plot(rtt, rate, marker="s", color="#C0504D")
    a2.set_yscale("log")
    a2.set_xlabel("inter-pod RTT (ms)")
    a2.set_ylabel("achievable rate $\\rho$ (proc/s)", color="#C0504D")
    a2b = a2.twinx()
    a2b.plot(rtt, grace, marker="D", color="#1F3B73")
    a2b.axhline(120, ls=":", color="gray", lw=1)
    a2b.text(max(rtt) * 0.05, 121, "$g_{\\max}$", fontsize=8, color="gray")
    a2b.set_ylabel("projected grace, 2000 backlog (s)", color="#1F3B73")
    a2b.set_ylim(0, 135)
    a2.set_title("Rate collapses $\\to$ grace rises to cap")
    a2.grid(alpha=0.3)
    fig.tight_layout()
    save(fig, "eval_netem.pdf")


def scale_fig(rs):
    H = [int(float(r["backlog"])) for r in rs]
    drain = [float(r["drain_ms"]) / 1000 for r in rs]
    thr = [float(r["throughput_eps"]) for r in rs]
    mem = [float(r["mem_mb"]) for r in rs]
    fig, (a1, a2) = plt.subplots(1, 2, figsize=(8.0, 3.2))
    a1.plot(H, drain, marker="o", color="#1F3B73")
    a1.set_xlabel("$|H|$ (stateful processes)")
    a1.set_ylabel("handoff time (s)", color="#1F3B73")
    a1b = a1.twinx()
    a1b.plot(H, thr, marker="s", color="#C0504D")
    a1b.set_ylabel("throughput (proc/s)", color="#C0504D")
    a1.set_title("Handoff scaling")
    a1.grid(alpha=0.3)
    a2.plot(H, mem, marker="D", color="#3C7D3C")
    a2.set_xlabel("$|H|$ (stateful processes)")
    a2.set_ylabel("memory added (MiB)")
    a2.set_title("Memory scaling")
    a2.grid(alpha=0.3)
    fig.tight_layout()
    save(fig, "eval_scale.pdf")


def main():
    if (rs := rows("results_scale.csv")):
        scale_fig(rs)
    if (rs := rows("results_netem.csv")):
        netem_fig(rs)
    if (rs := rows("results_presence.csv")):
        presence_fig(rs)
    if (rs := rows("results_sweep.csv")):
        sweep_curves(rs)
        invariant_fig(rs)
    if (rs := rows("results_rollout.csv")):
        rollout_fig(rs)
    if (rs := rows("results_sensitivity.csv")):
        sensitivity_fig(rs)
    # original two-load figures (kept for reference)
    if (rs := rows("results_runs.csv")):
        for ykey, ylabel, title, fname, log in [
            ("lost", "lost", "State loss (RQ1)", "eval_state_loss.pdf", False),
            ("grace_s", "grace (s)", "Grace granted (RQ2)", "eval_grace_budget.pdf", True),
        ]:
            fig, ax = plt.subplots(figsize=(6.0, 3.2))
            needs = sorted({float(r["need_s"]) for r in rs})
            x = range(len(needs))
            w = 0.2
            for i, pol in enumerate(POLICIES):
                ys = [next((float(r[ykey]) for r in rs if r["policy"] == pol and float(r["need_s"]) == n), 0) for n in needs]
                ax.bar([xi + (i - 1.5) * w for xi in x], ys, w, label=LABELS[pol], color=COLORS[pol])
            ax.set_xticks(list(x)); ax.set_xticklabels([f"need≈{n:.0f}s" for n in needs])
            ax.set_ylabel(ylabel); ax.set_title(title)
            if log: ax.set_yscale("log")
            ax.legend(fontsize=8, ncol=2); ax.grid(axis="y", alpha=0.3)
            fig.tight_layout(); save(fig, fname)


if __name__ == "__main__":
    main()
