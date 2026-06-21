# grace_convergence (app)

Implementasi acuan (reference implementation) dari controller grace-convergence yang dijelaskan di paper. Lihat
`../DESIGN.md` untuk analisis, kebutuhan, desain, dan rencana validasi.

## Modul
- `GraceConvergence.Grace` — kebijakan (policy) grace-period `g = clamp(T_d + B/ρ + T_c + σ, g_min, g_max)`.
- `GraceConvergence.Probe` — probe konvergensi: backlog, rate handoff EWMA, estimasi `T_c`.
- `GraceConvergence.StatefulWorker` / `GraceConvergence.Workers` — proses stateful terdistribusi-Horde.
- `GraceConvergence.Handoff` — menguras (drain) worker lokal dengan memindahkan state ke node yang bertahan (di-throttle).
- `GraceConvergence.Shutdown` — hook terminasi adaptif; memilih grace sesuai policy yang dikonfigurasi.
- `GraceConvergence.ProbeHTTP` — `/probe` (pembacaan), `/healthz`, dan `POST /drain` (hook preStop).
- `GraceConvergence.Operator` — koordinator Kubernetes: loop rekonsiliasi (`kubectl` get pods → `/probe`
  → `Grace.compute` → `kubectl patch` TGPS). Hanya berjalan pada peran operator (`GRACE_ROLE=operator`).
- `GraceConvergence.Harness` — penggerak (driver) eksperimen: `run/2`, `run_sweep/3`, `rollout/4`, `overhead/1`,
  `scale/1`.
- `GraceConvergence.Presence` — presence `Phoenix.Tracker` (mesin CRDT di balik Phoenix.Presence),
  sebuah beban kerja (workload) terdistribusi yang realistis untuk mengukur waktu konvergensi nyata `T_c` (RQ8).

## Menjalankan tes & eksperimen

### 1. Unit test (cepat, tanpa cluster) — memvalidasi policy grace
```bash
mix deps.get
mix compile
mix test                 # 6 Grace-policy tests; the :cluster suite is excluded by default
```

### 2. Integration test multi-node (V1) — cluster BEAM 2-node nyata
Node primary harus berupa node terdistribusi, jadi luncurkan secara eksplisit (ia akan membuat (spawn) peer "survivor"
secara internal melalui `:peer`):
```bash
MIX_ENV=test elixir --name primary@127.0.0.1 --cookie ck -S mix test --only cluster
```
Memastikan bahwa (a) drain yang graceful melakukan handoff **semua** worker lokal ke survivor dengan **state
terjaga**, dan (b) grace yang terlalu pendek **memotong (truncate)** handoff (`{:timeout, remaining>0}` — kasus
kehilangan pada RQ1). `epmd` dijalankan otomatis oleh BEAM.

### 3. Probe 2-node manual (mengamati handoff secara langsung)
```bash
MIX_ENV=test elixir --name primary@127.0.0.1 --cookie ck -S mix run scripts/cluster_probe.exs
```
Mencetak penempatan worker BEFORE/AFTER dan hasil drain, mis.
`BEFORE local_primary=20 local_peer=20 … drain result=:ok … AFTER local_primary=0 local_peer=40`.

### 4. REPL single-node (menyentuh API)
```bash
iex -S mix
iex> GraceConvergence.start_many(500)    # create 500 stateful workers
iex> GraceConvergence.reading()          # probe reading (backlog, rate, T_c)
iex> GraceConvergence.drain_and_await()  # run the adaptive drain
```

### 5. Suite eksperimen lengkap (data nyata → `../../data/`, figur melalui `analysis/plot.py`)
Semua dijalankan dengan primary terdistribusi (membuat peer survivor); **jangan pernah `pkill -f '…@127.0.0.1'`** —
pola itu cocok dengan shell yang sedang berjalan dan mematikannya (exit 144). Matikan beam yatim (orphan) berdasarkan PID.
```bash
P="MIX_ENV=test elixir --name primary@127.0.0.1 --cookie ck -S mix run"
$P harness/run.exs        # two-load table (RQ1/RQ2)        -> results_runs.csv
$P harness/sweep.exs      # sweep + rollout + overhead + sensitivity (RQ1/2/4/5)
$P harness/repeats.exs    # N=10 table + N=5 rollout (CIs)   -> results_runs_ci.csv, results_rollout_ci.csv
$P harness/scale.exs      # |H| 1k->40k scalability (RQ6)    -> results_scale.csv
$P harness/presence.exs   # Phoenix.Presence convergence (RQ8) -> results_presence.csv
~/venv/bin/python ../analysis/plot.py   # render all figures
```
Eksperimen Kubernetes (RQ7 + fail-safe) berada di `../k8s/`: `bash ../k8s/netem.sh` (latensi nyata) dan
`bash ../k8s/faults.sh` (operator crash / fallback probe / RBAC dicabut). Lihat `../k8s/README.md`.

**Status: unit 6/6 lulus; integrasi cluster 2/2 lulus; suite lengkap + K8s (RQ1–RQ7) dijalankan pada data nyata.**

## Policy terminasi (config `:grace_policy`, FR6)
`:m3` (adaptif, default) · `:prestop_sleep` (fixed `:static_grace`) · `:static30` · `:static300`.
Ganti per run, mis. `config :grace_convergence, grace_policy: :static30`. Harness (M-c) akan
menyapu (sweep) keempatnya untuk menghasilkan perbandingan di `../data/` → `../figures/`.

> Deployment Kubernetes (operator + manifest) adalah M-d; `config/prod.exs` sudah memilih
> strategi libcluster Kubernetes.
