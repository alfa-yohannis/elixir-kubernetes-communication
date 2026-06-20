defmodule GraceConvergence.StatefulWorker do
  @moduledoc """
  A stateful process whose in-memory state must survive a node leaving (via handoff).
  Registered cluster-wide under a unique key in `Horde.Registry`.
  """
  use GenServer, restart: :transient

  @registry GraceConvergence.Registry

  def child_spec(opts) do
    id = Keyword.fetch!(opts, :id)

    %{
      id: {__MODULE__, id},
      start: {__MODULE__, :start_link, [opts]},
      restart: :transient,
      shutdown: 5_000
    }
  end

  def start_link(opts) do
    id = Keyword.fetch!(opts, :id)
    GenServer.start_link(__MODULE__, opts, name: via(id))
  end

  @doc "via-tuple naming through Horde.Registry (cluster-wide unique)."
  def via(id), do: {:via, Horde.Registry, {@registry, id}}

  def state(id), do: GenServer.call(via(id), :state)
  def touch(id), do: GenServer.cast(via(id), :touch)

  @impl true
  def init(opts) do
    id = Keyword.fetch!(opts, :id)
    data = Keyword.get(opts, :state) || %{id: id, updates: 0, born: System.os_time(:millisecond)}
    {:ok, data}
  end

  @impl true
  def handle_call(:state, _from, data), do: {:reply, data, data}

  @impl true
  def handle_cast(:touch, data), do: {:noreply, Map.update(data, :updates, 1, &(&1 + 1))}
end
