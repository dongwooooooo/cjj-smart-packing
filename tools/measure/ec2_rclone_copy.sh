#!/bin/bash
# EC2에서 실행. 드라이브 → 로컬 디스크. 토큰은 ~/.config/rclone/rclone.conf 에만 둔다.
# 사용: bash ec2_rclone_copy.sh <token-json-one-line>
set -euo pipefail
TOKEN="$(cat "$1")"
ROOT_ID="1L1wmJ9gYfBV0mGmmnWiu_JJfwFCvWc6e"   # 데이터셋 루트 폴더
mkdir -p ~/.config/rclone
umask 077
cat > ~/.config/rclone/rclone.conf <<EOF
[gd]
type = drive
scope = drive.readonly
root_folder_id = ${ROOT_ID}
token = ${TOKEN}
EOF
mkdir -p ~/data/VS ~/data/TS_calib ~/data/index
# 1) 정답 CSV
rclone copy gd:index/items.csv ~/data/index/ --drive-chunk-size 64M
# 2) VS: shot1 cam1~3 만 (파일명 {KAN}_{barcode}_1_{cam}.jpg)
rclone copy gd:VS ~/data/VS --include "*_1_[123].jpg" --transfers 16 --checkers 32 --tpslimit 10 --drive-chunk-size 64M --stats 30s --stats-one-line
# 3) 보정용 TS 일부: 가공식품 대분류의 입고물품만, shot1 cam1~3 (수백 품목)
rclone copy "gd:TS/01_입고물품/01_가공식품" ~/data/TS_calib --include "*_1_[123].jpg" --transfers 16 --checkers 32 --tpslimit 10 --stats 30s --stats-one-line
echo "VS jpg: $(find ~/data/VS -name '*.jpg' | wc -l)  TS_calib jpg: $(find ~/data/TS_calib -name '*.jpg' | wc -l)  items.csv: $(wc -l < ~/data/index/items.csv) lines"
