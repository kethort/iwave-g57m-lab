#!/usr/bin/env bash
set -euo pipefail

VITIS_SETTINGS="${VITIS_SETTINGS:-/development/2025.2/Vitis/settings64.sh}"
HW_SERVER_URL="${HW_SERVER_URL:-TCP:127.0.0.1:3121}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -r "$VITIS_SETTINGS" ]]; then
    echo "FAIL: Vitis settings script is not readable: $VITIS_SETTINGS" >&2
    exit 1
fi

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
echo

# shellcheck disable=SC1090
source "$VITIS_SETTINGS"
hash -r

for tool in hw_server xsdb; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "FAIL: $tool was not found after sourcing Vitis." >&2
        exit 1
    fi
    printf '%-15s %s\n' "$tool" "$(command -v "$tool")"
done
echo

echo "Host hw_server processes:"
pgrep -af '[h]w_server' || echo "  none"
echo

echo "Port $port listeners:"
ss -ltnp "sport = :$port" 2>/dev/null || true
echo

if ! timeout 2 bash -c 'exec 3<>/dev/tcp/"$1"/"$2"' _ "$host" "$port" 2>/dev/null; then
    echo "FAIL: Nothing is accepting TCP connections at $host:$port." >&2
    echo >&2
    echo "Start this in a separate host terminal and leave it running:" >&2
    echo "  source '$VITIS_SETTINGS'" >&2
    echo "  hw_server" >&2
    exit 2
fi

echo "PASS: TCP connection to $host:$port succeeded."
echo
HW_SERVER_URL="$HW_SERVER_URL" xsdb "$SCRIPT_DIR/diagnose-jtag.tcl"
