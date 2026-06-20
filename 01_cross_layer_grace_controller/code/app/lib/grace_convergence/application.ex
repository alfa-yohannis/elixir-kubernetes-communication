defmodule GraceConvergence.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    cfg = Application.get_all_env(:grace_convergence)

    children =
      case role() do
        # operator pod: the cross-layer coordinator only (talks to the API server via kubectl)
        :operator ->
          [GraceConvergence.Operator]

        # app pod (default): the stateful workload + probe + adaptive termination
        :app ->
          cluster_children(cfg) ++
            [
              {Horde.Registry, [name: GraceConvergence.Registry, keys: :unique, members: :auto]},
              # Workers are hosted by a local supervisor (placement is controlled by the handoff,
              # not by Horde's ring); Horde.Registry still provides cluster-wide unique identity.
              {DynamicSupervisor, name: GraceConvergence.WorkerSup, strategy: :one_for_one},
              # Phoenix.Tracker presence (realistic distributed workload / convergence case study).
              {Phoenix.PubSub, name: GraceConvergence.PubSub},
              GraceConvergence.Presence,
              GraceConvergence.Probe,
              # large shutdown timeout so the adaptive drain can run during graceful stop
              Supervisor.child_spec({GraceConvergence.Shutdown, []}, shutdown: 310_000)
            ] ++ http_children(cfg)
      end

    Supervisor.start_link(children, strategy: :one_for_one, name: GraceConvergence.Supervisor)
  end

  # Role from GRACE_ROLE env (operator pod sets it), else config, else :app.
  defp role do
    case System.get_env("GRACE_ROLE") do
      "operator" -> :operator
      _ -> Application.get_env(:grace_convergence, :role, :app)
    end
  end

  defp cluster_children(cfg) do
    if Keyword.get(cfg, :start_cluster, true) do
      topologies = Application.get_env(:grace_convergence, :topologies, [])
      [{Cluster.Supervisor, [topologies, [name: GraceConvergence.ClusterSupervisor]]}]
    else
      []
    end
  end

  defp http_children(cfg) do
    if Keyword.get(cfg, :start_http, true) do
      [{Bandit, plug: GraceConvergence.ProbeHTTP, port: Keyword.get(cfg, :http_port, 4000)}]
    else
      []
    end
  end
end
