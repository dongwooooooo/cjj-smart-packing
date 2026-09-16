#!/bin/bash
# 백엔드 EC2 에서 실행. 드라이브의 검증셋(VS shot1 cam1~3 + index/items.csv)을 로컬을 거치지 않고
# S3 평가 버킷으로 복사한다. S3 인증은 인스턴스 프로파일(EvalDataWrite), 드라이브는 토큰 파일.
#
# 준비(내 PC): rclone authorize "drive" '{"scope":"drive.readonly"}'  → 출력된 토큰 JSON 을 파일로 저장
#             scp -i key.pem <토큰파일> ubuntu@<ec2-ip>:~/gd-token.json
# 실행(EC2):   bash drive_to_s3.sh ~/gd-token.json [접두사=vs2024]
set -euo pipefail
TOKEN_FILE="$1"; PREFIX="${2:-vs2024}"
BUCKET="cjj-eval-data-300390308149"
ROOT_ID="1L1wmJ9gYfBV0mGmmnWiu_JJfwFCvWc6e"   # 데이터셋 루트 폴더
command -v rclone >/dev/null || curl -fsSL https://rclone.org/install.sh | sudo bash
mkdir -p ~/.config/rclone; umask 077
cat > ~/.config/rclone/rclone.conf <<CONF
[gd]
type = drive
scope = drive.readonly
root_folder_id = ${ROOT_ID}
token = $(cat "$TOKEN_FILE")

[s3]
type = s3
provider = AWS
env_auth = true
region = ap-northeast-2
CONF
# 공용 client_id 라 드라이브 API 쿼터가 낮다. tps 4 를 넘기면 403 rateLimitExceeded 가 난다(2026-09-15 실측).
COMMON=(--fast-list --tpslimit 4 --transfers 8 --checkers 8 --stats 60s --stats-one-line)
rclone copy gd:index/items.csv "s3:${BUCKET}/${PREFIX}/index/" "${COMMON[@]}"
rclone copy gd:VS "s3:${BUCKET}/${PREFIX}/VS" --include "*_1_[123].jpg" "${COMMON[@]}"
echo "VS jpg in S3: $(rclone size "s3:${BUCKET}/${PREFIX}/VS" --json | python3 -c 'import sys,json;print(json.load(sys.stdin)["count"])')"
rm -f "$TOKEN_FILE"; sed -i '/^\[gd\]/,/^$/d' ~/.config/rclone/rclone.conf
echo "드라이브 토큰 삭제 완료. 이제 저장소 변수 EVAL_PREFIX=${PREFIX} 로 바꾸면 게이트가 이 셋을 쓴다."
