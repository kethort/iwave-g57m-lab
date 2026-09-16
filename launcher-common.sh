#!/usr/bin/env bash

QT_BOOT_GUI_LOCAL_IMAGE="qt-boot-gui:2025.2"
QT_BOOT_GUI_PUBLISHED_IMAGE="ghcr.io/kethort/iwave-g57m-lab:latest"

trim_value() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
}

launcher_key_supported() {
    case "$1" in
        IMAGE_NAME|VITIS_SETTINGS|XILINX_ROOT|WORKSPACE|TFTP_ROOT|CONTAINER_HOME|\
        AUTO_START_HW_SERVER|HW_SERVER_URL|HW_SERVER_LOG|ALLOW_IMAGE_PULL|\
        XAUTHORITY|XILINXD_LICENSE_FILE|LM_LICENSE_FILE|QT_BOOT_GUI_JTAG_CONFIG|\
        QT_BOOT_GUI_QSPI_CONFIG)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

load_launcher_config() {
    local config_file="$1"
    local line key value
    local home_braced='${HOME}'
    local home_plain='$HOME'

    [[ -r "$config_file" ]] || return 0

    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        line="$(trim_value "$line")"
        [[ -z "$line" || "$line" == \#* ]] && continue
        [[ "$line" == *=* ]] || continue

        key="$(trim_value "${line%%=*}")"
        value="$(trim_value "${line#*=}")"
        launcher_key_supported "$key" || continue

        if [[ "$value" == \"*\" && "$value" == *\" ]]; then
            value="${value:1:${#value}-2}"
        elif [[ "$value" == \'*\' && "$value" == *\' ]]; then
            value="${value:1:${#value}-2}"
        fi

        if [[ "$value" == "$home_braced"* ]]; then
            value="$HOME${value:${#home_braced}}"
        elif [[ "$value" == "$home_plain"* ]]; then
            value="$HOME${value:${#home_plain}}"
        elif [[ "$value" == ~/* ]]; then
            value="$HOME/${value:2}"
        fi

        # Explicit shell variables take precedence over machine-local defaults.
        if [[ ! -v "$key" ]]; then
            printf -v "$key" '%s' "$value"
            export "$key"
        fi
    done < "$config_file"
}

discover_vitis_settings() {
    local candidate
    local -a candidates=()

    if [[ -n "${XILINX_ROOT:-}" ]]; then
        candidates+=(
            "$XILINX_ROOT/Vitis/2025.2/settings64.sh"
            "$XILINX_ROOT/2025.2/Vitis/settings64.sh"
            "$XILINX_ROOT/Vitis/settings64.sh"
        )
    fi

    candidates+=(
        "/opt/amd/2025.2/Vitis/settings64.sh"
        "/opt/Xilinx/Vitis/2025.2/settings64.sh"
        "/tools/Xilinx/2025.2/Vitis/settings64.sh"
        "/tools/Xilinx/Vitis/2025.2/settings64.sh"
        "/development/2025.2/Vitis/settings64.sh"
    )

    for candidate in "${candidates[@]}"; do
        if [[ -r "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}

discover_xilinx_root() {
    local settings="$1"
    local candidate
    candidate="$(dirname -- "$settings")"

    while [[ "$candidate" != "/" ]]; do
        if [[ -d "$candidate/Vitis" && -d "$candidate/Vivado" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
        candidate="$(dirname -- "$candidate")"
    done

    # This supports Vitis-only installations while still mounting settings64.sh.
    dirname -- "$(dirname -- "$settings")"
}

seed_workspace_configs() {
    local script_dir="$1"
    local workspace="$2"
    local config_name

    mkdir -p "$workspace/configs" "$workspace/output"
    for config_name in jtag_config.json qspi_config.json; do
        if [[ ! -e "$workspace/configs/$config_name" ]]; then
            cp "$script_dir/$config_name" "$workspace/configs/$config_name"
            echo "Created editable startup config: $workspace/configs/$config_name"
        fi
    done
}

find_xauthority() {
    local candidate
    local -a candidates=(
        "${XAUTHORITY:-}"
        "$HOME/.Xauthority"
        "${XDG_RUNTIME_DIR:-}/gdm/Xauthority"
        "/run/user/$(id -u)/gdm/Xauthority"
    )

    for candidate in "${candidates[@]}"; do
        if [[ -n "$candidate" && -r "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}

find_cable_driver_installer() {
    local xilinx_root="$1"
    local candidate
    local -a candidates=(
        "$xilinx_root/Vivado/data/xicom/cable_drivers/lin64/install_script/install_drivers/install_drivers"
        "$xilinx_root/Vitis/data/xicom/cable_drivers/lin64/install_script/install_drivers/install_drivers"
    )

    for candidate in "${candidates[@]}"; do
        if [[ -x "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}

cable_udev_rules_present() {
    compgen -G '/etc/udev/rules.d/*xilinx*' >/dev/null ||
        compgen -G '/etc/udev/rules.d/*digilent*' >/dev/null ||
        compgen -G '/usr/lib/udev/rules.d/*xilinx*' >/dev/null ||
        compgen -G '/usr/lib/udev/rules.d/*digilent*' >/dev/null
}
