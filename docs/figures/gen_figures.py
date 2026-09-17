"""포트폴리오 그림 4장을 SVG로 생성한다. 실행: python3 gen_figures.py"""
FONT = "font-family='Apple SD Gothic Neo, Noto Sans KR, Helvetica, Arial, sans-serif'"
C = {"box":"#F4F6F8","edge":"#4A5568","accent":"#2B6CB0","accent_bg":"#EBF4FF","warn":"#C05621","warn_bg":"#FFF5EB","ok":"#2F855A","ok_bg":"#F0FFF4","text":"#1A202C","muted":"#718096"}

def esc(s): return s.replace("&","&amp;").replace("<","&lt;").replace(">","&gt;")

def box(x,y,w,h,title,lines=(),kind="box",r=8):
    fill={"box":C["box"],"accent":C["accent_bg"],"warn":C["warn_bg"],"ok":C["ok_bg"]}[kind]
    stroke={"box":C["edge"],"accent":C["accent"],"warn":C["warn"],"ok":C["ok"]}[kind]
    o=[f"<rect x='{x}' y='{y}' width='{w}' height='{h}' rx='{r}' fill='{fill}' stroke='{stroke}' stroke-width='1.5'/>"]
    cy=y+24
    o.append(f"<text x='{x+w/2}' y='{cy}' text-anchor='middle' font-size='15' font-weight='600' fill='{C['text']}' {FONT}>{esc(title)}</text>")
    for ln in lines:
        cy+=19
        o.append(f"<text x='{x+w/2}' y='{cy}' text-anchor='middle' font-size='12.5' fill='{C['muted']}' {FONT}>{esc(ln)}</text>")
    return "\n".join(o)

def arrow(x1,y1,x2,y2,label="",dashed=False,color=None):
    color=color or C["edge"]; d=" stroke-dasharray='6 5'" if dashed else ""
    o=[f"<line x1='{x1}' y1='{y1}' x2='{x2}' y2='{y2}' stroke='{color}' stroke-width='1.6' marker-end='url(#ah)'{d}/>"]
    if label:
        mx,my=(x1+x2)/2,(y1+y2)/2-8
        o.append(f"<text x='{mx}' y='{my}' text-anchor='middle' font-size='11.5' fill='{color}' {FONT}>{esc(label)}</text>")
    return "\n".join(o)

def path_arrow(pts,label="",dashed=False,color=None,lx=None,ly=None):
    color=color or C["edge"]; d=" stroke-dasharray='6 5'" if dashed else ""
    dstr="M "+" L ".join(f"{x} {y}" for x,y in pts)
    o=[f"<path d='{dstr}' fill='none' stroke='{color}' stroke-width='1.6' marker-end='url(#ah)'{d}/>"]
    if label:
        o.append(f"<text x='{lx}' y='{ly}' text-anchor='middle' font-size='11.5' fill='{color}' {FONT}>{esc(label)}</text>")
    return "\n".join(o)

def label(x,y,s,size=13,color=None,anchor="start",weight="500"):
    return f"<text x='{x}' y='{y}' text-anchor='{anchor}' font-size='{size}' font-weight='{weight}' fill='{color or C['text']}' {FONT}>{esc(s)}</text>"

def group(x,y,w,h,title):
    return (f"<rect x='{x}' y='{y}' width='{w}' height='{h}' rx='10' fill='none' stroke='{C['muted']}' stroke-width='1' stroke-dasharray='4 4'/>"
            + label(x+12,y+18,title,12,C["muted"],weight="600"))

def svg(w,h,body,caption):
    return f"""<svg xmlns='http://www.w3.org/2000/svg' width='{w}' height='{h}' viewBox='0 0 {w} {h}'>
<defs><marker id='ah' markerWidth='10' markerHeight='10' refX='9' refY='5' orient='auto' markerUnits='userSpaceOnUse'><path d='M0,0 L10,5 L0,10 z' fill='{C['edge']}'/></marker></defs>
<rect width='{w}' height='{h}' fill='white'/>
{body}
{label(w/2,h-14,caption,12,C['muted'],anchor='middle')}
</svg>"""

# ---------- 그림 1. 시스템 아키텍처 ----------
b=[]
b.append(box(40,110,150,90,"작업자",["입고 등록 / 출고 포장","바코드·토트 스캔"]))
b.append(box(250,100,190,110,"프론트엔드",["Next.js 16 (Vercel)","route handler 프록시","백엔드 키 서버측 부착"]))
b.append(box(510,90,230,130,"API 서버",["Spring Boot 4.1 · EC2 (compose)","입고·출고·주문·재고 API","출고지시 배치 엔진","편성 · 박스 추천 · 요금 계산"]))
b.append(box(820,40,200,90,"PostgreSQL 18 (RDS)",["Flyway 스키마 이력","상품 치수·무게 마스터"]))
b.append(box(820,160,200,100,"S3",["촬영 사진 (커밋 후 비동기 업로드)","30분 임시 주소 조회"]))
b.append(box(1090,90,270,130,"추론 Lambda 컨테이너",["FastAPI + ONNX Runtime","EfficientNet-B3 3뷰 회귀 (13.3M)","사진 3장 → 가로·세로·높이","VS 2,024 MAE 2.06 / 2.17 / 1.62cm"],kind="accent"))
b.append(arrow(190,155,250,155))
b.append(arrow(440,155,510,155,"HTTPS"))
b.append(arrow(740,120,820,90,"JDBC"))
b.append(arrow(740,190,820,205,"put (비동기)"))
b.append(arrow(740,150,1090,150,"SDK Invoke · 인스턴스 프로파일 (공개 URL 없음)",color=C["accent"]))
# 모델 승격 파이프라인
b.append(group(40,320,1320,170,"모델 승격 파이프라인 (ai 저장소)"))
b.append(box(60,355,190,110,"Hugging Face",["비공개 저장소","safetensors (AI 담당 업로드)"]))
b.append(box(300,355,230,110,"2단계 Docker 빌드",["변환: safetensors → ONNX","torch 대조 max diff ≤ 1e-4","런타임: model.onnx + config만"]))
b.append(box(580,355,150,110,"ECR",["이미지 저장"]))
b.append(box(780,355,260,110,"고정셋 평가 게이트",["VS 2,024품목 × 3장, 서빙 전처리","비열화 + 절대 상한 판정","하네스 구현 · 연결은 미결"],kind="warn"))
b.append(box(1090,355,250,110,"Lambda 배포",["버전 발행","live 별칭 이동"],kind="accent"))
b.append(arrow(250,410,300,410)); b.append(arrow(530,410,580,410)); b.append(arrow(730,410,780,410,"",dashed=True)); b.append(arrow(1040,410,1090,410,"통과 시",dashed=True))
b.append(path_arrow([(1215,355),(1215,290),(1225,290),(1225,220)],label="",dashed=False))
# CI/CD
b.append(group(40,520,1320,150,"CI/CD (GitHub Actions, OIDC로 AWS 역할 위임)"))
b.append(box(60,555,230,90,"backend 트랙",["이미지 빌드 → ECR push","SSM Run Command로 EC2 교체"]))
b.append(box(340,555,230,90,"헬스 확인 · 롤백",["/health 실패 시 이전 이미지 복귀"]))
b.append(box(640,555,230,90,"ai 트랙",["이미지 빌드 → ECR push","Lambda 코드 갱신 → live 별칭"]))
b.append(box(940,555,400,90,"명세 (docs 저장소)",["MVP · API 계약 · ERD · 결정 이력 D-01~D-25","코드와 어긋나면 문서를 먼저 고침"]))
b.append(arrow(290,600,340,600))
b.append(label(40,40,"그림 1. 시스템 아키텍처",18,weight="700"))
b.append(label(40,64,"작업자 요청 경로(위), 모델 승격 파이프라인(중간), 배포 트랙(아래). 점선은 게이트가 파이프라인에 아직 연결되지 않은 구간.",12.5,C["muted"]))
open("fig1-architecture.svg","w").write(svg(1400,720,"\n".join(b),"cjj-smart-packing · 2026-09"))

# ---------- 그림 2. 출고지시 배치 처리 흐름 ----------
b=[]
b.append(label(40,40,"그림 2. 출고지시 배치 처리 흐름",18,weight="700"))
b.append(label(40,64,"배치 1건이 한 트랜잭션으로 처리된다. 거부 주문 제외는 트랜잭션 안의 분기이며 부분 커밋이 아니다.",12.5,C["muted"]))
xs=[40,290,540,790,1040]; y=110; w=210; h=150
b.append(box(xs[0],y,w,h,"접수 · 검증",["요청 결함: 배치 전체 400","주문별 거부 목록:","미등록 지역 · 재고 부족","초과 치수 · 초과 무게","재전송 멱등: 주문번호 UNIQUE"]))
b.append(box(xs[1],y,w,h,"블록화",["유효 내치수 = 내치수 − 마진 3cm","파손주의: 완충재 두께 × 2 가산","상품 무게 합산 (입고 시 저장값)","적층불가 SKU는 단독 단위"]))
b.append(box(xs[2],y,w,h,"배치 엔진",["extreme point 후보점","축 평행 6방향 시도","판정 = 실제 배치 구성","무효 추천 없음"],kind="accent"))
b.append(box(xs[3],y,w,h,"편성 최적화",["① 주문 전체 박스 1개 시도","② FFD 초기해 (부피 내림차순)","③ 국소 탐색: 이동 · 분리","목적함수: 총 배송비 → 박스 수 → 부피"],kind="accent"))
b.append(box(xs[4],y,w,h,"라인 · 토트 · 저장",["지역별 라인 배정","토트 할당","배송 단위 · 추천 박스 저장","예상 총무게 기록"]))
for i in range(4): b.append(arrow(xs[i]+w,y+h/2,xs[i+1],y+h/2))
b.append(box(790,310,210,110,"요금 구간표 (기준정보)",["세 변 합 80/100/120/140/160cm","무게 2/5/10/15/20kg","높은 쪽 구간으로 요금 결정"],kind="warn"))
b.append(arrow(895,310,895,260))
b.append(box(540,310,210,110,"하드 제약",["세 변 합 160cm · 최장변 100cm","총무게 20kg (택배 접수 한도)","낱개 초과 시 OVERWEIGHT_ITEM"],kind="warn"))
b.append(arrow(645,310,645,260))
b.append(box(1040,310,210,110,"출고 무게 검수 (포장 완료)",["실측 무게 입력","허용 오차 max(0.1kg, 3%)","벗어나면 WEIGHT_MISMATCH"],kind="ok"))
b.append(arrow(1145,260,1145,310,"",dashed=True))
b.append(label(40,470,"확장성 실측: 주문 100 / 1,000 / 5,000건에서 주문당 p50 1.8 / 2.4 / 2.3ms, p95 12.8 / 12.9 / 13.8ms (단일 스레드, 순수 로직).",12.5,C["muted"]))
open("fig2-batch-flow.svg","w").write(svg(1300,510,"\n".join(b),"cjj-smart-packing · backend Cartonizer · 2026-09"))

# ---------- 그림 3. 모델 승격 파이프라인 ----------
b=[]
b.append(label(40,40,"그림 4. 모델 승격 파이프라인과 정확도 게이트",18,weight="700"))
b.append(label(40,64,"변환 게이트는 변환의 정확성만 검사한다. 정확도 게이트는 모델 자체를 고정 프로토콜로 평가해 승격 여부를 판정한다. 점선 구간은 파이프라인 연결 미결.",12.5,C["muted"]))
y=110; h=150
b.append(box(40,y,180,h,"Hugging Face",["safetensors","AI 담당 업로드"]))
b.append(box(270,y,230,h,"변환 게이트 (빌드 시)",["safetensors → ONNX","torch 출력 대조","max diff > 1e-4 → 빌드 실패","런타임 이미지: onnx + config"]))
b.append(box(550,y,260,h,"고정셋 평가",["VS 2,024품목 × shot1 cam1~3","정답: items.csv 실측","전처리: 서빙 코드 dimension.py","x86 ONNX Runtime CPU"],kind="accent"))
b.append(box(860,y,260,h,"정확도 판정",["비열화: 축별 MAE 악화 ≤ 0.2cm","          3축 ±3cm 하락 ≤ 2%p","절대 상한: 축별 MAE ≤ 3cm","속도는 기록만 (판정 제외)"],kind="accent"))
b.append(box(1170,y,190,h,"Lambda live 승격",["버전 발행","별칭 이동","EC2 백엔드가 Invoke"],kind="ok"))
b.append(arrow(220,185,270,185)); b.append(arrow(500,185,550,185,"",dashed=True)); b.append(arrow(810,185,860,185)); b.append(arrow(1120,185,1170,185,"통과",dashed=True))
# 결과 표
ty=310
b.append(label(40,ty,"2026-09-15 평가 결과 (기준선 FP32: MAE 2.06 / 2.17 / 1.62cm, 3축 ±3cm 62.5%, p50 243ms)",13,weight="600"))
rows=[("FP16","2.06 / 2.17 / 1.62","62.5%","243ms","통과 · 속도 이득 없음","ok"),
      ("INT8 정적 PTQ (MinMax, 보정 100)","3.57 / 3.24 / 2.89","22.6%","164ms","차단 · ±3cm 기준 위반","warn"),
      ("INT8 정적 PTQ (첫 conv·헤드 FP32)","3.71 / 3.42 / 2.66","20.5%","167ms","차단","warn"),
      ("INT8 동적","11.45 / 8.22 / 7.72","6.7%","1,828ms","차단","warn"),
      ("FP32 OpenVINO EP","현행과 동일","61.2%","244ms","통과 · 속도 이득 없음","ok")]
cols=[40,420,700,860,1000]; hdr=["변형","MAE L/W/H (cm)","3축 ±3cm","p50","판정"]
yy=ty+28
for c,hh in zip(cols,hdr): b.append(label(c,yy,hh,12.5,C["muted"],weight="600"))
b.append(f"<line x1='40' y1='{yy+8}' x2='1360' y2='{yy+8}' stroke='{C['muted']}' stroke-width='1'/>")
for r in rows:
    yy+=26
    col=C["ok"] if r[5]=="ok" else C["warn"]
    for i,c in enumerate(cols):
        b.append(label(c,yy,r[i],12.5,col if i==4 else C["text"],weight="600" if i==4 else "400"))
b.append(label(40,yy+40,"판정 기준을 두 단계로 둔 효과: INT8 정적은 MAE 악화가 1.5cm에 그치지만 ±3cm 안에 드는 비율이 62.5%에서 22.6%로 떨어져 차단된다.",12.5,C["muted"]))
open("fig4-model-promotion.svg","w").write(svg(1400,560,"\n".join(b),"cjj-smart-packing · ai/eval · 2026-09"))

# ---------- 그림 4. 촬영 1회 시간 분해 ----------
b=[]
b.append(label(40,40,"그림 3. 촬영 1회의 응답 시간 분해와 저장 구간 변경 효과",18,weight="700"))
b.append(label(40,64,"핸들러 시간은 CloudWatch 웜 호출 246건(2026-08-26~31) 정본. 백엔드 구간은 로컬 RIE·MinIO 실측(사진 490KB, 11상품 × 5회). SLO는 p95 1초.",12.5,C["muted"]))
scale=1.0  # px per ms
x0=260; y=110
def bar(y,name,val,color,note=""):
    o=[label(x0-12,y+17,name,13,anchor="end"),
       f"<rect x='{x0}' y='{y}' width='{val*scale}' height='24' fill='{color}' rx='3'/>",
       label(x0+val*scale+8,y+17,f"{val}ms"+(f"  ·  {note}" if note else ""),12.5,C["muted"])]
    return "\n".join(o)
b.append(bar(y,"Lambda 핸들러 p50",325,C["accent"])); y+=34
b.append(bar(y,"Lambda 핸들러 p95",609,C["accent"])); y+=34
b.append(bar(y,"Lambda 핸들러 p99",652,C["accent"])); y+=50
b.append(bar(y,"백엔드 경로 p95 (변경 전)",243,C["edge"],"저장 구간 36ms 포함")); y+=34
b.append(bar(y,"백엔드 경로 p95 (변경 후)",192,C["ok"],"저장 구간 12ms, 업로드는 응답 밖 32ms")); y+=50
b.append(bar(y,"운영 E2E p95 추정",609+192,C["warn"])); y+=40
# SLO line
sx=x0+1000*scale
b.append(f"<line x1='{sx}' y1='100' x2='{sx}' y2='{y}' stroke='{C['warn']}' stroke-width='1.5' stroke-dasharray='6 5'/>")
b.append(label(sx,92,"SLO p95 1,000ms",12,C["warn"],anchor="middle",weight="600"))
b.append(label(40,y+30,"저장 구간: 세션 커밋과 사진 3장 동기 업로드를 한 트랜잭션에서 처리하던 것을, 사진 키만 저장해 커밋한 뒤 AFTER_COMMIT 이벤트로 비동기 업로드하도록 바꿨다. 저장 구간 p95 36ms에서 12ms. 운영 E2E 추정은 핸들러 p95와 백엔드 p95의 합이다.",12.5,C["muted"]))
open("fig3-latency-breakdown.svg","w").write(svg(1400,y+80,"\n".join(b),"cjj-smart-packing · docs/evidence/measurement · 2026-09"))
print("ok")
