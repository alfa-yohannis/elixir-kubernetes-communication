defmodule GraceConvergence.ClusterHandoffTest do
  @moduledoc """
  V1 integration test (DESIGN.md): a real 2-node BEAM cluster (primary = leaving node, a spawned
  peer = survivor). Excluded from the default suite; run with a distributed primary:

      MIX_ENV=test elixir --name primary@127.0.0.1 --cookie ck -S mix test --only cluster
  """
  use ExUnit.Case
  @moduletag :cluster
  @moduletag timeout: 120_000

  alias GraceConvergence.{Workers, Handoff, StatefulWorker}

  setup do
    unless Node.alive?() do
      flunk("""
      This test needs a distributed primary node. Run:
        MIX_ENV=test elixir --name primary@127.0.0.1 --cookie ck -S mix test --only cluster
      """)
    end

    Node.set_cookie(:ck)
    peer_name = :"surv#{System.unique_integer([:positive])}"

    {:ok, ppid, peer} =
      :peer.start(%{
        name: peer_name,
        host: ~c"127.0.0.1",
        longnames: true,
        connection: :standard,
        args: [~c"-setcookie", ~c"ck"]
      })

    :rpc.call(peer, :code, :add_paths, [:code.get_path()])
    :rpc.call(peer, Application, :put_all_env, [[grace_convergence: Application.get_all_env(:grace_convergence)]])
    {:ok, _} = :rpc.call(peer, Application, :ensure_all_started, [:grace_convergence])

    wait_until(fn ->
      peer in Node.list() and length(Horde.Cluster.members(GraceConvergence.Registry)) >= 2
    end)

    on_exit(fn ->
      try do
        :peer.stop(ppid)
      catch
        _, _ -> :ok
      end
    end)

    %{peer: peer}
  end

  test "graceful drain hands off all local workers to the survivor, preserving state", %{peer: peer} do
    Workers.start_many(40, "a")
    wait_until(fn -> Workers.count() >= 40 end)
    assert Workers.local_count() > 0

    # mutate one local worker so we can verify its state survives the handoff
    [{id, _pid} | _] = Workers.local()
    for _ <- 1..7, do: StatefulWorker.touch(id)
    assert StatefulWorker.state(id).updates == 7

    # generous grace => handoff completes
    assert :ok = Handoff.drain(60_000, nil)

    assert Workers.local_count() == 0
    wait_until(fn -> :rpc.call(peer, Workers, :local_count, []) >= 40 end)

    # the worker now lives on the survivor with its mutated state intact.
    # (retry: the new registration may take a moment to propagate back to this node's CRDT view)
    moved = fetch_state(id)
    assert moved.id == id
    assert moved.updates == 7
  end

  defp fetch_state(id, tries \\ 50) do
    StatefulWorker.state(id)
  catch
    :exit, _ when tries > 0 ->
      Process.sleep(100)
      fetch_state(id, tries - 1)
  end

  test "too-short grace truncates the handoff (RQ1): drain times out with workers still local" do
    Workers.start_many(40, "b")
    wait_until(fn -> Workers.count() >= 40 end)
    assert Workers.local_count() > 0

    # throttle to 2 handoffs/s and allow only 1s => most workers cannot be handed off in time
    assert {:timeout, remaining} = Handoff.drain(1_000, 2)
    assert remaining > 0
  end

  defp wait_until(fun, tries \\ 100) do
    cond do
      fun.() -> :ok
      tries <= 0 -> flunk("condition not met in time")
      true -> Process.sleep(100); wait_until(fun, tries - 1)
    end
  end
end
