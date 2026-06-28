defmodule QuorumBudget.Quorum do
  @moduledoc """
  Menentukan **berapa banyak pod yang boleh "hilang" sekaligus** saat gangguan sukarela (rolling
  update, drain node, scale-down) tanpa memecah kuorum cluster BEAM.

  Latar yang perlu dipahami. Cluster BEAM (Elixir terdistribusi) sering bergantung pada *kuorum*:
  jumlah anggota hidup minimum agar cluster tetap berwenang membuat keputusan (mis. mayoritas untuk
  konsensus, atau ambang yang dideklarasikan operator untuk `:global`/CRDT). Jika gangguan sukarela
  menurunkan jumlah anggota hidup di bawah kuorum, cluster bisa pecah (*split-brain*) atau kehilangan
  salinan state yang otoritatif.

  Kubernetes membatasi gangguan sukarela lewat **PodDisruptionBudget (PDB)** — `minAvailable`
  (paling sedikit pod yang harus tetap hidup) atau `maxUnavailable` (paling banyak yang boleh mati).
  Masalahnya: nilai itu disetel manual dalam satuan jumlah pod dan **tidak tahu kuorum runtime**.
  Modul ini menghitung PDB dari kuorum runtime, sehingga gangguan sukarela tak pernah memecah kuorum.

  Rumus intinya:

      min_available  = clamp(Q, q_min, N)                 # jamin anggota hidup >= kuorum
      max_unavailable = clamp(N - min_available, 0, cap)   # juga batasi laju agar handoff sempat

  dengan `N` = ukuran cluster, `Q` = ambang kuorum, dan `cap` = kapasitas handoff (berapa pod yang
  state-nya bisa dipindahkan tepat waktu — kopling ke pengendali grace M3). Suku `min_available = Q`
  menegakkan invarian keselamatan `A >= Q` (anggota tersedia tak pernah turun di bawah kuorum); suku
  `max_unavailable` membatasi konkurensi gangguan ke kapasitas handoff.
  """

  @typedoc """
  Pembacaan untuk policy: ukuran cluster `n`, ambang kuorum `q`. Key opsional `cap` membatasi
  `max_unavailable` ke kapasitas handoff (default: tak ada batas tambahan selain `n - q`).
  """
  @type reading :: %{optional(any) => any, n: pos_integer(), q: pos_integer()}

  @doc """
  Menghitung PDB `%{min_available, max_unavailable}` dari satu `reading`.

  `opts`:
    * `:q_min` – batas bawah `min_available` (default 1): jangan pernah izinkan cluster kosong.

  Mengembalikan map dengan dua bilangan bulat non-negatif. `min_available` dijepit ke `[q_min, n]`;
  `max_unavailable = n - min_available`, lalu dibatasi lagi oleh `cap` (kapasitas handoff) bila ada.
  """
  @spec budget(reading, keyword) :: %{min_available: non_neg_integer(), max_unavailable: non_neg_integer()}
  def budget(reading, opts \\ []) do
    n = reading.n
    q = reading.q
    q_min = Keyword.get(opts, :q_min, 1)
    # Batas atas konkurensi dari kapasitas handoff (jumlah pod yang state-nya bisa dipindah tepat
    # waktu). Bila tak diberikan, satu-satunya batas adalah kuorum itu sendiri (n - min_available).
    cap = Map.get(reading, :cap, n)

    # min_available = kuorum, dijepit ke [q_min, n]. Inilah penegak invarian A >= Q.
    min_available = q |> max(q_min) |> min(n)
    # max_unavailable = sisa di atas kuorum, tapi tak lebih dari kapasitas handoff, dan tak negatif.
    max_unavailable = (n - min_available) |> min(trunc(cap)) |> max(0)

    %{min_available: min_available, max_unavailable: max_unavailable}
  end

  @doc """
  Ambang kuorum **mayoritas** untuk cluster berukuran `n`: `div(n, 2) + 1` (mis. 3 dari 5, 4 dari 7).
  Ini default yang lazim untuk konsensus dan untuk mencegah dua partisi sama-sama merasa berwenang.
  """
  @spec majority(pos_integer()) :: pos_integer()
  def majority(n) when is_integer(n) and n > 0, do: div(n, 2) + 1

  @doc """
  Apakah mengusir `d` pod dari `a` anggota yang sekarang tersedia akan **melanggar kuorum** `q`?
  Yakni: apakah `a - d < q`. Dipakai oleh keputusan admission eviction.
  """
  @spec violates_quorum?(non_neg_integer(), non_neg_integer(), pos_integer()) :: boolean()
  def violates_quorum?(a, d, q), do: a - d < q

  @doc """
  Keputusan **admission** untuk satu permintaan eviction: izinkan hanya bila setelah satu pod pergi,
  anggota tersedia masih memenuhi `min_available`. Inilah yang ditegakkan PDB Kubernetes.
  Mengembalikan `:allow` atau `:deny`.
  """
  @spec admit_eviction(non_neg_integer(), non_neg_integer()) :: :allow | :deny
  def admit_eviction(available, min_available) do
    if available - 1 >= min_available, do: :allow, else: :deny
  end
end
