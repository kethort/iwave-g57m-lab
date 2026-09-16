# Container Setup

The GUI and AMD command-line clients run in an Ubuntu 20.04 container. Vitis,
the TFTP service, USB cable support, and `hw_server` remain on the Linux host.

```text
Qt GUI + XSDB in Docker
          |
          | host networking: TCP 127.0.0.1:3121
          v
host hw_server -> host USB/udev -> JTAG cable -> Versal target
```

The release does not place the USB device inside Docker. This keeps AMD cable
drivers and permissions in one place and lets both the GUI and host diagnostics
use the same `hw_server`.

## Host Prerequisites

- Linux x86-64 with X11 or XWayland
- Docker Engine
- AMD Vitis 2025.2
- AMD/Xilinx or Digilent cable drivers and udev rules
- `tftpd-hpa` and a writable TFTP root
- Board artifacts under one user-selected workspace

Typical Ubuntu packages are:

```bash
sudo apt update
sudo apt install -y docker.io tftpd-hpa tftp-hpa x11-xserver-utils xauth usbutils iproute2
sudo systemctl enable --now docker tftpd-hpa
sudo usermod -aG docker "$USER"
```

Log out and back in after adding the Docker group. Do not run the GUI container
with `sudo` to work around Docker or X11 permissions.

## Install JTAG Cable Support

The Vitis installation includes the cable-driver installer. Its exact location
depends on the selected installation root. Locate it with:

```bash
find /opt/amd /tools/Xilinx /development \
  -type f -path '*/cable_drivers/lin64/install_script/install_drivers/install_drivers' \
  -print 2>/dev/null
```

Run the discovered installer once with `sudo`, reload udev, and reconnect the
cable:

```bash
sudo /path/from/find/install_drivers
sudo udevadm control --reload-rules
sudo udevadm trigger
```

`setup-host.sh` reports whether common Xilinx/Digilent rules and USB interfaces
are visible. A running `hw_server` with no targets often means this host step is
missing or the cable is not accessible to the current user.

## One-Time Setup

From the cloned release repository, run:

```bash
./setup-host.sh --pull
```

The script does not install packages or perform privileged changes. It:

- discovers common Vitis 2025.2 installations, including `/opt/amd/2025.2`;
- checks required Vitis tools;
- creates `$HOME/versal-lab-data` by default;
- creates editable `configs/jtag_config.json` and `configs/qspi_config.json`;
- creates the persistent, ignored `qt-boot-gui.env` launcher configuration;
- checks Docker access, TFTP, X11, cable rules, and connected USB interfaces;
- pulls `ghcr.io/kethort/iwave-g57m-lab:latest` when `--pull` is supplied.

If Vitis or data uses a nonstandard location, provide it for the first run:

```bash
VITIS_SETTINGS=/opt/amd/2025.2/Vitis/settings64.sh \
WORKSPACE="$HOME/versal-lab-data" \
TFTP_ROOT=/srv/tftp \
./setup-host.sh --pull
```

Shell variables override `qt-boot-gui.env`, which makes one-off testing possible
without editing the saved host configuration.

## Workspace And Artifacts

The default host workspace is `$HOME/versal-lab-data`, mounted in the container
as `/work`:

```text
$HOME/versal-lab-data/
|-- configs/
|   |-- jtag_config.json
|   `-- qspi_config.json
|-- output/
`-- build/tmp/deploy/images/versal-iwg57m/
    |-- boot.bin
    |-- boot.bin-extracted/
    |-- Image
    |-- system.dtb
    `-- petalinux-image-minimal-versal-iwg57m.cpio.gz
```

The `build/...` layout matches the seeded templates, but it is not mandatory.
Artifacts may use any organization beneath the workspace if the editable JSON
or GUI fields use corresponding `/work/...` paths. Host files outside the
workspace, TFTP root, and Vitis installation are intentionally invisible to the
container.

Mounts used by the launcher:

| Host resource | Container path | Access |
| --- | --- | --- |
| `$WORKSPACE` | `/work` | Read/write |
| `$TFTP_ROOT` | `/srv/tftp` | Read/write |
| `$XILINX_ROOT` | Same absolute path | Read-only |
| `~/.qt-boot-gui-container` | `/home/qtboot` | Read/write |

## Runtime Validation

Run the container tool check before connecting hardware:

```bash
QT_BOOT_GUI_CHECK_ONLY=1 ./run-container.sh
```

Check-only mode validates Docker, Vitis mounting, startup configurations,
`bootgen`, `xsdb`, `program_flash`, `mkimage`, and `mkenvimage`. It deliberately
does not require `DISPLAY`, X11 authorization, TFTP, `hw_server`, or JTAG.

## JTAG Validation

Connect and power the board, select JTAG boot mode, and run:

```bash
./diagnose-jtag.sh
```

The diagnostic starts a temporary host `hw_server` when necessary, checks TCP
connectivity, prints the complete XSDB target list, and selects the PMC target.
It stops only the server instance it started. Failures include cable-rule and
USB-enumeration hints.

## Launch

```bash
./run-container.sh
```

The launcher:

- loads `qt-boot-gui.env` automatically;
- prefers `qt-boot-gui:2025.2` when built locally;
- otherwise selects and pulls the published GHCR image;
- starts host `hw_server` when needed;
- discovers the active Xauthority file or temporarily uses restricted `xhost`
  access;
- retains software-rendering safeguards for portable Qt Quick display.

Use `AUTO_START_HW_SERVER=0` in `qt-boot-gui.env` when managing a local or remote
server independently.

## Build Locally

The published image is the normal installation path. To test a release binary
or Dockerfile from the checkout instead:

```bash
./build-image.sh
./run-container.sh
```

The launcher detects the local `qt-boot-gui:2025.2` image and prefers it without
requiring `IMAGE_NAME` to be exported.
