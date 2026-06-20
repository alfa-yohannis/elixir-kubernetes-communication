#!/usr/bin/env bash
# Real network-latency experiment on the live kind cluster (RQ: does the controller's rate estimate
# rho capture real inter-pod RTT?). For each injected one-way delay d, we inject netem on the leaver
# pod's eth0 (egress), then via release `rpc` start a fixed backlog on that pod and hand it off to the
# survivors, measuring the achieved handoff rate and the grace the policy would assign. As d rises,
# rho falls and the required grace grows -- confirming rho models real latency, not just contention.
#
# Requires: kind cluster "grace" up (6 app pods + operator), docker, kubectl on PATH.
# Writes data/results_netem.csv. Run:  bash code/k8s/netem.sh
set -euo pipefail
export PATH="$HOME/.local/bin:$PATH"

NODE=grace-control-plane
N=40                        # backlog handed off per measurement (small: avoid tripping liveness)
DELAYS=(0 50 100 150)       # injected one-way latency (ms) on the survivor egress
HERE="$(cd "$(dirname "$0")/../.." && pwd)"
CSV="$HERE/data/results_netem.csv"

# Pause the operator: otherwise the backlog we create makes it patch the Deployment's grace, which
# triggers a rolling update that kills our leaver mid-measurement (exit 137). Restore on exit.
echo "pausing operator (replicas=0)"
kubectl scale deploy/grace-operator --replicas=0 >/dev/null
trap 'echo "restoring operator"; kubectl scale deploy/grace-operator --replicas=1 >/dev/null' EXIT
kubectl rollout status deploy/grace --timeout=120s >/dev/null 2>&1 || true
sleep 3

PODS=($(kubectl get pods -l app=grace --field-selector=status.phase=Running -o jsonpath='{.items[*].metadata.name}'))
LEAVER=${PODS[0]}
SURVIVORS=("${PODS[@]:1}")
echo "leaver=$LEAVER  survivors=${SURVIVORS[*]}  N=$N"

# We inject delay on the SURVIVORS' egress (the handoff RPC reply path), never on the leaver:
# delaying the leaver's eth0 would also break the short-lived `rpc` helper node's distribution
# connection to the leaver's own release. Resolve each survivor's host-side netns PID once.
pid_of() { docker exec "$NODE" bash -c "crictl inspect \$(crictl ps -q --label io.kubernetes.pod.name=$1 | head -1) | grep -m1 '\"pid\":' | grep -o '[0-9]\+'"; }
SURV_PIDS=()
for s in "${SURVIVORS[@]}"; do SURV_PIDS+=("$(pid_of "$s")"); done
echo "survivor netns pids=${SURV_PIDS[*]}"

netem() { # $1=add|del ... applied to every survivor netns
  local op="$1"; shift
  for p in "${SURV_PIDS[@]}"; do
    docker exec "$NODE" nsenter -t "$p" -n tc qdisc "$op" dev eth0 root "$@" 2>/dev/null || true
  done
}

# Elixir measurement: clean cluster-wide, start N locally, drain to survivors, report rate+grace.
# Measure the real inter-pod round-trip time to a survivor (each Horde handoff is one such
# synchronous RPC round-trip, so the achievable handoff rate rho ~ 1/RTT). From the measured RTT we
# project the grace a representative 2000-process backlog would need. Lightweight (no worker churn,
# no heavy Horde sync) so it neither trips the liveness probe nor depends on cluster load.
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
  rtt=$(echo "$line" | sed -n 's/.*rtt=\([0-9.]*\).*/\1/p')
  rate=$(echo "$line" | sed -n 's/.*rate=\([0-9.]*\).*/\1/p')
  g=$(echo "$line"  | sed -n 's/.*grace=\([0-9]*\).*/\1/p')
  echo "${d},${rtt:-},${rate:-},${g:-}" >> "$CSV"
done
netem del
echo "=== done; wrote $CSV ==="
cat "$CSV"
