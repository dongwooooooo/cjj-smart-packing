#!/usr/bin/env bash
# 사용법: run.sh <시나리오 폴더> <로그 파일> [psql -v 인자...]
# 시나리오 폴더: setup.sql, session_*.sql(동시 실행), final.sql
# 세션 파일은 :'t0'(공통 시작 시각) 기준 pg_sleep_until 로 각자 시점을 맞춘다.
set -euo pipefail
DIR=$1; LOG=$2; shift 2
PG=ledger-cursor-pg
PSQL=(docker exec -i "$PG" psql -X -U postgres -v ON_ERROR_STOP=1 --echo-queries "$@")
TMP=$(mktemp -d)
{
  echo "=== 실행 $(date -u '+%Y-%m-%dT%H:%M:%SZ') 시나리오 $(basename "$DIR") 인자: $*"
  echo "=== setup"
  "${PSQL[@]}" < "$DIR/setup.sql"
} > "$LOG" 2>&1
T0=$(docker exec "$PG" psql -X -U postgres -Atc "select (clock_timestamp() + interval '2 s')::text")
echo "=== t0 = $T0 (세션 공통 기준 시각)" >> "$LOG"
PIDS=()
for f in "$DIR"/session_*.sql; do
  "${PSQL[@]}" -v t0="$T0" < "$f" > "$TMP/$(basename "$f").out" 2>&1 &
  PIDS+=($!)
done
for p in "${PIDS[@]}"; do wait "$p"; done
for f in "$DIR"/session_*.sql; do
  echo; echo "--- $(basename "$f" .sql)"; cat "$TMP/$(basename "$f").out"
done >> "$LOG"
{ echo; echo "=== final"; "${PSQL[@]}" < "$DIR/final.sql"; } >> "$LOG" 2>&1
rm -rf "$TMP"
