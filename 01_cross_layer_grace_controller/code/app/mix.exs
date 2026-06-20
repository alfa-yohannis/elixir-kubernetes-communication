defmodule GraceConvergence.MixProject do
  use Mix.Project

  def project do
    [
      app: :grace_convergence,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :inets],
      mod: {GraceConvergence.Application, []}
    ]
  end

  defp deps do
    [
      {:horde, "~> 0.9"},
      {:libcluster, "~> 3.3"},
      {:bandit, "~> 1.5"},
      {:plug, "~> 1.16"},
      {:jason, "~> 1.4"},
      # Phoenix.Tracker / Phoenix.PubSub: the real CRDT presence engine behind Phoenix.Presence
      # (no web server needed) — used for the realistic-workload case study (convergence T_c).
      {:phoenix_pubsub, "~> 2.1"}
    ]
  end
end
