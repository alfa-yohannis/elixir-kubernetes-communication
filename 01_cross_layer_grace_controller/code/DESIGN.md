# Prototipe: Analisis → Kebutuhan → Desain → Validasi

Implementasi acuan (reference implementation) dari **controller grace-convergence** pada paper. Dokumen
ini adalah dasar rekayasa (engineering basis) untuk kode di bawah `code/`. Urutan pembangunan bersifat bottom-up dan
**dapat divalidasi secara lokal terlebih dahulu** (BEAM multi-node pada satu host, tanpa Kubernetes), lalu Kubernetes.

---

## 1. Analisis

**Masalah (dari paper).** Selama rolling update atau pengurasan (drain) node, sebuah pod yang sedang dimatikan harus
*menguras (drain)*, *melakukan handoff* proses statefulnya, dan membiarkan cluster *ber-konvergensi ulang* dalam batas waktu
`terminationGracePeriodSeconds` yang tetap. Jika grace tetap itu lebih pendek dari waktu yang (bergantung-beban) benar-benar
dibutuhkan, `SIGKILL` memotong handoff dan state hilang; jika disetel terlalu tinggi demi keamanan,
setiap rollout menjadi lambat. Informasi yang seharusnya menentukan ukuran deadline berada di runtime; sedangkan kontrol
yang menegakkannya berada di orchestrator; tidak ada yang menghubungkan keduanya.

**Apa yang harus didemonstrasikan prototipe (dipetakan ke RQ1–RQ7 paper).**
- **RQ1 (kebenaran):** grace tetap 30 s memotong handoff dan kehilangan state di bawah beban;
  controller menghilangkan kehilangan itu.
- **RQ2 (efisiensi):** waktu grace/rollout controller jauh di bawah grace over-provisioned 300 s.
- **RQ3 (adaptivitas):** controller mengikuti perubahan beban (lonjakan backlog, penurunan rate) tanpa
  deadlock atau pod zombie.
- **RQ4 (overhead):** latensi probe, memori per-proses, throughput handoff, footprint operator.
- **RQ5 (ketahanan/robustness):** sensitivitas grace terhadap σ, batas-batas g, dan galat estimasi-ρ.
- **RQ6 (skalabilitas):** bagaimana biaya handoff menskala dengan \|H\| per-node, dan di mana plafon per-node-nya.
- **RQ7 (realisme jaringan):** di bawah latensi antar-pod nyata, apakah ρ (dan grace) mengikuti throughput handoff
  yang terdegradasi? Didukung oleh `Proposition 1`: policy terbukti memenuhi invarian grace-safety
  di bawah estimasi rate yang konservatif.
- **RQ8 (beban kerja realistis):** apakah mekanisme bertahan pada fitur terdistribusi Phoenix yang tidak dimodifikasi
  (Phoenix.Presence / Phoenix.Tracker), dan berapa waktu konvergensi nyata `T_c` yang harus dicakup grace?

**Besaran terukur yang harus kita hasilkan (data nyata → `../data/`):** proses stateful yang hilang,
durasi total rolling-update, waktu penyelesaian handoff p50/p99, jumlah `SIGKILL` prematur,
grace yang benar-benar dipakai vs. batas bawah keamanan.

**Realita lingkungan.** Elixir/Erlang/Docker tersedia; `kind`/`kubectl`/`helm` belum terpasang
(lihat README tingkat-atas). Logika inti handoff/konvergensi/grace dapat divalidasi pada **cluster BEAM
multi-node lokal** (beberapa node `iex`/rilis pada satu host melalui EPMD) sebelum Kubernetes
terlibat — ini mengurangi risiko logika tersulit sejak dini.

---

## 2. Kebutuhan

### Fungsional
- **FR1 — Beban kerja stateful.** Sebuah registry terdistribusi-horde dari proses stateful (`StatefulWorker`)
  yang state in-memory-nya harus bertahan saat sebuah node pergi melalui handoff Horde. Jumlah `|H|` dapat dikonfigurasi.
- **FR2 — Convergence probe.** Sebuah endpoint read-only yang mengekspos, per node: handoff backlog `B`
  (proses yang masih harus dipindahkan), rate handoff `ρ` teramati (EWMA), state membership/konvergensi, dan
  estimasi waktu konvergensi `T_c`. (HTTP + API in-VM.)
- **FR3 — Komputasi grace.** Diberikan nilai-nilai probe, hitung
  `g = clamp(T_d + B/ρ + T_c + σ, g_min, g_max)` (Persamaan 2 paper dengan margin σ dan batas-batas).
- **FR4 — Terminasi adaptif.** Saat `SIGTERM`, lakukan drain, lalu **blokir sampai handoff backlog kosong**
  (bukan sleep tetap), dibatasi oleh `g_max`; laporkan penyelesaian.
- **FR5 — Koordinator/operator.** Menyetel `terminationGracePeriodSeconds = g` per-pod dan mengatur ritme (pace)
  rollout (mengizinkan pod berikutnya hanya saat pod saat ini melaporkan handoff selesai atau `g` berlalu).
- **FR6 — Baseline.** Policy terminasi yang dapat dipilih: `static30`, `static300`, `prestop_sleep`,
  `m3` (adaptif) — agar harness dapat membandingkan keempatnya.
- **FR7 — Harness.** Menjalankan rolling update / drain berulang, menyuntikkan gangguan (mematikan node, men-throttle CPU
  untuk menurunkan ρ, melonjakkan `|H|`), dan mengumpulkan metrik §1 ke dalam CSV di bawah `../data/`.

### Non-fungsional
- **NFR1 — Fail-safe:** probe yang tidak tersedia/tidak masuk akal ⇒ jatuh kembali (fall back) ke grace konservatif yang dikonfigurasi
  (aman-secara-default). `g_min`/`g_max` membatasi kedua arah; penetapannya idempoten.
- **NFR2 — Overhead rendah:** probe bebas efek-samping; penghalusan (smoothing) rate berkompleksitas O(1).
- **NFR3 — Reproduksibilitas:** `make reproduce` menghasilkan ulang semua CSV dan figur; dependensi dipatok (pinned).
- **NFR4 — Berjalan pada mesin dev:** kind/k3s satu host (i9, 30 GB) sudah cukup.
- **NFR5 — Tanpa data fabrikasi:** setiap baris CSV berasal dari run nyata.

---

## 3. Desain

### Peran → komponen (cocok dengan Tabel `tab:roles` paper)
| Peran | Komponen (modul / artefak) |
|---|---|
| Membership layer | topologi `libcluster` (`Cluster.Strategy.Kubernetes` in-cluster; `Epmd`/`Gossip` secara lokal) |
| Registry & handoff layer | `Horde.Registry` + `Horde.DynamicSupervisor` yang menampung `StatefulWorker` |
| Convergence probe | `GraceConvergence.Probe` (+ endpoint Plug/Bandit `GraceConvergence.ProbeHTTP`) |
| Adaptive termination hook | `GraceConvergence.Shutdown` (men-trap shutdown, memblokir sampai backlog terkuras) |
| Coordinator (operator) | `GraceConvergence.Operator` — loop rekonsiliasi GenServer yang memanggil `kubectl` (System.cmd) untuk membaca pods dan menambal TGPS (**bukan** Bonny) |
| Grace-convergence controller | `GraceConvergence.Grace` (policy `g = clamp(...)`) |

### Struktur data / antarmuka kunci
- **Pembacaan probe** (JSON + struct): `{node, backlog, rate_eps, converged?, t_c_ms, in_flight}`.
- **Policy grace:** `Grace.compute(reading, %{sigma, g_min, g_max, t_d}) -> g_seconds`.
- **Protokol shutdown:** saat `:terminate`/SIGTERM → `Shutdown.drain()` lalu
  `Shutdown.await_handoff(timeout: g_max)` melakukan loop pada `Probe.backlog/0` sampai 0.
- **Pengalih policy (FR6):** konfigurasi `:grace_policy` = `:static30 | :static300 | :prestop_sleep | :m3`.

### Pembentukan cluster local-first
- Secara lokal: strategi Epmd/Gossip `libcluster` membentuk cluster berisi `n` node bernama pada satu host; Horde
  menyebarkan `StatefulWorker`; mematikan sebuah node memicu handoff — memungkinkan kita mengukur `ρ`, `B`, `T_c`
  **tanpa Kubernetes**.
- Di Kubernetes: tukar libcluster ke strategi Kubernetes; operator menambal TGPS dan mengatur ritme (pace).

### Formula grace (satu sumber kebenaran)
```
g* = T_d + B/ρ + T_c + σ
g  = min(g_max, max(g_min, g*))
```
`T_d` diukur saat awal drain; `B`,`ρ`,`T_c` dari probe; `σ` margin keamanan.

---

## 4. Rencana validasi (validasi desain sebelum/bersama pengembangan)

- **V1 — Logika, lokal, tanpa k8s:** unit test untuk `Grace.compute` (batas, fallback) dan sebuah
  integration test yang menjalankan `n` node BEAM lokal, mendaftarkan `|H|` worker, mematikan satu node, dan
  memastikan bahwa (a) Horde melakukan handoff semua worker, (b) `Probe.backlog` kembali ke 0, (c) `await_handoff`
  kembali sebelum `g_max`. Ini memvalidasi invarian inti secara murah.
- **V2 — Harness perbandingan policy, lokal:** jalankan keempat policy (FR6) terhadap skenario kill/handoff
  yang di-script dengan `|H|` bervariasi dan `ρ` yang di-throttle; keluarkan CSV; konfirmasi `static30` kehilangan state saat
  `B/ρ > 30 s` sedangkan `m3` tidak — klaim sentral.
- **V3 — Kubernetes:** deploy app + operator pada `kind`, jalankan rolling update, dan reproduksi V2 pada
  cluster nyata (dideklarasikan ter-emulasi satu-host — ancaman terhadap validitas). **DONE** (termasuk skala 6-replika).
- **V4 — Ketelitian statistik:** ulangi skenario utama (tabel N=10, rollout N=5, `repeats.exs`)
  dan laporkan mean ± 95% CI. **DONE** — loss/grace persis dapat direproduksi (CI=0), drain ±0.003 s.
- **V5 — Latensi jaringan nyata (RQ7):** suntikkan `tc netem` pada pod kind (`k8s/netem.sh`) dan konfirmasi
  RTT terukur menggerakkan ρ dan grace. **DONE** — ρ≈1/RTT runtuh, grace jenuh di g_max melewati ~100 ms.
- **V6 — Injeksi fail-safe:** crash-kan operator, beri probe yang tidak dapat dipakai, cabut RBAC API
  (`k8s/faults.sh`); konfirmasi degradasi konservatif. **DONE** — pemulihan / fallback g_max / tanpa crash.
- **V7 — Beban kerja realistis (Phoenix.Presence):** lacak N presence pada `Phoenix.Tracker`, kuras sebuah
  node, ukur konvergensi-ulang nyata T_c (`harness/presence.exs`). **DONE** — T_c ≈ 1.5 s, ~konstan terhadap
  N (ditentukan oleh periode broadcast CRDT); ~30× heuristik naif 50 ms, tercakup oleh σ.
- **Kriteria keluar (exit criteria):** V1 hijau; V2 menunjukkan pemisahan state-loss/waktu-rollout yang diprediksi pada pengukuran
  nyata; V3 mereproduksi tren; V4–V6 mengonfirmasi determinisme, pelacakan-latensi, dan fail-safety.
  **Semua terpenuhi.**

---

## 5. Milestone pembangunan (prototipe ini)
1. **M-a — DONE:** mix project `app/` — Horde + libcluster + `StatefulWorker` + `Probe` + `Grace`
   + `Shutdown` + probe HTTP; unit test `Grace` (6/6). *(inti yang dapat divalidasi secara lokal)*
2. **M-b — DONE:** integration test 2-node lokal (V1, 2/2 lulus) + pengalih policy (FR6). Kriteria keluar V1
   terpenuhi: handoff yang graceful selesai dengan state terjaga; grace yang terlalu pendek memotong (RQ1).
   Hosting menggunakan `DynamicSupervisor` + `Horde.Registry` lokal (penempatan survivor terkontrol).
3. **M-c — DONE:** `harness/run.exs` → `data/results_runs.csv` nyata; `analysis/plot.py` → figur.
   V2 terkonfirmasi: 30 s tetap kehilangan 40/160 begitu need>grace; adaptif kehilangan 0, grace 16→46 s vs 300 s tetap.
4. **M-d — DONE (termasuk V3):** `GraceConvergence.Operator` (menambal `terminationGracePeriodSeconds`
   dari `/probe`), manifest `k8s/` (preStop→`/drain`, PDB, service headless, RBAC), `Dockerfile`.
   V3 dijalankan pada cluster `kind`: cluster BEAM 3-replika via libcluster; operator menambal grace 6→26 s
   dari backlog runtime. (Angka kuantitatif tetap berasal dari M-c; V3 memvalidasi deployment + loop.)
5. **M-c++ — DONE:** evaluasi yang diperluas untuk RQ4/RQ5 — `harness/sweep.exs` menambahkan overhead (probe ~7 µs,
   ~6.7 KB/proses, ~8.3k handoff/s), sweep beban dengan pengulangan, dan sensitivitas grace.
6. **M-e — DONE:** skalabilitas (RQ6) — `harness/scale.exs` menyapu \|H\| 1k→40k → `results_scale.csv`;
   plafon per-node di 40k (handoff tidak dapat selesai dalam 600 s → 19,392 hilang); memori linier.
7. **M-f — DONE (penguatan Q2):** ketelitian statistik (V4, `repeats.exs`), latensi jaringan nyata (V5/RQ7,
   `k8s/netem.sh`), injeksi fail-safe (V6, `k8s/faults.sh`), beban kerja Phoenix.Presence yang realistis
   (V7/RQ8, `harness/presence.exs`), dan `Proposition 1` (bukti keamanan). Paper mendapat §Implementation
   (dengan listing kode), Appendix A/B, dan subbagian Practitioner-guidance; kini **20 halaman, RQ1–RQ8**,
   0 referensi tak-terdefinisi, semua float dirujuk.

> Status dilacak di `README.md` tingkat-atas. Jaga dependensi tetap dipatok (pinned) di `app/mix.exs`.
> **Gotcha:** jangan pernah `pkill -f '…@127.0.0.1'` di sekitar harness — pola itu cocok dengan shell
> yang sedang berjalan itu sendiri (exit 144, tanpa output). Matikan beam yatim (orphan) berdasarkan PID. Untuk `netem.sh`, jeda operator
> terlebih dahulu (rollout-nya akan mematikan node yang pergi di tengah pengukuran).
