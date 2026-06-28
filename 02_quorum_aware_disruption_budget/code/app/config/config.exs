import Config

# Konfigurasi dasar aplikasi M7 (pengendali PDB sadar-kuorum). Nilai berbasis lingkungan (mis.
# topologi libcluster dari env Kubernetes) diisi saat runtime; di sini hanya default yang masuk akal.
config :quorum_budget,
  # Peran pod: :app (anggota cluster BEAM) atau :operator (pengendali yang menambal PDB).
  role: :app,
  # Ambang kuorum. :majority -> div(N,2)+1 dihitung dari ukuran cluster hidup; atau bilangan tetap
  # (floor yang dideklarasikan operator untuk beban :global/CRDT).
  quorum: :majority,
  # Batas bawah min_available (jangan pernah izinkan cluster kosong saat gangguan sukarela).
  q_min: 1,
  # Kapasitas handoff (pod yang state-nya bisa dipindah tepat waktu); nil = tak ada batas tambahan.
  handoff_cap: nil,
  # Nama Deployment + PDB + namespace + selector yang dikelola operator (bisa ditimpa via env).
  deployment: "quorum",
  pdb: "quorum",
  namespace: "default",
  selector: "app=quorum",
  http_port: 4000,
  start_cluster: true,
  start_http: true,
  topologies: []

import_config "#{config_env()}.exs"
