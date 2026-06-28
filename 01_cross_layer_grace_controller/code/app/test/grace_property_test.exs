defmodule GraceConvergence.GracePropertyTest do
  @moduledoc """
  Uji properti (manual, tanpa dependensi StreamData) untuk `GraceConvergence.Grace.compute/2`:
  apa pun input-nya, hasil grace HARUS berupa integer non-negatif yang selalu berada di dalam
  [g_min, g_max]. Ini menjamin invariant clamp dan menutup risiko bagi-nol/over-flow.
  """
  use ExUnit.Case, async: true
  alias GraceConvergence.Grace

  test "compute/2 selalu mengembalikan integer di dalam [g_min, g_max] untuk ribuan input acak" do
    for _ <- 1..3000 do
      g_min = Enum.random(0..30)
      g_max = g_min + Enum.random(1..300)
      sigma = Enum.random(0..20)
      t_d = Enum.random(0..10)
      backlog = Enum.random(0..200_000)
      # rate 0 memicu jalur fallback (saat backlog > 0); selain itu b/rate yang bisa sangat besar.
      rate = Enum.random([0, 1, 5, 50, 1000])
      t_c_ms = Enum.random(0..5000)

      reading = %{backlog: backlog, rate_eps: rate, t_c_ms: t_c_ms}
      g = Grace.compute(reading, sigma: sigma, g_min: g_min, g_max: g_max, t_d: t_d, fallback: g_max)

      assert is_integer(g)
      assert g >= g_min, "g=#{g} < g_min=#{g_min} (reading=#{inspect(reading)})"
      assert g <= g_max, "g=#{g} > g_max=#{g_max} (reading=#{inspect(reading)})"
    end
  end

  test "backlog 0 -> handoff 0 detik, grace turun ke g_min setelah clamp" do
    g = Grace.compute(%{backlog: 0, rate_eps: 0, t_c_ms: 0},
          sigma: 0, g_min: 5, g_max: 120, t_d: 0, fallback: 120)
    assert g == 5
  end

  test "backlog > 0 tanpa laju -> fallback (g_max), bukan crash" do
    g = Grace.compute(%{backlog: 500, rate_eps: 0, t_c_ms: 0},
          sigma: 5, g_min: 5, g_max: 90, t_d: 1, fallback: 90)
    assert g == 90
  end
end
