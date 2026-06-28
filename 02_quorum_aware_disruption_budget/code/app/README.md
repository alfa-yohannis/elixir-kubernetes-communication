# Artifact M7 — pengendali PodDisruptionBudget sadar-kuorum

Aplikasi Elixir/OTP kecil (~0,5 KLOC) yang menyetel disruption budget Kubernetes dari
kuorum cluster BEAM. Komentar kode dalam Bahasa Indonesia.

## Modul

| Modul | Tugas |
|-------|-------|
| `QuorumBudget.Quorum` | Policy murni: `budget/2`, `majority/1`, `admit_eviction/2`. |
| `QuorumBudget.Cluster` | Baca keanggotaan (`Node.list`) + turunkan ambang kuorum `Q`. |
| `QuorumBudget.QuorumProbe` | Sensor read-only (`GenServer`) → `%{n, q, cap, in_quorum}`. |
| `QuorumBudget.ProbeHTTP` | Endpoint `GET /probe` (JSON) + `/healthz`. |
| `QuorumBudget.PDBOperator` | Operator: baca probe tiap pod → tambal `minAvailable` PDB via `kubectl`. |
| `QuorumBudget.Disruptor` | Mesin eksperimen: rolling update nyata + ukur ukuran cluster tersisa. |
| `QuorumBudget.Harness` | Bungkus pengukuran tiap RQ → baris CSV. |

## Menjalankan

```sh
# Tes unit (policy murni)
MIX_ENV=test mix test

# Tes terdistribusi (klaim safety pada cluster peer nyata)
MIX_ENV=test elixir --name primary@127.0.0.1 --cookie ck -S mix test --only cluster

# RQ1 (safety) + RQ2 (efficiency) — cluster peer nyata
MIX_ENV=test elixir --name primary@127.0.0.1 --cookie ck -S mix run harness/run.exs

# RQ3–RQ6 (policy murni)
MIX_ENV=test mix run harness/policy.exs
```

Catatan: harness terdistribusi memakai `:peer` dengan cookie `ck`. **Jangan**
`pkill -f '...@127.0.0.1'` — pola itu cocok dengan shell yang sedang berjalan dan
mematikannya; hentikan beam yatim berdasarkan PID.

## Peran

Satu image, dua peran lewat env `QUORUM_ROLE`: `app` (anggota cluster BEAM + probe) atau
`operator` (penambal PDB). Lihat `../k8s/` untuk manifes.
