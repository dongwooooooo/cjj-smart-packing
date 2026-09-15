"""E2E 촬영 응답 시간 측정 — 백엔드(compose) + 추론 컨테이너(RIE) 로컬 구성.
사용: python measure_e2e.py <profile-name> [rounds] [threads]
결과: 클라이언트 왕복 분포 + 백엔드 로그의 구간별 분포를 표로 찍고 JSON 저장."""
import json, sys, time, re, subprocess, statistics, urllib.request, urllib.error
from concurrent.futures import ThreadPoolExecutor
BASE="http://localhost:8010"; SP="/private/tmp/claude-501/-Users-idong-u-cjj/0c3bfd62-e675-4c27-b46c-cdcc7811107e/scratchpad"
COMPOSE=["docker","compose","-p","cjj-measure","-f","docker-compose.yml","-f","docker-compose.override.yml","-f",f"{SP}/docker-compose.measure.yml"]
profile=sys.argv[1]; rounds=int(sys.argv[2]) if len(sys.argv)>2 else 5; threads=int(sys.argv[3]) if len(sys.argv)>3 else 1

def call(method,path,body=None):
    data=json.dumps(body).encode() if body is not None else None
    req=urllib.request.Request(BASE+path,data=data,method=method,headers={"Content-Type":"application/json"})
    t=time.perf_counter()
    try:
        with urllib.request.urlopen(req,timeout=60) as r: out=json.loads(r.read() or b"{}"); code=r.status
    except urllib.error.HTTPError as e: out=json.loads(e.read() or b"{}"); code=e.code
    return code,out,(time.perf_counter()-t)*1000

def pct(v,p):
    v=sorted(v); k=(len(v)-1)*p/100; f=int(k); c=min(f+1,len(v)-1); return v[f]+(v[c]-v[f])*(k-f)
def row(name,v): return f"{name:14s} n={len(v):4d} p50={pct(v,50):7.0f} p95={pct(v,95):7.0f} p99={pct(v,99):7.0f} max={max(v):7.0f} ms"

# 1) 리셋 (상품 적재 + 워밍)
code,out,ms=call("POST","/api/v1/admin/demo/reset"); print(f"reset -> {code} ({ms:.0f}ms)", str(out)[:200])
# 2) 상품 id
prods=json.load(open("/Users/idong-u/cjj/backend/demo/data/products.json")); ids=[]
for p in prods:
    code,out,_=call("POST","/api/v1/inbound/scans",{"barcode":p["gtin"]})
    prod=out.get("product") or {}; pid=prod.get("productId") or prod.get("id")
    if pid: ids.append(pid)
    else: print("scan no product:",p["gtin"],code,str(out)[:120])
print("products:",len(ids))
# 3) 측정 반복
mark=f"MEASURE-START {profile} {time.time()}"; subprocess.run(COMPOSE+["exec","-T","backend","sh","-c",f"echo '{mark}' >/dev/null"],cwd="/Users/idong-u/cjj/backend",capture_output=True)
t_start=time.time(); results=[]
def one(pid):
    code,out,ms=call("POST","/api/v1/inbound/measurements",{"productId":pid}); return dict(pid=pid,code=code,status=out.get("status"),ms=ms)
jobs=[pid for _ in range(rounds) for pid in ids]
with ThreadPoolExecutor(max_workers=threads) as ex:
    for r in ex.map(one,jobs): results.append(r)
elapsed=time.time()-t_start
client=[r["ms"] for r in results if r["code"]==200]; statuses={}
for r in results: statuses[f"{r['code']}/{r['status']}"]=statuses.get(f"{r['code']}/{r['status']}",0)+1
print(f"\n== profile={profile} rounds={rounds} threads={threads} requests={len(results)} wall={elapsed:.1f}s statuses={statuses}")
print(row("client e2e",client))
# 4) 백엔드 로그 구간 파싱 (최근 N줄만: 이번 실행분)
_r=subprocess.run(["docker","logs","--since",f"{int(elapsed)+20}s","cjj-measure-backend-1"],capture_output=True,text=True); logs=_r.stdout+_r.stderr
stages={k:[] for k in ["loadMs","inferMs","saveMs","totalMs","uploadMs","buildMs","invokeMs","parseMs","elapsed_ms"]}; jpeg=[]; ev=[]
for line in logs.splitlines():
    for k in stages:
        m=re.search(rf"\b{k}=(\d+)",line)
        if m and ("timing" in line or k=="elapsed_ms"): stages[k].append(int(m.group(1)))
    m=re.search(r"jpegBytes=(\d+) eventBytes=(\d+)",line)
    if m: jpeg.append(int(m.group(1))); ev.append(int(m.group(2)))
print("-- backend stages (from logs)")
for k,v in stages.items():
    if v: print(row(k,v))
if stages["invokeMs"] and stages["elapsed_ms"]:
    n=min(len(stages["invokeMs"]),len(stages["elapsed_ms"])); over=[a-b for a,b in zip(stages["invokeMs"][-n:],stages["elapsed_ms"][-n:])]
    print(row("invoke-overhead",over), "(invokeMs - handler elapsed_ms: 전송·RIE·Mangum 비용)")
if jpeg: print(f"payload: jpeg 3장 avg {statistics.mean(jpeg)/1024:.0f}KB -> event JSON avg {statistics.mean(ev)/1024:.0f}KB (base64 팽창 {statistics.mean(ev)/statistics.mean(jpeg):.2f}x)")
json.dump(dict(profile=profile,rounds=rounds,threads=threads,results=results,stages=stages,jpeg=jpeg,event=ev),open(f"{SP}/measure-{profile}-t{threads}.json","w"))
print("saved",f"{SP}/measure-{profile}-t{threads}.json")
