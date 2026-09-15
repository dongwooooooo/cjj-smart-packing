#!/bin/bash
cd ~/eval && . venv/bin/activate
for cfg in "d1 --static-method percentile" "d2 --static-method minmax --exclude-edges --reduce-range" "d3 --static-method entropy --exclude-edges"; do
  set -- $cfg; name=$1; shift
  rm -rf ~/eval/results_$name; mkdir -p ~/eval/results_$name; cp ~/eval/results_b/model.pre.onnx ~/eval/results_b/model.fp16.onnx ~/eval/results_b/model.int8dyn.onnx ~/eval/results_$name/ 2>/dev/null
  python eval_variants.py --vs ~/data/VS --items ~/data/index/items.csv --calib ~/data/TS_calib --calib-n 100 --model-dir ~/inference --out ~/eval/results_$name --threads 2 --variants int8_static "$@" > ~/eval/run_$name.log 2>&1
done
echo D_DONE > ~/eval/D_DONE
