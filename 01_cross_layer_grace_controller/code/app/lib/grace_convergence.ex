defmodule GraceConvergence do
  @moduledoc """
  Top-level helpers for the grace-convergence controller prototype.

  See `GraceConvergence.Grace` for the grace-period policy, `GraceConvergence.Probe` for the
  convergence probe, and `GraceConvergence.Shutdown` for the adaptive termination hook.
  """

  defdelegate reading(), to: GraceConvergence.Probe
  defdelegate drain_and_await(), to: GraceConvergence.Shutdown
  defdelegate start_many(n), to: GraceConvergence.Workers
end
