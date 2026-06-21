defmodule GraceConvergence.Shutdown do
  @moduledoc """
  **Hook terminasi adaptif** — bagian yang dijalankan tepat ketika pod akan dimatikan.

  Saat shutdown yang rapi (atau ketika `drain_and_await/0` dipanggil eksplisit oleh preStop hook), ia
  menghitung jendela grace sesuai policy yang dikonfigurasi, lalu men-drain & meng-handoff di dalam
  jendela itu. Idenya: gunakan waktu grace untuk benar-benar menyelesaikan handoff, bukan sekadar
  "tidur" sekian detik.

  Pilihan policy (config `:grace_policy`) — dipakai untuk membandingkan beberapa strategi:
    * `:m3`            -> grace dihitung dari probe lewat `Grace.compute/2` (adaptif; kontribusi kita)
    * `:prestop_sleep` -> grace tetap `:static_grace` detik (meniru preStop sleep yang umum)
    * `:static30`      -> grace tetap 30 detik (default Kubernetes)
    * `:static300`     -> grace tetap 300 detik (over-provisioned/aman tapi lambat)
  """
  use GenServer
  require Logger
  alias GraceConvergence.{Grace, Probe, Handoff}

  @doc "Memulai proses hook dan mendaftarkannya di bawah nama modul ini."
  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  @doc "Menjalankan drain secara sinkron (dipakai oleh tes dan oleh jalur SIGTERM/preStop)."
  def drain_and_await, do: GenServer.call(__MODULE__, :drain, :infinity)

  @impl true
  def init(_) do
    # `trap_exit` mengubah sinyal exit menjadi pesan biasa sehingga callback `terminate/2` di bawah
    # dijalankan saat shutdown — di situlah kita menjalankan drain sebelum proses benar-benar mati.
    Process.flag(:trap_exit, true)
    {:ok, %{}}
  end

  @impl true
  # Permintaan :drain eksplisit (mis. dari endpoint POST /drain) -> jalankan drain dan balas hasilnya.
  def handle_call(:drain, _from, s), do: {:reply, do_drain(), s}

  @impl true
  # Dipanggil otomatis saat proses dihentikan (mis. SIGTERM): jalankan drain sebelum pamit.
  def terminate(_reason, _s) do
    do_drain()
    :ok
  end

  # Logika drain bersama: tentukan policy & grace, log, lalu jalankan handoff dalam batas grace itu.
  defp do_drain do
    cfg = Application.get_all_env(:grace_convergence)
    policy = Keyword.get(cfg, :grace_policy, :m3)
    g_max = Keyword.get(cfg, :g_max, 120)
    rate_limit = Keyword.get(cfg, :handoff_rate_limit)
    reading = Probe.reading()

    # Hitung berapa detik grace menurut policy yang aktif.
    g_seconds = grace_for(policy, reading, cfg, g_max)

    Logger.info(
      "drain policy=#{policy} grace=#{g_seconds}s backlog=#{reading.backlog} rate=#{reading.rate_eps}/s"
    )

    # Jalankan handoff dengan tenggat = grace (dalam milidetik). `Handoff.drain` balas :ok atau
    # {:timeout, sisa} bila grace keburu habis.
    result = Handoff.drain(g_seconds * 1000, rate_limit)
    %{policy: policy, grace_s: g_seconds, result: result, lost: lost(result)}
  end

  # Policy adaptif: grace dihitung dari reading probe lewat `Grace.compute/2`.
  defp grace_for(:m3, reading, cfg, g_max) do
    Grace.compute(reading,
      sigma: Keyword.get(cfg, :sigma, 5),
      g_min: Keyword.get(cfg, :g_min, 5),
      g_max: g_max,
      t_d: Keyword.get(cfg, :t_d, 1),
      fallback: g_max
    )
  end

  # Policy baseline (grace tetap, tidak melihat beban) — untuk pembanding di eksperimen.
  defp grace_for(:prestop_sleep, _r, cfg, _), do: Keyword.get(cfg, :static_grace, 30)
  defp grace_for(:static30, _r, _cfg, _), do: 30
  defp grace_for(:static300, _r, _cfg, _), do: 300

  # Menerjemahkan hasil drain menjadi "jumlah worker yang hilang": sisa saat timeout, atau 0 bila :ok.
  defp lost({:timeout, remaining}), do: remaining
  defp lost(:ok), do: 0
end
