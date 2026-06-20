defmodule GraceConvergence.Operator do
  @moduledoc """
  The cross-layer coordinator, running as a Kubernetes operator pod. Each cycle it reads every app
  pod's `/probe`, computes the adequate grace via `Grace.compute/2`, and patches the app Deployment's
  `terminationGracePeriodSeconds` so the next rollout uses a grace sized to the runtime's handoff
  need (and, optionally, paces `maxUnavailable`). It talks to the API server with `kubectl` using the
  pod's ServiceAccount (RBAC in `../../k8s/`). Started only in the operator role
  (`config :grace_convergence, role: :operator`, set from `GRACE_ROLE=operator`).
  """
  use GenServer
  require Logger
  alias GraceConvergence.Grace

  @interval_ms 5_000

  def start_link(_), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  @impl true
  def init(s) do
    send(self(), :reconcile)
    {:ok, s}
  end

  @impl true
  def handle_info(:reconcile, s) do
    try do
      reconcile()
    catch
      kind, e -> Logger.warning("operator reconcile #{inspect(kind)}: #{inspect(e)}")
    end

    Process.send_after(self(), :reconcile, @interval_ms)
    {:noreply, s}
  end

  @doc "One reconcile pass: probe pods → compute grace → patch the Deployment."
  def reconcile do
    readings = for ip <- pod_ips(), r = probe(ip), do: r

    if readings != [] do
      grace = readings |> Enum.map(&Grace.compute(&1, grace_opts())) |> Enum.max()
      patch_grace(grace)
      Logger.info("operator: pods=#{length(readings)} grace=#{grace}s")
    end
  end

  defp pod_ips do
    case System.cmd("kubectl", [
           "get", "pods", "-n", namespace(), "-l", selector(),
           "-o", "jsonpath={.items[*].status.podIP}"
         ]) do
      {out, 0} -> out |> String.split() |> Enum.reject(&(&1 == ""))
      _ -> []
    end
  end

  defp probe(ip) do
    url = ~c"http://#{ip}:4000/probe"

    case :httpc.request(:get, {url, []}, [{:timeout, 2_000}], []) do
      {:ok, {{_, 200, _}, _, body}} ->
        m = body |> to_string() |> Jason.decode!()
        %{backlog: m["backlog"], rate_eps: m["rate_eps"], t_c_ms: m["t_c_ms"]}

      _ ->
        nil
    end
  end

  defp patch_grace(grace) do
    patch = Jason.encode!(%{spec: %{template: %{spec: %{terminationGracePeriodSeconds: grace}}}})

    System.cmd("kubectl", [
      "patch", "deployment", deployment(), "-n", namespace(),
      "--type", "merge", "-p", patch
    ])
  end

  defp grace_opts do
    cfg = Application.get_all_env(:grace_convergence)
    [sigma: cfg[:sigma], g_min: cfg[:g_min], g_max: cfg[:g_max], t_d: cfg[:t_d], fallback: cfg[:g_max]]
  end

  defp deployment, do: System.get_env("GRACE_DEPLOYMENT", "grace")
  defp namespace, do: System.get_env("GRACE_NAMESPACE", "default")
  defp selector, do: System.get_env("GRACE_SELECTOR", "app=grace")
end
