defmodule GraceConvergence.Grace do
  @moduledoc """
  Menentukan **berapa detik "grace" (tenggang) yang diberikan ke sebuah pod** sebelum Kubernetes
  mematikannya paksa.

  Latar yang perlu dipahami sebelum membaca modul ini. Saat Kubernetes menghapus sebuah pod
  (misalnya ketika rolling update), pertama ia mengirim sinyal `SIGTERM` ke proses, menunggu sekian
  detik yang disebut *termination grace period*, lalu mengirim `SIGKILL` yang tidak bisa ditolak.
  Jika sebelum tenggat itu pod belum selesai memindahkan state in-memory-nya ke node lain (proses
  ini disebut "handoff"), state-nya hilang. Grace yang terlalu pendek menghilangkan state; yang
  terlalu panjang membuat setiap deployment lambat. Nilai yang benar BUKAN konstanta — ia bergantung
  pada beban (load) saat itu.

  Modul ini menghitung nilai tersebut dari beberapa pengukuran runtime (dikumpulkan oleh
  `GraceConvergence.Probe`). Rumusnya:

      g_star = T_d + B / rho + T_c + sigma     # waktu yang sebenarnya dibutuhkan shutdown
      g      = clamp(g_star, g_min, g_max)     # lalu dijaga dalam batas yang masuk akal

  dengan
    * `B`     = backlog handoff: berapa banyak proses stateful yang masih harus dipindahkan,
    * `rho`   = laju handoff dalam proses per detik (seberapa cepat kita bisa memindahkannya),
    * `T_c`   = convergence time: berapa lama cluster perlu "menetap" setelahnya,
    * `T_d`   = drain time: waktu menyelesaikan request yang masih berjalan sebelum memindah state,
    * `sigma` = margin keamanan, supaya kita tidak pas berada di garis batas.

  Suku kunci `B / rho` hanyalah "jumlah pekerjaan / kecepatan = waktu", yakni lama handoff.

  Jika pengukurannya tidak masuk akal (misalnya ada backlog tetapi belum pernah ada laju handoff
  yang teramati, sehingga `B / rho` tak bisa dihitung), fungsi ini menolak menebak dan mengembalikan
  grace *fallback* yang sudah dikonfigurasi. Fallback sengaja dibuat besar: kalau ragu, beri waktu
  LEBIH, jangan kurang ("default-safe, bukan default-fast"), karena kehilangan state tidak bisa
  dibatalkan sedangkan membuang beberapa detik bisa.
  """

  @typedoc """
  Satu hasil pembacaan probe: sebuah map dengan minimal tiga key di bawah (key tambahan boleh ada
  dan diabaikan — itu arti `optional(any) => any`). `backlog` dan `rate_eps` dipakai untuk
  mengestimasi lama handoff; `t_c_ms` adalah convergence time dalam milidetik.
  """
  @type reading :: %{
          optional(any) => any,
          backlog: non_neg_integer(),
          rate_eps: number(),
          t_c_ms: number()
        }

  @doc """
  Menghitung grace period, dalam **detik bulat**, untuk satu `reading` probe.

  `opts` menimpa konstanta policy (semuanya dalam detik):
    * `:g_min`    – batas bawah (default 5): jangan pernah memberi kurang dari ini.
    * `:g_max`    – batas atas (default 120): jangan pernah memberi lebih, agar satu pod yang
                    bermasalah tidak menahan rollout selamanya.
    * `:sigma`    – margin keamanan yang ditambahkan ke estimasi (default 5).
    * `:t_d`      – asumsi drain time untuk pekerjaan yang masih berjalan (default 1).
    * `:fallback` – grace yang dipakai saat lama handoff tak bisa diestimasi (default `g_max`).

  Mengembalikan bilangan bulat detik yang non-negatif.
  """
  @spec compute(reading, keyword) :: non_neg_integer()
  def compute(reading, opts \\ []) do
    # Ambil konstanta policy dari `opts`, pakai default yang masuk akal bila key tidak diberikan.
    g_min = Keyword.get(opts, :g_min, 5)
    g_max = Keyword.get(opts, :g_max, 120)
    sigma = Keyword.get(opts, :sigma, 5)
    t_d = Keyword.get(opts, :t_d, 1)
    fallback = Keyword.get(opts, :fallback, g_max)

    # Keputusan inti. `handoff_seconds/1` mengembalikan estimasi lama handoff (B / rho) ATAU atom
    # `:unknown` bila tak bisa diestimasi dari reading ini.
    g =
      case handoff_seconds(reading) do
        # Tak bisa diestimasi -> main aman dengan nilai fallback (yang besar).
        :unknown -> fallback
        # Ada estimasi -> tambahkan drain time, convergence time, dan margin keamanan.
        secs -> t_d + secs + t_c_seconds(reading) + sigma
      end

    # Jepit (clamp) ke [g_min, g_max] dan bulatkan ke detik:
    # `max(_, g_min)` menaikkan nilai yang terlalu kecil; `min(_, g_max)` membatasi yang terlalu besar.
    g |> max(g_min) |> min(g_max) |> round()
  end

  # --- handoff_seconds/1 : estimasi B / rho, lama memindahkan seluruh backlog --------------------
  # Elixir mencoba klausa fungsi dari atas ke bawah dan memakai yang PERTAMA cocok (pola + guard),
  # jadi urutan ketiga klausa ini penting.

  # Kasus normal: backlog `b` (angka) dan laju `r` positif -> waktu = pekerjaan / kecepatan = b / r.
  defp handoff_seconds(%{backlog: b, rate_eps: r})
       when is_number(b) and is_number(r) and r > 0,
       do: b / r

  # Tidak ada yang perlu dipindah (backlog tepat 0) -> handoff butuh nol detik.
  defp handoff_seconds(%{backlog: 0}), do: 0

  # Selain itu (mis. backlog > 0 tapi laju 0 atau hilang): kita tak bisa menghitung b / r tanpa
  # membagi nol atau menebak, jadi laporkan `:unknown` dan biarkan `compute/2` memakai fallback aman.
  defp handoff_seconds(_), do: :unknown

  # --- t_c_seconds/1 : ubah convergence time dari milidetik ke detik -----------------------------

  # Bila `t_c_ms` ada dan non-negatif, bagi 1000 untuk mengubah milidetik menjadi detik.
  defp t_c_seconds(%{t_c_ms: ms}) when is_number(ms) and ms >= 0, do: ms / 1000
  # Selain itu anggap konvergensi dapat diabaikan (0 detik).
  defp t_c_seconds(_), do: 0
end
