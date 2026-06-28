defmodule QuorumBudget.MixProject do
  use Mix.Project

  # Proyek Mix untuk artifact M7: pengendali PodDisruptionBudget sadar-kuorum. Definisi aplikasi
  # (modul callback + dependensi) ada di bawah; versi Elixir/OTP mengikuti yang umum dipakai 2024+.
  def project do
    [
      app: :quorum_budget,
      version: "0.1.0",
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Konfigurasi aplikasi OTP: modul yang dijalankan saat start (Application callback).
  def application do
    [
      extra_applications: [:logger],
      mod: {QuorumBudget.Application, []}
    ]
  end

  # Dependensi. Sengaja minimal: pembentukan cluster (libcluster), server HTTP kecil untuk endpoint
  # probe (bandit + plug), dan JSON (jason) untuk berbicara dengan API Kubernetes lewat kubectl.
  # M7 berfokus pada keanggotaan-cluster + kuorum, jadi TIDAK butuh Horde (registry handoff) seperti
  # artifact M3.
  defp deps do
    [
      {:libcluster, "~> 3.3"},
      {:bandit, "~> 1.5"},
      {:plug, "~> 1.16"},
      {:jason, "~> 1.4"}
    ]
  end
end
