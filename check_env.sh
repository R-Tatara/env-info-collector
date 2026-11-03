#!/usr/bin/env bash
# ==============================================================================
# check_env.sh
# Generic environment information collector (for AI input)
# Usage: bash check_env.sh              # print to stdout only
#        bash check_env.sh [DIR]        # also save to DIR/env_info_YYYYmmdd_HHMMSS.txt
#                                       # (DIR defaults to current directory)
# ==============================================================================

# No `set -e`: a failing probe must not abort the remaining sections.
set -uo pipefail

CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

info() { echo -e "  ${CYAN}[INFO]${RESET}  $*"; }
section() { echo -e "\n${BOLD}━━━ $* ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"; }

main() {
# ==============================================================================
section "OS / Kernel / BIOS"

if [ -f /etc/os-release ]; then
    . /etc/os-release
    info "Distribution : ${PRETTY_NAME:-unknown}"
    info "Release      : ${VERSION:-${VERSION_ID:-unknown}}"
else
    info "/etc/os-release not found"
fi
command -v lsb_release &>/dev/null && info "lsb_release  : $(lsb_release -ds 2>/dev/null || echo unknown)"

info "Kernel       : $(uname -r)"
info "Architecture : $(uname -m)"

DMI=/sys/class/dmi/id
if [ -d "$DMI" ]; then
    for f in sys_vendor product_name bios_vendor bios_version bios_date; do
        info "DMI ${f} : $(cat "$DMI/$f" 2>/dev/null || echo 'n/a')"
    done
else
    info "DMI information not available"
fi

# ==============================================================================
section "CPU / Memory"

CPU_MODEL=$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | xargs || echo "unknown")
CPU_CORES=$(nproc 2>/dev/null || echo "?")
info "CPU : ${CPU_MODEL} (${CPU_CORES} cores)"

MEM_TOTAL_KB=$(awk '/MemTotal/ {print $2}' /proc/meminfo 2>/dev/null)
MEM_TOTAL_GB=$(( ${MEM_TOTAL_KB:-0} / 1024 / 1024 ))
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

    DRIVER_CUDA=$(nvidia-smi 2>/dev/null | grep -oP 'CUDA Version: \K[0-9]+\.[0-9]+' | head -n1 || true)
    info "CUDA supported by driver (nvidia-smi) : ${DRIVER_CUDA:-unknown}"

    GPU_COUNT=$(nvidia-smi --list-gpus 2>/dev/null | wc -l)
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
    CUDA_VER=$(nvcc --version 2>/dev/null | grep -oP 'release \K[0-9]+\.[0-9]+' || true)
    info "CUDA Toolkit installed (nvcc) : ${CUDA_VER:-unknown}"
else
    info "CUDA Toolkit (nvcc) not found in PATH"
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
section "Network"

info "Hostname : $(hostname 2>/dev/null || uname -n)"
if command -v ip &>/dev/null; then
    info "Interfaces / IP addresses:"
    ip -brief addr 2>/dev/null | while read -r line; do info "  $line"; done
    DEF_ROUTE=$(ip route show default 2>/dev/null | head -n1)
    info "Default route : ${DEF_ROUTE:-none}"
else
    info "ip command not found"
    info "IP addresses : $(hostname -I 2>/dev/null || echo unknown)"
fi
DNS_SERVERS=$(grep -E '^nameserver' /etc/resolv.conf 2>/dev/null | awk '{print $2}' | xargs)
info "DNS (resolv.conf) : ${DNS_SERVERS:-unknown}"
if command -v resolvectl &>/dev/null; then
    UPSTREAM_DNS=$(resolvectl dns 2>/dev/null | sed 's/^/    /' || true)
    [ -n "$UPSTREAM_DNS" ] && { info "DNS (resolvectl):"; echo "$UPSTREAM_DNS"; }
fi

# ==============================================================================
section "Python / uv"

SYS_PYTHON=$(python3 --version 2>&1 || echo "none")
info "System Python : ${SYS_PYTHON}"

if command -v uv &>/dev/null; then
    info "uv : $(uv --version 2>/dev/null || echo unknown)"
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
    RS_USB=$(lsusb 2>/dev/null | grep -i "intel" | grep -iE "realsense|8086:0[ab][0-9a-f]{2}" || true)
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
}

SAVE_DIR="${1:-}"
if [ -n "$SAVE_DIR" ]; then
    mkdir -p "$SAVE_DIR" || { echo "Cannot create $SAVE_DIR" >&2; exit 1; }
    OUT_FILE="${SAVE_DIR%/}/env_info_$(date +%Y%m%d_%H%M%S).txt"
    main 2>&1 | tee >(sed -u 's/\x1b\[[0-9;]*m//g' > "$OUT_FILE")
    sleep 0.2
    echo "Saved to: ${OUT_FILE}"
else
    main
fi
