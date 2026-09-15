"""OpenVINO EP(Intel CPU)로 FP32 모델 지연·정확도 측정 — 정확도는 CPU EP 와 동일해야 한다(연산 동일, 실행기만 교체)."""
import sys, os, json, time, re, csv, numpy as np, onnxruntime as ort
sys.path.insert(0, os.path.expanduser("~/inference")); from dimension import OnnxDimensionModel
sys.path.insert(0, os.path.expanduser("~/eval")); from eval_variants import find_items, load_gt, pct
vs=os.path.expanduser("~/data/VS"); items=find_items(vs); gt=load_gt(os.path.expanduser("~/data/index/items.csv"))
keys=sorted(k for k in items if k in gt); limit=int(sys.argv[1]) if len(sys.argv)>1 else 0
if limit: keys=keys[:limit]
base=OnnxDimensionModel(os.path.expanduser("~/inference"), threads=2); views=["1-1","1-2","1-3"]
tm=np.array(base.cfg["tgt_mean"]); ts=np.array(base.cfg["tgt_std"])
print("providers:", ort.get_available_providers(), flush=True)
out={}
for name, prov in [("cpu_ep",[("CPUExecutionProvider",{})]), ("openvino_cpu",[("OpenVINOExecutionProvider",{"device_type":"CPU","num_of_threads":2})])]:
    try:
        so=ort.SessionOptions(); so.intra_op_num_threads=2
        s=ort.InferenceSession(os.path.expanduser("~/inference/model.onnx"), so, providers=prov)
    except Exception as e: print(name,"session error:",e); continue
    errs=[]; lat=[]
    for i,k in enumerate(keys):
        x,m,_=base._batch(items[k],views); x=x.astype(np.float32); m=m.astype(np.float32)
        t=time.perf_counter(); y=s.run(None,{"images":x,"mask":m})[0][0]; lat.append((time.perf_counter()-t)*1000)
        pred=y*ts+tm; errs.append(np.abs(pred-np.array(gt[k])))
        if i%200==0: print(f"  {name}: {i}/{len(keys)}", flush=True)
    E=np.array(errs); lat=lat[3:]
    out[name]=dict(n=len(keys), mae=[float(v) for v in E.mean(axis=0)], within3=float((E<=3).all(axis=1).mean()), p50=pct(lat,50), p95=pct(lat,95))
    print(f"[{name}] MAE={out[name]['mae']} ±3cm={out[name]['within3']*100:.1f}% p50={out[name]['p50']:.0f} p95={out[name]['p95']:.0f}ms", flush=True)
json.dump(out, open(os.path.expanduser("~/eval/results_ov/summary.json"),"w"), indent=1); print("saved")
