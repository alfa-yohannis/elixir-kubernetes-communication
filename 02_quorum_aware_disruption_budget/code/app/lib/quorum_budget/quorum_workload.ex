defmodule QuorumBudget.QuorumWorkload do
  @moduledoc """
  Beban kerja yang **bergantung-kuorum**, dipakai untuk studi kasus RQ8: mengukur konsekuensi NYATA
  ketika kuorum pecah, bukan sekadar "anggota tersedia < Q".

  Modelnya meniru sebuah grup konsensus (mis. Raft) atau singleton `:global` yang otoritatif: sebuah
  *write* (commit) hanya boleh dilakukan bila penulis melihat KUORUM. Tiap `@tick_ms` milidetik
  workload memeriksa `Cluster.in_quorum?`:

    * bila ya  -> *commit* berhasil (hitung `committed`),
    * bila tidak -> *commit* DIBLOKIR (hitung `blocked`) -- persis seperti grup konsensus yang
      kehilangan mayoritas: ia tak bisa maju sampai kuorum pulih.

  Jadi `blocked` adalah ukuran progres yang HILANG selama jendela kehilangan-kuorum. Pada policy
  quorum-aware, anggota tersedia tak pernah turun di bawah Q, sehingga `blocked` seharusnya nol; pada
  budget statis yang memecah kuorum, `blocked` membesar selama jendela tersebut.
  """
  use GenServer
  alias QuorumBudget.Cluster

  # Periode tick (ms). Kecil agar resolusi pengukuran progres halus.
  @tick_ms 25

  def start_link(_), do: GenServer.start_link(__MODULE__, fresh(), name: __MODULE__)

  @doc "Statistik saat ini: `%{committed, blocked}`."
  @spec stats() :: %{committed: non_neg_integer(), blocked: non_neg_integer()}
  def stats, do: GenServer.call(__MODULE__, :stats)

  @doc "Reset penghitung (dipanggil harness sebelum tiap skenario)."
  def reset, do: GenServer.call(__MODULE__, :reset)

  @impl true
  def init(s) do
    schedule()
    {:ok, s}
  end

  @impl true
  def handle_info(:tick, s) do
    s =
      if Cluster.in_quorum?() do
        %{s | committed: s.committed + 1}
      else
        %{s | blocked: s.blocked + 1}
      end

    schedule()
    {:noreply, s}
  end

  @impl true
  def handle_call(:stats, _from, s), do: {:reply, s, s}
  def handle_call(:reset, _from, _s), do: {:reply, :ok, fresh()}

  defp fresh, do: %{committed: 0, blocked: 0}
  defp schedule, do: Process.send_after(self(), :tick, @tick_ms)
end
