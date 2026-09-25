#!/usr/bin/env bash
# 커넥션 풀·서버 설정 스윕 도구. 부하는 고정하고 설정(풀 크기·connectionTimeout·Tomcat 스레드)만 바꿔 가며
# 조건마다 같은 절차로 잰다: 설정 반영·재시작 → 데이터 원복 → k6 → 지표 수집 → 한 줄 출력. 끝나면(중단돼도)
# 백엔드를 실험 전 설정으로 되돌린다. 조작 값은 pool-sweep.env 한 곳에 있다.
#
#   bash tools/loadtest/pool-sweep.sh check              접속·현재 설정 확인(아무것도 바꾸지 않음)
#   bash tools/loadtest/pool-sweep.sh fixture 20000      실험용 출고지시 20,000건 접수(한 번만)
#   bash tools/loadtest/pool-sweep.sh sweep              스윕 실행 → docs/evidence/pool-sizing/<시각>/
#   bash tools/loadtest/pool-sweep.sh report <디렉터리>   비교표 README.md 다시 만들기
#   bash tools/loadtest/pool-sweep.sh restore            백엔드를 실험 전 설정으로 되돌리기(수동)
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HERE="$REPO_ROOT/tools/loadtest"
# shellcheck source=pool-sweep.env
source "$HERE/pool-sweep.env"
STATE_DIR="$REPO_ROOT/local/pool-sweep"; mkdir -p "$STATE_DIR"
BASELINE="$STATE_DIR/baseline.env"
OVERRIDE="docker-compose.pool-sweep.yml"
PY="${PY:-python3}"

SSH_OPTS=(-i "$SSH_KEY" -o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=30
          -o UserKnownHostsFile="$KNOWN_HOSTS" -o StrictHostKeyChecking=yes)
on_backend() { ssh "${SSH_OPTS[@]}" "$SSH_USER@$BACKEND_HOST" "$@"; }
on_loadgen() { ssh "${SSH_OPTS[@]}" "$SSH_USER@$LOADGEN_HOST" "$@"; }
log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }

# 백엔드 호스트에서 RDS 로 psql 을 실행한다. SQL 파일은 ~/pool-sweep 에 복사돼 있다. 나머지 인자는 psql 옵션.
psql_file() {
  local f="$1"; shift
  on_backend "cd $BACKEND_DIR && sudo docker run --rm --network host --env-file .env -v \$HOME/pool-sweep:/sql:ro $PSQL_IMAGE \
    sh -c 'PGPASSWORD=\$POSTGRES_PASSWORD exec psql -h \$POSTGRES_HOST -U \$POSTGRES_USER -d \$POSTGRES_DB -X -q $* -f /sql/$f'"
}
psql_cmd() {  # 한 줄 SQL(표준입력으로 보낸다 — 따옴표가 원격 셸을 거치지 않게), 결과는 값만
  printf '%s\n' "$1" | on_backend "cd $BACKEND_DIR && sudo docker run --rm -i --network host --env-file .env $PSQL_IMAGE \
    sh -c 'PGPASSWORD=\$POSTGRES_PASSWORD exec psql -h \$POSTGRES_HOST -U \$POSTGRES_USER -d \$POSTGRES_DB -XAt'"
}
demo_key() { on_backend "grep '^DEMO_API_KEY=' $BACKEND_DIR/.env | cut -d= -f2-"; }
metrics_grep() {  # 백엔드 /actuator/prometheus 에서 패턴에 맞는 줄
  on_backend "K=\$(grep '^DEMO_API_KEY=' $BACKEND_DIR/.env | cut -d= -f2-); curl -s -H \"X-Demo-Key: \$K\" localhost:8000/actuator/prometheus | grep -E '$1' || true"
}
wait_health() {
  on_backend "for i in \$(seq 1 90); do curl -fsS --max-time 3 localhost:8000/actuator/health 2>/dev/null | grep -q '\"UP\"' && exit 0; sleep 2; done; exit 1"
}
annotate() {  # $1 text, $2 start ms, [$3 end ms]
  [ -f "$GRAFANA_ENV" ] || return 0
  local pw body; pw=$(grep '^GRAFANA_ADMIN_PASSWORD=' "$GRAFANA_ENV" | cut -d= -f2-)
  if [ -n "${3:-}" ]; then body=$(printf '{"tags":["pool-sweep"],"text":"%s","time":%s,"timeEnd":%s}' "$1" "$2" "$3")
  else body=$(printf '{"tags":["pool-sweep"],"text":"%s","time":%s}' "$1" "$2"); fi
  curl -s --max-time 10 -u "admin:$pw" -H 'Content-Type: application/json' -d "$body" "$GRAFANA_PUBLIC/api/annotations" >/dev/null || true
}

# ── 기준 상태(실험 전 설정) ───────────────────────────────────────────────
container_env_has_override() {
  on_backend "sudo docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' $BACKEND_CONTAINER | grep -c '^SPRING_APPLICATION_JSON=' || true"
}
capture_baseline() {
  if [ "$(container_env_has_override)" != "0" ]; then
    [ -f "$BASELINE" ] || { log "백엔드에 이미 실험 설정이 있는데 기준 파일이 없다. 수동 확인 필요"; exit 1; }
    log "이전 실행이 남긴 실험 설정 발견 — 기존 기준 파일 사용: $BASELINE"; return
  fi
  local ref id
  ref=$(on_backend "sudo docker inspect --format '{{.Config.Image}}' $BACKEND_CONTAINER")
  id=$(on_backend "sudo docker inspect --format '{{.Image}}' $BACKEND_CONTAINER")
  printf 'BASE_IMAGE_REF=%s\nBASE_IMAGE_ID=%s\nCAPTURED_AT=%s\n' "$ref" "$id" "$(date -u +%FT%TZ)" > "$BASELINE"
  log "기준 상태 기록: 이미지 ${ref##*/} (${id:7:12}), 실험 설정 없음"
}
restore_backend() {
  [ -f "$BASELINE" ] || { log "기준 파일 없음 — 복원할 것 없음"; return 0; }
  # shellcheck disable=SC1090
  source "$BASELINE"
  log "복원: 실험 설정 제거, 기준 이미지로 재생성"
  on_backend "cd $BACKEND_DIR && rm -f $OVERRIDE && sudo env BACKEND_IMAGE='$BASE_IMAGE_REF' docker compose up -d --no-build backend >/dev/null 2>&1"
  wait_health || log "경고: 복원 후 헬스 UP 확인 실패"
  local has id; has=$(container_env_has_override)
  id=$(on_backend "sudo docker inspect --format '{{.Image}}' $BACKEND_CONTAINER")
  if [ "$has" = "0" ] && [ "$id" = "$BASE_IMAGE_ID" ]; then log "복원 확인: SPRING_APPLICATION_JSON 없음, 이미지 ${id:7:12} 일치"
  else log "경고: 복원 불일치 (override=$has, image=${id:7:12} 기준=${BASE_IMAGE_ID:7:12})"; fi
  metrics_grep '^(hikaricp_connections_max|tomcat_threads_config_max_threads)' >&2
}

rds_credit() {  # 최근 10분의 CPUCreditBalance 마지막 값(5분 주기). 조회 실패면 빈 값
  "$PY" - "$RDS_ID" "$AWS_REGION" <<'PYEOF' 2>/dev/null || true
import sys, datetime as dt, boto3
cw = boto3.client("cloudwatch", region_name=sys.argv[2]); now = dt.datetime.now(dt.timezone.utc)
r = cw.get_metric_statistics(Namespace="AWS/RDS", MetricName="CPUCreditBalance", Statistics=["Average"], Period=300,
    Dimensions=[{"Name": "DBInstanceIdentifier", "Value": sys.argv[1]}], StartTime=now - dt.timedelta(minutes=15), EndTime=now)
pts = sorted(r["Datapoints"], key=lambda p: p["Timestamp"])
print(round(pts[-1]["Average"], 1) if pts else "")
PYEOF
}

# ── 조건 반영 ─────────────────────────────────────────────────────────────
apply_config() {  # $1 pool $2 conn_timeout_ms $3 tomcat_threads
  # shellcheck disable=SC1090
  source "$BASELINE"
  local json
  json=$(printf '{"spring":{"datasource":{"hikari":{"maximum-pool-size":%s,"connection-timeout":%s}}},"server":{"tomcat":{"threads":{"max":%s}}},"management":{"metrics":{"distribution":{"percentiles-histogram":{"hikaricp.connections":true},"minimum-expected-value":{"hikaricp.connections":"100us"}}}}}' "$1" "$2" "$3")
  MODIFIED=1  # 파일을 쓰기 전에 표시해야 중간 실패에도 복원이 돈다
  # JVM_OPTS_EXTRA: 가설 확인용 JVM 시스템 속성(예: -Dcom.zaxxer.hikari.aliveBypassWindowMs=600000). 비우면 넣지 않는다.
  { printf "services:\n  backend:\n    environment:\n      SPRING_APPLICATION_JSON: '%s'\n" "$json"
    [ -n "${JVM_OPTS_EXTRA:-}" ] && printf "      JAVA_TOOL_OPTIONS: '%s'\n" "$JVM_OPTS_EXTRA"; true; } \
    | on_backend "cat > $BACKEND_DIR/$OVERRIDE"
  on_backend "cd $BACKEND_DIR && sudo env BACKEND_IMAGE='$BASE_IMAGE_REF' COMPOSE_FILE=docker-compose.yml:$OVERRIDE \
    docker compose up -d --no-build --force-recreate backend >/dev/null 2>&1"
  wait_health || { log "헬스 UP 실패 (pool=$1)"; return 1; }
  local got; got=$(metrics_grep '^(hikaricp_connections_max|tomcat_threads_config_max_threads)' | awk '{print $2}' | tr '\n' ' ')
  log "반영 확인: hikari max / tomcat max = $got"
}

# ── 명령 ──────────────────────────────────────────────────────────────────
cmd_check() {
  log "백엔드 $(on_backend hostname), 부하 발생기 $(on_loadgen hostname)"
  log "RDS max_connections=$(psql_cmd 'show max_connections'), 현재 연결=$(psql_cmd 'select count(*) from pg_stat_activity')"
  log "실험 설정 흔적(SPRING_APPLICATION_JSON) 수: $(container_env_has_override)"
  metrics_grep '^(hikaricp_connections_max|tomcat_threads_config_max_threads)' >&2
  log "실험 묶음 배송단위: $(psql_cmd "select count(*) from shipment s join orders o on o.id=s.order_id where o.receipt_no like '${FIXTURE_PREFIX}%'")"
}

sync_tools() {
  on_backend "mkdir -p \$HOME/pool-sweep" && scp -q "${SSH_OPTS[@]}" "$HERE"/sweep/*.sql "$SSH_USER@$BACKEND_HOST:pool-sweep/"
  # 풀 크기 대시보드를 모니터링 스택(파일 프로비저닝, 30초 주기)에 올린다
  scp -q "${SSH_OPTS[@]}" "$HERE/monitoring/grafana/dashboards/cjj-pool-sizing.json" "$SSH_USER@$BACKEND_HOST:monitoring/grafana/dashboards/"
  on_loadgen "mkdir -p \$HOME/pool-sweep/k6" && scp -q "${SSH_OPTS[@]}" "$HERE"/k6/*.js "$HERE"/k6/*.json "$SSH_USER@$LOADGEN_HOST:pool-sweep/k6/"
}

cmd_fixture() {
  local n="${1:?주문 수}"
  local key; key=$(demo_key)
  DEMO_KEY="$key" FIXTURE_PREFIX="$FIXTURE_PREFIX" "$PY" "$HERE/sweep/make_fixture.py" \
    --base "http://$BACKEND_HOST:8000" --orders "$n" "${@:2}"
}

run_condition() {  # $1 dir $2 load-spec $3 pool $4 timeout $5 threads $6 rep
  local dir="$1" name vus pacing think after
  IFS=: read -r name vus pacing think after <<< "$2"
  local warm=$WARMUP_S
  if [ "$pacing" -gt 0 ] && [ $((pacing / 1000)) -gt "$warm" ]; then warm=$((pacing / 1000)); fi  # 흩어진 첫 사이클이 다 돈 뒤부터 판독
  local id="${name}-p$3-t$4-th$5-r$6" d="$dir/${name}-p$3-t$4-th$5-r$6"; mkdir -p "$d"
  printf '{"id":"%s","load":"%s","vus":%s,"pacing_ms":%s,"think_ms":%s,"sleep_after_ms":%s,"pool":%s,"conn_timeout_ms":%s,"tomcat_threads":%s,"rep":%s,"warmup_s":%s,"measure_s":%s,"scenario":"%s","client_timeout":"%s","lock_inject":"%s","jvm_opts_extra":"%s"}\n' \
    "$id" "$name" "$vus" "$pacing" "$think" "$after" "$3" "$4" "$5" "$6" "$warm" "$MEASURE_S" "$SCENARIO" "$CLIENT_TIMEOUT" "$LOCK_INJECT" "${JVM_OPTS_EXTRA:-}" > "$d/meta.json"
  log "── 조건 $id"
  local credit; credit=$(rds_credit)
  log "RDS CPU 크레딧 잔고 $credit (기준 $CREDIT_BASE)"; echo "$credit" > "$d/rds-credit-before.txt"
  if [ -n "$CREDIT_BASE" ] && [ -n "$credit" ] && "$PY" -c "import sys; sys.exit(0 if $credit < $CREDIT_BASE * $CREDIT_STOP_RATIO else 1)"; then
    echo "- $(date '+%m-%d %H:%M') \`$id\` 시작 전 중단: RDS CPU 크레딧 $credit < 기준 $CREDIT_BASE × $CREDIT_STOP_RATIO" >> "$OUT_ROOT/progress.md"
    log "크레딧 부족으로 중단"; exit 3
  fi
  apply_config "$3" "$4" "$5"
  if [ "$SCENARIO" = packing ] && [ -n "$LEDGER_CUTOFF_ID" ]; then
    psql_file ledger-reset.sql "--set=prefix=$FIXTURE_PREFIX --set=cutoff=$LEDGER_CUTOFF_ID" > "$d/ledger-reset.log" 2>&1
    log "원장 원복: $(grep -m1 ledger_rows "$d/ledger-reset.log" | tr -s ' ')"
  fi
  if [ "$SCENARIO" = packing ]; then
    psql_file fixture-reset.sql "--set=prefix=$FIXTURE_PREFIX --set=box_stock=$FIXTURE_BOX_STOCK" > "$d/fixture-reset.log" 2>&1
    # 토트 목록은 원복 뒤에 뽑는다. 원복 전에 뽑으면 앞 조건이 포장한 배송단위가 빠져 목록이 짧아진다.
    psql_file fixture-totes.sql "-At --set=prefix=$FIXTURE_PREFIX" \
      | "$PY" -c 'import json,sys; print(json.dumps([{"barcode": l.strip()} for l in sys.stdin if l.strip()]))' > "$STATE_DIR/totes.json"
    log "실험 묶음 토트 $("$PY" -c "import json;print(len(json.load(open('$STATE_DIR/totes.json'))))")개" 2>&1 | tee -a "$d/fixture-reset.log"
    scp -q "${SSH_OPTS[@]}" "$STATE_DIR/totes.json" "$SSH_USER@$LOADGEN_HOST:pool-sweep/totes.json"
  fi
  sleep "$SETTLE_S"
  on_backend "sudo docker rm -f pool-sweep-waits >/dev/null 2>&1; cd $BACKEND_DIR && sudo docker run -d --name pool-sweep-waits --network host --env-file .env -v \$HOME/pool-sweep:/sql:ro $PSQL_IMAGE \
    sh -c 'PGPASSWORD=\$POSTGRES_PASSWORD exec psql -h \$POSTGRES_HOST -U \$POSTGRES_USER -d \$POSTGRES_DB -XAt -F, -f /sql/pg-waits.sql' >/dev/null"
  local lock_pid=""
  if [ -n "$LOCK_INJECT" ]; then
    local at hold; IFS=: read -r at hold <<< "$LOCK_INJECT"
    ( sleep $((warm + at + 2)); psql_file lock-inject.sql "-At --set=hold=$hold" ) > "$d/lock-inject.log" 2>&1 & lock_pid=$!
  fi
  local rdir="pool-sweep/runs/$(basename "$dir")/$id" t0 k6args
  k6args="-e WARMUP_S=$warm -e MEASURE_S=$MEASURE_S -e TIMEOUT=$CLIENT_TIMEOUT"
  if [ -n "$LOCK_INJECT" ]; then  # k6 가 락 구간에 시작한 요청을 따로 센다(psql 기동 지연 2초 포함)
    k6args="$k6args -e LOCK_FROM_S=$((warm + at + 2)) -e LOCK_TO_S=$((warm + at + 2 + hold))"
  fi
  if [ "$SCENARIO" = packing ]; then
    k6args="$k6args -e VUS=$vus -e DURATION=$((warm + MEASURE_S))s -e PACING_MS=$pacing -e THINK_MS=$think -e SLEEP_AFTER_MS=$after -e TOTES_FILE=/home/$SSH_USER/pool-sweep/totes.json"
  else
    k6args="$k6args -e ORDERS=${IMPORT_ORDERS:-100} -e RATE=${IMPORT_RATE:-4} -e DURATION=$((warm + MEASURE_S))s"
  fi
  t0=$(date +%s)
  annotate "start $id" "$((t0 * 1000))"
  set +e
  on_loadgen "read -r DEMO_KEY; export DEMO_KEY; mkdir -p ~/$rdir && cd ~/pool-sweep && echo K6START=\$(date +%s) > ~/$rdir/k6.log && \
    K6_PROMETHEUS_RW_SERVER_URL=http://$BACKEND_PRIVATE:9090/api/v1/write K6_PROMETHEUS_RW_TREND_STATS='p(50),p(95),p(99),max' \
    k6 run --out experimental-prometheus-rw --tag run=$id --summary-export ~/$rdir/summary.json \
      -e BASE=http://$BACKEND_PRIVATE:8000 $k6args k6/$SCENARIO.js >> ~/$rdir/k6.log 2>&1; echo rc=\$?" <<< "$DEMO_KEY_VALUE" > "$d/k6.rc"
  set -e
  local t1; t1=$(date +%s)
  annotate "$id" "$((t0 * 1000))" "$((t1 * 1000))"
  [ -n "$lock_pid" ] && wait "$lock_pid" || true
  on_backend "sudo docker logs pool-sweep-waits 2>/dev/null; sudo docker rm -f pool-sweep-waits >/dev/null 2>&1" > "$d/waits.csv" || true
  scp -q "${SSH_OPTS[@]}" "$SSH_USER@$LOADGEN_HOST:$rdir/summary.json" "$SSH_USER@$LOADGEN_HOST:$rdir/k6.log" "$d/" || log "k6 결과 회수 실패"
  local k6start; k6start=$(grep -m1 '^K6START=' "$d/k6.log" | cut -d= -f2)
  local ws=$((k6start + warm)) we=$((k6start + warm + MEASURE_S))
  sleep 12  # 마지막 스크레이프(5초 주기)가 Prometheus 에 들어올 때까지
  local row; row=$("$PY" "$HERE/sweep/collect.py" --dir "$d" --prom "$PROM_PUBLIC" --start "$ws" --end "$we" --rds-id "$RDS_ID" --region "$AWS_REGION")
  echo "$row" | tee -a "$dir/console.txt"
  printf -- '- %s `%s` %s (%s)\n' "$(date '+%m-%d %H:%M')" "$id" "$row" "$(cat "$d/k6.rc")" >> "$OUT_ROOT/progress.md"
  if [ "$CAPTURE" = 1 ]; then
    "$PY" "$HERE/sweep/capture.py" --url "$GRAFANA_PUBLIC/d/cjj-pool-sizing/?orgId=1&from=$(((ws - 30) * 1000))&to=$(((we + 30) * 1000))" \
      --out "$d/grafana.png" 2>/dev/null || log "캡처 실패(무시)"
  fi
}

cmd_sweep() {
  # SWEEP_DIR 를 주면 그 디렉터리에 조건을 이어 붙인다(긴 스윕을 여러 번 나눠 부를 때 비교표를 하나로)
  local ts dir; ts=$(date +%Y%m%d-%H%M%S); dir="${SWEEP_DIR:-$OUT_ROOT/$ts}"; mkdir -p "$dir"
  MODIFIED=0
  trap 'rc=$?; [ "${MODIFIED:-0}" = 1 ] && restore_backend; exit $rc' EXIT
  trap 'log "중단 신호 — 복원 후 종료"; exit 130' INT TERM
  capture_baseline
  sync_tools
  DEMO_KEY_VALUE=$(demo_key)
  # shellcheck disable=SC1090
  source "$BASELINE"
  printf '{"started":"%s","pool_sizes":"%s","conn_timeouts_ms":"%s","tomcat_threads":"%s","loads":"%s","repeat":%s,"warmup_s":%s,"measure_s":%s,"scenario":"%s","client_timeout":"%s","lock_inject":"%s","image":"%s","rds_max_connections":"%s","portfolio_sha":"%s"}\n' \
    "$ts" "$POOL_SIZES" "$CONN_TIMEOUTS_MS" "$TOMCAT_THREADS" "$LOADS" "$REPEAT" "$WARMUP_S" "$MEASURE_S" "$SCENARIO" \
    "$CLIENT_TIMEOUT" "$LOCK_INJECT" "${BASE_IMAGE_ID:7:12}" "$(psql_cmd 'show max_connections')" "$(git -C "$REPO_ROOT" rev-parse --short HEAD)" > "$dir/sweep-$ts.json"
  echo "- $(date '+%m-%d %H:%M') 스윕 시작 \`$(basename "$dir")\` pools=[$POOL_SIZES] timeouts=[$CONN_TIMEOUTS_MS] threads=[$TOMCAT_THREADS] loads=[$LOADS] repeat=$REPEAT lock=[$LOCK_INJECT]" >> "$OUT_ROOT/progress.md"
  local load pool to th rep
  for rep in $(seq "${REP_START:-1}" $(( ${REP_START:-1} + REPEAT - 1 ))); do
    for load in $LOADS; do for to in $CONN_TIMEOUTS_MS; do for th in $TOMCAT_THREADS; do for pool in $POOL_SIZES; do
      run_condition "$dir" "$load" "$pool" "$to" "$th" "$rep"
    done; done; done; done
  done
  "$PY" "$HERE/sweep/report.py" --dir "$dir" --grafana "$GRAFANA_PUBLIC"
  restore_backend; MODIFIED=0
  echo "- $(date '+%m-%d %H:%M') 스윕 종료 \`$ts\`, 백엔드 기준 설정으로 복원" >> "$OUT_ROOT/progress.md"
  log "결과: $dir/README.md"
}

case "${1:-}" in
  check) cmd_check ;;
  fixture) shift; cmd_fixture "$@" ;;
  sweep) cmd_sweep ;;
  report) "$PY" "$HERE/sweep/report.py" --dir "${2:?디렉터리}" --grafana "$GRAFANA_PUBLIC" ;;
  restore) restore_backend ;;
  *) sed -n '2,11p' "$0"; exit 1 ;;
esac
