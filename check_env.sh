#!/usr/bin/env bash
# ==============================================================================
# check_env.sh
# Generic environment information collector (for AI input)
# Usage: bash check_env.sh
# ==============================================================================

set -euo pipefail

CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

info() { echo -e "  ${CYAN}[INFO]${RESET}  $*"; }
section() { echo -e "\n${BOLD}━━━ $* ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"; }

# ==============================================================================
section "OS / Kernel"

if [ -f /etc/os-release ]; then
    . /etc/os-release
    info "Distribution : ${PRETTY_NAME}"
else
    info "/etc/os-release not found"
fi

info "Kernel       : $(uname -r)"
info "Architecture : $(uname -m)"

# ==============================================================================
section "CPU / Memory"

CPU_MODEL=$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | xargs || echo "unknown")
CPU_CORES=$(nproc)
info "CPU : ${CPU_MODEL} (${CPU_CORES} cores)"

MEM_TOTAL_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
MEM_TOTAL_GB=$(( MEM_TOTAL_KB / 1024 / 1024 ))
info "RAM total : ${MEM_TOTAL_GB} GB"

# ==============================================================================
section "NVIDIA GPU / CUDA"

if command -v nvidia-smi &>/dev/null; then
    info "nvidia-smi found"
    echo ""
    nvidia-smi --query-gpu=name,driver_version,memory.total,compute_cap \
               --format=csv,noheader 2>/dev/null | while IFS=',' read -r name driver mem cap; do
        info "GPU name    : $(echo "$name" | xargs)"
        info "Driver ver  : $(echo "$driver" | xargs)"
        info "VRAM        : $(echo "$mem" | xargs)"
        info "Compute Cap : $(echo "$cap" | xargs)"
    done
    echo ""

    GPU_COUNT=$(nvidia-smi --list-gpus | wc -l)
    info "GPU count : ${GPU_COUNT}"

    # Compute Capability expressed as sm_XX (e.g. 12.0 -> sm_120, 9.0 -> sm_90)
    # Relevant because a given torch/CUDA build only ships kernels for certain sm_XX targets.
    nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | while read -r cap; do
        SM=$(echo "$cap" | xargs | tr -d '.')
        info "Compute Capability sm equivalent : sm_${SM}"
    done
else
    info "nvidia-smi not found (no NVIDIA GPU or driver not installed)"
fi

if command -v nvcc &>/dev/null; then
    CUDA_VER=$(nvcc --version | grep -oP 'release \K[0-9]+\.[0-9]+' || echo "unknown")
    info "CUDA (nvcc) : ${CUDA_VER}"
else
    info "nvcc not found in PATH"
fi

if python3 -c "import torch" &>/dev/null; then
    python3 - <<'EOF'
import torch
print(f"  [INFO]  torch version : {torch.__version__}")
print(f"  [INFO]  torch built with CUDA : {torch.version.cuda}")
print(f"  [INFO]  torch CUDA available : {torch.cuda.is_available()}")
try:
    print(f"  [INFO]  torch supported arch list (sm) : {torch.cuda.get_arch_list()}")
except Exception:
    pass
EOF
fi

# ==============================================================================
section "Python / uv"

SYS_PYTHON=$(python3 --version 2>/dev/null || echo "none")
info "System Python : ${SYS_PYTHON}"

if command -v uv &>/dev/null; then
    info "uv : $(uv --version)"
else
    info "uv not found in PATH"
fi

# ==============================================================================
section "RealSense"

if command -v rs-enumerate-devices &>/dev/null; then
    info "librealsense tools found (rs-enumerate-devices)"
    RS_OUT=$(rs-enumerate-devices --short 2>/dev/null || echo "")
    if [ -n "$RS_OUT" ]; then
        echo "$RS_OUT" | while read -r line; do
            info "  $line"
        done
    else
        info "  No RealSense device enumerated"
    fi
else
    info "librealsense tools not found (rs-enumerate-devices missing)"
fi

if command -v lsusb &>/dev/null; then
    RS_USB=$(lsusb | grep -i "intel" | grep -iE "realsense|8086:0[ab][0-9a-f]{2}" || true)
    if [ -n "$RS_USB" ]; then
        info "USB device(s) matching Intel RealSense:"
        echo "$RS_USB" | while read -r line; do
            info "  $line"
        done
    else
        info "No Intel RealSense USB device detected via lsusb"
    fi
fi

if python3 -c "import pyrealsense2" &>/dev/null; then
    info "pyrealsense2 importable from system python3"
fi
