defmodule GraceConvergence.Presence do
  @moduledoc """
  Beban kerja terdistribusi yang **realistis**, dibangun di atas `Phoenix.Tracker` — mesin CRDT yang
  menjadi dasar `Phoenix.Presence` (fitur Phoenix yang lazim dipakai untuk melacak "siapa yang sedang
  online" di seluruh cluster).

  Tanpa perlu server web, kita memakainya untuk mengukur **waktu konvergensi keanggotaan yang nyata**
  ketika sebuah node pergi: yaitu suku `T_c` pada invariant keselamatan. Karena ini fitur Phoenix
  asli (tidak dimodifikasi), pengukurannya merepresentasikan beban kerja produksi sungguhan.

  `use Phoenix.Tracker` menyediakan callback `init/1` dan `handle_diff/2` yang wajib; tracker
  menyebarkan perubahan presence antar-node lewat `Phoenix.PubSub`.
  """
  use Phoenix.Tracker

  # Nama server PubSub yang dipakai tracker untuk menyebarkan perubahan antar-node.
  @pubsub GraceConvergence.PubSub

  @doc "Memulai shard tracker. `opts` boleh menimpa `:name`/`:pubsub_server`; default memakai modul ini."
  def start_link(opts \\ []) do
    opts = Keyword.merge([name: __MODULE__, pubsub_server: @pubsub], opts)
    Phoenix.Tracker.start_link(__MODULE__, opts, opts)
  end

  @impl true
  # State awal tracker: cukup menyimpan nama server PubSub yang dipakai.
  def init(opts), do: {:ok, %{pubsub_server: Keyword.fetch!(opts, :pubsub_server)}}

  @impl true
  # Dipanggil tiap kali ada perubahan (diff) presence. Kita tidak perlu bereaksi apa pun di sini,
  # cukup kembalikan state apa adanya — yang kita ukur hanyalah berapa lama diff menyebar/konvergen.
  def handle_diff(_diff, state), do: {:ok, state}

  @doc """
  Melacak `key` di bawah `topic`, dimiliki oleh `pid` (presence-nya lenyap saat `pid` mati). Inilah
  cara kita menambahkan N "kehadiran" dari proses-proses di node yang akan pergi.
  """
  def track(pid, topic, key, meta \\ %{}),
    do: Phoenix.Tracker.track(__MODULE__, pid, topic, key, meta)

  @doc "Jumlah presence berbeda untuk `topic` se-cluster, sebagaimana terlihat dari node INI."
  def count(topic), do: __MODULE__ |> Phoenix.Tracker.list(topic) |> length()
end
