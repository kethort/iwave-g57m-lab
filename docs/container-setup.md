# Container Setup

The GUI runs inside an Ubuntu 20.04 container while Vitis, `hw_server`, the TFTP
service, and the JTAG cable remain on the host.

```text
Qt GUI + XSDB in Docker
          |
          | TCP 127.0.0.1:3121
          v
host hw_server -> USB JTAG -> Versal target
```

Host networking lets containerized XSDB reach `hw_server` without exposing the
USB bus to Docker. The launcher mounts only the Vitis installation, artifact
workspace, TFTP root, X11 socket, and a persistent application home.

## Prerequisites

- Linux x86-64 with X11 or XWayland
- Docker Engine
- AMD Vitis 2025.2
- Host TFTP service
- Read/write access to the configured TFTP root
- Board artifacts and JSON configurations in one host workspace

## Locate Vitis

Find and export the Vitis 2025.2 settings script:

```bash
find /tools/Xilinx /development -path '*2025.2*' -name settings64.sh -print 2>/dev/null
export VITIS_SETTINGS=/development/2025.2/Vitis/settings64.sh
```

`run-container.sh` discovers the installation root containing `Vitis/` and
`Vivado/`. Set `XILINX_ROOT` only for a nonstandard layout.

## Build Or Pull

Build locally:

```bash
./build-image.sh
```

The default image name is `qt-boot-gui:2025.2`. To use the published image:

```bash
docker pull ghcr.io/kethort/iwave-g57m-lab:latest
export IMAGE_NAME=ghcr.io/kethort/iwave-g57m-lab:latest
```

## Configure Mounts

```bash
export WORKSPACE="$HOME/versal-lab-data"
export TFTP_ROOT=/srv/tftp
export CUSTOM_ARTIFACTS="$HOME/vitis_projects/secure-boot/plm/build/plm/build"
```

| Host resource | Container path | Access |
| --- | --- | --- |
| `$WORKSPACE` | `/work` | Read/write |
| `$TFTP_ROOT` | `/srv/tftp` | Read/write |
| `$CUSTOM_ARTIFACTS` | `/artifacts` | Read-only, optional |
| `$XILINX_ROOT` | Same absolute path | Read-only |
| `~/.qt-boot-gui-container` | `/home/qtboot` | Read/write |

Place custom PLM files and other browsed artifacts under `WORKSPACE`, or set
`CUSTOM_ARTIFACTS` to an additional host directory. The latter is mounted
read-only at `/artifacts`; for example, mounting the directory containing
`plm.elf` makes it selectable as `/artifacts/plm.elf`. Paths outside these
mounts are not visible in the container.

License-server variables are forwarded when set:

```bash
export XILINXD_LICENSE_FILE=2100@license-server.example.com
```

## Validate And Launch

Check that all required tools resolve before opening the GUI:

```bash
QT_BOOT_GUI_CHECK_ONLY=1 ./run-container.sh
```

A successful check finds `bootgen`, `xsdb`, `program_flash`, `mkimage`, and
`mkenvimage`. Launch with:

```bash
./run-container.sh
```

The launcher starts host `hw_server` if port 3121 is unused and stops only the
instance it started. Set `AUTO_START_HW_SERVER=0` when managing it separately.

If X11 rejects the connection:

```bash
xhost +SI:localuser:"$(id -un)"
./run-container.sh
```
