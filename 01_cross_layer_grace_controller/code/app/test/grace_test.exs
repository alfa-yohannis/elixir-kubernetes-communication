defmodule GraceConvergence.GraceTest do
  use ExUnit.Case, async: true
  alias GraceConvergence.Grace

  @opts [sigma: 5, g_min: 5, g_max: 120, t_d: 1, fallback: 120]

  test "g = T_d + B/rho + T_c + sigma, within bounds" do
    # 1000 backlog at 100/s = 10s; + T_d 1 + T_c 0 + sigma 5 = 16
    assert Grace.compute(%{backlog: 1000, rate_eps: 100.0, t_c_ms: 0}, @opts) == 16
  end

  test "convergence time T_c is included" do
    # 200/100 = 2s; + T_d 1 + T_c 2s(=2000ms) + sigma 5 = 10
    assert Grace.compute(%{backlog: 200, rate_eps: 100.0, t_c_ms: 2000}, @opts) == 10
  end

  test "clamps to g_max under heavy load" do
    assert Grace.compute(%{backlog: 1_000_000, rate_eps: 100.0, t_c_ms: 0}, @opts) == 120
  end

  test "clamps to g_min when there is almost nothing to do" do
    assert Grace.compute(%{backlog: 0, rate_eps: 0.0, t_c_ms: 0}, @opts) == 6

    assert Grace.compute(%{backlog: 0, rate_eps: 0.0, t_c_ms: 0},
             sigma: 0,
             t_d: 0,
             g_min: 5,
             g_max: 120
           ) == 5
  end

  test "default-safe fallback when backlog > 0 but the rate is unknown" do
    # nonzero backlog, no observed rate => cannot estimate => fall back to g_max (default-safe)
    assert Grace.compute(%{backlog: 50, rate_eps: 0.0, t_c_ms: 0}, @opts) == 120
  end

  test "the fallback value is configurable" do
    assert Grace.compute(
             %{backlog: 50, rate_eps: 0.0, t_c_ms: 0},
             Keyword.put(@opts, :fallback, 99)
           ) == 99
  end
end
