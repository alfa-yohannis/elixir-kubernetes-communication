defmodule GraceConvergence.Application do
  @moduledoc """
  **Titik masuk OTP**: modul yang dijalankan saat aplikasi `:grace_convergence` start, dan yang
  membangun *supervision tree*-nya.

  Di OTP, sebuah aplikasi memulai satu supervisor akar yang mengawasi sekumpulan proses anak; jika
  ada anak yang crash, supervisor me-restart-nya ("let it crash" lalu pulih otomatis). Modul ini
  memilih daftar anak berdasarkan **peran** pod, yang ditentukan oleh env `GRACE_ROLE`:

    * `:operator` -> hanya menjalankan `GraceConvergence.Operator` (koordinator lintas-lapis).
    * `:app` (default) -> menjalankan beban kerja stateful + probe + hook terminasi adaptif.

  Image kontainer yang sama dipakai untuk kedua peran; `GRACE_ROLE` yang membedakannya.
  """
  use Application

  @impl true
  # Dipanggil OTP saat aplikasi start. Menyusun daftar anak sesuai peran, lalu menjalankan supervisor
  # akar dengan strategi `:one_for_one` (jika satu anak mati, hanya anak itu yang di-restart).
  def start(_type, _args) do
    cfg = Application.get_all_env(:grace_convergence)

    children =
      case role() do
        # Pod operator: cukup koordinator lintas-lapis (bicara ke API server lewat kubectl).
        :operator ->
          [GraceConvergence.Operator]

        # Pod aplikasi (default): beban kerja stateful + probe + terminasi adaptif.
        :app ->
          cluster_children(cfg) ++
            [
              # Registry terdistribusi (CRDT) untuk identitas unik worker se-cluster.
              {Horde.Registry, [name: GraceConvergence.Registry, keys: :unique, members: :auto]},
              # Worker di-host oleh supervisor LOKAL (penempatan dikendalikan oleh handoff, bukan oleh
              # ring Horde); Horde.Registry tetap menyediakan identitas unik se-cluster.
              {DynamicSupervisor, name: GraceConvergence.WorkerSup, strategy: :one_for_one},
              # Presence berbasis Phoenix.Tracker (beban kerja realistis / studi kasus konvergensi).
              {Phoenix.PubSub, name: GraceConvergence.PubSub},
              GraceConvergence.Presence,
              # Probe konvergensi (sensor read-only).
              GraceConvergence.Probe,
              # Timeout shutdown besar agar drain adaptif sempat berjalan saat graceful stop.
              Supervisor.child_spec({GraceConvergence.Shutdown, []}, shutdown: 310_000)
            ] ++ http_children(cfg)
      end

    Supervisor.start_link(children, strategy: :one_for_one, name: GraceConvergence.Supervisor)
  end

  # Tentukan peran: dari env `GRACE_ROLE` (diset oleh pod operator), lalu dari config, default `:app`.
  defp role do
    case System.get_env("GRACE_ROLE") do
      "operator" -> :operator
      _ -> Application.get_env(:grace_convergence, :role, :app)
    end
  end

  # Anak pembentukan cluster (libcluster). Hanya disertakan bila `:start_cluster` true (di tes
  # dimatikan agar logika diuji tanpa benar-benar membentuk cluster).
  defp cluster_children(cfg) do
    if Keyword.get(cfg, :start_cluster, true) do
      topologies = Application.get_env(:grace_convergence, :topologies, [])
      [{Cluster.Supervisor, [topologies, [name: GraceConvergence.ClusterSupervisor]]}]
    else
      []
    end
  end

  # Anak server HTTP (Bandit menyajikan `ProbeHTTP`). Hanya disertakan bila `:start_http` true
  # (di tes dimatikan agar tidak membuka port).
  defp http_children(cfg) do
    if Keyword.get(cfg, :start_http, true) do
      [{Bandit, plug: GraceConvergence.ProbeHTTP, port: Keyword.get(cfg, :http_port, 4000)}]
    else
      []
    end
  end
end
