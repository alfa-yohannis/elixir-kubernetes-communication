#!/usr/bin/env bash
# Injeksi gangguan (fault-injection) pada cluster kind yang hidup: memvalidasi klaim fail-safe controller.
#   A  operator crash       -> koordinator pulih dan penetapan grace bersifat idempoten
#   B  probe tak terpakai    -> policy mengembalikan grace default-aman (g_max), bukan nilai kecil
#   C  akses API dicabut      -> patch yang gagal ditoleransi (tanpa crash, tanpa korupsi); grace bertahan
# Syarat: cluster kind "grace" hidup. Memulihkan RBAC saat keluar. Jalankan:  bash code/k8s/faults.sh
set -uo pipefail
export PATH="$HOME/.local/bin:$PATH"
HERE="$(cd "$(dirname "$0")/../.." && pwd)"

kubectl scale deploy/grace-operator --replicas=1 >/dev/null 2>&1
kubectl rollout status deploy/grace-operator --timeout=90s >/dev/null 2>&1 || true

echo "===== Fault A: operator crash -> recovery (idempotent grace) ====="
GB=$(kubectl get deploy grace -o jsonpath='{.spec.template.spec.terminationGracePeriodSeconds}')
echo "before: deployment grace=${GB}s"
kubectl delete pod -l app=grace-operator >/dev/null
kubectl rollout status deploy/grace-operator --timeout=90s >/dev/null 2>&1 || true
sleep 8
echo "operator log after restart:"; kubectl logs deploy/grace-operator --tail=2 2>/dev/null | sed 's/^/  /'
GA=$(kubectl get deploy grace -o jsonpath='{.spec.template.spec.terminationGracePeriodSeconds}')
echo "after:  deployment grace=${GA}s  (recovered, grace stable ${GB}->${GA})"

echo; echo "===== Fault B: unusable probe -> default-safe fallback ====="
APP=$(kubectl get pods -l app=grace --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}')
# Panggil Grace.compute dengan tiga reading: normal, tak terpakai (rate 0), dan field hilang.
kubectl exec "$APP" -- /app/bin/grace_convergence rpc '
o = [sigma: 5, g_min: 5, g_max: 120, t_d: 1, fallback: 120]
normal   = GraceConvergence.Grace.compute(%{backlog: 100, rate_eps: 10.0, t_c_ms: 0}, o)
unusable = GraceConvergence.Grace.compute(%{backlog: 500, rate_eps: 0, t_c_ms: 0}, o)
missing  = GraceConvergence.Grace.compute(%{foo: 1}, o)
IO.puts("FAULTB normal=#{normal}s (sized) unusable=#{unusable}s (=g_max) missing=#{missing}s (=g_max)")
' 2>&1 | grep FAULTB | sed 's/^/  /'

echo; echo "===== Fault C: revoked API patch permission -> safe degradation ====="
SA=system:serviceaccount:default:grace-operator
echo "can-i patch deployments (before): $(kubectl auth can-i patch deployments --as=$SA 2>/dev/null)"
# Pulihkan RBAC saat keluar apa pun yang terjadi (trap), agar cluster tak ditinggalkan tanpa izin.
trap 'echo "  restoring RBAC"; kubectl apply -f "$HERE/code/k8s/rbac.yaml" >/dev/null 2>&1' EXIT
kubectl delete rolebinding grace-operator >/dev/null 2>&1
echo "can-i patch deployments (after revoke): $(kubectl auth can-i patch deployments --as=$SA 2>/dev/null)"
R0=$(kubectl get pods -l app=grace-operator -o jsonpath='{.items[0].status.containerStatuses[0].restartCount}')
sleep 12
R1=$(kubectl get pods -l app=grace-operator -o jsonpath='{.items[0].status.containerStatuses[0].restartCount}')
echo "operator restarts ${R0}->${R1} under revoked perms (equal = no crash-loop)"
echo "operator log under revoked perms:"; kubectl logs deploy/grace-operator --tail=2 2>/dev/null | sed 's/^/  /'
echo "deployment grace still set: $(kubectl get deploy grace -o jsonpath='{.spec.template.spec.terminationGracePeriodSeconds}')s (last value persists)"
echo "=== fault-injection done ==="
