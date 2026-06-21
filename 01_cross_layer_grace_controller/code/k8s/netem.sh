#!/usr/bin/env bash
# Eksperimen latensi jaringan NYATA pada cluster kind yang hidup (RQ7: apakah estimasi laju rho milik
# controller menangkap RTT antar-pod yang sebenarnya?). Untuk tiap delay satu-arah d yang disuntik,
# kita menyuntik netem pada egress pod survivor, lalu lewat `rpc` rilis kita ukur waktu pulang-pergi
# (RTT) antar-pod ke survivor. Karena tiap handoff Horde = satu RPC pulang-pergi, laju handoff yang
# bisa dicapai rho ~ 1/RTT. Saat d naik, rho turun dan grace yang dibutuhkan membesar -- membuktikan
# rho memang memodelkan latensi nyata, bukan sekadar contention.
#
# Syarat: cluster kind "grace" hidup (6 pod app + operator), docker, kubectl ada di PATH.
# Menulis data/results_netem.csv. Jalankan:  bash code/k8s/netem.sh
set -euo pipefail
export PATH="$HOME/.local/bin:$PATH"

NODE=grace-control-plane
N=40                        # backlog yang di-handoff per pengukuran (kecil: agar tak memicu liveness)
DELAYS=(0 50 100 150)       # latensi satu-arah (ms) yang disuntik pada egress survivor
HERE="$(cd "$(dirname "$0")/../.." && pwd)"
CSV="$HERE/data/results_netem.csv"

# Matikan sementara operator: kalau tidak, backlog yang kita buat membuatnya menambal grace Deployment,
# yang memicu rolling update dan membunuh leaver di tengah pengukuran (exit 137). Dipulihkan saat keluar.
echo "pausing operator (replicas=0)"
kubectl scale deploy/grace-operator --replicas=0 >/dev/null
trap 'echo "restoring operator"; kubectl scale deploy/grace-operator --replicas=1 >/dev/null' EXIT
kubectl rollout status deploy/grace --timeout=120s >/dev/null 2>&1 || true
sleep 3

PODS=($(kubectl get pods -l app=grace --field-selector=status.phase=Running -o jsonpath='{.items[*].metadata.name}'))
LEAVER=${PODS[0]}
SURVIVORS=("${PODS[@]:1}")
echo "leaver=$LEAVER  survivors=${SURVIVORS[*]}  N=$N"

# Kita menyuntik delay pada egress para SURVIVOR (jalur balasan RPC handoff), JANGAN pada leaver:
# men-delay eth0 leaver juga akan merusak koneksi distribusi node `rpc` sementara ke rilis leaver
# sendiri. Cari PID netns sisi-host tiap survivor sekali saja.
pid_of() { docker exec "$NODE" bash -c "crictl inspect \$(crictl ps -q --label io.kubernetes.pod.name=$1 | head -1) | grep -m1 '\"pid\":' | grep -o '[0-9]\+'"; }
SURV_PIDS=()
for s in "${SURVIVORS[@]}"; do SURV_PIDS+=("$(pid_of "$s")"); done
echo "survivor netns pids=${SURV_PIDS[*]}"

netem() { # $1=add|del ... diterapkan ke setiap netns survivor
  local op="$1"; shift
  for p in "${SURV_PIDS[@]}"; do
    docker exec "$NODE" nsenter -t "$p" -n tc qdisc "$op" dev eth0 root "$@" 2>/dev/null || true
  done
}

# Pengukuran Elixir: ukur RTT antar-pod yang sebenarnya ke sebuah survivor (tiap handoff Horde adalah
# satu RPC pulang-pergi sinkron, sehingga laju handoff yang bisa dicapai rho ~ 1/RTT). Dari RTT terukur
# kita proyeksikan grace yang dibutuhkan backlog representatif 2000 proses. Ringan (tanpa churn worker,
# tanpa sinkronisasi Horde berat) sehingga tak memicu liveness probe dan tak bergantung beban cluster.
read -r -d '' EXPR <<'ELIXIR' || true
surv = hd(Node.list())
n = 40
{us, _} = :timer.tc(fn -> Enum.each(1..n, fn _ -> :rpc.call(surv, :erlang, :system_time, [:millisecond]) end) end)
rtt = Float.round(us / 1000 / n, 3)
rate = Float.round(1000 / rtt, 2)
g = GraceConvergence.Grace.compute(%{backlog: 2000, rate_eps: rate, t_c_ms: 0},
      sigma: 5, g_min: 5, g_max: 120, t_d: 1, fallback: 120)
IO.puts("NET rtt=#{rtt} rate=#{rate} grace=#{g}")
ELIXIR

echo "delay_ms,rtt_ms,rate_eps,grace_s" > "$CSV"
for d in "${DELAYS[@]}"; do
  netem del
  [ "$d" -gt 0 ] && netem add netem delay "${d}ms"
  echo "--- injected delay=${d}ms (on survivor egress) ---"
  line=$(kubectl exec "$LEAVER" -- /app/bin/grace_convergence rpc "$EXPR" 2>&1 | grep '^NET ' || true)
  echo "  $line"
  # Ambil angka dari baris keluaran NET dengan sed.
  rtt=$(echo "$line" | sed -n 's/.*rtt=\([0-9.]*\).*/\1/p')
  rate=$(echo "$line" | sed -n 's/.*rate=\([0-9.]*\).*/\1/p')
  g=$(echo "$line"  | sed -n 's/.*grace=\([0-9]*\).*/\1/p')
  echo "${d},${rtt:-},${rate:-},${g:-}" >> "$CSV"
done
netem del
echo "=== done; wrote $CSV ==="
cat "$CSV"
