# RQ1 (safety) + RQ2 (efficiency). Membentuk cluster peer BEAM sungguhan (full mesh), lalu
# menjalankan rolling update di bawah dua policy dan MENGUKUR ukuran cluster yang tersisa.
# Jalankan dengan primary terdistribusi:
#   MIX_ENV=test elixir --name primary@127.0.0.1 --cookie ck -S mix run harness/run.exs
# Menulis data/results_safety.csv dan data/results_efficiency.csv (pengukuran nyata).

Node.set_cookie(:ck)
alias QuorumBudget.{Harness, Disruptor, Quorum}

# Membentuk cluster `n` node app peer, semuanya saling terhubung (full mesh). Mengembalikan daftar
# node. Tiap peer mewarisi config (start_cluster/start_http=false di MIX_ENV=test -> tanpa port/cluster).
spawn_mesh = fn n ->
  env = Application.get_all_env(:quorum_budget)

  nodes =
    for i <- 1..n do
      {:ok, _pid, node} =
        :peer.start(%{
          name: :"app#{i}",
          host: ~c"127.0.0.1",
          longnames: true,
          connection: :standard,
          args: [~c"-setcookie", ~c"ck"]
        })

      :rpc.call(node, :code, :add_paths, [:code.get_path()])
      :rpc.call(node, Application, :put_all_env, [[quorum_budget: env]])
      {:ok, _} = :rpc.call(node, Application, :ensure_all_started, [:quorum_budget])
      node
    end

  # Full mesh: hubungkan tiap pasang node.
  for a <- nodes, b <- nodes, a < b, do: :rpc.call(a, Node, :connect, [b])
  Process.sleep(1000)
  nodes
end

stop_all = fn nodes ->
  for n <- nodes do
    case :rpc.call(n, :erlang, :whereis, [:peer]) do
      _ -> :ok
    end
  end

  # peer dimulai dengan nama; hentikan lewat :peer butuh pid. Lebih sederhana: matikan via rpc.
  Enum.each(nodes, fn n -> :rpc.call(n, :init, :stop, []) end)
  Process.sleep(300)
end

data = Path.expand("../../data", File.cwd!())
File.mkdir_p!(data)

# --- RQ1: safety (static vs quorum-aware) untuk beberapa ukuran cluster -------------------------
IO.puts("=== RQ1 safety ===")
safety_rows =
  for n <- [3, 5, 7, 9] do
    nodes = spawn_mesh.(n)
    q = Quorum.majority(n)
    # "static" = pilihan operator agresif yang mengabaikan kuorum: ceil(n/2) (satu di atas batas aman).
    static = div(n + 1, 2)
    rows = Harness.safety(nodes, static, pace_ms: 300)
    stop_all.(nodes)
    IO.puts("  n=#{n} q=#{q} static=#{static}: " <>
      Enum.map_join(rows, " | ", fn r -> "#{r.policy} batch=#{r.batch} min_avail=#{r.min_available} violated=#{r.quorum_violated?}" end))
    Enum.map(rows, &Map.put(&1, :static_budget, static))
  end
  |> List.flatten()

File.write!(
  Path.join(data, "results_safety.csv"),
  ["policy,n,q,static_budget,batch,min_available,quorum_violated,blocked_batches,maintenance_ms\n" |
   Enum.map(safety_rows, fn r ->
     "#{r.policy},#{r.n},#{r.q},#{r.static_budget},#{r.batch},#{r.min_available}," <>
       "#{r.quorum_violated?},#{r.blocked_batches},#{r.maintenance_ms}\n"
   end)]
)

# --- RQ2: efficiency (konservatif batch=1 vs quorum-aware) pada N tetap, 5 ulangan --------------
IO.puts("=== RQ2 efficiency (5 ulangan) ===")
n = 9
reps = 5
q = Quorum.majority(n)

eff_rows =
  for {policy, bf} <- [{"conservative", {:static, 1}}, {"quorum_aware", :quorum_aware}],
      rep <- 1..reps do
    nodes = spawn_mesh.(n)
    b = Disruptor.budget_for(bf, n, q)
    r = Disruptor.rolling_cycle(nodes, b, q, pace_ms: 300)
    stop_all.(nodes)
    Map.merge(r, %{policy: policy, rep: rep, batches: ceil(n / b)})
  end

# Ringkasan rata-rata waktu per policy.
for {policy, rows} <- Enum.group_by(eff_rows, & &1.policy) do
  ms = Enum.map(rows, & &1.maintenance_ms)
  mean = Enum.sum(ms) / length(ms)
  IO.puts("  #{policy}: batch=#{hd(rows).batch} batches=#{hd(rows).batches} mean_maint=#{Float.round(mean, 0)}ms (n=#{length(ms)})")
end

File.write!(
  Path.join(data, "results_efficiency.csv"),
  ["policy,n,q,batch,batches,rep,min_available,quorum_violated,maintenance_ms\n" |
   Enum.map(eff_rows, fn r ->
     "#{r.policy},#{r.n},#{r.q},#{r.batch},#{r.batches},#{r.rep},#{r.min_available}," <>
       "#{r.quorum_violated?},#{r.maintenance_ms}\n"
   end)]
)

IO.puts("DONE run.exs")
