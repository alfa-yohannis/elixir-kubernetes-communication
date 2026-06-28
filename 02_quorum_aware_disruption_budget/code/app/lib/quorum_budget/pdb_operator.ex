defmodule QuorumBudget.PDBOperator do
  @moduledoc """
  **Koordinator lintas-lapis** M7, berjalan sebagai pod *operator* Kubernetes.

  Tiap siklus (`reconcile`) ia:
    1. mendaftar semua pod aplikasi (lewat `kubectl`),
    2. membaca `/probe` tiap pod (ukuran cluster `n`, ambang kuorum `q`, kapasitas handoff),
    3. menghitung budget dengan `QuorumBudget.Quorum.budget/2` (mengambil `min_available` terbesar
       sebagai kasus paling aman bila pod tak sepakat soal ukuran cluster), lalu
    4. menambal `spec.minAvailable` milik **PodDisruptionBudget**, sehingga eviction/drain berikutnya
       ditolak Kubernetes bila akan menurunkan anggota tersedia di bawah kuorum.

  Inilah inti M7: PDB yang biasanya statis dan disetel manual kini **diturunkan dari kuorum runtime**.
  Operator berbicara ke API server lewat `kubectl` (via `System.cmd`) dengan ServiceAccount pod.
  Hanya jalan dalam peran operator (`QUORUM_ROLE=operator`).
  """
  use GenServer
  require Logger
  alias QuorumBudget.Quorum

  # Jarak antar-siklus reconcile (milidetik).
  @interval_ms 5_000

  @doc "Memulai operator dan mendaftarkannya di bawah nama modul ini."
  def start_link(_), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  @impl true
  def init(s) do
    send(self(), :reconcile)
    {:ok, s}
  end

  @impl true
  def handle_info(:reconcile, s) do
    # Error sementara dari API hanya di-log; operator tidak crash (fail-safe).
    try do
      reconcile()
    catch
      kind, e -> Logger.warning("operator reconcile #{inspect(kind)}: #{inspect(e)}")
    end

    Process.send_after(self(), :reconcile, @interval_ms)
    {:noreply, s}
  end

  @doc "Satu lintasan reconcile: probe semua pod -> hitung budget -> tambal minAvailable PDB."
  @spec reconcile() :: term()
  def reconcile do
    readings = for ip <- pod_ips(), r = probe(ip), do: r

    if readings != [] do
      # Hitung budget untuk tiap pod; ambil min_available TERBESAR (paling konservatif) bila pod tak
      # sepakat soal ukuran cluster saat membership sedang berubah.
      min_avail =
        readings
        |> Enum.map(fn r -> Quorum.budget(r, q_min: q_min()).min_available end)
        |> Enum.max()

      patch_pdb(min_avail)
      Logger.info("operator: pods=#{length(readings)} minAvailable=#{min_avail}")
    end
  end

  # Daftar IP pod aplikasi via `kubectl get pods ... -o jsonpath`. Kembalikan [] bila gagal.
  defp pod_ips do
    case System.cmd("kubectl", [
           "get", "pods", "-n", namespace(), "-l", selector(),
           "-o", "jsonpath={.items[*].status.podIP}"
         ]) do
      {out, 0} -> out |> String.split() |> Enum.reject(&(&1 == ""))
      _ -> []
    end
  end

  # Ambil reading `/probe` satu pod lewat HTTP. Kembalikan map `%{n, q, cap}` (sesuai bentuk yang
  # diminta `Quorum.budget/2`), atau `nil` bila gagal/JSON rusak (pod itu dilewati, fail-safe).
  defp probe(ip) do
    url = ~c"http://#{ip}:4000/probe"

    case :httpc.request(:get, {url, []}, [{:timeout, 2_000}], []) do
      {:ok, {{_, 200, _}, _, body}} ->
        case body |> to_string() |> Jason.decode() do
          {:ok, m} -> %{n: m["n"], q: m["q"], cap: m["cap"]}
          {:error, _} -> nil
        end

      _ ->
        nil
    end
  end

  # Tambal `spec.minAvailable` PDB (patch JSON tipe "merge" via `kubectl patch`).
  defp patch_pdb(min_avail) do
    patch = Jason.encode!(%{spec: %{minAvailable: min_avail}})

    System.cmd("kubectl", [
      "patch", "pdb", pdb(), "-n", namespace(),
      "--type", "merge", "-p", patch
    ])
  end

  defp q_min, do: Application.get_env(:quorum_budget, :q_min, 1)
  defp pdb, do: System.get_env("QUORUM_PDB", Application.get_env(:quorum_budget, :pdb, "quorum"))
  defp namespace, do: System.get_env("QUORUM_NAMESPACE", Application.get_env(:quorum_budget, :namespace, "default"))
  defp selector, do: System.get_env("QUORUM_SELECTOR", Application.get_env(:quorum_budget, :selector, "app=quorum"))
end
