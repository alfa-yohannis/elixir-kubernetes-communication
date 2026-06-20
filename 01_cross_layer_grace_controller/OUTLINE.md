# Outline Paper M3 — Target: SP&E (Software: Practice and Experience)

> ⚠️ **SUPERSEDED — historical planning doc.** The actual paper is `paper/main.tex` (20 pages, built
> clean). It expanded beyond this plan: **RQ1–RQ7** (not RQ1–3) + **Proposition 1** (safety proof);
> the coordinator is a **`kubectl`-based GenServer operator, NOT Bonny**; the title is *"Closing the
> Grace Gap: …Zero-Loss Rolling Updates"*; and the reader-facing text uses **no "M3" label**. The
> venue strategy below is still current. Treat the section structure here as the original sketch.
>
> **Status (original):** draft outline. Target venue **SP&E** (Wiley) — Q2, IF 3,77, **hybrid (gratis via jalur
> langganan)**, scope *practical software engineering, runtime systems, deployment tooling, real-world
> experience*. (Catatan: JISA dicoret — jurnal sudah tutup.) Cadangan: **CCPE** (Wiley, Q2, gratis via
> langganan) lalu **The Journal of Supercomputing** (Springer, Q2, gratis via langganan, paling mudah ditembus).
> Mekanisme: **M3 — Grace ↔ Convergence ↔ Probe feedback controller** (lihat `report/mechanisms.tex` §M3, `report/problems.tex` Masalah 4).
>
> **Penekanan SP&E:** SP&E menilai *artefak + evaluasi dunia nyata* ("practice and experience"). M3 adalah
> pengendali nyata yang dibangun & diukur — pas. Konsekuensi: **Bagian 5 (Implementasi) & 6 (Evaluasi)
> harus dominan**; framing "pengalaman membangun & mengoperasikan" lebih kuat daripada teori.

---

## Judul kerja (di-frame untuk SP&E — "practice and experience")

Utama (menonjolkan artefak + pengalaman operasional):
*Grace-Aware Draining in Practice: Building and Operating an Adaptive
`terminationGracePeriodSeconds` Controller that Couples Kubernetes Pod Termination with BEAM
Cluster Convergence for Zero-Loss Rolling Updates*

Alternatif (lebih ringkas):
*Closing the Grace Gap: An Adaptive Termination-Grace Controller Coupling Kubernetes Pod
Termination with Horde Handoff and libcluster Convergence in Stateful Elixir/OTP Services*

---

## Tesis inti (1 kalimat)

`terminationGracePeriodSeconds` Kubernetes adalah **tenggat statis yang ditebak**, buta terhadap
*berapa lama BEAM benar-benar butuh* untuk men-*drain* dan menuntaskan *handoff* state (Horde) serta
konvergensi keanggotaan (libcluster); M3 menggantinya dengan **pengendali umpan-balik lintas-lapis**
yang menetapkan grace dari sinyal konvergensi runtime secara real-time, sehingga `SIGKILL` tidak
pernah memutus *handoff* (tanpa kehilangan state) tanpa memperlambat *rollout* secara berlebihan.

---

## 1. Pendahuluan

- **Konteks:** layanan stateful Elixir/OTP (Horde untuk *distributed process registry*/*supervisor*,
  `:global`, Phoenix.Presence/PubSub) di atas Kubernetes; *rolling update* & *node drain* adalah
  operasi rutin yang memindahkan state antar-pod.
- **Friksi (Masalah 4 dari report):** siklus terminasi K8s `SIGTERM → preStop → grace → SIGKILL`
  memakai tenggat **tetap** (default 30 s). Jika grace **terlalu pendek** → `SIGKILL` membunuh pod
  saat *handoff* belum selesai → **state hilang / proses singleton menghilang**. Jika grace
  **terlalu panjang** → setiap pod menahan *rollout* → *deploy* lambat & mahal.
- **Gap:** grace ditetapkan saat *deploy-time* sebagai konstanta; ia tidak tahu *backlog handoff*
  atau waktu konvergensi yang **bervariasi menurut beban** (jumlah proses stateful, laju CRDT sync,
  ukuran cluster). preStop hook hanya bisa "tidur" sekian detik — juga buta.
- **Kontribusi (eksplisit, 4 butir):**
  1. Formalisasi *grace-safety invariant* lintas-lapis: terminasi aman ⇔ grace ≥ waktu *drain* +
     *handoff backlog*/laju + waktu konvergensi.
  2. Rancangan **pengendali M3**: operator (Bonny) + preStop hook + sinyal konvergensi dari BEAM,
     yang menghitung grace **dinamis** per-pod dan men-*pace* `maxUnavailable`.
  3. Implementasi referensi (Elixir + Horde + libcluster + manifest K8s).
  4. Evaluasi empiris: grace statis (30 s, over-provisioned 300 s) vs **M3 adaptif**, di bawah
     *rolling update* / *node drain* dengan beban handoff bervariasi.

## 2. Latar Belakang & Motivasi

- Ringkas dari report: siklus hidup terminasi pod (SIGTERM/preStop/grace/SIGKILL),
  `terminationGracePeriodSeconds`, *rolling update* & `maxUnavailable`, *node drain*/eviction.
- BEAM: Horde (CRDT registry + handoff *process state*), libcluster (pembentukan & konvergensi
  keanggotaan), `:global` re-registrasi.
- **Skenario motivasi konkret** — angkat *walkthrough* + tabel timeline Masalah 4 dari
  `report/problems.tex` (3.4.1): pod di-*drain*, grace 30 s, tetapi *handoff* 1.200 prong Horde
  butuh ~45 s → `SIGKILL` pada detik 30 → 600 proses singleton hilang sampai cluster
  re-konvergen. Tandai nama aplikasi skenario sebagai ilustratif/hipotetis.

## 3. Model Sistem & Definisi Masalah

- Model: pod $p$ memegang himpunan proses stateful $H_p$; laju *handoff* $\rho$ (proses/detik);
  waktu konvergensi keanggotaan $T_c$; waktu *drain* koneksi *in-flight* $T_d$.
- **Grace-safety invariant:**
  $g \ge T_d + |H_p|/\rho + T_c$. Grace statis $g_0$ melanggar invariant ketika beban naik
  ($|H_p|$ besar) atau $\rho$ turun (cluster sibuk).
- *Counterexample* (dari timeline Masalah 4): tunjukkan $g_0 = 30 < T_d + |H_p|/\rho + T_c$.
- Trade-off: over-provisioning ($g_0 = 300$) memenuhi invariant tapi melanggar tujuan *rollout cepat*.

## 4. Rancangan M3 (inti "practice")

- **Arsitektur (tiga komponen):**
  1. **Probe konvergensi BEAM** — pod mengekspos endpoint/metrik: `handoff_backlog`, laju $\rho$
     teramati, status konvergensi libcluster, daftar `:global`/Horde yang belum stabil.
  2. **preStop hook adaptif** — saat SIGTERM, men-*drain* lalu **blokir** sampai
     `HandoffPending()` habis (bukan `sleep` tetap); melapor balik laju aktual.
  3. **Operator (Bonny)** — sebelum *rollout*, hitung $g = \max(|H|/\rho,\ T_c,\ g_{\min})$,
     set `terminationGracePeriodSeconds` per-pod, dan **pace** `maxUnavailable` mengikuti laju
     *handoff* (perlambat *rollout* bila *handoff* melambat).
- **Algoritma keputusan** — angkat Algoritma `alg:m3` dari `mechanisms.tex`, perhalus:
  loop kendali yang memperpanjang $g$ / memperlambat *rollout* bila *handoff* melambat hingga tuntas.
- **Fail-safe:** batas atas $g_{\max}$ (agar pod *zombie* tetap dibunuh); default-deny vs default-allow
  saat probe konvergensi tak terjawab; interaksi dengan PDB (rujuk M7 sebagai komplementer).
- **Diagram:** pakai 2 diagram M3 yang sudah ada (`diagrams/mechanisms/m3-*` — sequence & activity).

## 5. Implementasi

- Stack: Elixir + Horde + libcluster + Bonny; manifest K8s (Deployment, preStop `exec`/HTTP hook,
  RBAC untuk operator membaca/menulis pod, readiness gate).
- Detail rekayasa: cara mengukur `handoff_backlog` & $\rho$, *smoothing*/EWMA laju, debounce,
  penetapan grace per-pod (patch ke Deployment vs anotasi), penanganan *node drain* mendadak.

## 6. Evaluasi (wajib kuat & dominan — SP&E menilai bukti empiris/pengalaman dunia nyata)

- **RQ1 (correctness):** Seberapa sering grace statis (30 s) menyebabkan *handoff* terpotong /
  state hilang di bawah beban berbeda? Apakah M3 menghilangkannya?
- **RQ2 (efficiency):** Berapa overhead *rollout* M3 vs over-provisioning (300 s)? (total durasi
  *rolling update*, p50/p99 grace yang benar-benar dipakai).
- **RQ3 (adaptivity):** Apakah M3 melacak perubahan beban (lonjakan $|H|$, penurunan $\rho$) tanpa
  *deadlock* (terminasi tak pernah selesai) dan tanpa pod zombie?
- **Setup:** cluster kind/k3s; beban stateful (mis. ArenaServer dari report, atau registry Horde
  sintetis) dengan $|H|$ divariasikan; *fault injection*: drain berulang, node kill, throttle CPU
  untuk menurunkan $\rho$.
- **Metrik:** jumlah proses/state hilang; durasi total *rolling update*; grace aktual vs invariant;
  p99 *handoff completion*; jumlah `SIGKILL` prematur.
- **Baseline:** (a) grace statis 30 s, (b) grace over-provisioned 300 s, (c) preStop `sleep` tetap,
  (d) **M3 adaptif**.

## 7. Diskusi & Ancaman Validitas

- Batas: akurasi estimasi $\rho$/backlog; beban yang sangat *bursty*; node mati mendadak
  (non-graceful) di luar cakupan M3 (ranah mekanisme lain).
- Generalisasi: prinsip "grace = fungsi sinyal konvergensi runtime" berlaku untuk Akka
  (CoordinatedShutdown), Orleans (graceful deactivation) — bandingkan, posisikan M3 sebagai
  generalisasi lintas-lapis yang eksplisit.

## 8. Related Work

Dari hasil riset agen (simpan untuk sitiran):
- **Souza, Neves & Kimura (JISA 2024)** — *Dependable Microservices in the Kubernetes Era* →
  survei celah dependability di K8s; posisikan M3 sebagai mekanisme konkret untuk salah satu celah itu
  (handoff stateful saat terminasi). (Sitiran, bukan venue target.)
- **SP&E special issue 2024** — *Efficient Management of Microservice-Based Systems and Applications*
  → bukti scope SP&E selaras dengan M3; sitir 1–2 paper di dalamnya.
- **RTilience (IEEE TSC 2025)**, **Cluster Computing 2025 (Istio resilience)**,
  **Resiliency-focused proactive lifecycle for stateful microservices (Computer Communications 2025)**,
  **eBPF-Shield (SOCA 2025/26)** — semuanya menangani resiliensi/handoff stateful **generik**,
  tetapi **tak satu pun mengikat `terminationGracePeriodSeconds` ke sinyal konvergensi runtime**
  → justru gap M3.
- Akka CoordinatedShutdown / Lease, Glasgow SCM (partially-covered untuk M1/M9), Nefele — pembanding.

## 9. Kesimpulan & Kerja Mendatang

- Tutup; arahkan ke M6 (single-spec compiler), M7 (PDB↔quorum), M8 (restart-budget↔backoff) sebagai
  agenda koordinasi lintas-lapis yang lebih besar.

---

## Catatan venue (SP&E)

- **Q2 (Scopus & WoS), IF 3,77, CiteScore 4,8** — Wiley. **Hybrid:** gratis terbit via jalur langganan
  (paper di balik *paywall*); OnlineOpen OA opsional ~$4.880 (tidak perlu diambil).
- Scope cocok: *practical software engineering, runtime systems, deployment tooling, real-world
  experience* — M3 (membangun + mengoperasikan + mengukur pengendali) pas. Special issue
  *Microservice-Based Systems* (2024) menegaskan kesesuaian.
- **Syarat lolos:** evaluasi & implementasi harus tebal dan kredibel (artefak nyata, hasil dunia
  nyata) — lebih selektif daripada jurnal Q2 lain. Sediakan artefak/replikasi (mis. repo + manifest).
- Format: ikuti *Wiley / SP&E author guidelines* (template LaTeX Wiley NJD tersedia).
- **Cadangan:** **CCPE** (Wiley, Q2, gratis via langganan, lebih longgar) → **The Journal of
  Supercomputing** (Springer, Q2, gratis via langganan, LetPub "Easy" — paling mudah ditembus).
  Runner-up **SN Computer Science** (Springer, Q2, gratis via langganan, akseptansi tinggi).
