defmodule GraceConvergence.WorkersTest do
  @moduledoc """
  Tes non-cluster untuk `GraceConvergence.Workers`: `survivor/0` saat terisolasi dan akurasi
  `local_count/0` (versi O(1) berbasis `DynamicSupervisor.count_children/1`).
  """
  use ExUnit.Case, async: false
  alias GraceConvergence.Workers

  setup do
    Workers.stop_all()
    Process.sleep(50)
    :ok
  end

  test "survivor/0 mengembalikan nil saat tidak ada peer (node terisolasi)" do
    # Di lingkungan tes tidak ada cluster, jadi Node.list() kosong.
    assert Workers.survivor() == nil
  end

  test "local_count/0 mulai 0 dan mengikuti worker yang dimulai/dihentikan" do
    assert Workers.local_count() == 0

    Workers.start_local("wt_a")
    Workers.start_local("wt_b")
    Process.sleep(80)
    assert Workers.local_count() == 2

    Workers.stop_all()
    Process.sleep(80)
    assert Workers.local_count() == 0
  end
end
