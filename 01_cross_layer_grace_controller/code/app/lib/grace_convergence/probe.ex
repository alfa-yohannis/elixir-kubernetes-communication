defmodule GraceConvergence.Probe do
  @moduledoc """
  The convergence probe (read-only). Tracks an EWMA of the observed handoff rate and reports
  the per-node reading consumed by the grace policy and the HTTP endpoint. When no rate has
  been observed yet, it reports the known/configured handoff throughput (`:handoff_rate_limit`)
  as the rate estimate — the controller's view of achievable handoff capacity.
  """
  use GenServer
  alias GraceConvergence.Workers

  @alpha 0.3
  @default_rate 1000.0

  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  @doc "Current probe reading (map)."
  def reading, do: GenServer.call(__MODULE__, :reading)

  @doc "Record that `n` workers were handed off just now (updates the rate EWMA)."
  def record_handoff(n \\ 1), do: GenServer.cast(__MODULE__, {:handoff, n, now_ms()})

  @doc "Mark the start of a drain (resets the inter-arrival clock)."
  def mark_drain_start, do: GenServer.cast(__MODULE__, :drain_start)

  @doc "Reset all rate history (used between harness scenarios)."
  def reset, do: GenServer.call(__MODULE__, :reset)

  @impl true
  def init(_), do: {:ok, fresh()}

  @impl true
  def handle_call(:reading, _from, s), do: {:reply, build_reading(s), s}
  def handle_call(:reset, _from, _s), do: {:reply, :ok, fresh()}

  @impl true
  def handle_cast({:handoff, n, ts}, s) do
    rate =
      case s.last_ts do
        nil -> s.rate_eps
        prev when ts > prev -> @alpha * (n * 1000 / (ts - prev)) + (1 - @alpha) * s.rate_eps
        _ -> s.rate_eps
      end

    {:noreply, %{s | rate_eps: rate, last_ts: ts, handed: s.handed + n}}
  end

  def handle_cast(:drain_start, s), do: {:noreply, %{s | last_ts: nil}}

  defp fresh, do: %{rate_eps: 0.0, last_ts: nil, handed: 0}

  defp build_reading(s) do
    backlog = Workers.local_count()
    rate = if s.rate_eps > 0, do: s.rate_eps, else: configured_rate()

    %{
      node: Node.self(),
      backlog: backlog,
      rate_eps: Float.round(rate, 3),
      t_c_ms: convergence_ms(),
      in_flight: backlog,
      converged?: Node.list() != [] or backlog == 0,
      handed_off: s.handed
    }
  end

  defp configured_rate do
    case Application.get_env(:grace_convergence, :handoff_rate_limit) do
      nil -> @default_rate
      r when is_number(r) and r > 0 -> r * 1.0
      _ -> @default_rate
    end
  end

  # Convergence-time estimate; small on a healthy local cluster.
  defp convergence_ms, do: length(Node.list()) * 50

  defp now_ms, do: System.monotonic_time(:millisecond)
end
