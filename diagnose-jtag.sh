#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=launcher-common.sh
source "$SCRIPT_DIR/launcher-common.sh"

LAUNCHER_CONFIG="${LAUNCHER_CONFIG:-$SCRIPT_DIR/qt-boot-gui.env}"
load_launcher_config "$LAUNCHER_CONFIG"

HW_SERVER_URL="${HW_SERVER_URL:-TCP:127.0.0.1:3121}"
AUTO_START_HW_SERVER="${AUTO_START_HW_SERVER:-1}"
CONTAINER_HOME="${CONTAINER_HOME:-$HOME/.qt-boot-gui-container}"
HW_SERVER_LOG="${HW_SERVER_LOG:-$CONTAINER_HOME/hw_server.log}"

if [[ -z "${VITIS_SETTINGS:-}" ]]; then
    if ! VITIS_SETTINGS="$(discover_vitis_settings)"; then
        echo "FAIL: AMD Vitis 2025.2 settings64.sh was not found." >&2
        echo "Run ./setup-host.sh or set VITIS_SETTINGS." >&2
        exit 1
    fi
fi
if [[ ! -r "$VITIS_SETTINGS" ]]; then
    echo "FAIL: Vitis settings script is not readable: $VITIS_SETTINGS" >&2
    exit 1
fi

XILINX_ROOT="${XILINX_ROOT:-$(discover_xilinx_root "$VITIS_SETTINGS")}"
mkdir -p "$CONTAINER_HOME"

endpoint="${HW_SERVER_URL#TCP:}"
endpoint="${endpoint#tcp:}"
host="${endpoint%:*}"
port="${endpoint##*:}"
if [[ -z "$host" || -z "$port" || "$host" == "$port" ]]; then
    echo "FAIL: Expected HW_SERVER_URL in TCP:host:port form, got: $HW_SERVER_URL" >&2
    exit 1
fi

echo "========== JTAG HOST DIAGNOSTIC =========="
echo "Vitis settings : $VITIS_SETTINGS"
echo "hw_server URL  : $HW_SERVER_URL"
echo "hw_server log  : $HW_SERVER_LOG"
echo

# shellcheck disable=SC1090
set +u
source "$VITIS_SETTINGS"
set -u
hash -r

for tool in hw_server xsdb; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "FAIL: $tool was not found after sourcing Vitis." >&2
        exit 1
    fi
    printf '%-15s %s\n' "$tool" "$(command -v "$tool")"
done
echo

hw_server_ready() {
    timeout 2 bash -c 'exec 3<>/dev/tcp/"$1"/"$2"' _ "$host" "$port" 2>/dev/null
}

started_hw_server_pid=""
cleanup() {
    if [[ -z "$started_hw_server_pid" ]]; then
        return
    fi
    local process_group="$started_hw_server_pid"
    started_hw_server_pid=""
    echo "Stopping diagnostic hw_server (process group $process_group)"
    kill -TERM -- "-$process_group" 2>/dev/null || true
    wait "$process_group" 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 130' INT TERM

if hw_server_ready; then
    echo "Using existing hw_server at $HW_SERVER_URL"
elif [[ "$AUTO_START_HW_SERVER" == "1" && ( "$host" == "127.0.0.1" || "$host" == "localhost" ) ]]; then
    if ! command -v setsid >/dev/null 2>&1; then
        echo "FAIL: setsid is required to start hw_server automatically." >&2
        exit 1
    fi

    echo "Starting a temporary host hw_server..."
    setsid hw_server >"$HW_SERVER_LOG" 2>&1 &
    started_hw_server_pid=$!
    for _ in {1..50}; do
        if hw_server_ready; then
            break
        fi
        if ! kill -0 "$started_hw_server_pid" 2>/dev/null; then
            break
        fi
        sleep 0.2
    done
else
    echo "FAIL: Nothing is accepting TCP connections at $host:$port." >&2
    echo "AUTO_START_HW_SERVER=$AUTO_START_HW_SERVER" >&2
    exit 2
fi

if ! hw_server_ready; then
    echo "FAIL: hw_server did not become ready at $host:$port." >&2
    tail -n 30 "$HW_SERVER_LOG" >&2 || true
    exit 2
fi

echo
echo "Host hw_server processes:"
pgrep -af '[h]w_server' || true
echo
if command -v ss >/dev/null 2>&1; then
    echo "Port $port listeners:"
    ss -ltnp "sport = :$port" 2>/dev/null || true
    echo
fi
echo "PASS: TCP connection to $host:$port succeeded."
echo

if ! HW_SERVER_URL="$HW_SERVER_URL" xsdb "$SCRIPT_DIR/diagnose-jtag.tcl"; then
    echo >&2
    echo "JTAG target enumeration failed." >&2
    if ! cable_udev_rules_present; then
        echo "No Xilinx/Digilent cable udev rules were detected." >&2
        if installer="$(find_cable_driver_installer "$XILINX_ROOT")"; then
            echo "Install the AMD cable rules with:" >&2
            echo "  sudo '$installer'" >&2
        fi
    fi
    if command -v lsusb >/dev/null 2>&1; then
        echo "Possible JTAG USB devices:" >&2
        lsusb | grep -Ei 'Xilinx|Digilent|Future Technology Devices|FTDI' >&2 || echo "  none" >&2
    fi
    echo "Inspect the server log: $HW_SERVER_LOG" >&2
    exit 3
fi
