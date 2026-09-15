#!/bin/bash
set -uo pipefail
mkdir -p ~/data/VS ~/data/TS_calib
rclone copy gd:VS ~/data/VS --include "*_1_[123].jpg" --fast-list --tpslimit 4 --tpslimit-burst 8 --transfers 8 --checkers 8 --retries 10 --low-level-retries 20 --drive-chunk-size 64M --stats 60s --stats-one-line -v 2>&1 | grep --line-buffered -v client_id
rclone copy "gd:TS/01_입고물품/01_가공식품" ~/data/TS_calib --include "*_1_[123].jpg" --fast-list --tpslimit 4 --tpslimit-burst 8 --transfers 8 --checkers 8 --retries 10 --low-level-retries 20 --stats 60s --stats-one-line -v 2>&1 | grep --line-buffered -v client_id
echo "COPY_DONE VS=$(find ~/data/VS -name '*.jpg' | wc -l) TS=$(find ~/data/TS_calib -name '*.jpg' | wc -l)"
