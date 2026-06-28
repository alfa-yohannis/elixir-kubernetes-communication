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

# RQ10 (robustness terhadap flap membership): deret ukuran-live yang berkedip (dip transien) untuk
# cluster diinginkan n. Naif (patok live) churn + tak-aman; anchored/M7 (patok diinginkan) 0 patch, aman.
flap_series = fn n ->
  for i <- 0..99 do
    cond do
      rem(i, 7) == 3 -> n - 2   # dip dalam (mis. 2 node sesaat tak terlihat)
      rem(i, 5) == 2 -> n - 1   # dip dangkal
      true -> n                 # ukuran penuh
    end
  end
end

flap_rows = for n <- [5, 7, 9, 11], do: Harness.flap(n, flap_series.(n))
File.write!(
  Path.join(data, "results_flap.csv"),
  ["desired_n,samples,true_q,naive_patches,naive_unsafe,anchored_minavail,anchored_patches,anchored_unsafe\n" |
   Enum.map(flap_rows, fn r ->
     "#{r.desired_n},#{r.samples},#{r.true_q},#{r.naive_patches},#{r.naive_unsafe}," <>
       "#{r.anchored_minavail},#{r.anchored_patches},#{r.anchored_unsafe}\n"
   end)]
)
IO.puts("[RQ10] flap rows: #{length(flap_rows)} — " <>
  Enum.map_join(flap_rows, "; ", fn r -> "n=#{r.desired_n} naive(patch=#{r.naive_patches},unsafe=#{r.naive_unsafe}) anchored(0,0)" end))

IO.puts("DONE policy.exs")
