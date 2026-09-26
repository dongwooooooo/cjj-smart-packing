#!/usr/bin/env bash
# 촬영 사진 업로드 A/C 실측 (specs/2026-09-26-upload-before-response-design.md 5절 M1~M4).
#   A = 실험 전 이미지(세션 커밋 뒤 비동기 업로드), C = cj-ai-backend:upload-c(추론과 병렬, 응답 전 업로드).
# 조건마다: 이미지 반영 → 데모 리셋(추론 워밍 포함) → [부하 조건은 같은 작업자 수로 30초 예열] → 측정 → 수집.
# 접속 값은 pool-sweep.env 를 그대로 쓴다. 결과는 docs/evidence/upload-before-response/<조건>/ 에 쌓인다.
#
#   bash tools/loadtest/upload-ab.sh check                 접속·현재 이미지 확인
#   bash tools/loadtest/upload-ab.sh build <backend 커밋> [태그]  EC2 에 C 이미지 빌드(git archive → docker build)
#   bash tools/loadtest/upload-ab.sh m1 A|C                단일 클라이언트 11종 × 5회 순차
#   bash tools/loadtest/upload-ab.sh m2 A|C <작업자 수>      k6 고정 작업자 3분
#   bash tools/loadtest/upload-ab.sh m3 A|C                작업자 10명 부하 중 60초 시점 backend 재시작
#   bash tools/loadtest/upload-ab.sh m3k A|C <작업자 수>     부하 중 60초 시점 SIGKILL(크래시) 뒤 재기동 — M3 보조
#   bash tools/loadtest/upload-ab.sh m4 A|C                작업자 60명 3분(포화)
#   bash tools/loadtest/upload-ab.sh restore               실험 전 이미지로 되돌리고 리셋·사진 행 정리
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HERE="$REPO_ROOT/tools/loadtest"
# shellcheck source=pool-sweep.env
source "$HERE/pool-sweep.env"
OUT_ROOT="$REPO_ROOT/docs/evidence/upload-before-response"
STATE_DIR="$REPO_ROOT/local/upload-ab"; mkdir -p "$STATE_DIR" "$OUT_ROOT"
BASELINE="$STATE_DIR/baseline.env"
C_IMAGE="cj-ai-backend:upload-c"
C6_IMAGE="cj-ai-backend:upload-c6"
PY="${PY:-python3}"
# AB_SETTLE_S: 종료 뒤 상태를 다시 셀 때까지 기다리는 초. pool-sweep.env 의 SETTLE_S 와 이름을 나눴다
DURATION="${DURATION:-3m}"; WARM="${WARM:-30s}"; AB_SETTLE_S="${AB_SETTLE_S:-60}"; RESTART_AT_S="${RESTART_AT_S:-60}"

SSH_OPTS=(-i "$SSH_KEY" -o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=30
          -o UserKnownHostsFile="$KNOWN_HOSTS" -o StrictHostKeyChecking=yes)
on_backend() { ssh "${SSH_OPTS[@]}" "$SSH_USER@$BACKEND_HOST" "$@"; }
on_loadgen() { ssh "${SSH_OPTS[@]}" "$SSH_USER@$LOADGEN_HOST" "$@"; }
log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
progress() { echo "- $(date '+%m-%d %H:%M') $*" >> "$OUT_ROOT/progress.md"; }

psql_cmd() {  # SQL 은 표준입력으로 보낸다(따옴표가 원격 셸을 거치지 않게). 결과는 값만, 쉼표 구분
  printf '%s\n' "$1" | on_backend "cd $BACKEND_DIR && sudo docker run --rm -i --network host --env-file .env $PSQL_IMAGE \
    sh -c 'PGPASSWORD=\$POSTGRES_PASSWORD exec psql -h \$POSTGRES_HOST -U \$POSTGRES_USER -d \$POSTGRES_DB -XAt -F,'"
}
demo_key() { on_backend "grep '^DEMO_API_KEY=' $BACKEND_DIR/.env | cut -d= -f2-"; }
metrics_grep() {
  on_backend "K=\$(grep '^DEMO_API_KEY=' $BACKEND_DIR/.env | cut -d= -f2-); curl -s -H \"X-Demo-Key: \$K\" localhost:8000/actuator/prometheus | grep -E '$1' || true"
}
wait_health() {
  on_backend "for i in \$(seq 1 90); do curl -fsS --max-time 3 localhost:8000/actuator/health 2>/dev/null | grep -q '\"UP\"' && exit 0; sleep 2; done; exit 1"
}
prom_query() {  # $1 PromQL, $2 평가 시각(epoch 초). 값만 출력(없으면 빈 값)
  on_backend "curl -s --max-time 10 localhost:9090/api/v1/query --data-urlencode 'query=$1' --data-urlencode 'time=$2'" \
    | "$PY" -c 'import json,sys; r=json.load(sys.stdin)["data"]["result"]; print(r[0]["value"][1] if r else "")'
}
annotate() {  # $1 text, $2 start ms, [$3 end ms]
  [ -f "$GRAFANA_ENV" ] || return 0
  local pw body; pw=$(grep '^GRAFANA_ADMIN_PASSWORD=' "$GRAFANA_ENV" | cut -d= -f2-)
  if [ -n "${3:-}" ]; then body=$(printf '{"tags":["upload-ab"],"text":"%s","time":%s,"timeEnd":%s}' "$1" "$2" "$3")
  else body=$(printf '{"tags":["upload-ab"],"text":"%s","time":%s}' "$1" "$2"); fi
  curl -s --max-time 10 -u "admin:$pw" -H 'Content-Type: application/json' -d "$body" "$GRAFANA_PUBLIC/api/annotations" >/dev/null || true
}
rds_credit() {
  "$PY" - "$RDS_ID" "$AWS_REGION" <<'PYEOF' 2>/dev/null || true
import sys, datetime as dt, boto3
cw = boto3.client("cloudwatch", region_name=sys.argv[2]); now = dt.datetime.now(dt.timezone.utc)
r = cw.get_metric_statistics(Namespace="AWS/RDS", MetricName="CPUCreditBalance", Statistics=["Average"], Period=300,
    Dimensions=[{"Name": "DBInstanceIdentifier", "Value": sys.argv[1]}], StartTime=now - dt.timedelta(minutes=15), EndTime=now)
pts = sorted(r["Datapoints"], key=lambda p: p["Timestamp"])
print(round(pts[-1]["Average"], 1) if pts else "")
PYEOF
}

# ── 이미지 ────────────────────────────────────────────────────────────────
capture_baseline() {
  [ -f "$BASELINE" ] && { log "기준 파일 사용: $BASELINE"; return; }
  local ref id
  ref=$(on_backend "sudo docker inspect --format '{{.Config.Image}}' $BACKEND_CONTAINER")
  id=$(on_backend "sudo docker inspect --format '{{.Image}}' $BACKEND_CONTAINER")
  printf 'BASE_IMAGE_REF=%s\nBASE_IMAGE_ID=%s\nCAPTURED_AT=%s\n' "$ref" "$id" "$(date -u +%FT%TZ)" > "$BASELINE"
  log "기준 상태 기록: ${ref##*/} (${id:7:12})"
}
image_ref() {  # $1 A|C
  # shellcheck disable=SC1090
  source "$BASELINE"
  # C6 = C 에서 업로드 풀 코어만 3 → 6 (backend exp/upload-c-core6, M4 보조)
  case "$1" in A) echo "$BASE_IMAGE_REF" ;; C) echo "$C_IMAGE" ;; C6) echo "$C6_IMAGE" ;; *) log "이미지는 A, C, C6"; exit 1 ;; esac
}
use_image() {  # $1 A|C. 이미 그 이미지로 떠 있어도 새로 띄운다 — 조건마다 같은 JVM 상태에서 시작하려고
  local ref; ref=$(image_ref "$1")
  on_backend "cd $BACKEND_DIR && sudo env BACKEND_IMAGE='$ref' docker compose up -d --no-build --force-recreate backend >/dev/null 2>&1"
  wait_health || { log "헬스 UP 실패 ($1)"; exit 1; }
  CUR_IMAGE_ID=$(on_backend "sudo docker inspect --format '{{.Image}}' $BACKEND_CONTAINER")
  log "이미지 $1 = ${ref##*/} (${CUR_IMAGE_ID:7:12})"
}
demo_reset() {  # 리셋은 측정 세션·사진 행을 지우고 끝에 추론을 한 번 깨운다(콜드 스타트 제외)
  on_backend "K=\$(grep '^DEMO_API_KEY=' $BACKEND_DIR/.env | cut -d= -f2-); curl -s --max-time 300 -X POST -H \"X-Demo-Key: \$K\" localhost:8000/api/v1/admin/demo/reset"
}
sync_tools() {
  on_loadgen "mkdir -p \$HOME/upload-ab/k6" && scp -q "${SSH_OPTS[@]}" "$HERE"/k6/*.js "$HERE"/k6/*.json "$SSH_USER@$LOADGEN_HOST:upload-ab/k6/"
  scp -q "${SSH_OPTS[@]}" "$REPO_ROOT/tools/measure/measure_prod.py" "$REPO_ROOT/backend/demo/data/products.json" "$SSH_USER@$LOADGEN_HOST:upload-ab/"
  scp -q "${SSH_OPTS[@]}" "$HERE/monitoring/grafana/dashboards/cjj-upload-ab.json" "$SSH_USER@$BACKEND_HOST:monitoring/grafana/dashboards/"
}

# ── 조건 공통 ─────────────────────────────────────────────────────────────
begin_condition() {  # $1 조건 id, $2 A|C → COND_DIR, DEMO_KEY_VALUE 설정
  COND_ID="$1"; COND_DIR="$OUT_ROOT/$1"; mkdir -p "$COND_DIR"
  capture_baseline
  sync_tools
  DEMO_KEY_VALUE=$(demo_key)
  local credit; credit=$(rds_credit); echo "$credit" > "$COND_DIR/rds-credit-before.txt"
  log "── 조건 $1 (RDS CPU 크레딧 $credit)"
  use_image "$2"
  demo_reset > "$COND_DIR/reset.json"
  log "리셋: $(head -c 300 "$COND_DIR/reset.json")"
  printf '{"id":"%s","image":"%s","image_id":"%s","rds_credit_before":"%s","started":"%s","portfolio_sha":"%s"}\n' \
    "$1" "$2" "${CUR_IMAGE_ID:7:12}" "$credit" "$(date -u +%FT%TZ)" "$(git -C "$REPO_ROOT" rev-parse --short HEAD)" > "$COND_DIR/meta.json"
}
db_now() { psql_cmd "select to_char(clock_timestamp(), 'YYYY-MM-DD HH24:MI:SS.US')"; }
db_counts() {  # $1 이후 생성된 사진 행·세션을 상태별로. 결과 파일 한 줄씩
  psql_cmd "select 'image', upload_status, count(*) from measurement_image where created_at >= '$1' group by 2
            union all select 'session', status, count(*) from measurement_session where created_at >= '$1' group by 2
            union all select 'session_without_image', s.status, count(*) from measurement_session s
              where s.created_at >= '$1' and not exists (select 1 from measurement_image i where i.session_id = s.id) group by 2
            order by 1, 2"
}
k6_run() {  # $1 원격 결과 디렉터리 $2 작업자 수 $3 기간 $4 run 태그. rc 한 줄을 출력한다
  on_loadgen "read -r DEMO_KEY; export DEMO_KEY; mkdir -p ~/$1 && cd ~/upload-ab && echo K6START=\$(date +%s) > ~/$1/k6.log && \
    K6_PROMETHEUS_RW_SERVER_URL=http://$BACKEND_PRIVATE:9090/api/v1/write K6_PROMETHEUS_RW_TREND_STATS='p(50),p(95),p(99),max' \
    K6_PROMETHEUS_RW_STALE_MARKERS=true \
    k6 run --out experimental-prometheus-rw --tag run=$4 --summary-trend-stats 'avg,min,med,max,p(95),p(99)' \
      --summary-export ~/$1/summary.json -e BASE=http://$BACKEND_PRIVATE:8000 -e VUS=$2 -e DURATION=$3 \
      k6/capture.js >> ~/$1/k6.log 2>&1; echo rc=\$?" <<< "$DEMO_KEY_VALUE"
}
fetch_k6() {  # $1 원격 결과 디렉터리 → COND_DIR
  scp -q "${SSH_OPTS[@]}" "$SSH_USER@$LOADGEN_HOST:$1/summary.json" "$SSH_USER@$LOADGEN_HOST:$1/k6.log" "$COND_DIR/" \
    || log "k6 결과 회수 실패"
}
backend_logs() {  # $1 epoch 초 이후 백엔드 로그 → $2 파일
  on_backend "sudo docker logs --since $1 $BACKEND_CONTAINER 2>&1" > "$2" || true
}
pool_stats() {  # $1 시작 $2 끝(epoch 초) → 업로드 풀 활성·큐 최대, CallerRuns 횟수
  local w=$(( $2 - $1 )) q a c
  q=$(prom_query "max(max_over_time(executor_queued_tasks{name=\"imageUploadExecutor\"}[${w}s]))" "$2")
  a=$(prom_query "max(max_over_time(executor_active_threads{name=\"imageUploadExecutor\"}[${w}s]))" "$2")
  c=$(prom_query "sum(increase(upload_caller_runs_total[${w}s]))" "$2")
  printf '{"queue_max":"%s","active_max":"%s","caller_runs":"%s","window_s":%s}\n' "$q" "$a" "$c" "$w"
}
capture_grafana() {  # $1 시작 $2 끝(epoch 초)
  "$PY" "$HERE/sweep/capture.py" --url "$GRAFANA_PUBLIC/d/cjj-upload-ab/?orgId=1&from=$((($1 - 30) * 1000))&to=$((($2 + 30) * 1000))" \
    --out "$COND_DIR/grafana.png" --height 1500 2>/dev/null || log "캡처 실패(무시)"
}
finish_condition() {  # $1 측정 시작 $2 측정 끝 $3 DB 시작 시각
  db_counts "$3" > "$COND_DIR/db-counts-at-end.csv"
  sleep 12  # 마지막 스크레이프(5초 주기)가 들어올 때까지
  pool_stats "$1" "$2" > "$COND_DIR/pool.json"
  log "종료 직후 상태별: $(tr '\n' ' ' < "$COND_DIR/db-counts-at-end.csv")"
  log "업로드 풀: $(cat "$COND_DIR/pool.json")"
  sleep "$AB_SETTLE_S"  # A 는 커밋 뒤 대기 줄이 마저 빠질 시간. 이 뒤에도 PENDING 이면 유실이다
  db_counts "$3" > "$COND_DIR/db-counts-settled.csv"
  log "${AB_SETTLE_S}초 뒤 상태별: $(tr '\n' ' ' < "$COND_DIR/db-counts-settled.csv")"
  backend_logs "$1" "$COND_DIR/backend.log"
  printf '{"rejected":%s,"caller_runs_log":%s,"upload_failed_log":%s,"image_store_failed_log":%s}\n' \
    "$(grep -c 'RejectedExecution\|TaskRejected' "$COND_DIR/backend.log" || true)" \
    "$(grep -c 'upload.caller_runs' "$COND_DIR/backend.log" || true)" \
    "$(grep -c '사진 업로드 실패\|사진 업로드가 .*실패' "$COND_DIR/backend.log" || true)" \
    "$(grep -c '촬영을 실패로 처리한다' "$COND_DIR/backend.log" || true)" > "$COND_DIR/log-counts.json"
  log "로그: $(cat "$COND_DIR/log-counts.json")"
  # 증거로 남길 줄만 두고 압축한다(구간 로그·경고·종료 과정). 전체 로그는 조건당 수 MB 다
  grep -E "timing|WARN|ERROR|Exception|GracefulShutdown|Started BackendApplication|Closing JPA|caller_runs|업로드|촬영을 실패" \
    "$COND_DIR/backend.log" | gzip -9 > "$COND_DIR/backend.log.gz" && rm -f "$COND_DIR/backend.log"
  echo "$(rds_credit)" > "$COND_DIR/rds-credit-after.txt"
  capture_grafana "$1" "$2"
  "$PY" "$HERE/upload-ab-summary.py" --dir "$COND_DIR" | tee "$COND_DIR/summary.txt"
  progress "\`$COND_ID\` $(cat "$COND_DIR/summary.txt")"
}

# ── 측정 ──────────────────────────────────────────────────────────────────
cmd_m1() {  # $1 A|C
  begin_condition "m1-$1${REP:+-r$REP}" "$1"
  local t0 t1; t0=$(date +%s)
  on_loadgen "read -r DEMO_KEY; export DEMO_KEY; cd ~/upload-ab && python3 measure_prod.py --base http://$BACKEND_PRIVATE:8000 \
    --rounds 5 --products products.json --out m1.json" <<< "$DEMO_KEY_VALUE" | tee "$COND_DIR/client.txt"
  t1=$(date +%s)
  scp -q "${SSH_OPTS[@]}" "$SSH_USER@$LOADGEN_HOST:upload-ab/m1.json" "$COND_DIR/client.json"
  backend_logs "$t0" "$COND_DIR/backend.log"
  # 업로드가 응답 뒤에 끝나는 A 는 마지막 upload.timing 이 조금 늦게 찍힌다
  sleep 3; backend_logs "$t0" "$COND_DIR/backend.log"
  grep -E 'measure\.timing|upload\.timing|inference\.timing' "$COND_DIR/backend.log" | "$PY" "$REPO_ROOT/tools/measure/parse_timing.py" \
    > "$COND_DIR/server-stages.md"
  cat "$COND_DIR/server-stages.md"
  echo "$(rds_credit)" > "$COND_DIR/rds-credit-after.txt"
  annotate "$COND_ID" "$((t0 * 1000))" "$((t1 * 1000))"
  progress "\`$COND_ID\` $(grep 'client e2e' "$COND_DIR/client.txt")"
}

cmd_load() {  # $1 조건 id $2 A|C $3 작업자 수 [$4 재시작 여부]
  begin_condition "$1" "$2"
  local tag="$1" rdir="upload-ab/runs/$1"
  log "예열: 작업자 $3명 $WARM"
  k6_run "$rdir-warm" "$3" "$WARM" "$tag-warm" > "$COND_DIR/warm.rc"
  local since; since=$(db_now); echo "$since" > "$COND_DIR/db-since.txt"
  local t0 t1 restart_pid=""; t0=$(date +%s)
  annotate "start $tag" "$((t0 * 1000))"
  if [ -n "${4:-}" ]; then  # restart = SIGTERM 뒤 정상 종료, kill = SIGKILL(크래시 흉내) 뒤 다시 시작
    local stop_cmd="sudo docker compose restart backend"
    [ "$4" = kill ] && stop_cmd="sudo docker compose kill -s SIGKILL backend && sudo docker compose start backend"
    ( sleep "$RESTART_AT_S"; date +%s > "$COND_DIR/restart-at.txt"
      on_backend "cd $BACKEND_DIR && $stop_cmd" > "$COND_DIR/restart.log" 2>&1
      date +%s >> "$COND_DIR/restart-at.txt" ) & restart_pid=$!
  fi
  k6_run "$rdir" "$3" "$DURATION" "$tag" > "$COND_DIR/k6.rc" || true
  t1=$(date +%s)
  [ -n "$restart_pid" ] && wait "$restart_pid" || true
  [ -n "${4:-}" ] && { wait_health || log "재시작 뒤 헬스 UP 실패"; }
  annotate "$tag" "$((t0 * 1000))" "$((t1 * 1000))"
  printf '{"t0":%s,"t1":%s,"vus":%s,"duration":"%s","warm":"%s","restart":"%s"}\n' "$t0" "$t1" "$3" "$DURATION" "$WARM" "${4:-}" > "$COND_DIR/window.json"
  fetch_k6 "$rdir"
  finish_condition "$t0" "$t1" "$since"
}

cmd_restore() {
  capture_baseline
  # shellcheck disable=SC1090
  source "$BASELINE"
  on_backend "cd $BACKEND_DIR && sudo env BACKEND_IMAGE='$BASE_IMAGE_REF' docker compose up -d --no-build --force-recreate backend >/dev/null 2>&1"
  wait_health || log "경고: 복원 후 헬스 UP 확인 실패"
  local id; id=$(on_backend "sudo docker inspect --format '{{.Image}}' $BACKEND_CONTAINER")
  demo_reset > "$STATE_DIR/restore-reset.json"
  local left; left=$(psql_cmd "select count(*) from measurement_image")
  if [ "$id" = "$BASE_IMAGE_ID" ]; then log "복원 확인: 이미지 ${id:7:12} 일치, 남은 measurement_image $left행"
  else log "경고: 복원 불일치 (image=${id:7:12} 기준=${BASE_IMAGE_ID:7:12})"; fi
  progress "복원: 이미지 ${id:7:12}(기준 ${BASE_IMAGE_ID:7:12}), 데모 리셋, measurement_image ${left}행"
}

cmd_build() {  # $1 backend 커밋 [$2 태그]. 소스는 git archive 로 보내 EC2 에서 빌드한다(ECR·GitHub push 없음)
  local sha="${1:?backend 커밋}" C_IMAGE="${2:-$C_IMAGE}"
  git -C "$REPO_ROOT/backend" archive --format=tar "$sha" | on_backend "rm -rf ~/upload-c-src && mkdir -p ~/upload-c-src && tar -x -C ~/upload-c-src"
  local t0; t0=$(date +%s)
  on_backend "cd ~/upload-c-src && sudo docker build -q -t $C_IMAGE . 2>&1 | tail -3"
  log "빌드 $(( $(date +%s) - t0 ))초, $(on_backend "sudo docker images --format '{{.ID}}' $C_IMAGE")"
  progress "C 이미지 빌드: git archive $sha → \`$C_IMAGE\` ($(on_backend "sudo docker images --format '{{.ID}}' $C_IMAGE"), $(( $(date +%s) - t0 ))초). 소스 EC2 ~/upload-c-src"
}

case "${1:-}" in
  check) capture_baseline; log "백엔드 $(on_backend hostname), 부하 발생기 $(on_loadgen hostname)"; cat "$BASELINE" >&2
         metrics_grep '^executor_(active_threads|queued_tasks|pool_max_threads)' >&2 ;;
  build) shift; cmd_build "$@" ;;
  m1) cmd_m1 "${2:?A|C}" ;;
  m2) cmd_load "m2-$2-v${3:?작업자 수}" "$2" "$3" ;;
  m3) cmd_load "m3-$2" "${2:?A|C}" 10 restart ;;
  m3k) cmd_load "m3k-$2-v${3:?작업자 수}" "$2" "$3" kill ;;
  m4) cmd_load "m4-$2" "${2:?A|C}" 60 ;;
  restore) cmd_restore ;;
  sh) shift; on_backend "$@" ;;
  *) sed -n '2,15p' "$0"; exit 1 ;;
esac
