import Config

# Konfigurasi spesifik-runtime: dibaca saat aplikasi START (bukan saat compile), sehingga bisa memakai
# variabel lingkungan yang diinjeksikan Kubernetes (Downward API, ConfigMap). Hanya berlaku di pod
# sungguhan; di tes/dev berkas ini sebagian besar tak berpengaruh.

if config_env() == :prod do
  # Topologi libcluster strategi Kubernetes: tiap pod menemukan peer lewat API server berdasarkan
  # label selector, lalu membentuk cluster BEAM. Mode :ip memakai POD_IP (Downward API).
  config :quorum_budget, :topologies,
    k8s: [
      strategy: Cluster.Strategy.Kubernetes,
      config: [
        mode: :ip,
        kubernetes_node_basename: System.get_env("RELEASE_NAME", "quorum"),
        kubernetes_selector: System.get_env("QUORUM_SELECTOR", "app=quorum"),
        kubernetes_namespace: System.get_env("QUORUM_NAMESPACE", "default"),
        polling_interval: 3_000
      ]
    ]

  # Floor kuorum: bila beban kerja bukan mayoritas (mis. :global/CRDT), operator bisa menetapkan
  # ambang tetap lewat env QUORUM_THRESHOLD; selain itu pakai mayoritas yang dihitung dari ukuran hidup.
  case System.get_env("QUORUM_THRESHOLD") do
    nil -> :ok
    s -> config :quorum_budget, :quorum, String.to_integer(s)
  end
end
