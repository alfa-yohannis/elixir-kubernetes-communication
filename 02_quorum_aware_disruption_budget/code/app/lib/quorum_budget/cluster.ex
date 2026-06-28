defmodule QuorumBudget.Cluster do
  @moduledoc """
  Helper kecil untuk **membaca keanggotaan cluster BEAM** dan menurunkan ambang kuorum.

  Di Erlang/Elixir terdistribusi, tiap node tahu node lain yang terhubung lewat `Node.list/0`
  (tidak termasuk dirinya sendiri). Ukuran cluster yang "terlihat" dari node ini = jumlah node lain
  + 1 (dirinya). Modul ini read-only: ia hanya melaporkan apa yang dilihat node, dipakai oleh probe
  kuorum dan oleh keputusan policy.
  """

  alias QuorumBudget.Quorum

  @doc """
  Ukuran cluster app yang terlihat dari node INI: jumlah peer-app terhubung + 1 (diri sendiri).
  Minimal 1 (sebuah node selalu melihat dirinya).

  Node pengendali (mis. `primary@...` di harness tes, atau pod operator bila ia ikut terhubung) TIDAK
  dihitung sebagai anggota kuorum: ia bukan bagian cluster aplikasi. Pengecualian diatur lewat config
  `:control_node_prefix` (default `nil` = hitung semua, benar di produksi di mana operator memang bukan
  anggota cluster BEAM).
  """
  @spec size() :: pos_integer()
  def size, do: length(peers()) + 1

  @doc "Daftar peer-app yang terhubung (mengecualikan node pengendali), tidak termasuk node ini."
  @spec peers() :: [node()]
  def peers do
    case Application.get_env(:quorum_budget, :control_node_prefix) do
      nil -> Node.list()
      prefix -> Enum.reject(Node.list(), &String.starts_with?(to_string(&1), prefix))
    end
  end

  @doc """
  Ambang kuorum `Q`, sesuai konfigurasi `:quorum`:
    * `:majority` -> `div(N, 2) + 1`, dengan `N` = ukuran cluster yang **DIINGINKAN** (jumlah replika
      Deployment), dari config `:cluster_size`; bila tak diset, jatuh ke ukuran hidup.
    * bilangan bulat tetap -> floor yang dideklarasikan operator (untuk beban `:global`/CRDT).

  PENTING: kuorum dipatok ke ukuran yang DIINGINKAN, BUKAN ukuran hidup. Kalau memakai ukuran hidup,
  sebuah partisi yang menyusut akan selalu mengira `majority(ukurannya sendiri)` terpenuhi --- yakni
  bug split-brain klasik yang justru ingin dicegah M7. Operator mengetahui jumlah replika yang
  diinginkan dari spec Deployment; angka itulah yang dipakai.
  """
  @spec quorum_threshold(pos_integer()) :: pos_integer()
  def quorum_threshold(live \\ size()) do
    desired = Application.get_env(:quorum_budget, :cluster_size, live)

    case Application.get_env(:quorum_budget, :quorum, :majority) do
      :majority -> Quorum.majority(desired)
      q when is_integer(q) and q > 0 -> q
      _ -> Quorum.majority(desired)
    end
  end

  @doc """
  Apakah node ini sekarang **berada dalam kuorum**: apakah ukuran cluster yang dilihatnya memenuhi
  ambang kuorum. Dipakai beban kerja yang bergantung-kuorum untuk memutuskan boleh-tidaknya commit.
  """
  @spec in_quorum?() :: boolean()
  def in_quorum? do
    n = size()
    n >= quorum_threshold(n)
  end
end
