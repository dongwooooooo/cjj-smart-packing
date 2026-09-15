#!/bin/bash
cd ~/eval
while [ ! -f ~/eval/DD_DONE ]; do sleep 30; done
python3 -m venv venv_ov && . venv_ov/bin/activate && pip -q install --upgrade pip && pip -q install onnxruntime-openvino numpy pillow > ~/eval/ov_install.log 2>&1
mkdir -p ~/eval/results_ov
python eval_openvino.py 500 > ~/eval/run_ov.log 2>&1
echo OV_DONE > ~/eval/OV_DONE
