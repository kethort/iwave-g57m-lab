#!/usr/bin/env bash
set -eo pipefail

VITIS_SETTINGS="${VITIS_SETTINGS:-/tools/Xilinx/Vitis/2025.2/settings64.sh}"

select_startup_config() {
    local configured_path="$1"
    local bundled_path="$2"
    local label="$3"

    if [[ -n "$configured_path" && -r "$configured_path" ]]; then
        printf '%s\n' "$configured_path"
        return
    fi
    if [[ -n "$configured_path" ]]; then
        echo "Ignoring unreadable $label config override: $configured_path" >&2
    fi
    printf '%s\n' "$bundled_path"
}

QT_BOOT_GUI_JTAG_CONFIG="$(select_startup_config "${QT_BOOT_GUI_JTAG_CONFIG:-}" "/opt/qt-boot-gui/configs/jtag_config.json" "JTAG")"
QT_BOOT_GUI_QSPI_CONFIG="$(select_startup_config "${QT_BOOT_GUI_QSPI_CONFIG:-}" "/opt/qt-boot-gui/configs/qspi_config.json" "QSPI")"
export QT_BOOT_GUI_JTAG_CONFIG QT_BOOT_GUI_QSPI_CONFIG

if [[ ! -r "$VITIS_SETTINGS" ]]; then
    echo "Vitis settings script not found: $VITIS_SETTINGS" >&2
    echo "Mount Vitis 2025.2 and set VITIS_SETTINGS correctly." >&2
    exit 1
fi

# AMD tools populate PATH and required runtime environment here.
source "$VITIS_SETTINGS"

for config in "$QT_BOOT_GUI_JTAG_CONFIG" "$QT_BOOT_GUI_QSPI_CONFIG"; do
    if [[ ! -r "$config" ]]; then
        echo "Required startup configuration is not readable: $config" >&2
        exit 1
    fi
done

missing_tools=()
for tool in bootgen xsdb program_flash mkimage mkenvimage; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        missing_tools+=("$tool")
    fi
done

if (( ${#missing_tools[@]} > 0 )); then
    echo "Required tools not found after sourcing Vitis: ${missing_tools[*]}" >&2
    echo "bootgen, xsdb, and program_flash must come from Vitis 2025.2; mkimage and mkenvimage come from u-boot-tools." >&2
    exit 1
fi

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/runtime-$(id -u)}"
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

if [[ "${QT_BOOT_GUI_CHECK_ONLY:-0}" == "1" ]]; then
    echo "Container runtime check passed."
    echo "Vitis settings: $VITIS_SETTINGS"
    echo "JTAG config:    $QT_BOOT_GUI_JTAG_CONFIG"
    echo "QSPI config:    $QT_BOOT_GUI_QSPI_CONFIG"
    for tool in bootgen xsdb program_flash mkimage mkenvimage; do
        printf '  %-14s %s\n' "$tool" "$(command -v "$tool")"
    done
    exit 0
fi

echo "Auto-loading JTAG config: $QT_BOOT_GUI_JTAG_CONFIG"
echo "Auto-loading QSPI config: $QT_BOOT_GUI_QSPI_CONFIG"
exec /opt/qt-boot-gui/qt_boot_gui "$@"
