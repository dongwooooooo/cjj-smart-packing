#!/bin/bash
cd ~/eval && . venv/bin/activate
while [ ! -f ~/eval/ALL_DONE ]; do sleep 30; done
rm -rf ~/eval/results_b2; mkdir -p ~/eval/results_b2; cp ~/eval/results_b/model.pre.onnx ~/eval/results_b/model.fp16.onnx ~/eval/results_b/model.int8dyn.onnx ~/eval/results_b2/ 2>/dev/null
python eval_variants.py --vs ~/data/VS --items ~/data/index/items.csv --calib ~/data/TS_calib --calib-n 100 --model-dir ~/inference --out ~/eval/results_b2 --threads 2 --variants int8_static > ~/eval/run_b2.log 2>&1
echo B2_DONE > ~/eval/B2_DONE
