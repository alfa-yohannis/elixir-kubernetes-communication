defmodule GraceConvergence.ProbeTest do
  @moduledoc """
  Tes untuk `GraceConvergence.Probe` — "sensor" yang mengumpan controller. Bug di sini bisa
  menyesatkan seluruh hasil eksperimen, jadi kita uji EWMA laju, fallback, reset, dan kasus tepi.
  """
  use ExUnit.Case, async: false
  alias GraceConvergence.Probe

  # Probe adalah GenServer singleton; bersihkan state sebelum tiap tes.
  setup do
    Probe.reset()
    :ok
  end

  test "reading memuat key yang diharapkan" do
    r = Probe.reading()
    assert Map.has_key?(r, :backlog)
    assert Map.has_key?(r, :rate_eps)
    assert Map.has_key?(r, :t_c_ms)
  end

  test "sebelum ada handoff, laju jatuh ke nilai yang dikonfigurasi" do
    old = Application.get_env(:grace_convergence, :handoff_rate_limit)
    Application.put_env(:grace_convergence, :handoff_rate_limit, 500)
    Probe.reset()
    assert Probe.reading().rate_eps == 500.0
    Application.put_env(:grace_convergence, :handoff_rate_limit, old)
  end

  test "EWMA mengikuti laju handoff yang teramati" do
    Probe.reset()
    Probe.mark_drain_start()
    # Catat 20 handoff berjarak ~10 ms -> laju sesaat ~100/s; EWMA mestinya menuju ke sana.
    for _ <- 1..20 do
      Probe.record_handoff(1)
      Process.sleep(10)
    end
    Process.sleep(30)
    rate = Probe.reading().rate_eps
    assert rate > 0
    # Batas longgar (EWMA + jitter penjadwalan), tapi harus di kisaran ratusan, bukan ekstrem.
    assert rate > 20 and rate < 500
  end

  test "handoff dengan selisih-waktu nol tidak crash dan laju tetap berhingga" do
    Probe.reset()
    Probe.mark_drain_start()
    # Dua handoff bisa jatuh di milidetik yang sama -> jangan sampai bagi-nol.
    Probe.record_handoff(1)
    Probe.record_handoff(1)
    assert is_number(Probe.reading().rate_eps)
  end

  test "reset membersihkan riwayat handoff" do
    Probe.mark_drain_start()
    Probe.record_handoff(5)
    Probe.reset()
    assert Probe.reading().handed_off == 0
  end
end
