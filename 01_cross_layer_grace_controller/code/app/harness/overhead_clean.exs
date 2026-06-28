# Ukur ulang overhead controller (RQ4) BERSIH saat mesin idle: ulang 5× lalu ambil median, supaya
# angka throughput handoff tak bias oleh keadaan GC/memori sesaat. Tulis ringkasan ke stdout saja
# (results_overhead.csv tetap dari sweep.exs, di-update tangan bila median berbeda).
Node.set_cookie(:ck)

{:ok, ppid, _} =
  :peer.start(%{name: :surv, host: ~c"127.0.0.1", longnames: true,
               connection: :standard, args: [~c"-setcookie", ~c"ck"]})

peer = :"surv@127.0.0.1"
:rpc.call(peer, :code, :add_paths, [:code.get_path()])
:rpc.call(peer, Application, :put_all_env, [[grace_convergence: Application.get_all_env(:grace_convergence)]])
{:ok, _} = :rpc.call(peer, Application, :ensure_all_started, [:grace_convergence])
Process.sleep(2000)

alias GraceConvergence.Harness
results =
  for i <- 1..5 do
    ov = Harness.overhead(200)
    IO.puts("rep #{i}: #{inspect(ov)}")
    Process.sleep(500)
    ov
  end

median = fn key ->
  xs = results |> Enum.map(&Map.fetch!(&1, key)) |> Enum.sort()
  Enum.at(xs, div(length(xs), 2))
end

IO.puts("\nMEDIAN probe_us=#{median.(:probe_latency_us)} mem_bytes=#{median.(:mem_per_worker_bytes)} throughput_eps=#{median.(:handoff_throughput_eps)}")
IO.puts("throughput all (sorted): #{inspect(results |> Enum.map(& &1.handoff_throughput_eps) |> Enum.sort())}")

:peer.stop(ppid)
IO.puts("DONE overhead_clean")
