defmodule GraceConvergence.ProbeHTTP do
  @moduledoc """
  **Permukaan HTTP** dari sebuah pod aplikasi. Inilah cara dunia luar (operator Kubernetes dan
  kubelet) berbicara dengan proses BEAM di dalam pod.

  Dibangun dengan `Plug.Router` (Plug = pustaka web minimal Elixir; "router" memetakan path URL ke
  kode). Tiga endpoint:
    * `GET  /probe`   — reading konvergensi (backlog, rate, T_c) yang dibaca operator untuk menghitung
                        grace. Body-nya JSON.
    * `GET  /healthz` — liveness/readiness probe Kubernetes (sekadar "ok" bila pod sehat).
    * `POST /drain`   — menjalankan drain adaptif secara sinkron dan baru membalas setelah handoff
                        selesai. Dipanggil oleh `preStop` hook pod, sehingga terminasi *menahan diri*
                        sampai handoff tuntas.
  """
  use Plug.Router
  alias GraceConvergence.{Probe, Shutdown}

  # `:match` mencocokkan request dengan salah satu rute di bawah; `:dispatch` menjalankan kodenya.
  plug(:match)
  plug(:dispatch)

  # Balas reading probe saat ini sebagai JSON (Jason = pustaka encoder JSON).
  get "/probe" do
    send_resp(conn, 200, Jason.encode!(Probe.reading()))
  end

  # Health check sederhana: selalu balas 200 "ok" selama proses HTTP ini hidup.
  get "/healthz" do
    send_resp(conn, 200, "ok")
  end

  # Jalankan drain adaptif dan tunggu sampai selesai, lalu balas hasilnya (policy, grace, lost) JSON.
  post "/drain" do
    result = Shutdown.drain_and_await()
    send_resp(conn, 200, Jason.encode!(result))
  end

  # Rute penampung: path apa pun yang tak cocok di atas dibalas 404.
  match _ do
    send_resp(conn, 404, "not found")
  end
end
