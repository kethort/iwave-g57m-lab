+++
title = "Experiment 001: Building the iWave PetaLinux Baseline"
date = 2026-09-20T00:00:00-07:00
description = "Reproduce the G57M boot firmware, U-Boot, Linux, device tree, root filesystem, and deploy artifacts from the iWave Yocto BSP."
tags = ["PetaLinux", "Yocto", "BitBake", "iWave", "Build"]
categories = ["Board Bring-Up"]
+++

This experiment establishes a reproducible software baseline for the iWave G57M VE2302 SOM and G57D R2.0 carrier. Its scope is deliberately narrow: understand the local layer, build it, and prove that the expected deploy artifacts were produced.

This workspace uses the **Yocto form of PetaLinux**, not a classic PetaLinux `project-spec` workflow. PetaLinux supplies the distribution and AMD layers, while BitBake performs the build. There is no `petalinux-build` or `petalinux-config` step in this BSP layout.

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
