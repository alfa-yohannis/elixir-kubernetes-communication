defmodule GraceConvergence.Handoff do
  @moduledoc """
  Inti dari sistem: **memindahkan worker stateful dari node yang akan pergi ke node yang bertahan**,
  satu per satu, sampai tak ada yang tersisa atau waktunya habis.

  Untuk tiap worker, satu "handoff" berarti: baca state-nya -> hentikan proses lokal -> buat ulang
  proses itu di node survivor dengan state yang sama. Pemindahan di-*throttle* (dibatasi lajunya)
  agar bisa mensimulasikan beban yang berbeda-beda.

  Bagian terpenting untuk dipahami: jika `deadline` tercapai sebelum backlog habis, fungsi
  mengembalikan `{:timeout, sisa}`. Inilah persis yang terjadi saat grace terlalu pendek — handoff
  terpotong, dan worker (beserta state-nya) yang masih di lokal akan hilang ketika node dimatikan.
  Itulah "state loss" yang ingin dicegah oleh controller.
  """
  require Logger
  alias GraceConvergence.{Workers, Probe}

  # Supervisor lokal tempat worker di-host di node ini.
  @sup GraceConvergence.WorkerSup

  @doc """
  Meng-handoff semua worker lokal. `deadline_ms` membatasi total waktu tunggu; `rate_limit`
  (worker/detik, atau `nil`) membatasi laju pemindahan. Mengembalikan `:ok` bila tuntas, atau
  `{:timeout, sisa_backlog}` bila tenggat keburu habis.
  """
  def drain(deadline_ms, rate_limit \\ nil) do
    # Tandai awal drain agar probe tidak salah mengukur laju terhadap drain sebelumnya.
    Probe.mark_drain_start()
    # Mulai loop, dengan tenggat absolut = waktu-sekarang + deadline_ms.
    loop(now_ms() + deadline_ms, rate_limit)
  end

  # Loop drain rekursif. Tiap putaran memeriksa tiga kondisi (dievaluasi berurutan oleh `cond`).
  defp loop(deadline, rate_limit) do
    cond do
      # (1) Backlog lokal sudah 0 -> selesai dengan sukses.
      Workers.local_count() == 0 ->
        :ok

      # (2) Tenggat sudah lewat -> berhenti dan laporkan berapa worker yang masih tertinggal (hilang).
      now_ms() >= deadline ->
        {:timeout, Workers.local_count()}

      # (3) Masih ada waktu dan masih ada worker -> pindahkan satu, lalu ulangi.
      true ->
        case Workers.local() do
          [{id, pid} | _] ->
            case handoff_one(id, pid) do
              # Berhasil dipindah: bila ada rate_limit, tidur sejenak agar laju ≈ rate_limit/detik.
              :ok -> if rate_limit, do: Process.sleep(max(1, trunc(1000 / rate_limit)))
              # Tidak ada survivor untuk dituju: tunggu sebentar lalu coba lagi.
              :no_survivor -> Process.sleep(100)
            end

            loop(deadline, rate_limit)

          # Daftar kosong (balapan dengan pembersihan): anggap selesai.
          [] ->
            :ok
        end
    end
  end

  # Memindahkan SATU worker (key `id`, proses `pid`) ke sebuah survivor.
  defp handoff_one(id, pid) do
    case Workers.survivor() do
      # Tidak ada peer untuk dituju.
      nil ->
        :no_survivor

      target ->
        state = safe_state(pid)                 # 1. baca state worker dulu
        _ = DynamicSupervisor.terminate_child(@sup, pid)  # 2. hentikan salinan lokal
        place(id, state, target, 40)            # 3. buat ulang di survivor (dengan beberapa retry)
        :ok
    end
  end

  # Menempatkan worker di `target` sampai benar-benar mendarat di sana. Argumen terakhir = sisa
  # percobaan; berhenti pada 0. Lihat penjelasan race CRDT di bawah.
  defp place(id, _state, _target, 0) do
    Logger.warning("handoff #{inspect(id)}: gave up placing on survivor")
  end

  defp place(id, state, target, tries) do
    case Workers.start_on(target, id, state) do
      # Sukses dan benar-benar mendarat di node tujuan -> catat satu handoff di probe.
      {:ok, p} when node(p) == target ->
        Probe.record_handoff(1)

      # Registry menolak dengan {:already_started, p}: entri worker lokal yang baru saja dimatikan
      # kadang masih tertinggal sesaat di CRDT, sehingga start dianggap "sudah ada". Jika proses `p`
      # itu memang hidup di target, anggap berhasil; jika tidak, tunggu CRDT bersih lalu coba lagi.
      {:error, {:already_started, p}} ->
        if node(p) == target and remote_alive?(p) do
          Probe.record_handoff(1)
        else
          Process.sleep(50)
          place(id, state, target, tries - 1)
        end

      # Hasil lain (mis. mendarat di node yang salah / error sementara) -> tunggu sebentar, ulangi.
      _other ->
        Process.sleep(50)
        place(id, state, target, tries - 1)
    end
  end

  # Memeriksa apakah proses `pid` (di node lain) masih hidup, lewat RPC ke node pemiliknya.
  defp remote_alive?(pid), do: :rpc.call(node(pid), Process, :alive?, [pid]) == true

  # Membaca state worker dengan aman. Jika worker keburu mati/timeout, kembalikan `nil` daripada crash.
  defp safe_state(pid) do
    GenServer.call(pid, :state, 1_000)
  catch
    _, _ -> nil
  end

  # Jam monotonic dalam milidetik (tidak pernah mundur — tepat untuk mengukur waktu berlalu).
  defp now_ms, do: System.monotonic_time(:millisecond)
end
