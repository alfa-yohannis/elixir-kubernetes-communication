# RQ8 (realistic workload). Beban kerja bergantung-kuorum (`QuorumWorkload`) di tiap node; saat rolling
# update, ukur SURVIVOR yang ter-stall (tak bisa commit karena kuorum pecah) untuk policy statis vs
# quorum-aware. Jalankan:
#   MIX_ENV=test elixir --name primary@127.0.0.1 --cookie ck -S mix run harness/workload.exs
# Menulis data/results_workload.csv (pengukuran nyata).
Node.set_cookie(:ck)
alias QuorumBudget.Harness

data = Path.expand("../../data", File.cwd!())
File.mkdir_p!(data)

reps = 3

rows =
  for n <- [5, 7, 9], rep <- 1..reps do
    nodes = Harness.spawn_mesh(n)
    static = div(n + 1, 2)
    res = Harness.workload(nodes, static, pace_ms: 300)
    Harness.stop_mesh(nodes)

    IO.puts("n=#{n} rep=#{rep}: " <>
      Enum.map_join(res, " | ", fn r ->
        "#{r.policy} blocked_survivors=#{r.stalled_survivors} violated=#{r.quorum_violated?}"
      end))

    Enum.map(res, &Map.merge(&1, %{rep: rep, static_budget: static}))
  end
  |> List.flatten()

File.write!(
  Path.join(data, "results_workload.csv"),
  ["policy,n,q,static_budget,batch,rep,min_available,quorum_violated,blocked_survivors,maintenance_ms\n" |
   Enum.map(rows, fn r ->
     "#{r.policy},#{r.n},#{r.q},#{r.static_budget},#{r.batch},#{r.rep},#{r.min_available}," <>
       "#{r.quorum_violated?},#{r.stalled_survivors},#{r.maintenance_ms}\n"
   end)]
)

IO.puts("DONE workload.exs")
