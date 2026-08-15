#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="${IMAGE_NAME:-qt-boot-gui:2025.2}"

if [[ ! -x "$SCRIPT_DIR/qt_boot_gui" ]]; then
    echo "Missing executable: $SCRIPT_DIR/qt_boot_gui" >&2
    exit 1
fi

echo "Building $IMAGE_NAME"
docker build --pull --tag "$IMAGE_NAME" "$SCRIPT_DIR"
docker image inspect "$IMAGE_NAME" >/dev/null
echo "Built $IMAGE_NAME"
