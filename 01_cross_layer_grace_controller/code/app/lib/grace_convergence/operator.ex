defmodule GraceConvergence.Operator do
  @moduledoc """
  **Koordinator lintas-lapis**, berjalan sebagai sebuah *operator* pod Kubernetes.

  "Operator" di Kubernetes adalah program yang terus berjalan, mengamati keadaan cluster, lalu
  menyesuaikan sesuatu agar sesuai keinginan — sebuah *control loop* (loop kendali). Operator inilah
  jembatan antara dua lapis: ia membaca sinyal runtime dari aplikasi (lapis BEAM) lalu menyetel
  perilaku Kubernetes (lapis orkestrator).

  Tiap siklus (`reconcile`) ia:
    1. mendaftar semua pod aplikasi (lewat `kubectl`),
    2. membaca `/probe` tiap pod (lewat HTTP),
    3. menghitung grace yang memadai dengan `Grace.compute/2` untuk kasus terburuk (maksimum), lalu
    4. menambal (patch) `terminationGracePeriodSeconds` milik Deployment, sehingga rollout berikutnya
       memakai grace yang pas dengan kebutuhan handoff saat itu.

  Ia bicara ke API server memakai `kubectl` (dijalankan via `System.cmd`) dengan ServiceAccount pod
  (izin RBAC ada di `../../k8s/`). Hanya dijalankan dalam peran operator
  (`config :grace_convergence, role: :operator`, diset dari env `GRACE_ROLE=operator`).
  """
  use GenServer
  require Logger
  alias GraceConvergence.Grace

  # Jarak antar-siklus reconcile (milidetik).
  @interval_ms 5_000

  @doc "Memulai proses operator dan mendaftarkannya di bawah nama modul ini."
  def start_link(_), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  @impl true
  def init(s) do
    # Picu reconcile pertama segera (mengirim pesan ke diri sendiri); siklus berikutnya dijadwalkan
    # di dalam handler.
    send(self(), :reconcile)
    {:ok, s}
  end

  @impl true
  def handle_info(:reconcile, s) do
    # Bungkus dengan try/catch: error sementara dari API (mis. jaringan) hanya di-log, TIDAK membuat
    # operator crash. Ini salah satu sifat fail-safe — kalau tak bisa menjangkau API, ia berhenti
    # memperbarui, bukan merusak apa pun.
    try do
      reconcile()
    catch
      kind, e -> Logger.warning("operator reconcile #{inspect(kind)}: #{inspect(e)}")
    end

    # Jadwalkan siklus berikutnya `@interval_ms` ms lagi (pesan :reconcile ke diri sendiri).
    Process.send_after(self(), :reconcile, @interval_ms)
    {:noreply, s}
  end

  @doc "Satu lintasan reconcile: probe semua pod -> hitung grace -> patch Deployment."
  @spec reconcile() :: term()
  def reconcile do
    # Untuk tiap IP pod, ambil reading-nya; `r = probe(ip)` di dalam comprehension juga menyaring nil
    # (pod yang gagal di-probe otomatis terlewati).
    readings = for ip <- pod_ips(), r = probe(ip), do: r

    if readings != [] do
      # Hitung grace untuk SETIAP pod, lalu ambil yang terbesar (kasus terburuk) untuk seluruh Deployment.
      grace = readings |> Enum.map(&Grace.compute(&1, grace_opts())) |> Enum.max()
      patch_grace(grace)
      Logger.info("operator: pods=#{length(readings)} grace=#{grace}s")
    end
  end

  # Ambil daftar IP pod aplikasi via `kubectl get pods ... -o jsonpath`. Kembalikan [] bila gagal.
  defp pod_ips do
    case System.cmd("kubectl", [
           "get", "pods", "-n", namespace(), "-l", selector(),
           "-o", "jsonpath={.items[*].status.podIP}"
         ]) do
      {out, 0} -> out |> String.split() |> Enum.reject(&(&1 == ""))
      _ -> []
    end
  end

  # Ambil reading `/probe` satu pod lewat HTTP (`:httpc` = klien HTTP bawaan Erlang). Kembalikan map
  # ringkas {backlog, rate_eps, t_c_ms}, atau `nil` bila bukan 200/gagal.
  defp probe(ip) do
    url = ~c"http://#{ip}:4000/probe"

    case :httpc.request(:get, {url, []}, [{:timeout, 2_000}], []) do
      {:ok, {{_, 200, _}, _, body}} ->
        # Pakai Jason.decode/1 (bukan decode!/1): JSON rusak mengembalikan {:error, _}, bukan crash.
        # Pod yang merespons tidak valid cukup dilewati (fail-safe), tak menjatuhkan operator.
        case body |> to_string() |> Jason.decode() do
          {:ok, m} -> %{backlog: m["backlog"], rate_eps: m["rate_eps"], t_c_ms: m["t_c_ms"]}
          {:error, _} -> nil
        end

      _ ->
        nil
    end
  end

  # Tambal field `spec.template.spec.terminationGracePeriodSeconds` Deployment dengan nilai `grace`
  # (patch JSON tipe "merge" via `kubectl patch`).
  defp patch_grace(grace) do
    patch = Jason.encode!(%{spec: %{template: %{spec: %{terminationGracePeriodSeconds: grace}}}})

    System.cmd("kubectl", [
      "patch", "deployment", deployment(), "-n", namespace(),
      "--type", "merge", "-p", patch
    ])
  end

  # Kumpulkan konstanta policy dari config untuk diteruskan ke `Grace.compute/2`.
  defp grace_opts do
    cfg = Application.get_all_env(:grace_convergence)
    [sigma: cfg[:sigma], g_min: cfg[:g_min], g_max: cfg[:g_max], t_d: cfg[:t_d], fallback: cfg[:g_max]]
  end

  # Nama Deployment, namespace, dan selector pod — bisa diatur lewat env, dengan default yang masuk akal.
  defp deployment, do: System.get_env("GRACE_DEPLOYMENT", "grace")
  defp namespace, do: System.get_env("GRACE_NAMESPACE", "default")
  defp selector, do: System.get_env("GRACE_SELECTOR", "app=grace")
end
