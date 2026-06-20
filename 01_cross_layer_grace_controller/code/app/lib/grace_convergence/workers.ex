defmodule GraceConvergence.Workers do
  @moduledoc """
  Start and enumerate stateful workers. Cluster-wide unique identity comes from
  `Horde.Registry`; each worker is *hosted* by its node's local `DynamicSupervisor`, so the
  controller can place a worker (and its handed-off state) on a chosen surviving node
  deterministically — Horde's ring would otherwise place a restart back on the leaving node.
  """
  alias GraceConvergence.StatefulWorker

  @registry GraceConvergence.Registry
  @sup GraceConvergence.WorkerSup

  @doc "Start a worker on THIS node (local supervisor), with optional seeded state."
  def start_local(id, state \\ nil) do
    DynamicSupervisor.start_child(@sup, {StatefulWorker, id: id, state: state})
  end

  @doc "Start a worker on a specific node."
  def start_on(node, id, state \\ nil) do
    :rpc.call(node, __MODULE__, :start_local, [id, state])
  end

  @doc "Start n fresh workers (keys `<prefix><i>`), round-robin across all cluster nodes (incl self)."
  def start_many(n, prefix \\ "w") when is_integer(n) and n > 0 do
    nodes = [Node.self() | Node.list()]
    Enum.map(1..n, fn i -> start_on(Enum.at(nodes, rem(i, length(nodes))), "#{prefix}#{i}") end)
  end

  @doc "Start n fresh workers all on THIS node (the leaving node in a drain experiment)."
  def start_many_local(n, prefix \\ "w") when is_integer(n) and n > 0 do
    Enum.map(1..n, fn i -> start_local("#{prefix}#{i}") end)
  end

  @doc "Terminate every worker hosted on this node (cleanup between scenarios)."
  def stop_all do
    for {_, pid, _, _} <- DynamicSupervisor.which_children(@sup), is_pid(pid) do
      DynamicSupervisor.terminate_child(@sup, pid)
    end

    :ok
  end

  @doc "All {key, pid} registered in the cluster (via Horde.Registry)."
  def all do
    Horde.Registry.select(@registry, [{{:"$1", :"$2", :"$3"}, [], [{{:"$1", :"$2"}}]}])
  end

  @doc """
  The {key, pid} pairs whose process currently lives **and is alive** on this node. The
  alive check skips registry entries whose owner has just died but whose CRDT de-registration
  has not yet propagated — otherwise a drain would re-process a dead entry forever.
  """
  def local do
    Enum.filter(all(), fn {_key, pid} -> node(pid) == Node.self() and Process.alive?(pid) end)
  end

  def local_count, do: length(local())
  def count, do: length(all())

  @doc "A surviving node to hand off to (any connected node), or nil if isolated."
  def survivor do
    case Node.list() do
      [] -> nil
      nodes -> Enum.random(nodes)
    end
  end
end
