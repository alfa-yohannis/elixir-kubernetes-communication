# k8s/ — deployment Kubernetes (M-d)

Integrasi Kubernetes yang sebenarnya dari controller. (Validasi M-a–M-c berjalan pada cluster BEAM
murni **tanpa** Kubernetes — validasi itu menguji logika grace/handoff/probe secara murah. Manifest ini
menempatkan controller pada cluster nyata; menjalankannya adalah **V3**, yang membutuhkan cluster lokal.)

## Isi direktori ini
- `rbac.yaml` — ServiceAccount + Role: app mencantumkan (list) pods/endpoints (penemuan/discovery libcluster); 
  operator membaca pods dan **menambal (patch) `terminationGracePeriodSeconds` milik Deployment app**.
- `app.yaml` — `Service` headless (penemuan distribusi BEAM), `Deployment` yang stateful
  (readiness/liveness pada `/healthz`; hook `preStop` adaptif yang melakukan `POST` ke `/drain` sehingga terminasi
  **diblokir sampai handoff selesai**), sebuah `Secret` cookie distribusi, dan sebuah `PodDisruptionBudget`.
- `operator.yaml` — `Deployment` koordinator lintas-lapis (cross-layer) (image yang sama, `GRACE_ROLE=operator`;
  `GraceConvergence.Operator` membaca `/probe` tiap pod, menghitung grace via `Grace.compute/2`,
  dan menambal Deployment). Operator hanyalah sebuah GenServer biasa yang memanggil `kubectl` (System.cmd) —
  **bukan** Bonny.
- `netem.sh` — **RQ7 (latensi jaringan nyata).** Menyuntikkan delay `tc netem` pada egress pod survivor
  (nsenter ke dalam netns pod dari node kind) dan mengukur, melalui `rpc` rilis, RTT antar-pod,
  rate handoff yang dapat dicapai ρ≈1/RTT, serta grace yang dihasilkan → `../../data/results_netem.csv`.
  **Menjeda operator terlebih dahulu** (jika tidak, backlog yang ia buat akan memicu rolling update yang mematikan node yang pergi).
- `faults.sh` — **validasi fail-safe.** Menyuntikkan tiga gangguan (operator crash, probe tidak dapat dipakai,
  RBAC patch dicabut) dan menunjukkan respons konservatif (pemulihan / fallback g_max / tanpa crash).
- `../Dockerfile` — satu image untuk kedua peran (`GRACE_ROLE` mengalihkan antara app dan operator; runtime-nya
  `elixir:1.16-alpine` agar cocok dengan OpenSSL milik builder — ketidakcocokan pernah menyebabkan CrashLoopBackOff pada crypto-NIF).

## Bagaimana loop lintas-lapis (cross-layer) dipetakan ke paper
- **Convergence probe** → `/probe` pada tiap pod app (`GraceConvergence.Probe`).
- **Adaptive termination hook** → `preStop` → `POST /drain` → `GraceConvergence.Shutdown` (diblokir
  sampai `GraceConvergence.Handoff` menguras backlog, dibatasi oleh `g_max`).
- **Coordinator** → `GraceConvergence.Operator` menambal `terminationGracePeriodSeconds`.
- **Membership layer** → strategi libcluster Kubernetes (`config/prod.exs`) melalui service headless.

## Menjalankannya (V3) — `kind` + `kubectl` sudah terpasang (`~/.local/bin`); `docker` tersedia
```bash
kind create cluster --name grace
docker build -t grace:dev code/             # build the image
kind load docker-image grace:dev --name grace
kubectl apply -f code/k8s/rbac.yaml -f code/k8s/app.yaml -f code/k8s/operator.yaml
kubectl rollout status deploy/grace
kubectl logs deploy/grace-operator          # "operator: pods=N grace=Ms"
bash code/k8s/netem.sh                       # RQ7: real latency -> rate/grace
bash code/k8s/faults.sh                       # fail-safe validation (Table in paper)
kind delete cluster --name grace             # tear down
```

> Status: **V3 dijalankan pada cluster `kind`.** Deployment 3-replika membentuk cluster BEAM melalui
> strategi libcluster Kubernetes, dan operator menambal `terminationGracePeriodSeconds` milik Deployment
> dari 6 s (idle) menjadi 26 s setelah ~190 proses stateful/pod terakumulasi
> pada rate handoff 10/s — loop lintas-lapis terkonfirmasi pada orchestrator nyata. Angka
> loss/efisiensi kuantitatif di paper berasal dari eksperimen cluster-BEAM terkontrol (M-c); deployment
> ini memvalidasi manifest dan control loop operator. Cluster juga diskalakan menjadi
> **6 replika** (operator menangani keenam probe), dan baik eksperimen **latensi-nyata**
> (`netem.sh`, RQ7) maupun injeksi **fail-safe** (`faults.sh`) berjalan di atasnya. Bongkar dengan
> `kind delete cluster --name grace`.
