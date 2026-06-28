defmodule QuorumBudget.Harness do
  @moduledoc """
  Mesin eksperimen untuk RQ. Fungsi-fungsi di sini menjalankan rolling update sungguhan atas
  sekumpulan node app (`QuorumBudget.Disruptor`) dan/atau mengevaluasi policy murni, lalu
  mengembalikan baris data untuk ditulis ke CSV. Penyiapan cluster peer ada di skrip `harness/*.exs`.
  """
  alias QuorumBudget.{Disruptor, Quorum}

  @doc """
  Membentuk cluster `n` node app peer (full mesh) untuk eksperimen. Tiap peer mewarisi config primary
  (di `MIX_ENV=test`: tanpa port/cluster, dan mengecualikan node pengendali dari hitungan kuorum).
  Mengembalikan daftar node. Hentikan dengan `stop_mesh/1`.
  """
  def spawn_mesh(n) do
    # Patok kuorum ke ukuran cluster yang DIINGINKAN = n (lihat Cluster.quorum_threshold/1).
    env = Application.get_all_env(:quorum_budget) |> Keyword.put(:cluster_size, n)

    nodes =
      for i <- 1..n do
        {:ok, _pid, node} =
          :peer.start(%{
            name: :"app#{i}",
            host: ~c"127.0.0.1",
            longnames: true,
            connection: :standard,
            # Nonaktifkan prevent_overlapping_partitions: kalau aktif, :global ikut menyambung/memutus
            # node untuk mencegah partisi tumpang-tindih, mengganggu topologi terkontrol eksperimen.
            args: [~c"-setcookie", ~c"ck", ~c"-kernel", ~c"prevent_overlapping_partitions", ~c"false"]
          })

        :rpc.call(node, :code, :add_paths, [:code.get_path()])
        :rpc.call(node, Application, :put_all_env, [[quorum_budget: env]])
        {:ok, _} = :rpc.call(node, Application, :ensure_all_started, [:quorum_budget])
        node
      end

    for a <- nodes, b <- nodes, a < b, do: :rpc.call(a, Node, :connect, [b])
    Process.sleep(1000)
    nodes
  end

  @doc "Menghentikan semua node peer (membersihkan antar-skenario)."
  def stop_mesh(nodes) do
    Enum.each(nodes, fn n -> :rpc.call(n, :init, :stop, []) end)
    Process.sleep(300)
  end

  @doc """
  **RQ8 (realistic workload).** Tiap node menjalankan beban kerja yang bergantung-kuorum
  (`QuorumBudget.QuorumWorkload`): sebuah *commit* hanya boleh bila node melihat kuorum (seperti grup
  konsensus yang butuh mayoritas). Saat rolling update, kita ukur berapa SURVIVOR yang **terblokir**
  (out-of-quorum, tak bisa commit) selama tiap jendela eviction, untuk policy statis vs quorum-aware.
  Pengukuran memakai cek `Cluster.in_quorum?` yang sama dengan yang dipakai workload. Pada
  quorum-aware survivor tak pernah terblokir (kuorum terjaga); pada statis, semua survivor terblokir
  selama jendela sub-kuorum (mereka tak bisa melayani walau "hidup" menurut probe pod).
  """
  def workload(app_nodes, static_budget, opts \\ []) do
    n = length(app_nodes)
    q = Quorum.majority(n)

    for {policy, b} <- [{"static", static_budget}, {"quorum_aware", Disruptor.budget_for(:quorum_aware, n, q)}] do
      Disruptor.rolling_cycle(app_nodes, b, q, opts)
      |> Map.put(:policy, policy)
    end
  end

  @doc """
  **RQ1 (safety) + RQ2 (efficiency).** Untuk cluster `app_nodes` dengan kuorum mayoritas, bandingkan
  policy `:static` (budget tetap, mungkin terlalu besar) dengan `:quorum_aware` (budget = n - Q).
  `pace_ms` mensimulasikan waktu pengganti menjadi siap per batch. Mengembalikan satu baris per policy
  dengan ukuran-tersedia minimum TERUKUR, pelanggaran kuorum, dan waktu maintenance.
  """
  def safety(app_nodes, static_budget, opts \\ []) do
    n = length(app_nodes)
    q = Quorum.majority(n)
    qa = Disruptor.budget_for(:quorum_aware, n, q)

    for {policy, b} <- [{"static", static_budget}, {"quorum_aware", qa}] do
      Disruptor.rolling_cycle(app_nodes, b, q, opts)
      |> Map.put(:policy, policy)
    end
  end

  @doc """
  **RQ9 (vs baseline reactive).** Baseline tanpa model: mulai dengan budget longgar (`minAvailable=1`,
  yakni `maxUnavailable=N-1`) lalu NAIKKAN `minAvailable` satu per satu setiap kali rolling update
  memecah kuorum, sampai aman. Tiap percobaan yang memecah kuorum membayar dengan kehilangan kuorum
  nyata. Kontras: pengendali berbasis-model menetapkan `minAvailable=Q` dari pembacaan PERTAMA -> 0
  pelanggaran. Mengembalikan daftar percobaan (apa yang dicoba, apakah pecah).
  """
  def reactive(app_nodes, opts \\ []) do
    n = length(app_nodes)
    q = Quorum.majority(n)

    {_final, attempts} =
      Enum.reduce_while(1..n, {1, []}, fn _, {min_avail, acc} ->
        batch = max(1, n - min_avail)
        r = Disruptor.rolling_cycle(app_nodes, batch, q, opts)

        attempt = %{
          attempt: length(acc) + 1,
          min_available: min_avail,
          batch: batch,
          min_observed: r.min_available,
          violated: r.quorum_violated?
        }

        if r.quorum_violated? do
          {:cont, {min_avail + 1, acc ++ [attempt]}}
        else
          {:halt, {min_avail, acc ++ [attempt]}}
        end
      end)

    attempts
  end

  @doc """
  **RQ3 (adaptivity).** Untuk tiap ukuran cluster `n`, kuorum mayoritas dan budget yang DIHITUNG
  policy (min_available harus melacak `div(n,2)+1`). Pure policy, deterministik.
  """
  def adaptivity(sizes) do
    for n <- sizes do
      q = Quorum.majority(n)
      b = Quorum.budget(%{n: n, q: q})
      %{n: n, q: q, min_available: b.min_available, max_unavailable: b.max_unavailable}
    end
  end

  @doc """
  **RQ4 (overhead).** Latensi perhitungan budget (nanodetik per panggilan), rata-rata `reps` panggilan.
  Perhitungan O(1), tak bergantung ukuran cluster.
  """
  def overhead(reps \\ 200_000) do
    r = %{n: 7, q: 4}
    {us, _} = :timer.tc(fn -> Enum.each(1..reps, fn _ -> Quorum.budget(r) end) end)
    %{reps: reps, budget_compute_ns: Float.round(us * 1000 / reps, 1)}
  end

  @doc """
  **RQ5 (robustness).** Sensitivitas budget terhadap estimasi kuorum `q` pada cluster ukuran `n`:
  untuk tiap `q` dari 1..n, tunjukkan min_available/max_unavailable yang dihasilkan. Menyorot bahwa
  meng-UNDER-estimasi `q` (terlalu kecil) mengizinkan terlalu banyak eviction (tak aman), sehingga
  fallback harus bias ke ATAS.
  """
  def sensitivity(n \\ 7) do
    for q <- 1..n do
      b = Quorum.budget(%{n: n, q: q})
      %{n: n, q: q, min_available: b.min_available, max_unavailable: b.max_unavailable}
    end
  end

  @doc """
  **RQ6 (scalability).** Untuk tiap ukuran `n`, budget mayoritas + waktu hitung budget. Menunjukkan
  perhitungan tetap O(1) saat `n` membesar.
  """
  def scale(sizes, reps \\ 100_000) do
    for n <- sizes do
      q = Quorum.majority(n)
      r = %{n: n, q: q}
      {us, _} = :timer.tc(fn -> Enum.each(1..reps, fn _ -> Quorum.budget(r) end) end)
      b = Quorum.budget(r)

      %{
        n: n,
        q: q,
        min_available: b.min_available,
        max_unavailable: b.max_unavailable,
        budget_compute_ns: Float.round(us * 1000 / reps, 1)
      }
    end
  end
end
