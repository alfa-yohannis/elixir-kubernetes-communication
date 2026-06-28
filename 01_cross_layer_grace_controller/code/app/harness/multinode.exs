# Eksperimen MULTI-NODE: handoff ke BEBERAPA survivor (bukan hanya satu) untuk menjawab kritik
# "evaluasi 2-node single-host". Spawn k peer survivor, jalankan beban tabel x policy, catat
# grace/drain/lost, lalu ukur DISTRIBUSI worker antar-survivor setelah satu drain. Juga menjalankan
# baseline adaptif reaktif (exponential-backoff) sebagai pembanding terhadap controller berbasis-model.
#   MIX_ENV=test elixir --name primary@127.0.0.1 --cookie ck -S mix run harness/multinode.exs
# Menulis data/results_multinode.csv, results_multinode_dist.csv, results_reactive.csv.
# (Jangan pernah pkill -f '...@127.0.0.1' di sekitar ini — mematikan shell yang berjalan.)

Node.set_cookie(:ck)

# Helper: spawn satu peer survivor, sambungkan path + start aplikasi di sana.
start_peer = fn name ->
  {:ok, pid, _} =
    :peer.start(%{name: name, host: ~c"127.0.0.1", longnames: true,
                  connection: :standard, args: [~c"-setcookie", ~c"ck"]})

  node = :"#{name}@127.0.0.1"
  :rpc.call(node, :code, :add_paths, [:code.get_path()])
  :rpc.call(node, Application, :put_all_env, [[grace_convergence: Application.get_all_env(:grace_convergence)]])
  {:ok, _} = :rpc.call(node, Application, :ensure_all_started, [:grace_convergence])
  {pid, node}
end

k = 3
peers = Enum.map(1..k, fn i -> start_peer.(:"surv#{i}") end)
Process.sleep(2500)
IO.puts("multinode cluster: #{inspect(Node.list())} (#{k} survivors)")

alias GraceConvergence.{Harness, Workers, Handoff}
data = Path.expand("../../data", File.cwd!())
File.mkdir_p!(data)

# (1) Beban tabel dengan k survivor: light + heavy, semua policy, 3 pengulangan.
loads = [%{backlog: 80, rate: 8}, %{backlog: 160, rate: 4}]
rows = Harness.run(loads, 3) |> Enum.map(&Map.put(&1, :survivors, k))
File.write!(
  Path.join(data, "results_multinode.csv"),
  Harness.csv(rows, [:policy, :survivors, :backlog, :rate, :need_s, :grace_s, :drain_ms, :lost, :completed])
)
IO.puts("multinode rows: #{length(rows)}")

# (2) Distribusi handoff antar-survivor: drain 300 worker (policy adaptif) lalu hitung per survivor.
Application.put_env(:grace_convergence, :grace_policy, :m3)
Application.put_env(:grace_convergence, :handoff_rate_limit, nil)
Workers.stop_all()
for n <- Node.list(), do: :rpc.call(n, Workers, :stop_all, [])
Process.sleep(400)
Workers.start_many_local(300, "dist_")
Process.sleep(300)
Handoff.drain(120_000, nil)
Process.sleep(600)
dist = for {_pid, node} <- peers, do: {node, :rpc.call(node, Workers, :local_count, [])}
IO.puts("distribusi handoff antar-survivor: #{inspect(dist)}")
File.write!(
  Path.join(data, "results_multinode_dist.csv"),
  "survivor,workers\n" <> Enum.map_join(dist, "\n", fn {n, c} -> "#{n},#{c}" end) <> "\n"
)

# (3) Baseline adaptif reaktif pada beban berat (need 40 s): gandakan grace sampai loss-free.
Workers.stop_all()
for n <- Node.list(), do: :rpc.call(n, Workers, :stop_all, [])
Process.sleep(400)
rx = Harness.reactive_backoff(%{backlog: 160, rate: 4}, 5, 120)
File.write!(Path.join(data, "results_reactive.csv"), Harness.csv(rx, [:attempt, :grace_s, :backlog, :rate, :lost]))
IO.puts("baseline reaktif: #{inspect(Enum.map(rx, &{&1.attempt, &1.grace_s, &1.lost}))}")

Enum.each(peers, fn {pid, _} -> :peer.stop(pid) end)
IO.puts("DONE multinode")
