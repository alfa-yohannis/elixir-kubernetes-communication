#!/usr/bin/env python3
"""Membuat figur evaluasi dari data/*.csv ke dalam figures/ (untuk paper).

Skrip ini membaca file CSV hasil eksperimen di folder ../../data dan menggambar grafiknya dengan
matplotlib, lalu menyimpannya sebagai PDF di ../../figures. Setiap fungsi `*_fig`/`*_curves`
menghasilkan satu (atau sepasang) gambar untuk satu research question.

Jalankan:  ~/venv/bin/python code/analysis/plot.py   (path dihitung relatif terhadap file ini)
Hanya menggambar yang datanya ada; CSV yang belum dibuat dilewati."""
import csv
import os
import statistics as st

import matplotlib
# "Agg" = backend non-interaktif (menggambar ke file, bukan ke layar) — wajib di server tanpa GUI.
matplotlib.use("Agg")
import matplotlib.pyplot as plt

# Path penting, dihitung relatif terhadap lokasi file ini, agar skrip bisa dijalankan dari mana saja.
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
DATA = os.path.join(ROOT, "data")
FIGS = os.path.join(ROOT, "figures")

# Empat policy yang dibandingkan, beserta label, warna, dan bentuk penanda (marker) yang konsisten
# di semua grafik supaya mudah dikenali.
POLICIES = ["static30", "static300", "prestop_sleep", "m3"]
LABELS = {"static30": "fixed 30 s", "static300": "fixed 300 s",
          "prestop_sleep": "preStop 30 s", "m3": "adaptive (ours)"}
COLORS = {"static30": "#C0504D", "static300": "#9BBB59",
          "prestop_sleep": "#E8A33D", "m3": "#1F3B73"}
MARK = {"static30": "o", "static300": "s", "prestop_sleep": "^", "m3": "D"}


def rows(name):
    """Membaca satu file CSV di folder data/ menjadi list of dict (satu dict per baris).

    Mengembalikan None bila file belum ada, sehingga main() bisa melewati figur yang datanya
    belum dibuat."""
    p = os.path.join(DATA, name)
    if not os.path.exists(p):
        return None
    with open(p) as f:
        return list(csv.DictReader(f))


def save(fig, name):
    """Menyimpan sebuah figur matplotlib sebagai PDF di folder figures/, lalu menutupnya (agar
    memori dibebaskan) dan mencetak path file yang ditulis."""
    os.makedirs(FIGS, exist_ok=True)
    fig.savefig(os.path.join(FIGS, name))
    plt.close(fig)
    print("wrote", os.path.join(FIGS, name))


def agg(rs, pol, xkey, ykey):
    """Menghitung rata-rata dan simpangan baku `ykey` yang dikelompokkan per nilai `xkey`, untuk
    satu `pol` (policy), di seluruh pengulangan (repeats). Mengembalikan (xs, means, stds)."""
    # Kumpulkan nilai-x unik (terurut) yang muncul untuk policy ini.
    xs = sorted({float(r[xkey]) for r in rs if r["policy"] == pol})
    means, stds = [], []
    for x in xs:
        # Semua nilai-y pada (policy, x) tertentu -> rata-rata + simpangan baku populasi.
        vals = [float(r[ykey]) for r in rs if r["policy"] == pol and float(r[xkey]) == x]
        means.append(st.mean(vals))
        stds.append(st.pstdev(vals) if len(vals) > 1 else 0.0)
    return xs, means, stds


def sweep_curves(rs):
    """Menggambar dua kurva sweep beban (RQ1 & RQ2): state yang hilang vs kebutuhan handoff, dan
    grace yang diberikan vs kebutuhan handoff, untuk keempat policy (dengan error bar)."""
    for ykey, ylabel, title, fname, log in [
        ("lost", "stateful processes lost", "State loss vs. handoff need (RQ1)", "eval_sweep_loss.pdf", False),
        ("grace_s", "grace granted (s)", "Grace granted vs. handoff need (RQ2)", "eval_sweep_grace.pdf", True),
    ]:
        fig, ax = plt.subplots(figsize=(6.0, 3.6))
        # Satu garis per policy; error bar dari simpangan baku antar-repeat.
        for pol in POLICIES:
            xs, m, s = agg(rs, pol, "need_target", ykey)
            if xs:
                ax.errorbar(xs, m, yerr=s, marker=MARK[pol], color=COLORS[pol],
                            label=LABELS[pol], capsize=3, linewidth=1.6)
        # Garis putus-putus menandai grace tetap 30 s sebagai acuan.
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
    """Diagram batang waktu rolling-update end-to-end per policy (RQ2), dengan anotasi berapa
    proses yang hilang di tiap batang."""
    pols = [r["policy"] for r in rs]
    secs = [float(r["rollout_ms"]) / 1000 for r in rs]
    lost = [int(float(r["lost"])) for r in rs]
    fig, ax = plt.subplots(figsize=(5.2, 3.4))
    bars = ax.bar([LABELS.get(p, p) for p in pols], secs,
                  color=[COLORS.get(p, "#888") for p in pols])
    # Tulis "lost N" di atas tiap batang (merah bila ada yang hilang, biru bila 0).
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
    """Tiga panel sensitivitas grace (RQ5): bagaimana grace berubah terhadap margin sigma, batas
    atas g_max, dan kesalahan estimasi laju (rho_hat/rho)."""
    kinds = [("sigma", "safety margin $\\sigma$ (s)"),
             ("g_max", "upper bound $g_{max}$ (s)"),
             ("rho_error", "rate estimate factor ($\\hat\\rho/\\rho$)")]
    fig, axes = plt.subplots(1, 3, figsize=(8.2, 2.8))
    # Satu panel per jenis "knob"; titik-titik diurutkan menurut nilai-x.
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
    """Validasi invariant (RQ1): grace yang diberikan vs kebutuhan handoff, dengan garis-aman
    g = |H|/rho. Titik DI ATAS garis = aman (grace menutupi handoff); grace tetap akan jatuh DI
    BAWAH garis begitu kebutuhan melewatinya (kehilangan state ditandai lingkaran merah)."""
    fig, ax = plt.subplots(figsize=(6.2, 3.8))
    needs = sorted({float(r["need_target"]) for r in rs})
    hi = max(needs)
    # Garis diagonal = lantai keselamatan; area di bawahnya (tidak aman) diarsir tipis.
    ax.plot([0, hi * 1.12], [0, hi * 1.12], ls="--", color="gray", lw=1.3,
            label="safety floor $g=|H|/\\rho$", zorder=1)
    ax.fill_between([0, hi * 1.12], [0, hi * 1.12], 0, color="#C0504D", alpha=0.06)
    ax.text(hi * 0.62, hi * 0.30, "unsafe\n(handoff truncated)", color="#C0504D",
            fontsize=8, ha="center")
    for pol in POLICIES:
        if pol == "static300":
            continue  # nilainya 300 s, di luar grafik; dianotasi terpisah
        xs, m, _ = agg(rs, pol, "need_target", "grace_s")
        if not xs:
            continue
        ax.plot(xs, m, marker=MARK[pol], color=COLORS[pol], label=LABELS[pol], lw=1.7, zorder=3)
        # Lingkari titik yang mengalami kehilangan state (lossy) dengan cincin merah.
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
    """Konvergensi Phoenix.Tracker/Presence vs jumlah presence (RQ8: beban kerja Phoenix realistis).
    Menampilkan T_c nyata (re-konvergensi setelah sebuah node pergi) dibanding estimasi naif 50 ms."""
    n = [int(float(r["n"])) for r in rs]
    add = [float(r["add_ms"]) / 1000 for r in rs]
    rec = [float(r["reconverge_ms"]) / 1000 for r in rs]
    fig, ax = plt.subplots(figsize=(6.0, 3.6))
    ax.plot(n, add, marker="o", color="#3C7D3C", label="add-convergence")
    ax.plot(n, rec, marker="D", color="#1F3B73",
            label="re-convergence after departure ($T_c$)")
    # Garis acuan = estimasi heuristik 50 ms, untuk menunjukkan selisihnya dengan nilai nyata.
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
    """Latensi antar-pod NYATA (tc netem di kind, RQ7): delay yang disuntik vs RTT terukur, lalu
    bagaimana laju handoff yang bisa dicapai (~1/RTT) dan grace yang dihasilkan ikut berubah."""
    d = [float(r["delay_ms"]) for r in rs]
    rtt = [float(r["rtt_ms"]) for r in rs]
    rate = [float(r["rate_eps"]) for r in rs]
    grace = [float(r["grace_s"]) for r in rs]
    fig, (a1, a2) = plt.subplots(1, 2, figsize=(8.4, 3.3))
    # Panel kiri: delay yang disuntik vs RTT terukur (garis y=x membuktikan injeksinya nyata).
    a1.plot(d, rtt, marker="o", color="#1F3B73")
    a1.plot([0, max(d)], [0, max(d)], ls="--", color="gray", lw=1, label="$y=x$")
    a1.set_xlabel("injected one-way delay (ms)")
    a1.set_ylabel("measured inter-pod RTT (ms)")
    a1.set_title("Latency injection is real")
    a1.legend(fontsize=8)
    a1.grid(alpha=0.3)
    # Panel kanan: laju (skala log, ambruk) dan grace (sumbu kanan, naik ke batas g_max).
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
    """Skalabilitas per-node (RQ6): saat backlog |H| dinaikkan, gambar waktu handoff & throughput
    (panel kiri) serta memori yang bertambah (panel kanan)."""
    H = [int(float(r["backlog"])) for r in rs]
    drain = [float(r["drain_ms"]) / 1000 for r in rs]
    thr = [float(r["throughput_eps"]) for r in rs]
    mem = [float(r["mem_mb"]) for r in rs]
    fig, (a1, a2) = plt.subplots(1, 2, figsize=(8.0, 3.2))
    # Panel kiri: waktu handoff (sumbu kiri) dan throughput (sumbu kanan) vs |H|.
    a1.plot(H, drain, marker="o", color="#1F3B73")
    a1.set_xlabel("$|H|$ (stateful processes)")
    a1.set_ylabel("handoff time (s)", color="#1F3B73")
    a1b = a1.twinx()
    a1b.plot(H, thr, marker="s", color="#C0504D")
    a1b.set_ylabel("throughput (proc/s)", color="#C0504D")
    a1.set_title("Handoff scaling")
    a1.grid(alpha=0.3)
    # Panel kanan: memori yang bertambah vs |H| (tumbuh linear & murah).
    a2.plot(H, mem, marker="D", color="#3C7D3C")
    a2.set_xlabel("$|H|$ (stateful processes)")
    a2.set_ylabel("memory added (MiB)")
    a2.set_title("Memory scaling")
    a2.grid(alpha=0.3)
    fig.tight_layout()
    save(fig, "eval_scale.pdf")


def main():
    """Titik masuk: untuk tiap CSV yang ada, panggil fungsi penggambar yang sesuai. CSV yang belum
    dibuat otomatis dilewati (lihat `rows`)."""
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
    # Figur dua-load asli (dipertahankan sebagai referensi/RQ1-RQ2 versi awal).
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
