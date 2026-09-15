#!/bin/bash
# 원격 저장소 3개 생성 → 푸시 → 상위에서 서브모듈로 묶기. 자동 모드에서는 `gh repo create` 가 막히므로 직접 실행한다.
# 사용: bash tools/publish.sh <github-user> [prefix]   예) bash tools/publish.sh dongwooooooo cjj-smart-packing
set -euo pipefail
USER="${1:?github user}"; PREFIX="${2:-cjj-smart-packing}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
for sub in backend ai; do
  ( cd "$ROOT/$sub"
    gh repo create "$USER/$PREFIX-$sub" --public --source=. --remote=origin --push )
done
cd "$ROOT"
# 하위 디렉터리를 서브모듈로 전환: 디렉터리는 그대로 두고 .gitmodules 만 등록한다
git rm -q --cached -r backend ai 2>/dev/null || true
sed -i '' '/^backend\/$/d; /^ai\/$/d' .gitignore
git submodule add "https://github.com/$USER/$PREFIX-backend.git" backend
git submodule add "https://github.com/$USER/$PREFIX-ai.git" ai
git add .gitmodules .gitignore backend ai
git commit -m "chore: backend·ai 를 서브모듈로 등록"
gh repo create "$USER/$PREFIX" --public --source=. --remote=origin --push
echo "done: https://github.com/$USER/$PREFIX"
