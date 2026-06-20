defmodule GraceConvergence.Shutdown do
  @moduledoc """
  The adaptive termination hook. On graceful shutdown (or an explicit `drain_and_await/0`)
  it computes the grace window per the configured policy and drains/hands off within it.

  Policies (config `:grace_policy`):
    * `:m3`            -> grace derived from the probe via `Grace.compute/2` (adaptive)
    * `:prestop_sleep` -> fixed `:static_grace` seconds
    * `:static30`      -> fixed 30 s
    * `:static300`     -> fixed 300 s
  """
  use GenServer
  require Logger
  alias GraceConvergence.{Grace, Probe, Handoff}

  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  @doc "Run the drain synchronously (used by tests and by the SIGTERM path)."
  def drain_and_await, do: GenServer.call(__MODULE__, :drain, :infinity)

  @impl true
  def init(_) do
    Process.flag(:trap_exit, true)
    {:ok, %{}}
  end

  @impl true
  def handle_call(:drain, _from, s), do: {:reply, do_drain(), s}

  @impl true
  def terminate(_reason, _s) do
    do_drain()
    :ok
  end

  defp do_drain do
    cfg = Application.get_all_env(:grace_convergence)
    policy = Keyword.get(cfg, :grace_policy, :m3)
    g_max = Keyword.get(cfg, :g_max, 120)
    rate_limit = Keyword.get(cfg, :handoff_rate_limit)
    reading = Probe.reading()

    g_seconds = grace_for(policy, reading, cfg, g_max)

    Logger.info(
      "drain policy=#{policy} grace=#{g_seconds}s backlog=#{reading.backlog} rate=#{reading.rate_eps}/s"
    )

    result = Handoff.drain(g_seconds * 1000, rate_limit)
    %{policy: policy, grace_s: g_seconds, result: result, lost: lost(result)}
  end

  defp grace_for(:m3, reading, cfg, g_max) do
    Grace.compute(reading,
      sigma: Keyword.get(cfg, :sigma, 5),
      g_min: Keyword.get(cfg, :g_min, 5),
      g_max: g_max,
      t_d: Keyword.get(cfg, :t_d, 1),
      fallback: g_max
    )
  end

  defp grace_for(:prestop_sleep, _r, cfg, _), do: Keyword.get(cfg, :static_grace, 30)
  defp grace_for(:static30, _r, _cfg, _), do: 30
  defp grace_for(:static300, _r, _cfg, _), do: 300

  defp lost({:timeout, remaining}), do: remaining
  defp lost(:ok), do: 0
end
