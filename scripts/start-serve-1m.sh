#!/usr/bin/env bash
# Qwen3.8 Flash-Next: 1M YaRN context, Q8 QSA KV, MTP, LAN listener.
set -euo pipefail
: "${HIPFIRE_MODEL:?Set HIPFIRE_MODEL to the absolute installed model path}"

export LD_LIBRARY_PATH="${ROCM_LIB_DIR:-/opt/rocm/core-10.1/lib}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export HIPFIRE_YARN_FACTOR=4
export HIPFIRE_PLE_FORMAT=q4
export HIPFIRE_QWEN4_TRUNK_OVERLAY=auto
export HIPFIRE_QWEN4_NPU_TRUNK=auto
export HIPFIRE_DPM_WARMUP_SECS=10

exec "${HIPFIRE_BIN:-$HOME/.hipfire/bin/hipfire}" serve "$HIPFIRE_MODEL" \
  "${BIND_ADDRESS:-0.0.0.0}" "${HIPFIRE_PORT:-11435}" \
  --max-seq 1048576 --kv-mode q8 --spec mtp --continuous-batch-size 1 \
  --idle-timeout 0 --ui "$@"
