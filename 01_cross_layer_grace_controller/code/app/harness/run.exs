# V2 experiment runner. Launch with a distributed primary (it spawns a survivor peer):
#   MIX_ENV=test elixir --name primary@127.0.0.1 --cookie ck -S mix run harness/run.exs
# Writes real measurements to ../../data/results_runs.csv and prints a summary.

Node.set_cookie(:ck)

{:ok, ppid, _peer} =
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
IO.puts("cluster up: primary=#{Node.self()} survivor=#{inspect(Node.list())}")

# Loads chosen so one is comfortably under and one comfortably over a 30 s fixed grace:
#   L1: need = 80/8  = 10 s  (< 30)     L2: need = 160/4 = 40 s  (> 30)
loads = [%{backlog: 80, rate: 8}, %{backlog: 160, rate: 4}]
rows = GraceConvergence.Harness.run(loads, 1)

data_dir = Path.expand("../../data", File.cwd!())
File.mkdir_p!(data_dir)
csv_path = Path.join(data_dir, "results_runs.csv")
File.write!(csv_path, GraceConvergence.Harness.to_csv(rows))
IO.puts("\nwrote #{csv_path}")

IO.puts("\n=== SUMMARY policy,B,rho,need_s,grace_s,drain_ms,lost ===")
for r <- rows do
  IO.puts("#{r.policy},#{r.backlog},#{r.rate},#{r.need_s},#{r.grace_s},#{r.drain_ms},#{r.lost}")
end

:peer.stop(ppid)
