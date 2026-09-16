#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=launcher-common.sh
source "$SCRIPT_DIR/launcher-common.sh"

LAUNCHER_CONFIG="${LAUNCHER_CONFIG:-$SCRIPT_DIR/qt-boot-gui.env}"
load_launcher_config "$LAUNCHER_CONFIG"

CHECK_ONLY="${QT_BOOT_GUI_CHECK_ONLY:-0}"
WORKSPACE="${WORKSPACE:-$HOME/versal-lab-data}"
TFTP_ROOT="${TFTP_ROOT:-/srv/tftp}"
CONTAINER_HOME="${CONTAINER_HOME:-$HOME/.qt-boot-gui-container}"
AUTO_START_HW_SERVER="${AUTO_START_HW_SERVER:-1}"
HW_SERVER_URL="${HW_SERVER_URL:-TCP:127.0.0.1:3121}"
HW_SERVER_LOG="${HW_SERVER_LOG:-$CONTAINER_HOME/hw_server.log}"
ALLOW_IMAGE_PULL="${ALLOW_IMAGE_PULL:-1}"

if [[ -z "${VITIS_SETTINGS:-}" ]]; then
    if ! VITIS_SETTINGS="$(discover_vitis_settings)"; then
        echo "Could not find AMD Vitis 2025.2 settings64.sh." >&2
        echo "Set VITIS_SETTINGS or run ./setup-host.sh after installing Vitis." >&2
        exit 1
    fi
fi
if [[ ! -r "$VITIS_SETTINGS" ]]; then
    echo "Vitis settings script is not readable: $VITIS_SETTINGS" >&2
    exit 1
fi

if [[ -z "${XILINX_ROOT:-}" || "$VITIS_SETTINGS" != "$XILINX_ROOT"/* ]]; then
    if [[ -n "${XILINX_ROOT:-}" ]]; then
        echo "Ignoring XILINX_ROOT=$XILINX_ROOT because it does not contain $VITIS_SETTINGS" >&2
    fi
    XILINX_ROOT="$(discover_xilinx_root "$VITIS_SETTINGS")"
fi
if [[ ! -d "$XILINX_ROOT" ]]; then
    echo "AMD installation root does not exist: $XILINX_ROOT" >&2
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

mkdir -p "$CONTAINER_HOME" "$WORKSPACE"
seed_workspace_configs "$SCRIPT_DIR" "$WORKSPACE"

QT_BOOT_GUI_JTAG_CONFIG="${QT_BOOT_GUI_JTAG_CONFIG:-/work/configs/jtag_config.json}"
QT_BOOT_GUI_QSPI_CONFIG="${QT_BOOT_GUI_QSPI_CONFIG:-/work/configs/qspi_config.json}"

if ! command -v docker >/dev/null 2>&1; then
    echo "Docker is not installed or is not in PATH." >&2
    exit 1
fi
if ! docker info >/dev/null 2>&1; then
    echo "Cannot access the Docker daemon as $(id -un)." >&2
    echo "Start Docker and ensure this user belongs to the docker group." >&2
    exit 1
fi

if [[ -z "${IMAGE_NAME:-}" ]]; then
    if docker image inspect "$QT_BOOT_GUI_LOCAL_IMAGE" >/dev/null 2>&1; then
        IMAGE_NAME="$QT_BOOT_GUI_LOCAL_IMAGE"
    else
        IMAGE_NAME="$QT_BOOT_GUI_PUBLISHED_IMAGE"
    fi
fi

if ! docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
    if [[ "$ALLOW_IMAGE_PULL" == "1" ]]; then
        echo "Docker image is not local; pulling $IMAGE_NAME"
        docker pull "$IMAGE_NAME"
    else
        echo "Docker image is not available locally: $IMAGE_NAME" >&2
        echo "Pull it manually, run ./build-image.sh, or set ALLOW_IMAGE_PULL=1." >&2
        exit 1
    fi
fi
image_id="$(docker image inspect "$IMAGE_NAME" --format '{{.Id}}')"
echo "Launching image: $IMAGE_NAME ($image_id)"

if [[ "$CHECK_ONLY" != "1" ]]; then
    if [[ ! -d "$TFTP_ROOT" ]]; then
        echo "TFTP root does not exist: $TFTP_ROOT" >&2
        echo "Create/configure it or set TFTP_ROOT in $LAUNCHER_CONFIG." >&2
        exit 1
    fi
    if [[ ! -w "$TFTP_ROOT" ]]; then
        echo "TFTP root is not writable by $(id -un): $TFTP_ROOT" >&2
        exit 1
    fi
fi

endpoint="${HW_SERVER_URL#TCP:}"
endpoint="${endpoint#tcp:}"
hw_server_host="${endpoint%:*}"
hw_server_port="${endpoint##*:}"
if [[ -z "$hw_server_host" || -z "$hw_server_port" || "$hw_server_host" == "$hw_server_port" ]]; then
    echo "Expected HW_SERVER_URL in TCP:host:port form, got: $HW_SERVER_URL" >&2
    exit 1
fi

hw_server_ready() {
    timeout 1 bash -c 'exec 3<>/dev/tcp/"$1"/"$2"' _ "$hw_server_host" "$hw_server_port" 2>/dev/null
}

started_hw_server_pid=""
xhost_granted=0
docker_pid=""
container_cidfile="$CONTAINER_HOME/container-$$.cid"
rm -f "$container_cidfile"
cleanup() {
    if [[ -s "$container_cidfile" ]]; then
        container_id="$(<"$container_cidfile")"
        docker stop --time 2 "$container_id" >/dev/null 2>&1 || true
    fi
    if [[ -n "$docker_pid" ]]; then
        kill -TERM "$docker_pid" 2>/dev/null || true
        wait "$docker_pid" 2>/dev/null || true
        docker_pid=""
    fi
    rm -f "$container_cidfile"

    if [[ -n "$started_hw_server_pid" ]]; then
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
    fi

    if [[ "$xhost_granted" == "1" ]]; then
        xhost -SI:localuser:"$(id -un)" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT
trap 'exit 130' INT TERM

if [[ "$CHECK_ONLY" != "1" ]]; then
    if hw_server_ready; then
        echo "Using existing hw_server at $HW_SERVER_URL"
    elif [[ "$AUTO_START_HW_SERVER" == "1" && ( "$hw_server_host" == "127.0.0.1" || "$hw_server_host" == "localhost" ) ]]; then
        if ! command -v setsid >/dev/null 2>&1; then
            echo "Cannot auto-start hw_server because setsid is unavailable." >&2
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
        echo "Host hw_server is ready at $HW_SERVER_URL"
    else
        echo "WARNING: hw_server is not reachable at $HW_SERVER_URL." >&2
        echo "JTAG operations will fail until that server is available." >&2
    fi
fi

docker_args=(
    --rm
    --cidfile "$container_cidfile"
    --network host
    --user "$(id -u):$(id -g)"
    --workdir /work
    --env "VITIS_SETTINGS=$VITIS_SETTINGS"
    --env "HW_SERVER_URL=$HW_SERVER_URL"
    --env HOME=/home/qtboot
    --env LIBGL_ALWAYS_SOFTWARE=1
    --env QT_QUICK_BACKEND=software
    --env QT_XCB_GL_INTEGRATION=none
    --env "QT_BOOT_GUI_JTAG_CONFIG=$QT_BOOT_GUI_JTAG_CONFIG"
    --env "QT_BOOT_GUI_QSPI_CONFIG=$QT_BOOT_GUI_QSPI_CONFIG"
    --mount "type=bind,source=$XILINX_ROOT,target=$XILINX_ROOT,readonly"
    --mount "type=bind,source=$WORKSPACE,target=/work"
    --mount "type=bind,source=$CONTAINER_HOME,target=/home/qtboot"
)

if [[ "$CHECK_ONLY" == "1" ]]; then
    docker_args+=(--env QT_BOOT_GUI_CHECK_ONLY=1)
else
    if [[ -z "${DISPLAY:-}" ]]; then
        echo "DISPLAY is not set. Run the GUI from a Linux graphical session." >&2
        exit 1
    fi
    if [[ ! -d /tmp/.X11-unix ]]; then
        echo "The X11 socket directory does not exist: /tmp/.X11-unix" >&2
        exit 1
    fi

    docker_args+=(
        --env "DISPLAY=$DISPLAY"
        --mount "type=bind,source=/tmp/.X11-unix,target=/tmp/.X11-unix,readonly"
        --mount "type=bind,source=$TFTP_ROOT,target=/srv/tftp"
    )

    if xauth_file="$(find_xauthority)"; then
        echo "Using X11 authorization: $xauth_file"
        docker_args+=(
            --env XAUTHORITY=/tmp/host.Xauthority
            --mount "type=bind,source=$xauth_file,target=/tmp/host.Xauthority,readonly"
        )
    elif command -v xhost >/dev/null 2>&1 && xhost +SI:localuser:"$(id -un)" >/dev/null; then
        echo "No readable Xauthority file found; granted temporary X11 access to $(id -un)."
        xhost_granted=1
    else
        echo "No usable X11 authorization was found." >&2
        echo "Install xauth or grant local access with: xhost +SI:localuser:$(id -un)" >&2
        exit 1
    fi
fi

if [[ -t 0 && -t 1 ]]; then
    docker_args+=(--interactive --tty)
fi

for variable in XILINXD_LICENSE_FILE LM_LICENSE_FILE; do
    if [[ -n "${!variable:-}" ]]; then
        docker_args+=(--env "$variable=${!variable}")
    fi
done

docker run "${docker_args[@]}" "$IMAGE_NAME" "$@" &
docker_pid=$!
set +e
wait "$docker_pid"
docker_status=$?
set -e
docker_pid=""
exit "$docker_status"
