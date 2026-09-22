+++
title = "Experiment 001: Building the iWave PetaLinux Baseline"
date = 2026-09-20T00:00:00-07:00
description = "Reproduce the G57M boot firmware, U-Boot, Linux, device tree, root filesystem, and deploy artifacts from the iWave Yocto BSP."
tags = ["PetaLinux", "Yocto", "BitBake", "iWave", "Build"]
categories = ["Board Bring-Up"]
+++

This experiment establishes a reproducible software baseline for the iWave G57M VE2302 SOM and G57D R2.0 carrier. Its scope is deliberately narrow: understand the local layer, build it, and prove that the expected deploy artifacts were produced.

This workspace uses the **Yocto form of PetaLinux**, not a classic PetaLinux `project-spec` workflow. PetaLinux supplies the distribution and AMD layers, while BitBake performs the build. There is no `petalinux-build` or `petalinux-config` step in this BSP layout.

```text
system.xsa + meta-iwave recipes + machine configuration
                         |
                         v
              petalinux-image-minimal
                         |
                         v
 build/tmp/deploy/images/versal-iwg57m/
                         |
       +-----------------+-----------------+
       |                 |                 |
  boot firmware      Linux payloads    host artifacts
```

## Inputs and boundaries

| Input | Value |
| --- | --- |
| Board | iWave G57M VE2302 SOM on G57D R2.0 carrier |
| Vendor BSP layer | `sources/meta-iwave` |
| Machine | `versal-iwg57m` |
| Distribution | `petalinux` with systemd |
| AMD tools | Vitis 2025.2 |
| Image target | `petalinux-image-minimal` |
| Hardware description | `sources/meta-iwave/recipes-bsp/hw-description/system.xsa` |

Obtain the matching BSP and carrier documentation from iWave rather than copying configuration from another Versal board or carrier revision. The [iWave platform guide](https://iwave-global.com/knowledge-base/products/get-started-with-versal-ai-edge-prime-som-development-platform/) remains the hardware starting point.

The vendor source, XSA, patches, and generated firmware are not reproduced on this website. The paths below describe this workspace.

## How the build is selected

`setupsdk` points `TEMPLATECONF` at the iWave template and enters the OpenEmbedded environment:

```bash
export TEMPLATECONF="${ROOT}/sources/meta-iwave/conf/templates/iwg57m"
source "${ROOT}/sources/poky/oe-init-build-env" build
```

That template adds `meta-iwave` to `BBLAYERS`. The resulting build configuration selects the `versal-iwg57m` machine and PetaLinux distribution. Keep maintained changes under `sources/meta-iwave`; do not edit `build/tmp`, which is generated state and may disappear after a clean build.

## Local recipe and configuration delta

| Area | Recipe or configuration | Change | Why it exists | Produced or runtime effect |
| --- | --- | --- | --- | --- |
| Machine | `conf/machine/versal-iwg57m.conf` | Selects the XSA, U-Boot and kernel configurations, serial console, load addresses, rootfs package list, and `uboot-env` dependency. | Binds the generic Versal layers to this carrier and SOM. | Drives firmware generation and installs the board's bring-up tools and services. |
| U-Boot | `recipes-bsp/u-boot/u-boot-xlnx_%.bbappend` | Applies the iWave baseline patch, automatic boot-method patch, and board configuration fragment. | Keeps board-specific U-Boot behavior in the machine layer. | Produces the board U-Boot binary and ELF with the scripted JTAG, network, and QSPI commands. |
| U-Boot configuration | `recipes-bsp/u-boot/files/versal_iwg57m.cfg` | Enables FIT, networking, NFS, SPI flash, MTD, I2C/FRU, `source`, and board drivers; defines the SPI environment location. | Supplies the commands and drivers used during bring-up. | U-Boot can load scripts, use TFTP/NFS, inspect FMC FRU data, and access the QSPI flash. |
| Automatic boot methods | `recipes-bsp/u-boot/files/0002-iwg57m-automatic-boot-methods.patch` | Adds named component, FIT, JTAG, NFS, and QSPI boot paths plus fallback behavior. | Makes each boot strategy selectable and observable from U-Boot. | `bootcmd` can dispatch through `modeboot` to the selected method. |
| Environment image | `recipes-bsp/uboot-env/uboot-env.bb` | Generates readable `uboot-env.txt` and a checksummed binary `uboot.env` with `mkenvimage`. | Provides reproducible initial network and boot variables. | Deploys environment artifacts; it does not contain the U-Boot program. |
| Linux | `recipes-kernel/linux/linux-xlnx_%.bbappend` and `versal_iwg57m.cfg` | Applies the iWave kernel baseline and enables Versal IPI mailbox, R5 remoteproc, and RPMsg support. | Makes the selected carrier peripherals and RPU communication support available to Linux. | Produces `Image`, modules, and drivers used at runtime. |
| Device tree | `recipes-bsp/device-tree/device-tree.bbappend` and `system-user.dtsi` | Includes board aliases and peripherals, QSPI geometry/partitions, RPU reserved memory, remoteproc, and IPI mailboxes. | Describes hardware that software cannot discover on its own. | Produces the final Linux DTB; its QSPI node also lets Linux expose the fixed MTD regions. |
| Startup service | `recipes-apps/bootscript/bootscript.bb` | Installs a one-shot systemd unit that sets the kernel log level, timezone, and displayed BSP version. | Makes the baseline identity visible at login. | Runs `bootscript.service` during multi-user startup. |
| Network fallback | `recipes-core/network-fallback/network-fallback.bb` | Installs a bounded DHCP attempt with a static IPv4 fallback for `end1`. | Keeps the board reachable when DHCP is unavailable. | Uses `192.168.0.137/24` only if no DHCP address is obtained. |

The RPU and RPMsg entries are capabilities in this baseline; building the image does not itself load an RPU application.

## U-Boot environment artifacts

These similarly named files have different jobs:

- `BOOT.bin` is the boot firmware package. It contains the Versal platform/PLM content, PSM firmware, TF-A, and U-Boot selected by the boot recipe.
- The **SPI environment** is persistent variable storage, not U-Boot itself. The U-Boot board configuration reserves `0x10000` bytes at offset `0x00a00000`, with erase-sector size `0x10000`.
- `uboot.env` is a host-generated environment image. It is useful only when the active U-Boot environment backend and installation method expect that image.
- A FAT-backed `uboot.env` is separate from the SPI environment and is used only when that U-Boot configuration and environment load order support it.
- `qspi-boot.scr` is a U-Boot command script that loads Linux components. It is neither an environment nor a U-Boot executable.

The environment recipe's default size is `0x10000`. Confirm the **effective** BitBake value before treating its output as a deployable environment, because a machine or local override wins over the recipe default:

```bash
bitbake -e uboot-env | grep '^UBOOT_ENV_SIZE='
stat -c '%n %s bytes' \
  tmp/deploy/images/versal-iwg57m/uboot.env
```

The expected result is `UBOOT_ENV_SIZE="0x10000"` and a 65,536-byte `uboot.env`. A different effective size must be reconciled with U-Boot's `CONFIG_ENV_SIZE` before deployment.

## Build the complete image

The checked-in wrapper performs the supported setup consistently:

```bash
cd /development/xilinx-dev/iwg57m-2025-2
export VITIS_SETTINGS=/development/2025.2/Vitis/settings64.sh
./build-image.sh
```

It sources Vitis, clears `DISPLAY` for non-interactive XSCT use, enters the build environment through `setupsdk`, and runs `bitbake petalinux-image-minimal`.

The interactive equivalent is:

```bash
cd /development/xilinx-dev/iwg57m-2025-2
source /development/2025.2/Vitis/settings64.sh
source ./setupsdk build
bitbake petalinux-image-minimal
```

To rebuild only the generated environment artifacts after entering that shell:

```bash
bitbake uboot-env
```

Do not run concurrent BitBake processes against the same `build` directory. They share caches, work directories, and task state.

## Required deploy artifacts

Successful outputs appear under:

```text
build/tmp/deploy/images/versal-iwg57m/
```

Prefer stable symlink names in commands. Timestamped names identify the exact build behind those links and are valuable in archived test records.

| Stable artifact | Typical timestamped form | Producer | Purpose |
| --- | --- | --- | --- |
| `boot.bin` / `BOOT-versal-iwg57m.bin` | `BOOT-versal-iwg57m-<timestamp>.bin` | Bootgen through the Yocto boot recipe | Normal Versal boot firmware package. |
| `plm-versal-iwg57m.elf` | `plm-versal-iwg57m-...-<timestamp>.elf` | PLM firmware recipe | Platform Loader and Manager ELF. |
| `psm-firmware-versal-iwg57m.elf` | `psm-firmware-versal-iwg57m-...-<timestamp>.elf` | PSM firmware recipe | Platform System Manager firmware. |
| `arm-trusted-firmware.elf` | `arm-trusted-firmware-...-<timestamp>.elf` | TF-A recipe | BL31 secure firmware. |
| `u-boot.elf` | `u-boot-versal-iwg57m-...elf` | U-Boot recipe | U-Boot ELF, including symbols needed when reconstructing a PDI. |
| `system.dtb` | `versal-iwg57m-system-<timestamp>.dtb` | Device-tree recipe | Final Linux hardware description. |
| `Image` | `Image-...-<timestamp>.bin` | Linux recipe | Uncompressed AArch64 kernel. |
| `petalinux-image-minimal-versal-iwg57m.cpio.gz` | `...-<timestamp>.cpio.gz` | Image recipe | Compressed initramfs payload. |
| `petalinux-image-minimal-versal-iwg57m.cpio.gz.u-boot` | `...-<timestamp>.cpio.gz.u-boot` | Image recipe | Legacy U-Boot-wrapped initramfs used by component boot paths. |
| `uboot-env.txt` | no timestamped variant in this recipe | `uboot-env` recipe | Human-readable initial variables. |
| `uboot.env` | no timestamped variant in this recipe | `uboot-env` recipe | Checksummed binary environment image. |
| `petalinux-image-minimal-versal-iwg57m.wic` | `...-<timestamp>.wic` | Image recipe | Optional complete SD-card image. |

The handoff DTB and `base-design.pdi` used to reconstruct a custom PDI may be found in `boot.bin-extracted/` after an extraction workflow. They are not interchangeable with the final Linux `system.dtb`.

## What this page does not build

The following are later, host-side workflow outputs rather than guaranteed products of `./build-image.sh`:

- a FIT `image.ub` assembled from `Image`, `system.dtb`, and an initramfs;
- `boot.cmd` and its `mkimage`-wrapped `boot.scr`;
- `qspi-boot.cmd`, `qspi-boot.scr`, or provisioning scripts;
- a reconstructed temporary JTAG PDI and its XSDB TCL file;
- a generated QSPI layout JSON or custom-PLM `BOOT.bin`.

Some of these names may already exist in the deploy directory after another tool has run. Their presence alone does not prove the current BitBake invocation produced them. Check timestamps and preserve the command log with the artifact.

## Verify the build

Confirm that the stable links resolve and the custom packages reached the image manifest:

```bash
DEPLOY=build/tmp/deploy/images/versal-iwg57m

readlink -f "$DEPLOY/boot.bin"
readlink -f "$DEPLOY/Image"
readlink -f "$DEPLOY/system.dtb"
readlink -f "$DEPLOY/petalinux-image-minimal-versal-iwg57m.cpio.gz"

grep -E '^(bootscript|network-fallback|kernel-modules) ' \
  "$DEPLOY/petalinux-image-minimal-versal-iwg57m.manifest"
```

Record the XSA checksum, resolved timestamped artifact names, and build log with the test result. That turns a future boot failure into a comparison against a known build rather than simply “the 2025.2 image.”
