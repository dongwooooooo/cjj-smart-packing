# 문제 1 작성 메모

본문은 `portfolio-docs-insert.md`의 문제 1로 옮겼다(Docs 에 옮기지 않음).

## 작성 메모 (Docs 에 옮기지 않음)

- 근거: `docs/evidence/benchmark/weight-objective-comparison.md`(개선 전·후 비교, backend `test/weight-objective-comparison` b0f5ac1), `docs/evidence/benchmark/bench2.log`(편성 시간), `backend/docs/decisions-weight.md`.
- 결론 표의 "치수만 판정"은 초기 구현 중간본 617fc5f 편성(박스 개수 → 부피, 치수만 봄)이다. 3D 배치 판정은 두 쪽이 같고, 다른 것은 편성 기준과 무게 반영이다.
- 주문·상품은 합성 데이터다. 시연 CJ 식품 11종 치수 ±20%, 무게 = 원 상품 밀도 × 부피. 1~3품목 주문에서는 개선 전에도 20kg 을 넘지 않았다(최대 15.7kg).
- 운임은 결론에 넣지 않았다. 전·후 운임 차이(−1.7%)는 무게가 아니라 탐색 범위 확장에서 나왔고, 요금표도 파스토 2024 인용이라 CJ 공식 요금과 대조하지 못했다.
- 편성 시간은 개발 PC(Apple M2 Pro) 측정이다.
- 이전 판(3D 배치 알고리즘 상세, 계약 대조, 테스트 수, NPE 결함)은 git 이력 962e49d 이전 커밋에 있다.
