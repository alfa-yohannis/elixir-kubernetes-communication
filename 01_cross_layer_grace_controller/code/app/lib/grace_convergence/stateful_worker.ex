defmodule GraceConvergence.StatefulWorker do
  @moduledoc """
  Satu **proses stateful** — unit pekerjaan yang justru ingin dilindungi oleh seluruh sistem ini.

  Bayangkan sebagai objek kecil di memori (ruang chat, sesi game, keranjang belanja pengguna, …):
  ia menyimpan state di RAM, dan state itu TIDAK boleh hilang saat node tempatnya dimatikan.
  Sebelum node mati, state-nya di-*handoff* (disalin) ke node yang bertahan.

  Ini sebuah `GenServer` dengan `restart: :transient`, artinya supervisor hanya me-restart-nya bila
  ia *crash* secara tidak normal; penghentian normal yang disengaja (itulah yang dilakukan handoff)
  dibiarkan.

  Tiap worker punya nama unik se-cluster yang terdaftar di `Horde.Registry`. `Horde.Registry` adalah
  registry *terdistribusi* yang dibangun di atas CRDT (Conflict-free Replicated Data Type — struktur
  data yang bisa diubah secara lokal di tiap node dan otomatis "menyatu" ke hasil yang sama di mana
  pun). Registry ini memungkinkan node mana pun mencari worker berdasarkan key, tak peduli node mana
  yang sedang meng-host-nya.
  """
  # `restart: :transient` di sini menetapkan kebijakan restart default untuk proses dari modul ini.
  use GenServer, restart: :transient

  @registry GraceConvergence.Registry

  @doc """
  *Child specification*: "resep" yang dipakai supervisor untuk memulai dan mengelola proses ini. Kita
  menyediakannya secara eksplisit agar tiap worker mendapat id supervisor unik `{__MODULE__, id}` dan
  jendela 5 detik untuk berhenti dengan rapi. `opts` harus memuat `:id`.
  """
  def child_spec(opts) do
    id = Keyword.fetch!(opts, :id)

    %{
      id: {__MODULE__, id},
      start: {__MODULE__, :start_link, [opts]},
      restart: :transient,
      shutdown: 5_000
    }
  end

  @doc """
  Memulai satu proses worker. `opts` harus berisi `:id` (key uniknya) dan boleh berisi `:state` (map
  state awal). Proses didaftarkan di bawah via-tuple-nya agar bisa dijangkau lewat key.
  """
  def start_link(opts) do
    id = Keyword.fetch!(opts, :id)
    GenServer.start_link(__MODULE__, opts, name: via(id))
  end

  @doc """
  Membangun *via-tuple* untuk menamai dan mengalamati worker lewat `Horde.Registry`. Via-tuple
  `{:via, Registry, {NamaRegistry, key}}` memberi tahu OTP "temukan proses ini berdasarkan `key` di
  `NamaRegistry`" alih-alih lewat PID mentah, sehingga tetap berfungsi walau worker pindah node.
  """
  def via(id), do: {:via, Horde.Registry, {@registry, id}}

  @doc "Membaca map state worker saat ini secara sinkron, dicari berdasarkan `id`-nya."
  def state(id), do: GenServer.call(via(id), :state)

  @doc "Menaikkan counter update worker secara asinkron (untuk menguji/mengubah state-nya)."
  def touch(id), do: GenServer.cast(via(id), :touch)

  # --- Callback GenServer (berjalan di dalam proses worker) --------------------------------------

  @impl true
  # Susun state awal worker. Jika pemanggil menanam `:state` (mis. state yang diterima saat handoff),
  # pakai itu; jika tidak, buat catatan baru yang dicap waktu pembuatannya.
  def init(opts) do
    id = Keyword.fetch!(opts, :id)
    data = Keyword.get(opts, :state) || %{id: id, updates: 0, born: System.os_time(:millisecond)}
    {:ok, data}
  end

  @impl true
  # Balas permintaan :state dengan seluruh map state (inilah yang dibaca handoff sebelum memindahnya).
  def handle_call(:state, _from, data), do: {:reply, data, data}

  @impl true
  # Tangani :touch dengan menaikkan counter `:updates` (mulai dari 1 bila belum ada).
  def handle_cast(:touch, data), do: {:noreply, Map.update(data, :updates, 1, &(&1 + 1))}
end
