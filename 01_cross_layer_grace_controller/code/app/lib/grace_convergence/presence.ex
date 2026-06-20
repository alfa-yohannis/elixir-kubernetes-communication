defmodule GraceConvergence.Presence do
  @moduledoc """
  A realistic distributed workload built on `Phoenix.Tracker` --- the CRDT engine behind
  `Phoenix.Presence` --- tracking presences across the BEAM cluster. We use it (no web server needed)
  to measure the real membership/convergence time on a node departure: the `T_c` term of the
  grace-safety invariant, on an unmodified, widely-used Phoenix distributed feature.
  """
  use Phoenix.Tracker

  @pubsub GraceConvergence.PubSub

  def start_link(opts \\ []) do
    opts = Keyword.merge([name: __MODULE__, pubsub_server: @pubsub], opts)
    Phoenix.Tracker.start_link(__MODULE__, opts, opts)
  end

  @impl true
  def init(opts), do: {:ok, %{pubsub_server: Keyword.fetch!(opts, :pubsub_server)}}

  @impl true
  def handle_diff(_diff, state), do: {:ok, state}

  @doc "Track `key` under `topic`, owned by `pid` (the presence vanishes when `pid` dies)."
  def track(pid, topic, key, meta \\ %{}),
    do: Phoenix.Tracker.track(__MODULE__, pid, topic, key, meta)

  @doc "Cluster-wide count of distinct presences for `topic` (as seen by THIS node)."
  def count(topic), do: __MODULE__ |> Phoenix.Tracker.list(topic) |> length()
end
