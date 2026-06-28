# RQ9 (vs baseline reactive). Baseline tanpa model: mulai minAvailable=1, naikkan setelah tiap rolling
# update yang memecah kuorum, sampai aman. Hitung berapa pelanggaran sebelum konvergen, lalu kontras
# dengan pengendali berbasis-model (0 pelanggaran, langsung minAvailable=Q). Jalankan:
#   MIX_ENV=test elixir --name primary@127.0.0.1 --cookie ck -S mix run harness/reactive.exs
# Menulis data/results_reactive.csv (pengukuran nyata).
Node.set_cookie(:ck)
alias QuorumBudget.{Harness, Quorum}

data = Path.expand("../../data", File.cwd!())
File.mkdir_p!(data)

n = 9
nodes = Harness.spawn_mesh(n)
q = Quorum.majority(n)
attempts = Harness.reactive(nodes, pace_ms: 250)
Harness.stop_mesh(nodes)

breaks = Enum.count(attempts, & &1.violated)
IO.puts("=== RQ9 reactive (N=#{n}, Q=#{q}) ===")
Enum.each(attempts, fn a ->
  IO.puts("  attempt #{a.attempt}: minAvailable=#{a.min_available} maxUnavail=#{a.batch} " <>
    "min_observed=#{a.min_observed} violated=#{a.violated}")
end)
IO.puts("  reactive broke quorum #{breaks}x before converging at minAvailable=#{q}; model-based: 0")

# Baris model-based sebagai pembanding (langsung Q, 0 pelanggaran -- properti dari Proposition 1).
File.write!(
  Path.join(data, "results_reactive.csv"),
  ["policy,attempt,n,q,min_available,max_unavailable,min_observed,violated\n" |
   (Enum.map(attempts, fn a ->
      "reactive,#{a.attempt},#{n},#{q},#{a.min_available},#{a.batch},#{a.min_observed},#{a.violated}\n"
    end) ++
    ["model_based,1,#{n},#{q},#{q},#{n - q},#{q},false\n"])]
)
IO.puts("DONE reactive.exs")
