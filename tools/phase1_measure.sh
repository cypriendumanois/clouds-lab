#!/usr/bin/env bash
# Phase 1 Task 8: one measure.py run with all three URLs (after ~15 min idle).
# Run from the repo root in Cloud Shell:   bash tools/phase1_measure.sh
set -euo pipefail
source ~/phase1_urls.env
source .venv/bin/activate
pip install -q -r requirements.txt -r phase-1-echo-bot/requirements.txt
python phase-1-echo-bot/measure.py --vm "$VM_URL" --cloudrun "$RUN_URL" --function "$FN_URL"
python -m pytest phase-1-echo-bot/tests -p autograder.points -q 2>&1 | tail -20
