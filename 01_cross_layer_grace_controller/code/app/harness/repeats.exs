# Penjalan rigor-statistik: mengulang skenario utama agar bisa melaporkan rata-rata +/- CI 95%.
# Men-stream tiap hasil begitu selesai (data parsial selamat bila terinterupsi). Luncurkan dengan:
#   MIX_ENV=test elixir --name primary@127.0.0.1 --cookie ck -S mix run harness/repeats.exs
# Menulis data/results_runs_ci.csv (beban tabel, N=10) dan data/results_rollout_ci.csv (rollout, N=5).
# JANGAN PERNAH pkill -f '...@127.0.0.1' di sekitar ini (mematikan shell yang berjalan); matikan beam yatim by PID.

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
IO.puts("cluster up: #{inspect(Node.list())}")

data = Path.expand("../../data", File.cwd!())
File.mkdir_p!(data)

# ---- Table loads with repeats (headline loss/grace claim) ----
runs_csv = Path.join(data, "results_runs_ci.csv")
File.write!(runs_csv, "policy,backlog,rate,rep,need_s,grace_s,drain_ms,lost,completed\n")
loads = [%{backlog: 80, rate: 8}, %{backlog: 160, rate: 4}]
n_table = 10

for rep <- 1..n_table, load <- loads do
  for r <- GraceConvergence.Harness.run([load], 1) do
    line =
      "#{r.policy},#{r.backlog},#{r.rate},#{rep},#{r.need_s},#{r.grace_s},#{r.drain_ms},#{r.lost},#{r.completed}"

    File.write!(runs_csv, line <> "\n", [:append])
    IO.puts("RUN #{line}")
  end
end

IO.puts("=== table done; starting rollout ===")

# ---- Rolling update with repeats (end-to-end time variance) ----
roll_csv = Path.join(data, "results_rollout_ci.csv")
File.write!(roll_csv, "policy,pods,backlog,rate,rep,rollout_ms,lost\n")
policies = [:static30, :static300, :prestop_sleep, :m3]
n_roll = 5

for rep <- 1..n_roll, pol <- policies do
  r = GraceConvergence.Harness.rollout(pol, 3, 160, 4)
  line = "#{r.policy},#{r.pods},#{r.backlog},#{r.rate},#{rep},#{r.rollout_ms},#{r.lost}"
  File.write!(roll_csv, line <> "\n", [:append])
  IO.puts("ROLL #{line}")
end

:peer.stop(ppid)
IO.puts("DONE repeats")
