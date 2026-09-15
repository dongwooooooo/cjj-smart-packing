#!/bin/bash
cd ~/eval && . venv/bin/activate
while [ ! -f ~/eval/results_a/summary.json ]; do sleep 30; done
python eval_variants.py --vs ~/data/VS --items ~/data/index/items.csv --calib ~/data/TS_calib --calib-n 200 --model-dir ~/inference --out ~/eval/results_b --threads 2 --variants int8_static > ~/eval/run_b.log 2>&1
cp ~/eval/results_b/model.*.onnx ~/eval/results_c/ 2>/dev/null; mkdir -p ~/eval/results_c; cp ~/eval/results_b/model.pre.onnx ~/eval/results_b/model.int8dyn.onnx ~/eval/results_c/ 2>/dev/null
python eval_variants.py --vs ~/data/VS --items ~/data/index/items.csv --model-dir ~/inference --out ~/eval/results_c --threads 2 --variants int8_dynamic --limit 300 > ~/eval/run_c.log 2>&1
echo ALL_DONE > ~/eval/ALL_DONE
