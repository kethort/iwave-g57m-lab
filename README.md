# Versal Boot GUI Container Release

[Website](https://kethort.github.io/iwave-g57m-lab/) | [Container packages](https://github.com/kethort/iwave-g57m-lab/pkgs/container/iwave-g57m-lab)

This is the public binary-release repository for **Versal AI Edge Lab Notes**
by Ken Orton. It intentionally contains no C++ or QML source code.

This directory packages the precompiled `qt_boot_gui` application in an Ubuntu
20.04 container with its Qt 5.12 runtime. The image does **not** contain AMD
Vitis. At runtime, the user's licensed Vitis 2025.2 installation is mounted
read-only so the GUI can invoke `bootgen`, `xsdb`, and `program_flash`.

The supplied executable is Linux x86-64 only.

## Runtime architecture

- The Qt GUI runs in the container and displays through the host X11 server.
- Vitis 2025.2 is installed on the host and mounted at the same absolute path.
- `hw_server` runs on the host and owns the JTAG USB cable.
- The container uses host networking, allowing XSDB to reach host
  `hw_server` at `127.0.0.1:3121`.
- The host TFTP service continues to serve its normal TFTP root. That directory
  is mounted read-write at `/srv/tftp` so the GUI can stage files into it.
- The artifact workspace is mounted read-write at `/work`.

This arrangement avoids putting Vitis in a redistributable image and avoids
granting the container unrestricted access to host USB devices.

## Prerequisites

- Linux x86-64 with an X11 or XWayland graphical session
- Docker Engine
- AMD Vitis 2025.2 installed on the host
- Access to a Versal JTAG cable through host `hw_server`
- A host TFTP server for TFTP, NFS, and QSPI provisioning workflows
- Read/write permission to the host TFTP root
- Board artifacts and JSON configurations in a host workspace

The executable was built against Ubuntu 20.04's Qt 5.12.8 runtime. Keep this
base image unless the application is rebuilt against a different distribution.

## Files

| File | Purpose |
| --- | --- |
| `qt_boot_gui` | Stripped, precompiled application |
| `Dockerfile` | Ubuntu and Qt runtime image |
| `docker-entrypoint.sh` | Loads Vitis and validates required tools |
| `build-image.sh` | Builds the local Docker image |
| `run-container.sh` | Validates mounts and launches the GUI |
| `diagnose-jtag.sh` | Host-side hw_server, XSDB, target, and PMC diagnostic |
| `diagnose-jtag.tcl` | Non-programming XSDB target probe used by the diagnostic |
| `qt_boot_gui.sha256` | SHA-256 checksum for the shipped executable |
| `jtag_config.json` | Portable JTAG configuration template |
| `qspi_config.json` | Portable QSPI configuration template |
| `LICENSES/` | Qt and third-party notices |

## Included configuration templates

The release contains `jtag_config.json` and `qspi_config.json` beside this
README. Their artifact paths start with `/work`, which is the container path for
the host directory selected through `WORKSPACE`.

For example, when a directory containing your artifacts and a checkout of this
release repository is mounted with:

```bash
export WORKSPACE="$HOME/versal-lab-data"
```

the editable repository copies appear in the GUI at:

```text
/work/iwave-g57m-lab/jtag_config.json
/work/iwave-g57m-lab/qspi_config.json
```

The same templates are also built into the image as read-only defaults:

```text
/opt/qt-boot-gui/configs/jtag_config.json
/opt/qt-boot-gui/configs/qspi_config.json
```

The GUI automatically loads both built-in templates at startup. Override either
startup file without rebuilding the image by setting a container-visible path:

```bash
export QT_BOOT_GUI_JTAG_CONFIG=/work/configs/jtag_config.json
export QT_BOOT_GUI_QSPI_CONFIG=/work/configs/qspi_config.json
```

Use the `/work/...` copies when you want changes to persist on the host. If you
load a built-in `/opt/...` template, save the resolved configuration somewhere
under `/work`; the application cannot modify files inside the image. Review the
board IP, server IP, NFS root, flash geometry, partition offsets, image paths,
and custom PLM/PDI inputs for each target before starting a hardware operation.

## 1. Locate Vitis

Find the Vitis 2025.2 settings script on the host. Common layouts include:

```text
/development/2025.2/Vitis/settings64.sh
/tools/Xilinx/Vitis/2025.2/settings64.sh
/tools/Xilinx/2025.2/Vitis/settings64.sh
```

For example:

```bash
find /tools/Xilinx -path '*2025.2*' -name settings64.sh -print
```

Set `VITIS_SETTINGS` to the exact script path. The launcher automatically finds
the nearest parent containing both `Vitis/` and `Vivado/` and mounts that
installation root at the same absolute path inside the container. AMD scripts
can rely on their original directory layout and symlinks.

Example for this development host:

```bash
export VITIS_SETTINGS=/development/2025.2/Vitis/settings64.sh
```

Set `XILINX_ROOT` explicitly only when automatic discovery is unsuitable:

```bash
export XILINX_ROOT=/development/2025.2
```

An explicit `VITIS_SETTINGS` is authoritative. If the shell still contains a
stale `XILINX_ROOT` from another Vitis release, the launcher ignores it and
discovers the correct installation root from `VITIS_SETTINGS`.

## 2. Build the image

From this directory:

```bash
chmod +x build-image.sh run-container.sh docker-entrypoint.sh
./build-image.sh
```

The default image name is `qt-boot-gui:2025.2`. Override it when needed:

```bash
IMAGE_NAME=ghcr.io/OWNER/qt-boot-gui:2025.2 ./build-image.sh
```

## 3. Host hardware server

`run-container.sh` starts the host `hw_server` automatically when port 3121 is
not already in use. It waits for the server, writes its output to
`~/.qt-boot-gui-container/hw_server.log`, and stops that server when the GUI
exits. A server that was already running is reused and left running.

Normally no separate command is required:

```bash
./run-container.sh
```

Disable automatic startup when managing the server separately:

```bash
AUTO_START_HW_SERVER=0 ./run-container.sh
```

The GUI's XSDB process connects to the host server through host networking. The
container does not need direct USB access.

Before launching the GUI, run the host-side diagnostic:

```bash
./diagnose-jtag.sh
```

It verifies the Vitis tool paths, process and TCP listener, XSDB connection,
complete target list, and PMC target. Run it separately when automatic startup
or target discovery fails.

Start or verify the host TFTP service separately. Confirm that its configured
root matches the directory supplied as `TFTP_ROOT`.

Examples of useful checks are:

```bash
ss -ltn | grep 3121
test -w /srv/tftp && echo 'TFTP root is writable'
```

## 4. Configure the launch environment

Set the host artifact workspace and TFTP root. The workspace should contain all
JSON files, deploy images, extracted boot components, and custom PLM files that
the GUI needs to browse.

```bash
export WORKSPACE="$HOME/versal-lab-data"
export TFTP_ROOT=/srv/tftp
export IMAGE_NAME=qt-boot-gui:2025.2
```

If a custom PLM is outside `WORKSPACE`, either move/copy it into a directory
under the workspace or set `WORKSPACE` to a common parent containing both the
project artifacts and PLM. Files outside mounted directories are intentionally
not visible to the GUI.

For a network license server, preserve the applicable host environment variable:

```bash
export XILINXD_LICENSE_FILE=2100@license-server.example.com
```

The launcher also forwards `LM_LICENSE_FILE` when it is set.

## 5. Validate without launching the GUI

Run the entrypoint's tool check first:

```bash
QT_BOOT_GUI_CHECK_ONLY=1 ./run-container.sh
```

A successful check prints the resolved locations of:

```text
bootgen
xsdb
program_flash
mkimage
mkenvimage
```

If this check fails, correct `XILINX_ROOT` or `VITIS_SETTINGS` before attempting
to program hardware.

## 6. Launch the GUI

```bash
./run-container.sh
```

The launcher runs the container as the current host UID/GID, mounts only the
required directories, and creates a persistent writable home at:

```text
~/.qt-boot-gui-container
```

If X11 denies the connection, grant only the current local user access and try
again:

```bash
xhost +SI:localuser:"$(id -un)"
./run-container.sh
```

## Container paths used in the GUI

The file dialogs run inside the container. Select paths using their container
locations:

| Host resource | GUI/container path |
| --- | --- |
| `$WORKSPACE` | `/work` |
| `$TFTP_ROOT` | `/srv/tftp` |
| `$XILINX_ROOT` | Same absolute path as the host |

Generated FIT images, PDIs, boot scripts, BIF files, and XSDB scripts are written
under `/work/output`, which maps to `$WORKSPACE/output` on the host. The launcher
creates this directory before starting the container.

For example, this host file:

```text
$HOME/versal-lab-data/configs/qspi_flash_config.generated.json
```

appears in the GUI as:

```text
/work/configs/qspi_flash_config.generated.json
```

Configurations that contain absolute host paths should be updated to use `/work`
paths, or loaded and corrected in the GUI before running an operation. Relative
paths remain preferable when the configuration format permits them.

## JTAG boot workflow

1. Start host `hw_server` and connect the board's JTAG cable.
2. Launch the container.
3. Open the JTAG tab and load the applicable JSON configuration.
4. Confirm every resolved artifact path points under `/work`.
5. For TFTP/NFS, confirm the host TFTP root is `/srv/tftp` in the GUI.
6. Select the desired JTAG mode and custom PLM, if applicable.
7. Start the operation; the GUI switches to Preview and streams tool output.

If XSDB cannot connect, verify that port 3121 is listening on the host and that
the container was launched with host networking.

## QSPI provisioning workflow

The equivalent of the former `--jtag-provision-qspi-components` command remains
a two-stage boot-and-provision flow:

1. `bootgen` creates a custom BOOT image/PDI using the selected base design,
   QSPI-specific PLM, PSM, ATF, U-Boot, and handoff DTB.
2. XSDB/JTAG starts that image on the board.
3. The GUI stages BOOT.bin, kernel, Linux DTB, rootfs, environment, and boot
   script files in `/srv/tftp` according to the loaded QSPI configuration.
4. U-Boot downloads those components over TFTP and writes them at the configured
   QSPI offsets.

To run it:

1. Open the QSPI tab.
2. Load `qspi_flash_config.generated.json` from `/work/...`.
3. Select the extracted `base-design.pdi`, QSPI custom `plm.elf`, `psmfw.elf`,
   `arm-trusted-firmware.elf`, `u-boot.elf`, and `system-top.dtb`.
4. Select or generate the QSPI custom BOOT image.
5. Review the partition offsets and ensure they fit the physical flash size.
6. Confirm U-Boot server IP, board IP, Ethernet device, and `/srv/tftp` root.
7. Press **JTAG boot U-Boot + provision QSPI**.
8. Follow the Preview log and board serial console until all erase/write/verify
   operations finish.

The **QSPI PLM** is separate from the custom PLM field on the JTAG tab. It is
baked into the custom QSPI boot image and must be selected in the QSPI tab.

Do not power-cycle or disconnect JTAG while flash erase/write operations are in
progress. Confirm the flash type, total size, erase size, and component offsets
before provisioning a board.

## Direct serial access

The recommended setup leaves serial monitoring on the host through minicom or a
similar tool. If a future GUI feature opens the serial port directly, add a
specific device to `docker_args` in `run-container.sh`, for example:

```bash
--device /dev/ttyUSB0:/dev/ttyUSB0
```

Do not use `--privileged` merely to access one serial or USB device.

## Troubleshooting

### Vitis tools are missing

Run:

```bash
QT_BOOT_GUI_CHECK_ONLY=1 ./run-container.sh
```

Check that the complete Vitis tree is mounted and the exact `settings64.sh` path
is readable. Mounting only one Vitis subdirectory can break relative tool paths.

### The GUI does not appear

Check `DISPLAY`, the Xauthority file, and `/tmp/.X11-unix`:

```bash
printf 'DISPLAY=%s\n' "$DISPLAY"
ls -l "${XAUTHORITY:-$HOME/.Xauthority}"
ls -ld /tmp/.X11-unix
```

### TFTP staging fails

The container runs as your host UID. Make the host TFTP directory writable by
that user or its group. Do not solve this by running the entire container as
root unless required for a controlled diagnostic.

### The board cannot download staged files

Confirm that the host TFTP daemon serves the same host directory mounted as
`/srv/tftp`, and that U-Boot's `serverip`, `ipaddr`, interface, filenames, and
network route are correct. Container host networking does not replace the host
TFTP daemon.

### Paths from JSON are missing

Host paths outside `$WORKSPACE`, `$TFTP_ROOT`, and `$XILINX_ROOT` are not mounted.
Use `/work/...` paths in the GUI or broaden `WORKSPACE` deliberately. Avoid
mounting the entire home directory.

## Publishing releases

The `Publish container` GitHub Actions workflow builds and publishes
`ghcr.io/kethort/iwave-g57m-lab` when a version tag is pushed. For example:

```bash
git tag v0.1.0
git push origin v0.1.0
```

The workflow publishes both `ghcr.io/kethort/iwave-g57m-lab:v0.1.0` and
`ghcr.io/kethort/iwave-g57m-lab:latest`. It can also be started manually from
the repository's Actions page.

The `Publish website` workflow deploys the Hugo site under `site/` whenever
site content is pushed to `main`. In the repository settings, set **Pages >
Build and deployment > Source** to **GitHub Actions** once after creating the
repository.

Create a checksum for a GitHub binary release:

```bash
sha256sum qt_boot_gui > qt_boot_gui.sha256
```

Verify a downloaded binary before building or running it:

```bash
sha256sum --check qt_boot_gui.sha256
```

Keep application source in a private repository and publish this release bundle,
the stripped executable, checksums, and container image from a separate public
release repository. Stripping reduces debug information but does not prevent
reverse engineering or extraction of embedded resources.

## Licensing

The application dynamically links Qt. The image includes the LGPL 3 license and
third-party notice. Before public distribution, verify that your release process
meets all Qt LGPL obligations, including notices, corresponding Qt source
availability, user relinking/replacement rights, and any required reverse-
engineering exception. Use a commercial Qt license if those obligations do not
fit the intended product terms.

AMD Vitis files are never copied into this image. Each user must install and
license Vitis 2025.2 separately and mount it at runtime. Review AMD's applicable
license terms before distributing any AMD-generated components.
