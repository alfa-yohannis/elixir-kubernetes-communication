defmodule GraceConvergence.Grace do
  @moduledoc """
  The grace-period policy (paper Eq. 2):

      g* = T_d + B/rho + T_c + sigma
      g  = clamp(g*, g_min, g_max)

  where B = handoff backlog, rho = observed handoff rate (events/s), T_c = convergence
  time, T_d = drain time, sigma = safety margin. If the reading is implausible (e.g. a
  nonzero backlog with no observed rate), fall back to a configured conservative grace
  (default-safe, never default-fast).
  """

  @type reading :: %{
          optional(any) => any,
          backlog: non_neg_integer(),
          rate_eps: number(),
          t_c_ms: number()
        }

  @doc """
  Compute the adequate grace period in **seconds**.

  Options: `:sigma`, `:g_min`, `:g_max` (seconds), `:t_d` (seconds), `:fallback`
  (seconds, used when the handoff time cannot be estimated; defaults to `g_max`).
  """
  @spec compute(reading, keyword) :: non_neg_integer()
  def compute(reading, opts \\ []) do
    g_min = Keyword.get(opts, :g_min, 5)
    g_max = Keyword.get(opts, :g_max, 120)
    sigma = Keyword.get(opts, :sigma, 5)
    t_d = Keyword.get(opts, :t_d, 1)
    fallback = Keyword.get(opts, :fallback, g_max)

    g =
      case handoff_seconds(reading) do
        :unknown -> fallback
        secs -> t_d + secs + t_c_seconds(reading) + sigma
      end

    g |> max(g_min) |> min(g_max) |> round()
  end

  # backlog clears at the observed rate
  defp handoff_seconds(%{backlog: b, rate_eps: r})
       when is_number(b) and is_number(r) and r > 0,
       do: b / r

  # nothing to hand off
  defp handoff_seconds(%{backlog: 0}), do: 0

  # backlog > 0 but no usable rate => cannot estimate => caller uses the fallback
  defp handoff_seconds(_), do: :unknown

  defp t_c_seconds(%{t_c_ms: ms}) when is_number(ms) and ms >= 0, do: ms / 1000
  defp t_c_seconds(_), do: 0
end
