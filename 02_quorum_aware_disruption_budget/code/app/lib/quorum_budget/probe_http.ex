defmodule QuorumBudget.ProbeHTTP do
  @moduledoc """
  Endpoint HTTP kecil yang menyajikan pembacaan probe kuorum sebagai JSON, supaya operator (di pod
  lain) bisa mengambilnya lewat jaringan.

  `Plug.Router` memetakan path ke fungsi. Dua rute penting:
    * `GET /probe`   – pembacaan kuorum saat ini (n, q, cap, in_quorum) dalam JSON,
    * `GET /healthz` – cek hidup sederhana untuk liveness probe Kubernetes.
  """
  use Plug.Router
  alias QuorumBudget.QuorumProbe

  plug(:match)
  plug(:dispatch)

  get "/probe" do
    r = QuorumProbe.reading()

    body =
      Jason.encode!(%{
        node: to_string(r.node),
        n: r.n,
        q: r.q,
        cap: r.cap,
        in_quorum: r.in_quorum
      })

    send_resp(conn, 200, body)
  end

  get "/healthz", do: send_resp(conn, 200, "ok")

  match _, do: send_resp(conn, 404, "not found")
end
