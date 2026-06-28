import Config

# Di lingkungan tes: jangan bentuk cluster sungguhan dan jangan buka port HTTP, supaya logika policy
# bisa diuji terisolasi (unit test cepat, tanpa efek samping jaringan).
config :quorum_budget,
  start_cluster: false,
  start_http: false,
  # Di harness/tes, peer juga terhubung ke node pengendali `primary@...`. Kecualikan ia dari hitungan
  # kuorum agar ukuran cluster app yang dilihat probe/workload tepat = jumlah node app.
  control_node_prefix: "primary"
