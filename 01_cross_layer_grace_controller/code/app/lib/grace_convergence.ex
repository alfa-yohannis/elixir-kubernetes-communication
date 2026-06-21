defmodule GraceConvergence do
  @moduledoc """
  Modul puncak (fasad) untuk prototipe grace-convergence controller. Isinya hanya pintasan ringkas
  agar nyaman dipakai dari konsol `iex`; logika sebenarnya ada di modul-modul lain:

    * `GraceConvergence.Grace`    — policy grace period (rumus `g = clamp(...)`).
    * `GraceConvergence.Probe`    — probe konvergensi (membaca backlog, laju, T_c).
    * `GraceConvergence.Shutdown` — hook terminasi adaptif (men-drain & handoff).
    * `GraceConvergence.Workers`  — membuat/menghitung worker stateful.
  """

  # `defdelegate` membuat fungsi yang langsung meneruskan panggilan ke modul lain (tanpa logika baru).

  @doc "Pintasan ke `Probe.reading/0`: mengambil reading probe saat ini."
  defdelegate reading(), to: GraceConvergence.Probe

  @doc "Pintasan ke `Shutdown.drain_and_await/0`: menjalankan drain adaptif dan menunggu selesai."
  defdelegate drain_and_await(), to: GraceConvergence.Shutdown

  @doc "Pintasan ke `Workers.start_many/1`: membuat `n` worker stateful baru."
  defdelegate start_many(n), to: GraceConvergence.Workers
end
