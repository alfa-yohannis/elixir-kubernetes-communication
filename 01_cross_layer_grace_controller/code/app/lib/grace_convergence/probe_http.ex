defmodule GraceConvergence.ProbeHTTP do
  @moduledoc """
  HTTP surface:
    * `GET  /probe`   — the convergence reading (backlog, rate, T_c) the operator consumes.
    * `GET  /healthz` — liveness.
    * `POST /drain`   — run the adaptive drain synchronously and return when handoff completes
                        (called by the pod's `preStop` hook so termination blocks until handoff is done).
  """
  use Plug.Router
  alias GraceConvergence.{Probe, Shutdown}

  plug(:match)
  plug(:dispatch)

  get "/probe" do
    send_resp(conn, 200, Jason.encode!(Probe.reading()))
  end

  get "/healthz" do
    send_resp(conn, 200, "ok")
  end

  post "/drain" do
    result = Shutdown.drain_and_await()
    send_resp(conn, 200, Jason.encode!(result))
  end

  match _ do
    send_resp(conn, 404, "not found")
  end
end
