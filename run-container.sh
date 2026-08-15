#!/usr/bin/env bash
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-qt-boot-gui:2025.2}"

discover_xilinx_root() {
    local candidate
    candidate="$(dirname -- "$VITIS_SETTINGS")"

    while [[ "$candidate" != "/" ]]; do
        if [[ -d "$candidate/Vitis" && -d "$candidate/Vivado" ]]; then
            printf '%s\n' "$candidate"
            return
        fi
        candidate="$(dirname -- "$candidate")"
    done

    # Fall back to the parent of the Vitis directory for nonstandard installs.
    dirname -- "$(dirname -- "$VITIS_SETTINGS")"
}

if [[ -z "${VITIS_SETTINGS:-}" ]]; then
    XILINX_ROOT="${XILINX_ROOT:-/tools/Xilinx}"
    VITIS_SETTINGS="$XILINX_ROOT/Vitis/2025.2/settings64.sh"
else
    if [[ -z "${XILINX_ROOT:-}" || "$VITIS_SETTINGS" != "$XILINX_ROOT"/* ]]; then
        if [[ -n "${XILINX_ROOT:-}" ]]; then
            echo "Ignoring XILINX_ROOT=$XILINX_ROOT because it does not contain $VITIS_SETTINGS" >&2
        fi
        XILINX_ROOT="$(discover_xilinx_root)"
    fi
fi

WORKSPACE="${WORKSPACE:-}"
TFTP_ROOT="${TFTP_ROOT:-/srv/tftp}"
CONTAINER_HOME="${CONTAINER_HOME:-$HOME/.qt-boot-gui-container}"
XAUTH_FILE="${XAUTHORITY:-$HOME/.Xauthority}"
AUTO_START_HW_SERVER="${AUTO_START_HW_SERVER:-1}"
HW_SERVER_LOG="${HW_SERVER_LOG:-$CONTAINER_HOME/hw_server.log}"

if [[ -z "$WORKSPACE" ]]; then
    echo "Set WORKSPACE to the host directory containing your configs and image artifacts." >&2
    exit 1
fi

for path in "$XILINX_ROOT" "$WORKSPACE" "$TFTP_ROOT"; do
    if [[ ! -d "$path" ]]; then
        echo "Required directory does not exist: $path" >&2
        exit 1
    fi
done

if [[ ! -r "$VITIS_SETTINGS" ]]; then
    echo "Vitis settings script is not readable: $VITIS_SETTINGS" >&2
    exit 1
fi

case "$VITIS_SETTINGS" in
    "$XILINX_ROOT"/*) ;;
    *)
        echo "VITIS_SETTINGS must be inside XILINX_ROOT so it is visible in the container." >&2
        echo "  VITIS_SETTINGS=$VITIS_SETTINGS" >&2
        echo "  XILINX_ROOT=$XILINX_ROOT" >&2
        exit 1
        ;;
esac

if [[ -z "${DISPLAY:-}" ]]; then
    echo "DISPLAY is not set. Run this script from a Linux graphical session." >&2
    exit 1
fi

if [[ ! -r "$XAUTH_FILE" ]]; then
    echo "X11 authorization file is not readable: $XAUTH_FILE" >&2
    exit 1
fi

mkdir -p "$CONTAINER_HOME" "$WORKSPACE/output"

image_id="$(docker image inspect "$IMAGE_NAME" --format '{{.Id}}' 2>/dev/null || true)"
if [[ -z "$image_id" ]]; then
    echo "Docker image is not available locally: $IMAGE_NAME" >&2
    echo "Build it with ./build-image.sh or set IMAGE_NAME to an installed image." >&2
    exit 1
fi
echo "Launching image: $IMAGE_NAME ($image_id)"

hw_server_ready() {
    timeout 1 bash -c 'exec 3<>/dev/tcp/127.0.0.1/3121' 2>/dev/null
}

started_hw_server_pid=""
stop_started_hw_server() {
    if [[ -z "$started_hw_server_pid" ]]; then
        return
    fi

    local process_group="$started_hw_server_pid"
    started_hw_server_pid=""
    echo "Stopping automatically started host hw_server (process group $process_group)"
    kill -TERM -- "-$process_group" 2>/dev/null || true
    for _ in {1..20}; do
        if ! kill -0 "$process_group" 2>/dev/null; then
            break
        fi
        sleep 0.1
    done
    if kill -0 "$process_group" 2>/dev/null; then
        kill -KILL -- "-$process_group" 2>/dev/null || true
    fi
    wait "$process_group" 2>/dev/null || true
}
trap stop_started_hw_server EXIT
trap 'exit 130' INT TERM

if hw_server_ready; then
    echo "Using existing host hw_server at TCP:127.0.0.1:3121"
elif [[ "$AUTO_START_HW_SERVER" == "1" ]]; then
    if ! command -v setsid >/dev/null 2>&1; then
        echo "Cannot auto-start hw_server because the host setsid command is unavailable." >&2
        exit 1
    fi

    echo "Starting host hw_server from Vitis: $VITIS_SETTINGS"
    echo "hw_server log: $HW_SERVER_LOG"
    setsid bash -c 'source "$1" && exec hw_server' _ "$VITIS_SETTINGS" >"$HW_SERVER_LOG" 2>&1 &
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

    if ! hw_server_ready; then
        echo "Automatically started hw_server did not become ready." >&2
        echo "Last hw_server log lines:" >&2
        tail -n 30 "$HW_SERVER_LOG" >&2 || true
        exit 1
    fi
    echo "Host hw_server is ready at TCP:127.0.0.1:3121"
else
    echo "WARNING: Host hw_server is not reachable at TCP:127.0.0.1:3121." >&2
    echo "AUTO_START_HW_SERVER=0; JTAG operations will fail until a server is started." >&2
fi

docker_args=(
    --rm
    --network host
    --user "$(id -u):$(id -g)"
    --workdir /work
    --env "DISPLAY=$DISPLAY"
    --env XAUTHORITY=/tmp/host.Xauthority
    --env "VITIS_SETTINGS=$VITIS_SETTINGS"
    --env HOME=/home/qtboot
    --mount "type=bind,source=/tmp/.X11-unix,target=/tmp/.X11-unix,readonly"
    --mount "type=bind,source=$XAUTH_FILE,target=/tmp/host.Xauthority,readonly"
    --mount "type=bind,source=$XILINX_ROOT,target=$XILINX_ROOT,readonly"
    --mount "type=bind,source=$WORKSPACE,target=/work"
    --mount "type=bind,source=$TFTP_ROOT,target=/srv/tftp"
    --mount "type=bind,source=$CONTAINER_HOME,target=/home/qtboot"
)

if [[ -t 0 && -t 1 ]]; then
    docker_args+=(--interactive --tty)
fi

for variable in XILINXD_LICENSE_FILE LM_LICENSE_FILE QT_BOOT_GUI_CHECK_ONLY QT_BOOT_GUI_JTAG_CONFIG QT_BOOT_GUI_QSPI_CONFIG; do
    if [[ -n "${!variable:-}" ]]; then
        docker_args+=(--env "$variable=${!variable}")
    fi
done

docker run "${docker_args[@]}" "$IMAGE_NAME" "$@"
