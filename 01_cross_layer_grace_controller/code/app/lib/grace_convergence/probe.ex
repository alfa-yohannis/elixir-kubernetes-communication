defmodule GraceConvergence.Probe do
  @moduledoc """
  **Probe konvergensi**: sensor kecil yang hanya membaca (read-only) dan melaporkan angka-angka
  runtime yang dibutuhkan policy grace (lihat `GraceConvergence.Grace`).

  Ini sebuah `GenServer` — "proses server" ala OTP yang memegang state pribadi dan menjawab pesan
  satu per satu. Proses lain berbicara dengannya melalui:
    * `GenServer.call/2`  – permintaan *sinkron*: pemanggil menunggu balasan, dan
    * `GenServer.cast/2`  – pesan *asinkron* "kirim lalu lupakan": pemanggil tidak menunggu.

  Angka terpenting yang dilaporkan adalah `rate_eps`, yaitu **laju handoff** yang bisa dicapai dalam
  proses per detik. Kita mengestimasinya dengan *exponentially weighted moving average* (EWMA):
  rata-rata berjalan yang memberi bobot lebih besar ke sampel terbaru daripada yang lama, sehingga
  satu kemacetan sesaat tidak merusak estimasi secara permanen. Rumus EWMA-nya:

      rata_baru = alpha * sampel_terbaru + (1 - alpha) * rata_lama

  dengan `alpha` antara 0 dan 1 (di sini `0.3`). `alpha` lebih besar = bereaksi lebih cepat tapi
  lebih berisik.

  Sebelum ada handoff yang teramati (jadi belum ada laju terukur), probe melaporkan throughput yang
  *dikonfigurasi* (`:handoff_rate_limit`), yaitu dugaan awal controller tentang seberapa cepat
  handoff bisa berjalan.
  """
  use GenServer
  alias GraceConvergence.Workers

  # Faktor pemulusan EWMA: bobot untuk sampel terbaru (0..1). 0.3 = cukup mulus.
  @alpha 0.3
  # Laju (proses/detik) yang diasumsikan sebelum kita benar-benar mengukur apa pun.
  @default_rate 1000.0

  @doc """
  Memulai probe dan mendaftarkannya di bawah nama modul ini agar pemanggil bisa menjangkaunya tanpa
  memegang PID. Dipanggil oleh supervision tree; argumennya diabaikan.
  """
  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  @doc "Mengambil reading probe saat ini (sebuah map) secara sinkron. Dipakai policy & endpoint HTTP."
  @spec reading() :: map()
  def reading, do: GenServer.call(__MODULE__, :reading)

  @doc """
  Memberi tahu probe bahwa `n` worker baru saja di-handoff, agar ia memperbarui EWMA laju. Ini cast
  (asinkron) karena pemanggilnya — loop handoff — tidak boleh terhambat hanya untuk pembukuan.
  """
  def record_handoff(n \\ 1), do: GenServer.cast(__MODULE__, {:handoff, n, now_ms()})

  @doc """
  Menandai awal sebuah drain. Ini menghapus "waktu handoff terakhir" supaya handoff pertama di drain
  baru tidak salah diukur terhadap jam drain sebelumnya.
  """
  def mark_drain_start, do: GenServer.cast(__MODULE__, :drain_start)

  @doc "Mereset seluruh riwayat laju ke keadaan bersih (dipakai antar-skenario eksperimen)."
  def reset, do: GenServer.call(__MODULE__, :reset)

  # --- Callback GenServer (berjalan di dalam proses probe) ---------------------------------------

  @impl true
  # State awal: catatan pengukuran yang kosong dan segar. `{:ok, state}` menjalankan server.
  def init(_), do: {:ok, fresh()}

  @impl true
  # Jawab permintaan :reading dengan menyusun laporan dari state saat ini lalu membalasnya.
  def handle_call(:reading, _from, s), do: {:reply, build_reading(s), s}
  # Jawab permintaan :reset dengan mengganti state menjadi catatan segar lalu membalas :ok.
  def handle_call(:reset, _from, _s), do: {:reply, :ok, fresh()}

  @impl true
  # Sebuah handoff terjadi pada waktu `ts` untuk `n` worker: lipat (fold) ke dalam EWMA laju.
  def handle_cast({:handoff, n, ts}, s) do
    rate =
      case s.last_ts do
        # Handoff pertama sejak drain dimulai: belum ada selisih waktu untuk diukur, pakai laju lama.
        nil ->
          s.rate_eps

        # Kasus normal: laju sesaat = n worker / detik berlalu = n * 1000 / (ts - prev) ms.
        # Campurkan ke rata-rata berjalan dengan rumus EWMA.
        prev when ts > prev ->
          @alpha * (n * 1000 / (ts - prev)) + (1 - @alpha) * s.rate_eps

        # Dua kejadian di milidetik yang sama (ts == prev): hindari pembagian nol, pakai laju lama.
        _ ->
          s.rate_eps
      end

    # Simpan laju baru, catat "sekarang" sebagai waktu handoff terakhir, dan tambah hitungan worker.
    {:noreply, %{s | rate_eps: rate, last_ts: ts, handed: s.handed + n}}
  end

  # Drain dimulai: lupakan timestamp handoff terakhir (lihat `mark_drain_start/0`).
  def handle_cast(:drain_start, s), do: {:noreply, %{s | last_ts: nil}}

  # --- helper privat -----------------------------------------------------------------------------

  # Catatan state kosong: belum ada laju, belum ada timestamp, belum ada yang di-handoff.
  defp fresh, do: %{rate_eps: 0.0, last_ts: nil, handed: 0}

  # Susun map reading publik dari state internal ditambah beberapa kueri cluster langsung.
  defp build_reading(s) do
    # Backlog = berapa worker stateful yang masih ada di node INI dan menunggu untuk dipindahkan.
    backlog = Workers.local_count()
    # Pakai laju terukur begitu ada (> 0); selain itu pakai laju yang dikonfigurasi.
    rate = if s.rate_eps > 0, do: s.rate_eps, else: configured_rate()

    %{
      node: Node.self(),
      backlog: backlog,
      rate_eps: Float.round(rate, 3),
      t_c_ms: convergence_ms(),
      in_flight: backlog,
      # "Converged" = entah kita terhubung ke node lain, atau sudah tidak ada yang perlu dipindah.
      converged?: Node.list() != [] or backlog == 0,
      handed_off: s.handed
    }
  end

  # Throughput handoff dari config aplikasi, dibersihkan menjadi float positif.
  defp configured_rate do
    case Application.get_env(:grace_convergence, :handoff_rate_limit) do
      nil -> @default_rate
      r when is_number(r) and r > 0 -> r * 1.0
      _ -> @default_rate
    end
  end

  # Estimasi convergence time T_c. Bila operator/admin menyetel nilai TERUKUR lewat config
  # `:t_c_ms` (mis. ~1500 ms dari studi Phoenix.Presence), pakai itu. Bila tidak, jatuh ke heuristik
  # kasar ~50 ms per peer — placeholder yang, seperti dicatat di moduledoc, sebaiknya diganti sinyal
  # konvergensi nyata di produksi.
  defp convergence_ms do
    case Application.get_env(:grace_convergence, :t_c_ms) do
      ms when is_number(ms) and ms >= 0 -> ms
      _ -> length(Node.list()) * 50
    end
  end

  # Pembacaan jam monotonic dalam milidetik. "Monotonic" tidak pernah mundur (berbeda dengan jam
  # dinding yang bisa melompat saat jam sistem disetel), jadi tepat untuk mengukur waktu yang berlalu.
  defp now_ms, do: System.monotonic_time(:millisecond)
end
