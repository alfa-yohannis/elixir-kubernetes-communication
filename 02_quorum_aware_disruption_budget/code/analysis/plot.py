#!/usr/bin/env python3
"""Render figur evaluasi M7 dari data/*.csv (pengukuran NYATA) ke figures/*.pdf.

Jalankan:  ~/venv/bin/python code/analysis/plot.py
Semua angka berasal dari harness (harness/run.exs untuk RQ1/RQ2; harness/policy.exs untuk RQ3-RQ6).
"""
import csv
import os
import statistics

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
DATA = os.path.join(ROOT, "data")
FIGS = os.path.join(ROOT, "figures")
os.makedirs(FIGS, exist_ok=True)

# Warna konsisten: merah = tak aman (static), hijau = aman (quorum-aware).
C_UNSAFE = "#C0392B"
C_SAFE = "#2E7D32"
C_NEUTRAL = "#1F3B73"


def rows(name):
    with open(os.path.join(DATA, name)) as f:
        return list(csv.DictReader(f))


def save(fig, name):
    fig.tight_layout()
    fig.savefig(os.path.join(FIGS, name))
    plt.close(fig)
    print("wrote", os.path.join(FIGS, name))


def safety_fig():
    """RQ1: ukuran cluster tersedia minimum (terukur) vs ambang kuorum, static vs quorum-aware."""
    rs = rows("results_safety.csv")
    ns = sorted({int(r["n"]) for r in rs})
    by = {(r["policy"], int(r["n"])): r for r in rs}
    qline = [int(by[("static", n)]["q"]) for n in ns]
    static = [int(by[("static", n)]["min_available"]) for n in ns]
    qa = [int(by[("quorum_aware", n)]["min_available"]) for n in ns]

    x = range(len(ns))
    w = 0.38
    fig, ax = plt.subplots(figsize=(6.2, 3.3))
    ax.bar([i - w / 2 for i in x], static, w, label="static PDB (quorum-unaware)", color=C_UNSAFE)
    ax.bar([i + w / 2 for i in x], qa, w, label="quorum-aware (ours)", color=C_SAFE)
    # Garis kuorum per ukuran cluster (ambang yang harus dipertahankan).
    for i, q in zip(x, qline):
        ax.plot([i - 0.5, i + 0.5], [q, q], color="black", lw=1.2, ls="--",
                label="quorum threshold $Q$" if i == 0 else None)
    ax.set_xticks(list(x))
    ax.set_xticklabels([f"$N={n}$" for n in ns])
    ax.set_ylabel("min. available members\n(measured during rollout)")
    ax.set_title("Quorum safety under a rolling update")
    ax.legend(fontsize=8, loc="upper left")
    ax.grid(axis="y", alpha=0.3)
    save(fig, "eval_safety.pdf")


def efficiency_fig():
    """RQ2: waktu maintenance (rolling update penuh) konservatif vs quorum-aware (mean +/- rentang)."""
    rs = rows("results_efficiency.csv")
    pols = ["conservative", "quorum_aware"]
    labels = {"conservative": "conservative\n(maxUnavail=1)", "quorum_aware": "quorum-aware\n(ours)"}
    means, errs, cols = [], [], []
    for p in pols:
        ms = [float(r["maintenance_ms"]) / 1000 for r in rs if r["policy"] == p]
        means.append(statistics.mean(ms))
        errs.append((max(ms) - min(ms)) / 2)
        cols.append(C_NEUTRAL if p == "conservative" else C_SAFE)
    fig, ax = plt.subplots(figsize=(4.2, 3.3))
    ax.bar([labels[p] for p in pols], means, yerr=errs, capsize=4, color=cols)
    for i, m in enumerate(means):
        ax.text(i, m, f" {m:.2f}s", ha="center", va="bottom", fontsize=9)
    ax.set_ylabel("rollout time (s)")
    ax.set_title("Maintenance time ($N=9$, both quorum-safe)")
    ax.grid(axis="y", alpha=0.3)
    save(fig, "eval_efficiency.pdf")


def adaptivity_fig():
    """RQ3: min_available (= minAvailable yang diberikan) melacak kuorum mayoritas saat N berubah."""
    rs = rows("results_scale.csv")
    ns = [int(r["n"]) for r in rs]
    mina = [int(r["min_available"]) for r in rs]
    maxu = [int(r["max_unavailable"]) for r in rs]
    fig, ax = plt.subplots(figsize=(5.6, 3.3))
    ax.plot(ns, mina, "o-", color=C_SAFE, label="minAvailable granted ($=Q$)")
    ax.plot(ns, maxu, "s--", color=C_NEUTRAL, label="maxUnavailable ($=N-Q$)")
    ax.set_xscale("log")
    ax.set_yscale("log")
    ax.set_xlabel("cluster size $N$ (log)")
    ax.set_ylabel("pods (log)")
    ax.set_title("Budget tracks majority quorum as $N$ scales")
    ax.legend(fontsize=8)
    ax.grid(alpha=0.3, which="both")
    save(fig, "eval_adaptivity.pdf")


def scale_fig():
    """RQ4/RQ6: latensi hitung budget tetap ~konstan (O(1)) saat N tumbuh 3 -> 10001."""
    rs = rows("results_scale.csv")
    ns = [int(r["n"]) for r in rs]
    ns_lat = [float(r["budget_compute_ns"]) for r in rs]
    fig, ax = plt.subplots(figsize=(5.6, 3.3))
    ax.plot(ns, ns_lat, "o-", color=C_NEUTRAL)
    ax.set_xscale("log")
    ax.set_ylim(0, max(ns_lat) * 1.6)
    ax.set_xlabel("cluster size $N$ (log)")
    ax.set_ylabel("budget compute (ns/call)")
    ax.set_title("Controller cost is $O(1)$ in cluster size")
    ax.grid(alpha=0.3, which="both")
    save(fig, "eval_scale.pdf")


def sensitivity_fig():
    """RQ5: budget vs estimasi kuorum q (N=9). Under-estimasi q -> max_unavailable besar (tak aman)."""
    rs = rows("results_sensitivity.csv")
    qs = [int(r["q"]) for r in rs]
    maxu = [int(r["max_unavailable"]) for r in rs]
    true_q = 5  # mayoritas dari 9
    fig, ax = plt.subplots(figsize=(5.6, 3.3))
    ax.plot(qs, maxu, "o-", color=C_NEUTRAL)
    ax.axvline(true_q, color=C_SAFE, ls="--", lw=1.2, label="true quorum $Q=5$")
    ax.axvspan(0.5, true_q - 0.5, alpha=0.12, color=C_UNSAFE)
    ax.text(2.4, max(maxu) * 0.7, "under-estimate $Q$\n= unsafe\n(too many evictions)",
            color=C_UNSAFE, fontsize=8, ha="center")
    ax.set_xlabel("quorum estimate $q$ (true $Q=5$)")
    ax.set_ylabel("maxUnavailable granted")
    ax.set_title("Sensitivity to the quorum estimate ($N=9$)")
    ax.legend(fontsize=8)
    ax.grid(alpha=0.3)
    save(fig, "eval_sensitivity.pdf")


def main():
    safety_fig()
    efficiency_fig()
    adaptivity_fig()
    scale_fig()
    sensitivity_fig()


if __name__ == "__main__":
    main()
