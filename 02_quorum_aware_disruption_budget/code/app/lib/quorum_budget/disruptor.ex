defmodule QuorumBudget.Disruptor do
  @moduledoc """
  Mensimulasikan **gangguan sukarela** (rolling update / drain node) pada cluster BEAM yang sungguhan
  dan **mengukur** apakah kuorum tetap terjaga. Ini mesin pengukur di balik eksperimen RQ.

  Idenya: kita punya cluster `n` node app yang saling terhubung (full mesh). Sebuah rolling update
  mengganti semua node secara bertahap, *satu batch sekaligus*; ukuran batch = **disruption budget**
  (maxUnavailable). Untuk tiap batch kita benar-benar memutus node-node itu dari cluster
  (`Node.disconnect`), lalu MENGUKUR ukuran cluster yang tersisa dari sudut pandang node yang masih
  hidup (nilai `Node.list/0` yang sungguhan, bukan aritmetika), lalu menyambungkannya kembali (node
  pengganti "versi baru" bergabung).

  Dua policy dibandingkan:
    * `:quorum_aware` — budget = `n - Q` (dari `QuorumBudget.Quorum`), sehingga anggota tersedia tak
      pernah turun di bawah kuorum `Q`.
    * `:static` — budget = nilai tetap yang disetel manual; bila melebihi `n - Q`, gangguan menurunkan
      anggota di bawah kuorum (kuorum pecah) walau PDB tingkat-pod "terpenuhi".

  Metrik per lintasan: `min_available` (ukuran cluster terkecil yang TERUKUR selama operasi),
  `quorum_violated?` (apakah `min_available < Q`), dan `blocked_batches` (berapa batch yang
  meninggalkan cluster di bawah kuorum — saat itu beban kerja yang bergantung-kuorum akan terblokir).
  """
  require Logger

  @doc """
  Menjalankan satu rolling update penuh atas `app_nodes` dengan ukuran batch `batch` dan ambang
  kuorum `q`. `pace_ms` adalah jeda per batch (mensimulasikan waktu handoff/konvergensi pengganti).

  Mengembalikan map metrik. Pengukuran ukuran cluster diambil dari node yang BUKAN bagian batch yang
  sedang diputus (selalu ada selama `batch < n`).
  """
  @spec rolling_cycle([node()], pos_integer(), pos_integer(), keyword()) :: map()
  def rolling_cycle(app_nodes, batch, q, opts \\ []) do
    n = length(app_nodes)
    pace_ms = Keyword.get(opts, :pace_ms, 0)
    t0 = System.monotonic_time(:millisecond)

    # Ganti semua node satu batch sekaligus (rolling update). Akumulasi: ukuran-tersedia minimum,
    # jumlah batch yang turun di bawah kuorum, dan jumlah SURVIVOR yang stall (tak bisa maju karena
    # kehilangan kuorum) -- inilah konsekuensi nyata bagi cluster yang masih melayani (RQ8).
    {min_avail, blocked, stalled} =
      app_nodes
      |> Enum.chunk_every(batch)
      |> Enum.reduce({n, 0, 0}, fn chunk, {min_a, blk, stl} ->
        survivors = app_nodes -- chunk
        Enum.each(chunk, &evict(&1, app_nodes))
        if pace_ms > 0, do: Process.sleep(pace_ms)

        # UKUR ukuran cluster yang tersisa dari sudut pandang node survivor (yang tidak di-evict).
        a = measure_available(app_nodes, chunk)
        # Hitung survivor yang TIDAK berkuorum (stall) selama jendela ini -- konsekuensi workload.
        stalled_now = count_stalled(survivors)

        Enum.each(chunk, &rejoin(&1, app_nodes))
        Process.sleep(80)

        {min(min_a, a), blk + if(a < q, do: 1, else: 0), stl + stalled_now}
      end)

    ms = System.monotonic_time(:millisecond) - t0

    %{
      n: n,
      q: q,
      batch: batch,
      min_available: min_avail,
      quorum_violated?: min_avail < q,
      blocked_batches: blocked,
      stalled_survivors: stalled,
      maintenance_ms: ms
    }
  end

  # Berapa survivor yang TIDAK berkuorum (tak bisa melakukan commit yang bergantung-kuorum) selama
  # sebuah jendela eviction. Query nyata `Cluster.in_quorum?` ke tiap survivor.
  defp count_stalled(survivors) do
    Enum.count(survivors, fn s ->
      case :rpc.call(s, QuorumBudget.Cluster, :in_quorum?, []) do
        true -> false
        false -> true
        _ -> false
      end
    end)
  end

  @doc """
  Ukuran budget (maxUnavailable) untuk sebuah policy:
    * `:quorum_aware` -> `n - q` (dari policy), dijepit minimal 1.
    * `{:static, b}`  -> nilai tetap `b`.
  """
  @spec budget_for(:quorum_aware | {:static, pos_integer()}, pos_integer(), pos_integer()) :: pos_integer()
  def budget_for(:quorum_aware, n, q), do: max(1, QuorumBudget.Quorum.budget(%{n: n, q: q}).max_unavailable)
  def budget_for({:static, b}, _n, _q), do: b

  # --- helper privat -----------------------------------------------------------------------------

  # Ukur ukuran cluster yang TERSEDIA dari sudut pandang sebuah node survivor (yang tidak sedang
  # diputus): ukuran komponen terhubung yang memuatnya = `length(Node.list)+1` di node itu, dibatasi
  # ke himpunan app. Mengembalikan jumlah node app yang masih saling terlihat.
  defp measure_available(app_nodes, evicted_chunk) do
    survivors = app_nodes -- evicted_chunk

    case survivors do
      [] ->
        0

      [ref | _] ->
        # Tanya satu survivor: app-node mana saja yang masih terhubung dengannya (+ dirinya).
        case :rpc.call(ref, Node, :list, []) do
          peers when is_list(peers) ->
            (([ref | peers] |> Enum.filter(&(&1 in app_nodes)) |> Enum.uniq()) |> length())

          _ ->
            length(survivors)
        end
    end
  end

  # "Usir" satu node dari cluster: putuskan ia dari setiap node app lain (dari sisi node itu, karena
  # putus bersifat dua-arah), lalu dari node pengendali. Urutan penting: RPC ke node dulu SELAGI masih
  # terhubung, baru putuskan dari diri kita.
  defp evict(node, app_nodes) do
    others = app_nodes -- [node]
    Enum.each(others, fn o -> :rpc.call(node, Node, :disconnect, [o]) end)
    :erlang.disconnect_node(node)
  end

  # Sambungkan kembali node (pengganti "versi baru" bergabung): pengendali menyambung dulu, lalu node
  # menyambung ke semua peer app lain untuk membentuk ulang mesh.
  defp rejoin(node, app_nodes) do
    others = app_nodes -- [node]
    Node.connect(node)
    Enum.each(others, fn o -> :rpc.call(node, Node, :connect, [o]) end)
  end
end
