# Extended evaluation: A (rollout time), B (overhead), C (load sweep + repeats), D (sensitivity).
# Launch with a distributed primary (spawns a survivor peer):
#   MIX_ENV=test elixir --name primary@127.0.0.1 --cookie ck -S mix run harness/sweep.exs
# Writes data/results_{overhead,sensitivity,sweep,rollout}.csv (real measurements).

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

alias GraceConvergence.{Harness, Grace}
data = Path.expand("../../data", File.cwd!())
File.mkdir_p!(data)

# B — overhead -------------------------------------------------------------
ov = Harness.overhead(200)
IO.puts("[B] overhead: #{inspect(ov)}")
File.write!(
  Path.join(data, "results_overhead.csv"),
  Harness.csv([ov], [:probe_latency_us, :mem_per_worker_bytes, :handoff_throughput_eps])
)

# D — sensitivity (pure Grace policy; no cluster needed) -------------------
base = %{t_c_ms: 50}
go = fn r, opts -> Grace.compute(Map.merge(base, r), opts) end

sens =
  for(s <- [0, 5, 10, 15],
      do: %{kind: "sigma", x: s, grace_s: go.(%{backlog: 200, rate_eps: 10.0}, sigma: s, g_min: 5, g_max: 120, t_d: 1, fallback: 120)}) ++
    for(gm <- [30, 60, 120, 300],
        do: %{kind: "g_max", x: gm, grace_s: go.(%{backlog: 2000, rate_eps: 10.0}, sigma: 5, g_min: 5, g_max: gm, t_d: 1, fallback: gm)}) ++
    for(e <- [0.5, 1.0, 2.0],
        do: %{kind: "rho_error", x: e, grace_s: go.(%{backlog: 200, rate_eps: 10.0 * e}, sigma: 5, g_min: 5, g_max: 120, t_d: 1, fallback: 120)})

File.write!(Path.join(data, "results_sensitivity.csv"), Harness.csv(sens, [:kind, :x, :grace_s]))
IO.puts("[D] sensitivity rows: #{length(sens)}")

# C — load sweep with repeats (curves) -------------------------------------
sweep = Harness.run_sweep([10, 25, 40], 10, 3)
File.write!(
  Path.join(data, "results_sweep.csv"),
  Harness.csv(sweep, [:policy, :need_target, :backlog, :rate, :grace_s, :drain_ms, :lost, :rep])
)
IO.puts("[C] sweep rows: #{length(sweep)}")

# A — end-to-end rollout time (3 pods, heavy load) -------------------------
roll = for pol <- [:static30, :static300, :m3], do: Harness.rollout(pol, 3, 400, 10)
File.write!(
  Path.join(data, "results_rollout.csv"),
  Harness.csv(roll, [:policy, :pods, :backlog, :rate, :rollout_ms, :lost])
)
IO.puts("[A] rollout: #{inspect(Enum.map(roll, &{&1.policy, &1.rollout_ms, &1.lost}))}")

:peer.stop(ppid)
IO.puts("DONE extended eval")
