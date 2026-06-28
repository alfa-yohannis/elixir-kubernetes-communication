defmodule QuorumBudget.Application do
  @moduledoc """
  **Titik masuk OTP** aplikasi `:quorum_budget`, sekaligus pembangun *supervision tree*-nya.

  Sama seperti artifact M3, satu image kontainer dipakai untuk dua peran, dipilih lewat env
  `QUORUM_ROLE`:

    * `:operator` -> hanya menjalankan `QuorumBudget.PDBOperator` (pengendali yang membaca probe
      kuorum tiap pod lalu menambal PodDisruptionBudget Deployment).
    * `:app` (default) -> menjadi anggota cluster BEAM: membentuk cluster (libcluster), menjalankan
      probe kuorum (sensor read-only), dan menyajikan endpoint HTTP `/probe`.
  """
  use Application

  @impl true
  def start(_type, _args) do
    cfg = Application.get_all_env(:quorum_budget)

    children =
      case role() do
        :operator ->
          [QuorumBudget.PDBOperator]

        :app ->
          cluster_children(cfg) ++
            [QuorumBudget.QuorumProbe, QuorumBudget.QuorumWorkload] ++
            http_children(cfg)
      end

    Supervisor.start_link(children, strategy: :one_for_one, name: QuorumBudget.Supervisor)
  end

  # Peran pod: env `QUORUM_ROLE` (diset pod operator), lalu config, default `:app`.
  defp role do
    case System.get_env("QUORUM_ROLE") do
      "operator" -> :operator
      _ -> Application.get_env(:quorum_budget, :role, :app)
    end
  end

  # Anak pembentukan cluster (libcluster). Dimatikan di tes agar logika diuji tanpa membentuk cluster.
  defp cluster_children(cfg) do
    if Keyword.get(cfg, :start_cluster, true) do
      topologies = Keyword.get(cfg, :topologies, [])
      [{Cluster.Supervisor, [topologies, [name: QuorumBudget.ClusterSupervisor]]}]
    else
      []
    end
  end

  # Server HTTP (Bandit menyajikan `ProbeHTTP`). Dimatikan di tes agar tidak membuka port.
  defp http_children(cfg) do
    if Keyword.get(cfg, :start_http, true) do
      [{Bandit, plug: QuorumBudget.ProbeHTTP, port: Keyword.get(cfg, :http_port, 4000)}]
    else
      []
    end
  end
end
