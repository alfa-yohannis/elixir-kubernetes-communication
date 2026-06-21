# code/ — artefak & harness eksperimen

Implementasi acuan (reference implementation) dari controller grace-convergence beserta harness yang menghasilkan
`../data/` dan `../figures/`. Lihat `DESIGN.md` untuk analisis → kebutuhan → desain → validasi, serta
`app/README.md` / `k8s/README.md` untuk cara menjalankan semuanya.

## Tata letak (sesuai yang dibangun)
```
code/
├── app/                        # Elixir/OTP mix project `grace_convergence`
│   ├── lib/grace_convergence/  #   grace (policy), probe, workers, stateful_worker, handoff,
│   │                           #   shutdown (preStop), probe_http, operator (kubectl-based), harness
│   ├── harness/                #   run.exs, sweep.exs, repeats.exs (CIs), scale.exs (RQ6) + scripts/
│   ├── test/                   #   grace_test (6 unit), cluster_handoff_test (2, :peer 2-node)
│   └── config/                 #   config/test/prod (prod = libcluster Kubernetes strategy)
├── k8s/                        # rbac.yaml, app.yaml, operator.yaml + netem.sh (RQ7), faults.sh
├── analysis/plot.py            # data/*.csv -> figures/*.pdf (matplotlib, ~/venv)
└── Dockerfile                  # one multi-stage image; GRACE_ROLE switches app vs operator
```

## Skenario eksperimen (baseline)
- (a) static 30 s, (b) over-provisioned 300 s, (c) preStop fixed sleep, (d) **controller adaptif** —
  disapu (swept) terhadap handoff backlog `|H|` dan rate `ρ`.

## Status
- **BEAM lokal:** unit 6/6 + integrasi cluster 2-node 2/2 lulus; suite lengkap (RQ1–RQ6) → menghasilkan
  `../data/*.csv` asli.
- **Kubernetes (kind):** app + operator ter-deploy; operator menambal (patch)
  `terminationGracePeriodSeconds` dari backlog runtime; RQ7 (latensi `tc netem` asli) dan
  injeksi fail-safe dijalankan di cluster.
- Koordinatornya adalah **operator GenServer berbasis `kubectl`** (`lib/grace_convergence/operator.ex`),
  **bukan** Bonny.

## Reproduksi
```bash
# BEAM experiments (from code/app), then figures:
MIX_ENV=test elixir --name primary@127.0.0.1 --cookie ck -S mix run harness/run.exs   # + sweep/repeats/scale
~/venv/bin/python analysis/plot.py
# Kubernetes: see k8s/README.md, then bash k8s/netem.sh and bash k8s/faults.sh
```
Toolchain: Elixir/Erlang/mix + Docker (linuxbrew); `kind` + `kubectl` di `~/.local/bin` — semuanya sudah tersedia.
**Jangan pernah `pkill -f '…@127.0.0.1'`** di sekitar harness (pola itu cocok dengan shell yang sedang berjalan → exit 144).
