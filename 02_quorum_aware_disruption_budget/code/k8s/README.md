# Manifes Kubernetes (M7)

| Berkas | Isi |
|--------|-----|
| `rbac.yaml` | ServiceAccount + Role hak-paling-kecil. Operator: baca pod, baca/tambal PDB. App: baca pod/endpoint (untuk libcluster). |
| `app.yaml` | Deployment `quorum` (5 replika, cluster BEAM via libcluster) + headless Service + PodDisruptionBudget awal. |
| `operator.yaml` | Deployment operator (1 replika, peran `operator`) yang menambal `minAvailable` PDB dari kuorum runtime. |
| `rq7_eviction.sh` | Eksperimen RQ7: pada cluster kind hidup, tunjukkan eviction API menolak eviction yang memecah kuorum saat PDB diturunkan dari kuorum. |

## Urutan penerapan

```sh
kubectl apply -f rbac.yaml
kubectl apply -f app.yaml          # tunggu 5 pod Ready
kubectl apply -f operator.yaml     # operator mulai menambal PDB
```

Operator menambal `spec.minAvailable` PDB ke kuorum mayoritas (mis. 3 untuk 5 replika)
tiap 5 detik. Setelah itu, `kubectl drain` / rolling update yang akan menurunkan anggota di
bawah kuorum akan ditolak oleh eviction API.

## RQ7 (penolakan eviction)

```sh
bash rq7_eviction.sh      # butuh cluster kind hidup + kubectl
```

Membandingkan PDB sadar-kuorum (`minAvailable=Q`) vs tak-sadar-kuorum (`minAvailable=Q-1`):
yang pertama menolak eviction yang memecah kuorum; yang kedua mengizinkannya. Menulis
`../../data/results_eviction.csv`.

## Catatan

Image `quorum_budget:latest` dibangun dari `../Dockerfile` (release Elixir + kubectl).
Untuk kind: `kind load docker-image quorum_budget:latest`. Cookie distribusi Erlang harus
identik di semua pod (di produksi: dari Secret, bukan nilai literal di manifes).
