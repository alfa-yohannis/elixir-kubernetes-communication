# RQ3 (adaptivity) + RQ4 (overhead) + RQ5 (robustness) + RQ6 (scalability). Semuanya evaluasi POLICY
# murni (deterministik, tanpa cluster) -> jalankan biasa:  MIX_ENV=test mix run harness/policy.exs
# Menulis data/results_{scale,sensitivity,overhead}.csv.
alias QuorumBudget.Harness

data = Path.expand("../../data", File.cwd!())
File.mkdir_p!(data)

# RQ3 (adaptivity) + RQ6 (scalability): budget mayoritas + waktu hitung budget vs ukuran cluster n.
scale = Harness.scale([3, 5, 7, 9, 11, 21, 51, 101, 1001, 10_001])
File.write!(
  Path.join(data, "results_scale.csv"),
  ["n,q,min_available,max_unavailable,budget_compute_ns\n" |
   Enum.map(scale, fn r -> "#{r.n},#{r.q},#{r.min_available},#{r.max_unavailable},#{r.budget_compute_ns}\n" end)]
)
IO.puts("[RQ3/RQ6] scale rows: #{length(scale)} (min_available melacak div(n,2)+1; compute ~O(1))")

# RQ5 (robustness): sensitivitas budget terhadap estimasi kuorum q pada n=9.
sens = Harness.sensitivity(9)
File.write!(
  Path.join(data, "results_sensitivity.csv"),
  ["n,q,min_available,max_unavailable\n" |
   Enum.map(sens, fn r -> "#{r.n},#{r.q},#{r.min_available},#{r.max_unavailable}\n" end)]
)
IO.puts("[RQ5] sensitivity rows: #{length(sens)}")

# RQ4 (overhead): latensi hitung budget (ns/panggilan), median dari beberapa ulangan.
ovs = for _ <- 1..5, do: Harness.overhead(200_000).budget_compute_ns
ov_median = ovs |> Enum.sort() |> Enum.at(2)
File.write!(Path.join(data, "results_overhead.csv"), "reps,budget_compute_ns\n200000,#{ov_median}\n")
IO.puts("[RQ4] budget_compute_ns (median of 5): #{ov_median}  all=#{inspect(Enum.sort(ovs))}")

IO.puts("DONE policy.exs")
