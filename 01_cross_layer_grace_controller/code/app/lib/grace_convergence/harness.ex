defmodule GraceConvergence.Harness do
  @moduledoc """
  **Driver eksperimen**: kode yang menjalankan skenario terkontrol pada cluster BEAM 2-node dan
  mencatat pengukuran NYATA ke dalam map/CSV (lalu diplot oleh `analysis/plot.py`).

  Pola dasarnya selalu sama: untuk tiap skenario, mulai sejumlah worker stateful di node INI (node
  yang akan "pergi"), jalankan drain di bawah suatu policy pada laju handoff tertentu, lalu catat:
  grace yang dipilih (detik), waktu drain nyata (ms), backlog, dan jumlah worker yang HILANG (handoff
  terpotong karena grace terlalu pendek). Dijalankan di node yang pergi pada cluster 2-node yang
  sudah terhubung — lihat skrip di `harness/`.

  Pemetaan ke research question (RQ): `run/2`+`run_sweep/3` -> RQ1/RQ2/RQ3, `rollout/4` -> RQ2,
  `overhead/1` -> RQ4, `scale/1` -> RQ6.
  """
  require Logger
  alias GraceConvergence.{Grace, Probe, Handoff, Workers}

  # Empat policy yang dibandingkan: tiga baseline tetap + satu adaptif (:m3).
  @policies [:static30, :static300, :prestop_sleep, :m3]

  @doc """
  Menjalankan matriks (policy x load). `loads` = `[%{backlog: B, rate: rho}, ...]`. Untuk tiap
  kombinasi policy dan load (diulang `repeats` kali) menjalankan satu skenario. Mengembalikan daftar
  baris hasil (map). Dipakai untuk RQ1/RQ2/RQ3.
  """
  def run(loads, repeats \\ 1) do
    for load <- loads, policy <- @policies, rep <- 1..repeats do
      scenario(policy, load, rep)
    end
  end

  # Menjalankan SATU skenario: set policy & laju, bersihkan, mulai backlog, hitung grace, drain, ukur.
  defp scenario(policy, %{backlog: backlog, rate: rate}, rep) do
    # Konfigurasikan policy dan batas laju handoff untuk run ini.
    Application.put_env(:grace_convergence, :grace_policy, policy)
    Application.put_env(:grace_convergence, :handoff_rate_limit, rate)
    Probe.reset()
    cleanup()

    # Tumpuk `backlog` worker di node ini, lalu tunggu sampai semuanya benar-benar hidup.
    Workers.start_many_local(backlog, "s#{policy}_#{backlog}_#{rate}_#{rep}_")
    wait_local(backlog)

    # Tentukan grace (detik) untuk policy ini, lalu drain dengan tenggat = grace dan ukur lama drain.
    grace_s = grace_for(policy)
    t0 = System.monotonic_time(:millisecond)
    result = Handoff.drain(grace_s * 1000, rate)
    drain_ms = System.monotonic_time(:millisecond) - t0

    # `lost` = berapa worker yang masih tertinggal saat tenggat habis (0 bila handoff tuntas).
    lost =
      case result do
        {:timeout, remaining} -> remaining
        :ok -> 0
      end

    Logger.info("#{policy} B=#{backlog} rho=#{rate} grace=#{grace_s}s drain=#{drain_ms}ms lost=#{lost}")
    cleanup()

    # Satu baris hasil. `need_s` = backlog/rate = lama handoff yang "dibutuhkan" (untuk perbandingan).
    %{
      policy: policy,
      backlog: backlog,
      rate: rate,
      rep: rep,
      need_s: Float.round(backlog / rate, 1),
      grace_s: grace_s,
      drain_ms: drain_ms,
      lost: lost,
      completed: result == :ok
    }
  end

  # Grace untuk policy adaptif: dihitung dari reading probe lewat `Grace.compute/2`.
  defp grace_for(:m3) do
    cfg = Application.get_all_env(:grace_convergence)

    Grace.compute(Probe.reading(),
      sigma: cfg[:sigma],
      g_min: cfg[:g_min],
      g_max: cfg[:g_max],
      t_d: cfg[:t_d],
      fallback: cfg[:g_max]
    )
  end

  # Grace untuk policy baseline (nilai tetap, tidak melihat beban).
  defp grace_for(:prestop_sleep), do: Application.get_env(:grace_convergence, :static_grace, 30)
  defp grace_for(:static30), do: 30
  defp grace_for(:static300), do: 300

  # Bersihkan semua worker di node ini DAN di semua peer (via RPC), lalu tunggu total kembali ke 0.
  defp cleanup do
    Workers.stop_all()
    for n <- Node.list(), do: :rpc.call(n, Workers, :stop_all, [])
    wait_total(0)
  end

  # Tunggu (polling tiap 50 ms, maksimal `tries` kali) sampai jumlah worker LOKAL >= `target`.
  defp wait_local(target, tries \\ 100) do
    cond do
      Workers.local_count() >= target -> :ok
      tries <= 0 -> :ok
      true -> Process.sleep(50); wait_local(target, tries - 1)
    end
  end

  # Tunggu sampai jumlah worker TOTAL se-cluster <= `target` (mis. 0 setelah cleanup).
  defp wait_total(target, tries \\ 60) do
    cond do
      Workers.count() <= target -> :ok
      tries <= 0 -> :ok
      true -> Process.sleep(50); wait_total(target, tries - 1)
    end
  end

  # ---- Sweep beban dengan pengulangan (kurva + selang kepercayaan) — RQ1/RQ2 -------------------
  @doc """
  Menyapu (sweep) berbagai "kebutuhan" handoff (`B = need*rate`), semua policy, masing-masing
  `repeats` kali. Menambahkan `:need_target` ke tiap baris untuk sumbu-x kurva.
  """
  def run_sweep(needs, rate, repeats) do
    for need <- needs, policy <- @policies, rep <- 1..repeats do
      scenario(policy, %{backlog: round(need * rate), rate: rate}, rep)
      |> Map.put(:need_target, need)
    end
  end

  # ---- Waktu rolling-update end-to-end (K pod di-drain berurutan, dipacu) — RQ2 ----------------
  @doc "Memodelkan rolling update `pods` drain berurutan di bawah satu policy; mengukur total waktu."
  def rollout(policy, pods, backlog, rate) do
    Application.put_env(:grace_convergence, :grace_policy, policy)
    Application.put_env(:grace_convergence, :handoff_rate_limit, rate)
    t0 = mono()

    # Untuk tiap "pod", mulai backlog, drain, dan akumulasikan jumlah worker yang hilang.
    lost =
      Enum.reduce(1..pods, 0, fn i, acc ->
        Probe.reset()
        cleanup()
        Workers.start_many_local(backlog, "r#{policy}#{i}_")
        wait_local(backlog)
        g = grace_for(policy)

        acc + (case Handoff.drain(g * 1000, rate) do
                 {:timeout, r} -> r
                 :ok -> 0
               end)
      end)

    cleanup()
    %{policy: policy, pods: pods, backlog: backlog, rate: rate, rollout_ms: mono() - t0, lost: lost}
  end

  # ---- Overhead controller (latensi probe, memori per-worker, throughput) — RQ4 ----------------
  @doc "Mengukur overhead controller di node ini: latensi probe, memori per-worker, throughput handoff."
  def overhead(n \\ 200) do
    cleanup()
    # Latensi probe: waktu rata-rata 1000 pembacaan (`:timer.tc` mengembalikan mikrodetik).
    {lat_us, _} = :timer.tc(fn -> for _ <- 1..1000, do: Probe.reading() end)

    # Memori per-worker: selisih memori VM total sebelum/sesudah memulai `n` worker, dibagi `n`.
    m0 = :erlang.memory(:total)
    Workers.start_many_local(n, "ov_")
    wait_local(n)
    mem_per_worker = (:erlang.memory(:total) - m0) / n

    # Throughput handoff mentah: lama men-drain `n` worker tanpa throttle -> proses/detik.
    Application.put_env(:grace_convergence, :handoff_rate_limit, nil)
    Probe.reset()
    {ho_us, _} = :timer.tc(fn -> Handoff.drain(60_000, nil) end)
    cleanup()

    %{
      probe_latency_us: Float.round(lat_us / 1000, 2),
      mem_per_worker_bytes: round(mem_per_worker),
      handoff_throughput_eps: round(n / (ho_us / 1_000_000))
    }
  end

  # ---- Skalabilitas: variasikan |H| lalu ukur waktu/throughput/memori/grace — RQ6 ---------------
  @doc "Untuk tiap ukuran backlog, mulai sebanyak itu worker lalu handoff semuanya (tanpa throttle)."
  def scale(sizes) do
    for h <- sizes do
      cleanup()
      Probe.reset()
      Application.put_env(:grace_convergence, :handoff_rate_limit, nil)

      # Ukur biaya memulai `h` worker: waktu start dan memori yang bertambah (MiB).
      m0 = :erlang.memory(:total)
      t_start = mono()
      Workers.start_many_local(h, "sc#{h}_")
      start_ms = mono() - t_start
      mem_mb = Float.round((:erlang.memory(:total) - m0) / 1_048_576, 1)

      # Drain semuanya dengan tenggat besar (600 s); ukur lama drain dan throughput efektif.
      grace_s = grace_for(:m3)
      t0 = mono()
      res = Handoff.drain(600_000, nil)
      drain_ms = max(mono() - t0, 1)

      lost = (case res do {:timeout, r} -> r; :ok -> 0 end)
      cleanup()

      %{
        backlog: h,
        start_ms: start_ms,
        mem_mb: mem_mb,
        grace_s: grace_s,
        drain_ms: drain_ms,
        throughput_eps: round(h / (drain_ms / 1000)),
        lost: lost
      }
    end
  end

  # Jam monotonic (ms) — alias pendek dipakai di banyak tempat di atas.
  defp mono, do: System.monotonic_time(:millisecond)

  @doc "Membuat teks CSV dari baris-baris (map) dan daftar kolom (atom) yang terurut."
  def csv(rows, columns) do
    header = Enum.map_join(columns, ",", &Atom.to_string/1)
    body = Enum.map_join(rows, "\n", fn r -> Enum.map_join(columns, ",", &"#{Map.get(r, &1)}") end)
    header <> "\n" <> body <> "\n"
  end

  @doc "CSV (satu baris per run) untuk matriks dua-load asli, dengan urutan kolom yang baku."
  def to_csv(rows) do
    csv(rows, [:policy, :backlog, :rate, :need_s, :grace_s, :drain_ms, :lost, :completed])
  end
end
