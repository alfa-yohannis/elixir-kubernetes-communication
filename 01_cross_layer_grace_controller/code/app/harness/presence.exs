# Studi kasus beban kerja realistis: re-konvergensi Phoenix.Tracker (mesin CRDT di balik
# Phoenix.Presence) saat sebuah node pergi. Mengukur waktu konvergensi-keanggotaan NYATA T_c (suku
# konvergensi pada invariant) sebagai fungsi jumlah presence N yang dilacak, pada fitur terdistribusi
# Phoenix yang tidak dimodifikasi. Luncurkan dengan primary terdistribusi (membuat/spawn peer survivor):
#   MIX_ENV=test elixir --name primary@127.0.0.1 --cookie ck -S mix run harness/presence.exs
# Menulis data/results_presence.csv. (Jangan pernah pkill -f '...@127.0.0.1' di sini -- mematikan shell ini.)

Node.set_cookie(:ck)

{:ok, ppid, _} =
  :peer.start(%{name: :surv, host: ~c"127.0.0.1", longnames: true,
                connection: :standard, args: [~c"-setcookie", ~c"ck"]})

peer = :"surv@127.0.0.1"
:rpc.call(peer, :code, :add_paths, [:code.get_path()])
:rpc.call(peer, Application, :put_all_env, [[grace_convergence: Application.get_all_env(:grace_convergence)]])
{:ok, _} = :rpc.call(peer, Application, :ensure_all_started, [:grace_convergence])
Process.sleep(1500)

# Phoenix.PubSub + the Phoenix.Tracker presence shard are started by the app's supervision tree on
# BOTH nodes (the primary via `mix run`, the survivor via `ensure_all_started` above), so they persist
# and replicate via PubSub/PG2 across the connected nodes. Just let them come up and discover.
Process.sleep(2500)
IO.puts("cluster=#{inspect(Node.list())} presence up local=#{inspect(Process.whereis(GraceConvergence.Presence))}")

topic = "room"
surv_count = fn -> :rpc.call(peer, GraceConvergence.Presence, :count, [topic]) end

# Elapsed ms until the SURVIVOR's view of the topic reaches `target` (or :timeout).
poll = fn target, deadline_ms ->
  t0 = System.monotonic_time(:millisecond)
  run = fn run ->
    cond do
      surv_count.() == target -> System.monotonic_time(:millisecond) - t0
      System.monotonic_time(:millisecond) - t0 > deadline_ms -> :timeout
      true -> Process.sleep(40); run.(run)
    end
  end
  run.(run)
end

data = Path.expand("../../data", File.cwd!())
File.mkdir_p!(data)
csv = Path.join(data, "results_presence.csv")
File.write!(csv, "n,add_ms,reconverge_ms\n")

for n <- [100, 500, 1000, 2000] do
  # N presence owners on the PRIMARY (each presence vanishes when its process exits).
  pids =
    for i <- 1..n do
      spawn(fn ->
        GraceConvergence.Presence.track(self(), topic, "u#{n}_#{i}")
        receive do
          :stop -> :ok
        end
      end)
    end

  add_ms = poll.(n, 30_000)              # survivor sees all N (add-convergence)
  Enum.each(pids, &send(&1, :stop))      # graceful departure: owners exit
  reconverge_ms = poll.(0, 30_000)       # survivor converges back to 0 (T_c)

  File.write!(csv, "#{n},#{add_ms},#{reconverge_ms}\n", [:append])
  IO.puts("PRESENCE n=#{n} add=#{add_ms}ms reconverge=#{reconverge_ms}ms")
  Process.sleep(800)
end

:peer.stop(ppid)
IO.puts("DONE presence")
