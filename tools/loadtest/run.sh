#!/usr/bin/env bash
# 부하 발생기 EC2 에서 실행. k6 를 Prometheus remote write 로 붙이고, Grafana 에 시험 구간 주석을 남긴다.
#   BASE=http://172.31.64.6:8000 PROM=http://172.31.64.6:9090 GRAFANA=http://172.31.64.6:3000 \
#   GRAFANA_AUTH=admin:<pw> DEMO_KEY=<key> bash run.sh capture [k6 옵션...]
#   bash run.sh orders_import -e ORDERS=500 -e RATE=2
set -euo pipefail
SCENARIO="${1:?capture|orders_import|packing}"; shift || true
BASE="${BASE:?}"; PROM="${PROM:?}"; GRAFANA="${GRAFANA:?}"; GRAFANA_AUTH="${GRAFANA_AUTH:?}"; DEMO_KEY="${DEMO_KEY:?}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_ID="$(date +%Y%m%d-%H%M%S)-${SCENARIO}"
OUT="$DIR/results/$RUN_ID"; mkdir -p "$OUT"

annotate() {  # $1=text $2=time_ms [$3=timeEnd_ms]
  local body
  if [ -n "${3:-}" ]; then body=$(printf '{"tags":["loadtest","%s"],"text":"%s","time":%s,"timeEnd":%s}' "$SCENARIO" "$1" "$2" "$3")
  else body=$(printf '{"tags":["loadtest","%s"],"text":"%s","time":%s}' "$SCENARIO" "$1" "$2"); fi
  curl -s -u "$GRAFANA_AUTH" -H 'Content-Type: application/json' -d "$body" "$GRAFANA/api/annotations" >/dev/null || true
}

START=$(date +%s%3N)
annotate "start $RUN_ID" "$START"
set +e
K6_PROMETHEUS_RW_SERVER_URL="$PROM/api/v1/write" \
K6_PROMETHEUS_RW_TREND_STATS="p(50),p(95),p(99),max" \
K6_PROMETHEUS_RW_STALE_MARKERS=true \
k6 run --out experimental-prometheus-rw \
  --tag run="$RUN_ID" \
  --summary-export "$OUT/summary.json" \
  -e BASE="$BASE" -e DEMO_KEY="$DEMO_KEY" "$@" \
  "$DIR/k6/$SCENARIO.js" 2>&1 | tee "$OUT/k6.log"
RC=${PIPESTATUS[0]}
set -e
END=$(date +%s%3N)
annotate "end $RUN_ID rc=$RC" "$START" "$END"
echo "run=$RUN_ID rc=$RC out=$OUT"
exit "$RC"
