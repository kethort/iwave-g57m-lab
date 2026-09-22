+++
title = "Experiment 001: Building the iWave PetaLinux Baseline"
date = 2026-09-21T00:00:00-07:00
description = "Rebuild the G57M boot firmware, U-Boot, Linux, device tree, and root filesystem from the iWave Yocto BSP, then identify the artifacts used by every boot flow."
tags = ["PetaLinux", "Yocto", "BitBake", "iWave", "Build"]
categories = ["Board Bring-Up"]
+++

The first experiment is deliberately a software build. Before changing PLM behavior, attaching an FMC card, or writing QSPI, we need a reproducible set of boot artifacts derived from the iWave G57M baseline.

This workspace uses the **Yocto form of PetaLinux**, not a classic `project-spec` project. PetaLinux supplies the distribution and AMD layers, while BitBake performs the build. The correct top-level target is therefore:

```bash
bitbake petalinux-image-minimal
```

There is no `petalinux-build` or `petalinux-config` step in this particular BSP layout.

## Inputs and boundaries

The working baseline is:

| Input | Value |
| --- | --- |
| Board | iWave G57M VE2302 SOM on G57D R2.0 carrier |
| Vendor BSP layer | `sources/meta-iwave` |
| Machine | `versal-iwg57m` |
| Distribution | `petalinux` with systemd |
| AMD tools | Vitis 2025.2 |
| Image target | `petalinux-image-minimal` |
| Hardware description | `sources/meta-iwave/recipes-bsp/hw-description/system.xsa` |

Obtain the matching BSP and board documentation from iWave rather than copying a machine configuration from a different carrier revision. The [iWave platform guide](https://iwave-global.com/knowledge-base/products/get-started-with-versal-ai-edge-prime-som-development-platform/) remains the hardware starting point.

The vendor patches, XSA, and generated firmware are not reproduced on this website. The notes below describe the layer structure and local configuration deltas.

## How the layer is selected

The setup script points `TEMPLATECONF` at iWave's template and then enters the OpenEmbedded environment:

```bash
export TEMPLATECONF="${ROOT}/sources/meta-iwave/conf/templates/iwg57m"
source "${ROOT}/sources/poky/oe-init-build-env" build
```

That template adds `meta-iwave` to `BBLAYERS`. The resulting `build/conf/local.conf` selects:

```bitbake
MACHINE ??= "versal-iwg57m"
DISTRO ?= "petalinux"
```

Keep board behavior in `meta-iwave`; do not make lasting changes under `build/tmp`. The latter is generated state and can disappear after a clean build.

## Recipes that define this image

### Machine and root filesystem

`conf/machine/versal-iwg57m.conf` connects the machine to its XSA, serial console, U-Boot defconfig, kernel defconfig, image packages, and deploy-time dependencies.

The current root filesystem extends the iWave package list with:

```bitbake
IMAGE_INSTALL:append = " kernel-modules network-fallback "
EXTRA_IMAGEDEPENDS:append = " uboot-env"
```

The complete vendor list also includes tools used during bring-up, including `i2c-tools`, `mtd-utils`, `ethtool`, `nfs-utils`, `u-boot-tools`, `can-utils`, `iperf3`, and the iWave `bootscript` service.

### U-Boot

`recipes-bsp/u-boot/u-boot-xlnx_%.bbappend` applies the iWave base patch and the lab's automatic boot-method patch. The latter adds named U-Boot flows for:

- separate-component TFTP boot;
- TFTP kernel and DTB with an NFS root filesystem;
- FIT boot from TFTP;
- JTAG-loaded FIT boot with a TFTP fallback;
- QSPI `boot.scr` execution with component fallback.

The accompanying `versal_iwg57m.cfg` enables the commands those flows require, including networking, NFS, FIT, SPI flash, MTD, I2C, FRU, and `source` support.

### Persistent U-Boot environment

`recipes-bsp/uboot-env/uboot-env.bb` generates both a readable `uboot-env.txt` and a binary `uboot.env` with `mkenvimage`. It supplies `ethact`, `serverip`, `ipaddr`, `netmask`, the FIT load address, and the default `modeboot` command.

> **Configuration check:** `UBOOT_ENV_SIZE` must match `CONFIG_ENV_SIZE`. The current machine override is `0x8000`, while `versal_iwg57m.cfg` specifies `0x10000`. Align these values before using the generated environment as a production QSPI artifact. The current deployed `uboot.env` is 32 KiB because the machine override wins.

### Linux and device tree

`recipes-kernel/linux/linux-xlnx_%.bbappend` applies the iWave kernel baseline and machine fragments. The current local fragment builds the Versal R5 remoteproc and core RPMsg support into the kernel so the later RPU experiment has deterministic early driver availability.

`recipes-bsp/device-tree/device-tree.bbappend` includes `system-user.dtsi`. The iWave baseline defines carrier Ethernet, I2C, QSPI, FMC VADJ, PMIC rails, USB, storage, and board identity. The current additions reserve RPU firmware and vring memory, describe the R5 subsystem and IPI mailboxes, and retain the QSPI partition layout used by provisioning.

### Root filesystem services

The `bootscript` recipe installs a one-shot systemd service that applies the console log level, timezone, and displayed BSP version.

The `network-fallback` recipe installs a bounded DHCP attempt followed by a static fallback. Its current defaults target `end1` and use `192.168.0.137/24` only when DHCP does not provide an address.

## Build from the workspace root

The checked-in wrapper performs the environment setup consistently:

```bash
cd /development/xilinx-dev/iwg57m-2025-2
export VITIS_SETTINGS=/development/2025.2/Vitis/settings64.sh
./build-image.sh
```

Internally it:

1. sources the Vitis 2025.2 environment;
2. clears `DISPLAY` so XSCT runs non-interactively;
3. sources `setupsdk build`;
4. runs `bitbake petalinux-image-minimal`.

For an interactive build shell, run the equivalent setup manually:

```bash
source /development/2025.2/Vitis/settings64.sh
source ./setupsdk build
bitbake petalinux-image-minimal
```

Do not run the two builds simultaneously against the same `build/tmp` directory.

## Required deploy artifacts

Successful output appears under:

```text
build/tmp/deploy/images/versal-iwg57m/
```

Use the stable symlink names rather than timestamped filenames:

| Artifact | Producer and purpose |
| --- | --- |
| `boot.bin` | Bootgen output containing the normal Versal boot firmware chain |
| `plm-versal-iwg57m.elf` | PLM built from the selected XSA and machine configuration |
| `psm-firmware-versal-iwg57m.elf` | PSM firmware |
| `arm-trusted-firmware.elf` | TF-A / BL31 |
| `u-boot.elf` | U-Boot used for reconstructed JTAG PDIs |
| `system.dtb` | Final Linux device tree from the generated tree plus `system-user.dtsi` |
| `Image` | AArch64 Linux kernel |
| `petalinux-image-minimal-versal-iwg57m.cpio.gz` | Compressed initramfs payload |
| `petalinux-image-minimal-versal-iwg57m.cpio.gz.u-boot` | Legacy-image-wrapped initramfs for component boot |
| `uboot-env.txt` and `uboot.env` | Generated readable and binary U-Boot environments |
| `*.wic` | Complete SD-card image |

`image.ub` is not produced by the wrapper shown above. In this lab it is assembled later from `Image`, `system.dtb`, and the compressed root filesystem by the Boot GUI or an equivalent `mkimage` step. Keep that distinction visible when diagnosing stale files.

## Verify the result before booting

Confirm that the expected symlinks resolve and that the custom packages reached the image manifest:

```bash
DEPLOY=build/tmp/deploy/images/versal-iwg57m

readlink -f "$DEPLOY/boot.bin"
readlink -f "$DEPLOY/Image"
readlink -f "$DEPLOY/system.dtb"
readlink -f "$DEPLOY/petalinux-image-minimal-versal-iwg57m.cpio.gz"

grep -E '^(bootscript|network-fallback|kernel-modules) ' \
  "$DEPLOY/petalinux-image-minimal-versal-iwg57m.manifest"
```

Expected package evidence includes `bootscript`, `network-fallback`, and `kernel-modules`. Also record the XSA checksum and the resolved artifact names with the test log; that makes a later boot failure traceable to an exact build rather than simply “the 2025.2 image.”

## Hand-off to the Boot GUI

With these files built, the GUI can consume them without inventing firmware:

- JTAG TFTP and NFS use `boot.bin`, `Image`, `system.dtb`, and the selected root filesystem strategy.
- Full JTAG PDI reconstruction uses the base PDI, PLM, PSM, TF-A, U-Boot ELF, and handoff DTB extracted from or built alongside `boot.bin`.
- QSPI provisioning uses the boot image plus separate kernel, DTB, rootfs, environment, and script artifacts according to the configured partition map.

Only after this build is repeatable do we move on to the physical FMC experiment.
