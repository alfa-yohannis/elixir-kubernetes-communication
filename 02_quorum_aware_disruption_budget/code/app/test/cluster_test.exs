defmodule QuorumBudget.ClusterTest do
  @moduledoc """
  Tes terdistribusi (tag `:cluster`): membentuk cluster peer BEAM sungguhan, lalu menegaskan klaim
  keselamatan inti M7 — budget quorum-aware tak pernah memecah kuorum saat rolling update, sedangkan
  budget statis yang terlalu besar memecahnya. Dikecualikan dari `mix test` baku; jalankan dengan:
    MIX_ENV=test elixir --name primary@127.0.0.1 --cookie ck -S mix test --only cluster
  """
  use ExUnit.Case, async: false
  @moduletag :cluster
  alias QuorumBudget.{Disruptor, Quorum, QuorumProbe}

  @n 5

  setup do
    Node.set_cookie(:ck)
    # Patok kuorum ke ukuran cluster yang diinginkan = @n (lihat Cluster.quorum_threshold/1).
    env = Application.get_all_env(:quorum_budget) |> Keyword.put(:cluster_size, @n)

    nodes =
      for i <- 1..@n do
        {:ok, _pid, node} =
          :peer.start(%{
            name: :"ct#{i}",
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

    for a <- nodes, b <- nodes, a < b, do: :rpc.call(a, Node, :connect, [b])
    Process.sleep(800)

    on_exit(fn -> Enum.each(nodes, fn n -> :rpc.call(n, :init, :stop, []) end) end)
    {:ok, nodes: nodes}
  end

  test "probe menurunkan kuorum mayoritas yang benar dari ukuran cluster yang dilihatnya", %{nodes: nodes} do
    # Node pengendali (primary) dikecualikan dari hitungan kuorum (config :control_node_prefix), jadi
    # probe melihat tepat @n node app. Kuorum dipatok ke ukuran yang diinginkan (:cluster_size=@n).
    r = :rpc.call(hd(nodes), QuorumProbe, :reading, [])
    assert r.n == @n
    assert r.q == Quorum.majority(@n)
    assert r.in_quorum == true
  end

  test "budget quorum-aware menjaga kuorum; budget statis terlalu besar memecahnya", %{nodes: nodes} do
    q = Quorum.majority(@n)

    qa = Disruptor.rolling_cycle(nodes, Disruptor.budget_for(:quorum_aware, @n, q), q, pace_ms: 100)
    refute qa.quorum_violated?
    assert qa.min_available >= q

    static = Disruptor.rolling_cycle(nodes, q, q, pace_ms: 100)
    assert static.quorum_violated?
    assert static.min_available < q
  end
end
