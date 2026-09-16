#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=launcher-common.sh
source "$SCRIPT_DIR/launcher-common.sh"

LAUNCHER_CONFIG="${LAUNCHER_CONFIG:-$SCRIPT_DIR/qt-boot-gui.env}"
PULL_IMAGE=0

usage() {
    cat <<'EOF'
Usage: ./setup-host.sh [--pull]

Initializes the host workspace and persistent launcher configuration, then
checks Docker, Vitis, TFTP, X11, and JTAG cable support. It does not install
packages or make privileged system changes.

  --pull    Pull the published container image after the checks
EOF
}

while (( $# > 0 )); do
    case "$1" in
        --pull)
            PULL_IMAGE=1
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
    shift
done

load_launcher_config "$LAUNCHER_CONFIG"
WORKSPACE="${WORKSPACE:-$HOME/versal-lab-data}"
TFTP_ROOT="${TFTP_ROOT:-/srv/tftp}"
CONTAINER_HOME="${CONTAINER_HOME:-$HOME/.qt-boot-gui-container}"
AUTO_START_HW_SERVER="${AUTO_START_HW_SERVER:-1}"
HW_SERVER_URL="${HW_SERVER_URL:-TCP:127.0.0.1:3121}"
ALLOW_IMAGE_PULL="${ALLOW_IMAGE_PULL:-1}"

failures=0
warnings=0
pass() { printf 'PASS: %s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*"; warnings=$((warnings + 1)); }
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

echo "========== VERSAL BOOT GUI HOST SETUP =========="

if [[ -z "${VITIS_SETTINGS:-}" ]]; then
    if VITIS_SETTINGS="$(discover_vitis_settings)"; then
        pass "Discovered Vitis settings: $VITIS_SETTINGS"
    else
        fail "AMD Vitis 2025.2 was not found in a common installation path."
        echo "      Set VITIS_SETTINGS and rerun this script."
        VITIS_SETTINGS=""
    fi
elif [[ -r "$VITIS_SETTINGS" ]]; then
    pass "Vitis settings are readable: $VITIS_SETTINGS"
else
    fail "Vitis settings are not readable: $VITIS_SETTINGS"
fi

XILINX_ROOT="${XILINX_ROOT:-}"
if [[ -n "$VITIS_SETTINGS" && -r "$VITIS_SETTINGS" ]]; then
    if [[ -z "$XILINX_ROOT" || "$VITIS_SETTINGS" != "$XILINX_ROOT"/* ]]; then
        XILINX_ROOT="$(discover_xilinx_root "$VITIS_SETTINGS")"
    fi
    pass "AMD installation root: $XILINX_ROOT"

    missing_vitis_tools=()
    for tool in bootgen xsdb program_flash hw_server; do
        if ! bash -c 'source "$1" >/dev/null 2>&1 && command -v "$2" >/dev/null 2>&1' _ "$VITIS_SETTINGS" "$tool"; then
            missing_vitis_tools+=("$tool")
        fi
    done
    if (( ${#missing_vitis_tools[@]} == 0 )); then
        pass "Vitis provides bootgen, xsdb, program_flash, and hw_server."
    else
        fail "Vitis tools are missing: ${missing_vitis_tools[*]}"
    fi
fi

mkdir -p "$WORKSPACE" "$CONTAINER_HOME"
seed_workspace_configs "$SCRIPT_DIR" "$WORKSPACE"
pass "Workspace initialized: $WORKSPACE"

if [[ ! -e "$LAUNCHER_CONFIG" ]]; then
    {
        printf '# Machine-local Versal Boot GUI settings.\n'
        printf '# Explicit shell variables override these values.\n\n'
        if [[ -n "$VITIS_SETTINGS" ]]; then
            printf 'VITIS_SETTINGS=%s\n' "$VITIS_SETTINGS"
        fi
        printf 'WORKSPACE=%s\n' "$WORKSPACE"
        printf 'TFTP_ROOT=%s\n' "$TFTP_ROOT"
        printf 'AUTO_START_HW_SERVER=%s\n' "$AUTO_START_HW_SERVER"
        printf 'HW_SERVER_URL=%s\n' "$HW_SERVER_URL"
        printf 'ALLOW_IMAGE_PULL=%s\n' "$ALLOW_IMAGE_PULL"
        printf 'QT_BOOT_GUI_JTAG_CONFIG=/work/configs/jtag_config.json\n'
        printf 'QT_BOOT_GUI_QSPI_CONFIG=/work/configs/qspi_config.json\n'
    } > "$LAUNCHER_CONFIG"
    pass "Created persistent launcher config: $LAUNCHER_CONFIG"
else
    pass "Using existing launcher config: $LAUNCHER_CONFIG"
fi

echo
echo "========== DOCKER =========="
if ! command -v docker >/dev/null 2>&1; then
    fail "Docker is not installed."
elif ! docker info >/dev/null 2>&1; then
    fail "Docker is installed, but $(id -un) cannot access the daemon."
    echo "      Start Docker and add this user to the docker group, then log in again."
else
    pass "Docker daemon is accessible."
    if docker image inspect "$QT_BOOT_GUI_LOCAL_IMAGE" >/dev/null 2>&1; then
        pass "Local development image is available: $QT_BOOT_GUI_LOCAL_IMAGE"
    elif docker image inspect "$QT_BOOT_GUI_PUBLISHED_IMAGE" >/dev/null 2>&1; then
        pass "Published image is available: $QT_BOOT_GUI_PUBLISHED_IMAGE"
    elif [[ "$PULL_IMAGE" == "1" ]]; then
        echo "Pulling $QT_BOOT_GUI_PUBLISHED_IMAGE"
        if docker pull "$QT_BOOT_GUI_PUBLISHED_IMAGE"; then
            pass "Published image downloaded."
        else
            fail "Could not pull the published image."
        fi
    else
        warn "No GUI image is local; run ./setup-host.sh --pull or let the launcher pull it."
    fi
fi

echo
echo "========== TFTP =========="
if [[ ! -d "$TFTP_ROOT" ]]; then
    fail "TFTP root does not exist: $TFTP_ROOT"
    echo "      sudo mkdir -p '$TFTP_ROOT'"
    echo "      sudo chown -R '$(id -un):$(id -gn)' '$TFTP_ROOT'"
elif [[ ! -w "$TFTP_ROOT" ]]; then
    fail "TFTP root is not writable by $(id -un): $TFTP_ROOT"
    echo "      sudo chown -R '$(id -un):$(id -gn)' '$TFTP_ROOT'"
else
    pass "TFTP root is writable: $TFTP_ROOT"
fi

if command -v systemctl >/dev/null 2>&1; then
    if systemctl is-active --quiet tftpd-hpa 2>/dev/null; then
        pass "tftpd-hpa is active."
    else
        warn "tftpd-hpa is not active; TFTP/NFS and QSPI staging will not reach the board."
    fi
fi
if [[ -r /etc/default/tftpd-hpa ]]; then
    configured_tftp_root="$(sed -n 's/^[[:space:]]*TFTP_DIRECTORY=["'\'']\([^"'\'']*\)["'\''][[:space:]]*$/\1/p' /etc/default/tftpd-hpa | tail -n 1)"
    if [[ -n "$configured_tftp_root" && "$configured_tftp_root" != "$TFTP_ROOT" ]]; then
        warn "tftpd-hpa serves $configured_tftp_root, but the GUI mounts $TFTP_ROOT."
    elif [[ -n "$configured_tftp_root" ]]; then
        pass "tftpd-hpa serves the configured GUI TFTP root."
    fi
fi
if command -v ss >/dev/null 2>&1; then
    if ss -lun 2>/dev/null | grep -Eq '(^|[[:space:]])[^[:space:]]*:69[[:space:]]'; then
        pass "A UDP listener is available on TFTP port 69."
    else
        warn "No UDP listener was detected on TFTP port 69."
    fi
fi

echo
echo "========== DESKTOP =========="
if [[ -n "${DISPLAY:-}" ]]; then
    pass "DISPLAY is set to $DISPLAY"
else
    warn "DISPLAY is not set in this shell; check-only works, but the GUI cannot open."
fi
if xauth_file="$(find_xauthority)"; then
    pass "X11 authorization is readable: $xauth_file"
elif command -v xhost >/dev/null 2>&1; then
    warn "No readable Xauthority file was found; the launcher will try temporary xhost access."
else
    fail "Neither a readable Xauthority file nor xhost is available."
fi

echo
echo "========== JTAG CABLE SUPPORT =========="
if cable_udev_rules_present; then
    pass "AMD/Xilinx or Digilent cable udev rules are installed."
else
    warn "No AMD/Xilinx or Digilent cable udev rules were detected."
    if [[ -n "${XILINX_ROOT:-}" ]] && installer="$(find_cable_driver_installer "$XILINX_ROOT")"; then
        echo "      Install them with: sudo '$installer'"
        echo "      Then reload udev rules and reconnect the JTAG cable."
    else
        echo "      Run the cable-driver installer included with Vivado/Vitis."
    fi
fi

if command -v lsusb >/dev/null 2>&1; then
    usb_matches="$(lsusb | grep -Ei 'Xilinx|Digilent|Future Technology Devices|FTDI' || true)"
    if [[ -n "$usb_matches" ]]; then
        pass "A possible JTAG USB interface is connected:"
        printf '%s\n' "$usb_matches" | sed 's/^/      /'
    else
        warn "No common Xilinx, Digilent, or FTDI JTAG USB interface is currently visible."
    fi
else
    warn "lsusb is unavailable; install usbutils to inspect the JTAG cable."
fi

echo
echo "========== SUMMARY =========="
printf 'Workspace : %s (mounted as /work)\n' "$WORKSPACE"
printf 'Configs   : %s/configs\n' "$WORKSPACE"
printf 'Output    : %s/output\n' "$WORKSPACE"
printf 'TFTP root : %s (mounted as /srv/tftp)\n' "$TFTP_ROOT"
printf 'Config    : %s\n' "$LAUNCHER_CONFIG"
printf 'Failures  : %d\nWarnings  : %d\n' "$failures" "$warnings"

if (( failures > 0 )); then
    echo
    echo "Resolve the FAIL items, then rerun ./setup-host.sh."
    exit 1
fi

echo
echo "Host setup is ready for the container runtime check:"
echo "  QT_BOOT_GUI_CHECK_ONLY=1 ./run-container.sh"
echo "Then connect the board and run:"
echo "  ./diagnose-jtag.sh"
echo "  ./run-container.sh"
