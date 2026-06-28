defmodule QuorumBudget.QuorumTest do
  @moduledoc """
  Tes unit untuk policy kuorum murni `QuorumBudget.Quorum`: perhitungan budget, mayoritas, deteksi
  pelanggaran kuorum, dan keputusan admission. Deterministik, tanpa cluster.
  """
  use ExUnit.Case, async: true
  alias QuorumBudget.Quorum

  describe "majority/1" do
    test "mayoritas = floor(n/2) + 1" do
      assert Quorum.majority(1) == 1
      assert Quorum.majority(3) == 2
      assert Quorum.majority(5) == 3
      assert Quorum.majority(7) == 4
      assert Quorum.majority(8) == 5
    end
  end

  describe "budget/2" do
    test "min_available = kuorum, max_unavailable = n - kuorum (mayoritas)" do
      assert Quorum.budget(%{n: 5, q: 3}) == %{min_available: 3, max_unavailable: 2}
      assert Quorum.budget(%{n: 7, q: 4}) == %{min_available: 4, max_unavailable: 3}
    end

    test "kapasitas handoff `cap` membatasi max_unavailable lebih jauh" do
      # n - q = 4, tapi cap = 1 -> hanya 1 yang boleh turun sekaligus.
      assert Quorum.budget(%{n: 9, q: 5, cap: 1}) == %{min_available: 5, max_unavailable: 1}
    end

    test "q_min menaikkan min_available, tak pernah melebihi n" do
      assert Quorum.budget(%{n: 4, q: 1}, q_min: 3) == %{min_available: 3, max_unavailable: 1}
      assert Quorum.budget(%{n: 2, q: 5}) == %{min_available: 2, max_unavailable: 0}
    end

    test "max_unavailable tak pernah negatif" do
      assert Quorum.budget(%{n: 3, q: 3}).max_unavailable == 0
    end
  end

  describe "violates_quorum?/3 dan admit_eviction/2" do
    test "mengusir d pod melanggar kuorum bila a - d < q" do
      refute Quorum.violates_quorum?(5, 2, 3)
      assert Quorum.violates_quorum?(5, 3, 3)
    end

    test "admission mengizinkan hanya bila setelah satu eviction tetap >= min_available" do
      assert Quorum.admit_eviction(5, 3) == :allow
      assert Quorum.admit_eviction(4, 3) == :allow
      assert Quorum.admit_eviction(3, 3) == :deny
    end
  end
end
