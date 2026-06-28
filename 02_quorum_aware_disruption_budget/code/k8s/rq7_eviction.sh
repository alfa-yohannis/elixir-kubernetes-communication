#!/usr/bin/env bash
# RQ7 (real cluster). Pada cluster kind yang hidup, tunjukkan bahwa PodDisruptionBudget yang diturunkan
# dari kuorum BENAR-BENAR menolak eviction yang akan memecah kuorum -- sedangkan PDB statis yang
# tak-sadar-kuorum mengizinkannya. Kita pakai Deployment 5 replika dengan kuorum mayoritas Q=3.
#
#   Kasus quorum-aware: minAvailable=Q=3  -> eviction API mengizinkan 2, MENOLAK ke-3 (tetap >=3).
#   Kasus static      : minAvailable=2    -> mengizinkan 3 (turun ke 2 < Q=3, kuorum pecah).
#
# Menulis data/results_eviction.csv. Jalankan:  bash code/k8s/rq7_eviction.sh
set -uo pipefail
NS=qbtest
HERE="$(cd "$(dirname "$0")/../.." && pwd)"
CSV="$HERE/data/results_eviction.csv"
N=5
Q=3

kubectl create namespace "$NS" >/dev/null 2>&1 || true

cat <<YAML | kubectl apply -f - >/dev/null
apiVersion: apps/v1
kind: Deployment
metadata: {name: qb, namespace: $NS}
spec:
  replicas: $N
  selector: {matchLabels: {app: qb}}
  template:
    metadata: {labels: {app: qb}}
    spec:
      terminationGracePeriodSeconds: 1
      containers:
      - name: pause
        image: registry.k8s.io/pause:3.9
YAML

kubectl -n "$NS" rollout status deploy/qb --timeout=90s >/dev/null 2>&1 || true
sleep 2

# Mulai proxy API untuk mengirim permintaan Eviction langsung (subresource /eviction).
kubectl proxy --port=8769 >/dev/null 2>&1 &
PROXY=$!
trap 'kill $PROXY 2>/dev/null; kubectl delete namespace "$NS" --wait=false >/dev/null 2>&1' EXIT
sleep 2

evict_round() { # $1 = minAvailable untuk PDB  -> cetak "allowed denied disruptionsAllowed"
  local minav="$1"
  kubectl -n "$NS" delete pdb qb >/dev/null 2>&1 || true
  cat <<YAML | kubectl apply -f - >/dev/null
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata: {name: qb, namespace: $NS}
spec:
  minAvailable: $minav
  selector: {matchLabels: {app: qb}}
YAML
  # Tunggu PDB menghitung status terhadap 5 pod sehat.
  for _ in $(seq 1 20); do
    da=$(kubectl -n "$NS" get pdb qb -o jsonpath='{.status.disruptionsAllowed}' 2>/dev/null)
    ch=$(kubectl -n "$NS" get pdb qb -o jsonpath='{.status.currentHealthy}' 2>/dev/null)
    [ "${ch:-0}" = "$N" ] && [ -n "${da:-}" ] && break
    sleep 1
  done

  # Coba usir SEMUA pod secepatnya lewat eviction API; hitung 201 (diizinkan) vs 429 (ditolak PDB).
  local allowed=0 denied=0
  for pod in $(kubectl -n "$NS" get pods -l app=qb -o jsonpath='{.items[*].metadata.name}'); do
    code=$(curl -s -o /dev/null -w '%{http_code}' -XPOST \
      "http://localhost:8769/api/v1/namespaces/$NS/pods/$pod/eviction" \
      -H 'Content-Type: application/json' \
      -d "{\"apiVersion\":\"policy/v1\",\"kind\":\"Eviction\",\"metadata\":{\"name\":\"$pod\"}}")
    case "$code" in
      20*) allowed=$((allowed+1)) ;;
      429) denied=$((denied+1)) ;;
    esac
  done
  echo "$allowed $denied ${da:-NA}"
}

echo "policy,n,q,min_available,disruptions_allowed,evictions_allowed,evictions_denied,min_available_after,quorum_broken" > "$CSV"

# Kasus quorum-aware (minAvailable = Q).
read -r a d da <<<"$(evict_round "$Q")"
after=$((N - a)); broken=$([ "$after" -lt "$Q" ] && echo true || echo false)
echo "  quorum_aware minAvailable=$Q: disruptionsAllowed=$da allowed=$a denied=$d -> min_available=$after broken=$broken"
echo "quorum_aware,$N,$Q,$Q,$da,$a,$d,$after,$broken" >> "$CSV"

# Tunggu Deployment pulih ke 5 sebelum kasus berikutnya.
kubectl -n "$NS" rollout status deploy/qb --timeout=90s >/dev/null 2>&1 || true
sleep 3

# Kasus static quorum-unaware (minAvailable = Q-1, "kelihatan aman" di level pod).
read -r a d da <<<"$(evict_round "$((Q-1))")"
after=$((N - a)); broken=$([ "$after" -lt "$Q" ] && echo true || echo false)
echo "  static minAvailable=$((Q-1)): disruptionsAllowed=$da allowed=$a denied=$d -> min_available=$after broken=$broken"
echo "static,$N,$Q,$((Q-1)),$da,$a,$d,$after,$broken" >> "$CSV"

echo "=== wrote $CSV ==="; cat "$CSV"
