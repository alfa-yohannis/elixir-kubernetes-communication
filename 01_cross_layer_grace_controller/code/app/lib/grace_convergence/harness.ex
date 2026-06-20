defmodule GraceConvergence.Harness do
  @moduledoc """
  V2 experiment driver. For each (policy, load) scenario it starts a backlog of stateful workers
  on THIS (leaving) node, runs the drain under that policy at the load's handoff rate, and records
  real measurements: the grace chosen (s), the actual drain time (ms), the backlog, and the number
  of workers lost (handoff truncated by a too-short grace). Run on the leaving node of a connected
  2-node cluster — see `harness/run.exs`.
  """
  require Logger
  alias GraceConvergence.{Grace, Probe, Handoff, Workers}

  @policies [:static30, :static300, :prestop_sleep, :m3]

  @doc "Run the matrix. `loads` = [%{backlog: B, rate: rho}, ...]. Returns result rows (maps)."
  def run(loads, repeats \\ 1) do
    for load <- loads, policy <- @policies, rep <- 1..repeats do
      scenario(policy, load, rep)
    end
  end

  defp scenario(policy, %{backlog: backlog, rate: rate}, rep) do
    Application.put_env(:grace_convergence, :grace_policy, policy)
    Application.put_env(:grace_convergence, :handoff_rate_limit, rate)
    Probe.reset()
    cleanup()

    Workers.start_many_local(backlog, "s#{policy}_#{backlog}_#{rate}_#{rep}_")
    wait_local(backlog)

    grace_s = grace_for(policy)
    t0 = System.monotonic_time(:millisecond)
    result = Handoff.drain(grace_s * 1000, rate)
    drain_ms = System.monotonic_time(:millisecond) - t0

    lost =
      case result do
        {:timeout, remaining} -> remaining
        :ok -> 0
      end

    Logger.info("#{policy} B=#{backlog} rho=#{rate} grace=#{grace_s}s drain=#{drain_ms}ms lost=#{lost}")
    cleanup()

    %{
      policy: policy,
      backlog: backlog,
      rate: rate,
      rep: rep,
      need_s: Float.round(backlog / rate, 1),
      grace_s: grace_s,
      drain_ms: drain_ms,
      lost: lost,
      completed: result == :ok
    }
  end

  defp grace_for(:m3) do
    cfg = Application.get_all_env(:grace_convergence)

    Grace.compute(Probe.reading(),
      sigma: cfg[:sigma],
      g_min: cfg[:g_min],
      g_max: cfg[:g_max],
      t_d: cfg[:t_d],
      fallback: cfg[:g_max]
    )
  end

  defp grace_for(:prestop_sleep), do: Application.get_env(:grace_convergence, :static_grace, 30)
  defp grace_for(:static30), do: 30
  defp grace_for(:static300), do: 300

  defp cleanup do
    Workers.stop_all()
    for n <- Node.list(), do: :rpc.call(n, Workers, :stop_all, [])
    wait_total(0)
  end

  defp wait_local(target, tries \\ 100) do
    cond do
      Workers.local_count() >= target -> :ok
      tries <= 0 -> :ok
      true -> Process.sleep(50); wait_local(target, tries - 1)
    end
  end

  defp wait_total(target, tries \\ 60) do
    cond do
      Workers.count() <= target -> :ok
      tries <= 0 -> :ok
      true -> Process.sleep(50); wait_total(target, tries - 1)
    end
  end

  # ---- C: load sweep with repeats (curves with confidence intervals) ----
  @doc "Sweep over handoff needs (B = need*rate), all policies, `repeats` runs each."
  def run_sweep(needs, rate, repeats) do
    for need <- needs, policy <- @policies, rep <- 1..repeats do
      scenario(policy, %{backlog: round(need * rate), rate: rate}, rep)
      |> Map.put(:need_target, need)
    end
  end

  # ---- A: end-to-end rolling-update time (K pods drained sequentially, paced) ----
  @doc "Model a rolling update of `pods` sequential paced drains under one policy."
  def rollout(policy, pods, backlog, rate) do
    Application.put_env(:grace_convergence, :grace_policy, policy)
    Application.put_env(:grace_convergence, :handoff_rate_limit, rate)
    t0 = mono()

    lost =
      Enum.reduce(1..pods, 0, fn i, acc ->
        Probe.reset()
        cleanup()
        Workers.start_many_local(backlog, "r#{policy}#{i}_")
        wait_local(backlog)
        g = grace_for(policy)

        acc + (case Handoff.drain(g * 1000, rate) do
                 {:timeout, r} -> r
                 :ok -> 0
               end)
      end)

    cleanup()
    %{policy: policy, pods: pods, backlog: backlog, rate: rate, rollout_ms: mono() - t0, lost: lost}
  end

  # ---- B: controller overhead (probe latency, per-worker memory, raw throughput) ----
  @doc "Measure the controller's overhead on this node."
  def overhead(n \\ 200) do
    cleanup()
    {lat_us, _} = :timer.tc(fn -> for _ <- 1..1000, do: Probe.reading() end)

    m0 = :erlang.memory(:total)
    Workers.start_many_local(n, "ov_")
    wait_local(n)
    mem_per_worker = (:erlang.memory(:total) - m0) / n

    Application.put_env(:grace_convergence, :handoff_rate_limit, nil)
    Probe.reset()
    {ho_us, _} = :timer.tc(fn -> Handoff.drain(60_000, nil) end)
    cleanup()

    %{
      probe_latency_us: Float.round(lat_us / 1000, 2),
      mem_per_worker_bytes: round(mem_per_worker),
      handoff_throughput_eps: round(n / (ho_us / 1_000_000))
    }
  end

  # ---- Scalability: vary |H| and measure handoff time, throughput, memory, grace ----
  @doc "For each backlog size, start that many workers and hand them all off (unthrottled)."
  def scale(sizes) do
    for h <- sizes do
      cleanup()
      Probe.reset()
      Application.put_env(:grace_convergence, :handoff_rate_limit, nil)

      m0 = :erlang.memory(:total)
      t_start = mono()
      Workers.start_many_local(h, "sc#{h}_")
      start_ms = mono() - t_start
      mem_mb = Float.round((:erlang.memory(:total) - m0) / 1_048_576, 1)

      grace_s = grace_for(:m3)
      t0 = mono()
      res = Handoff.drain(600_000, nil)
      drain_ms = max(mono() - t0, 1)

      lost = (case res do {:timeout, r} -> r; :ok -> 0 end)
      cleanup()

      %{
        backlog: h,
        start_ms: start_ms,
        mem_mb: mem_mb,
        grace_s: grace_s,
        drain_ms: drain_ms,
        throughput_eps: round(h / (drain_ms / 1000)),
        lost: lost
      }
    end
  end

  defp mono, do: System.monotonic_time(:millisecond)

  @doc "Generic CSV from rows (maps) and an ordered list of column atoms."
  def csv(rows, columns) do
    header = Enum.map_join(columns, ",", &Atom.to_string/1)
    body = Enum.map_join(rows, "\n", fn r -> Enum.map_join(columns, ",", &"#{Map.get(r, &1)}") end)
    header <> "\n" <> body <> "\n"
  end

  @doc "CSV (one row per run) — original two-load matrix."
  def to_csv(rows) do
    csv(rows, [:policy, :backlog, :rate, :need_s, :grace_s, :drain_ms, :lost, :completed])
  end
end
