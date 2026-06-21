# Probe 2-node manual untuk M-b (dijalankan manual, jangan disertakan di `mix test`):
#   MIX_ENV=test elixir --name primary@127.0.0.1 --cookie ck -S mix run scripts/cluster_probe.exs
# primary = node yang pergi; peer yang di-spawn = survivor-nya.
defmodule ClusterProbe do
  def run do
    Node.set_cookie(:ck)

    {:ok, ppid, peer} =
      :peer.start_link(%{
        name: :surv,
        host: ~c"127.0.0.1",
        longnames: true,
        connection: :standard,
        args: [~c"-setcookie", ~c"ck"]
      })

    IO.puts("peer=#{peer} connected?=#{peer in Node.list()}")

    :rpc.call(peer, :code, :add_paths, [:code.get_path()])
    :rpc.call(peer, Application, :put_all_env, [[grace_convergence: Application.get_all_env(:grace_convergence)]])
    {:ok, _} = :rpc.call(peer, Application, :ensure_all_started, [:grace_convergence])
    Process.sleep(2000)

    IO.puts("primary Node.list=#{inspect(Node.list())}")
    IO.puts("Horde members=#{inspect(safe(fn -> Horde.Cluster.members(GraceConvergence.Registry) end))}")

    GraceConvergence.Workers.start_many(40)
    Process.sleep(1500)
    report("BEFORE", peer)

    res = GraceConvergence.Handoff.drain(60_000, nil)
    Process.sleep(1000)
    IO.puts("drain result=#{inspect(res)}")
    report("AFTER", peer)

    :peer.stop(ppid)
  end

  defp report(tag, peer) do
    IO.puts(
      "#{tag} total=#{GraceConvergence.Workers.count()} " <>
        "local_primary=#{GraceConvergence.Workers.local_count()} " <>
        "local_peer=#{:rpc.call(peer, GraceConvergence.Workers, :local_count, [])}"
    )
  end

  defp safe(f) do
    f.()
  rescue
    e -> {:error, e}
  end
end

ClusterProbe.run()
