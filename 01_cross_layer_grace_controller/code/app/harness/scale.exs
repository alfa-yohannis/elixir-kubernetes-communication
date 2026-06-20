# Scalability-to-the-limit: step |H| up until start cost or memory caps out. Streams each size to
# CSV as it completes (so partial results survive a timeout). Run with a distributed primary:
#   MIX_ENV=test elixir --name primary@127.0.0.1 --cookie ck -S mix run harness/scale.exs
# Writes data/results_scale.csv. NOTE: the first limit hit is usually Horde.Registry registration
# (delta-CRDT), not RAM — start_ms is reported separately from handoff throughput for that reason.

Node.set_cookie(:ck)

{:ok, ppid, _} =
  :peer.start(%{
    name: :surv,
    host: ~c"127.0.0.1",
    longnames: true,
    connection: :standard,
    args: [~c"-setcookie", ~c"ck"]
  })

peer = :"surv@127.0.0.1"
:rpc.call(peer, :code, :add_paths, [:code.get_path()])
:rpc.call(peer, Application, :put_all_env, [[grace_convergence: Application.get_all_env(:grace_convergence)]])
{:ok, _} = :rpc.call(peer, Application, :ensure_all_started, [:grace_convergence])
Process.sleep(2000)
IO.puts("cluster: #{inspect(Node.list())}")

data = Path.expand("../../data", File.cwd!())
File.mkdir_p!(data)
csv = Path.join(data, "results_scale.csv")
File.write!(csv, "backlog,start_ms,mem_mb,grace_s,drain_ms,throughput_eps,lost\n")

sizes = [1_000, 2_000, 5_000, 10_000, 20_000, 40_000, 80_000]
mem_cap = 20 * 1024 * 1024 * 1024

Enum.reduce_while(sizes, nil, fn h, _ ->
  cond do
    :erlang.memory(:total) > mem_cap ->
      IO.puts("STOP: memory cap reached before |H|=#{h}")
      {:halt, nil}

    true ->
      [r] = GraceConvergence.Harness.scale([h])

      line =
        "#{r.backlog},#{r.start_ms},#{r.mem_mb},#{r.grace_s},#{r.drain_ms},#{r.throughput_eps},#{r.lost}"

      File.write!(csv, line <> "\n", [:append])
      IO.puts("SCALE #{line}")

      # stop once worker registration itself becomes impractical (Horde registry limit)
      if r.start_ms > 180_000, do: {:halt, nil}, else: {:cont, nil}
  end
end)

:peer.stop(ppid)
IO.puts("DONE scale")
