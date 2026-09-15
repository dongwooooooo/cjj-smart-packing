# 편성 확장성 벤치마크 원본

| 파일 | 실행 시각 | 용도 |
| --- | --- | --- |
| `bench2.log` | 2026-09-14 23:36 | 정본. 설계 문서·포트폴리오가 인용하는 수치(5,000주문 21.0초, p95 13.8ms, 최대 96.6ms, 상위 10건 표). 국소 탐색 결함을 찾은 실행 |
| `bench.log` | 2026-09-14 (첫 실행) | 결함 수정 전 실행. NPE로 중단된 기록 |
| `cartonization-benchmark-rerun-2338.md` | 2026-09-14 23:38 | 수정 확인용 재실행. 같은 입력이지만 JIT·부하 차이로 총 20.0초, p95 13.1ms, 최대 54.1ms. 문서에는 인용하지 않는다 |

재현: `cd backend && ./gradlew benchmark` → `build/reports/cartonization-benchmark.md`.
