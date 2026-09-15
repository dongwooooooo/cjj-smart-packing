#!/bin/bash
cd ~/eval && . venv/bin/activate
while [ ! -f ~/eval/D_DONE ]; do sleep 30; done
for cfg in "d1b --static-method percentile --calib-n 24" "d3b --static-method entropy --exclude-edges --calib-n 24"; do
  set -- $cfg; name=$1; shift
  rm -rf ~/eval/results_$name; mkdir -p ~/eval/results_$name; cp ~/eval/results_b/model.pre.onnx ~/eval/results_b/model.fp16.onnx ~/eval/results_b/model.int8dyn.onnx ~/eval/results_$name/ 2>/dev/null
  python eval_variants.py --vs ~/data/VS --items ~/data/index/items.csv --calib ~/data/TS_calib --model-dir ~/inference --out ~/eval/results_$name --threads 2 --variants int8_static "$@" > ~/eval/run_$name.log 2>&1
done
echo DD_DONE > ~/eval/DD_DONE
