defmodule GraceConvergence.Handoff do
  @moduledoc """
  Drains local stateful workers by transferring each one's state to a chosen surviving node
  (read state → stop local → start on the survivor with that state), throttled to a
  configurable rate to emulate load. Returns when the local backlog reaches 0 or the deadline
  elapses — the latter is exactly what a too-short grace produces: a truncated handoff in which
  the still-local workers (and their state) are lost when the node is killed.
  """
  require Logger
  alias GraceConvergence.{Workers, Probe}

  @sup GraceConvergence.WorkerSup

  @doc """
  Hand off all local workers. `deadline_ms` bounds the wait; `rate_limit` (workers/s or nil)
  throttles transfers. Returns `:ok` or `{:timeout, remaining_backlog}`.
  """
  def drain(deadline_ms, rate_limit \\ nil) do
    Probe.mark_drain_start()
    loop(now_ms() + deadline_ms, rate_limit)
  end

  defp loop(deadline, rate_limit) do
    cond do
      Workers.local_count() == 0 ->
        :ok

      now_ms() >= deadline ->
        {:timeout, Workers.local_count()}

      true ->
        case Workers.local() do
          [{id, pid} | _] ->
            case handoff_one(id, pid) do
              :ok -> if rate_limit, do: Process.sleep(max(1, trunc(1000 / rate_limit)))
              :no_survivor -> Process.sleep(100)
            end

            loop(deadline, rate_limit)

          [] ->
            :ok
        end
    end
  end

  defp handoff_one(id, pid) do
    case Workers.survivor() do
      nil ->
        :no_survivor

      target ->
        state = safe_state(pid)
        _ = DynamicSupervisor.terminate_child(@sup, pid)
        place(id, state, target, 40)
        :ok
    end
  end

  # Retry placement on the survivor until it lands there. The stale registration of the
  # just-killed local worker can briefly make Horde reject the new start with
  # {:already_started, dead_pid}; we wait for the CRDT to purge it and retry.
  defp place(id, _state, _target, 0) do
    Logger.warning("handoff #{inspect(id)}: gave up placing on survivor")
  end

  defp place(id, state, target, tries) do
    case Workers.start_on(target, id, state) do
      {:ok, p} when node(p) == target ->
        Probe.record_handoff(1)

      {:error, {:already_started, p}} ->
        if node(p) == target and remote_alive?(p) do
          Probe.record_handoff(1)
        else
          Process.sleep(50)
          place(id, state, target, tries - 1)
        end

      _other ->
        Process.sleep(50)
        place(id, state, target, tries - 1)
    end
  end

  defp remote_alive?(pid), do: :rpc.call(node(pid), Process, :alive?, [pid]) == true

  defp safe_state(pid) do
    GenServer.call(pid, :state, 1_000)
  catch
    _, _ -> nil
  end

  defp now_ms, do: System.monotonic_time(:millisecond)
end
