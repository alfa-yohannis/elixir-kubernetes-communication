defmodule QuorumBudget.QuorumProbe do
  @moduledoc """
  **Probe kuorum**: sensor read-only yang melaporkan angka-angka runtime yang dibutuhkan policy PDB
  (lihat `QuorumBudget.Quorum`).

  Ini `GenServer` sederhana. Tiap pembacaan (`reading/0`) melaporkan:
    * `n`   – ukuran cluster BEAM yang terlihat dari node ini,
    * `q`   – ambang kuorum saat ini (mayoritas, atau floor yang dikonfigurasi),
    * `cap` – kapasitas handoff (opsional; pembatas konkurensi tambahan),
    * `in_quorum` – apakah node ini sekarang melihat cukup anggota untuk berkuorum.

  Operator membaca probe ini dari tiap pod lalu menyetel PDB Deployment. Endpoint HTTP `/probe`
  (`QuorumBudget.ProbeHTTP`) hanyalah pembungkus JSON dari `reading/0`.
  """
  use GenServer
  alias QuorumBudget.Cluster

  @doc "Memulai probe dan mendaftarkannya di bawah nama modul ini."
  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  @doc "Pembacaan probe saat ini: map `%{node, n, q, cap, in_quorum}`."
  @spec reading() :: map()
  def reading, do: GenServer.call(__MODULE__, :reading)

  @impl true
  def init(_), do: {:ok, %{}}

  @impl true
  def handle_call(:reading, _from, s) do
    n = Cluster.size()
    q = Cluster.quorum_threshold(n)
    cap = Application.get_env(:quorum_budget, :handoff_cap)

    {:reply, %{node: Node.self(), n: n, q: q, cap: cap, in_quorum: n >= q}, s}
  end
end
