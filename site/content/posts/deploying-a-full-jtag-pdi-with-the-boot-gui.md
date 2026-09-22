+++
title = "Experiment 002: Deploying a Full JTAG PDI with the Boot GUI"
date = 2026-09-21T00:00:00-07:00
description = "Package the Versal firmware chain and Linux FIT into a temporary PDI, then load and boot it over JTAG with Bootgen, XSDB, and the Versal Boot GUI."
tags = ["JTAG", "PDI", "Bootgen", "XSDB", "Qt"]
categories = ["Board Bring-Up"]
+++

This experiment boots a complete Linux system over JTAG without writing QSPI. The Versal Boot GUI combines the firmware chain, U-Boot, a generated U-Boot script, and a Linux FIT into one temporary PDI. Bootgen packages the PDI; XSDB transfers it to the board through `hw_server`.

{{< lab-figure src="images/jtag-boot-flow.png" alt="Full JTAG PDI generation and boot flow" >}}

Everything loaded by this flow is volatile. Resetting or removing power discards it. This operation does **not** erase, write, or otherwise provision QSPI.

## What the GUI needs

Open **JTAG Modes** and select `jtag-full-pdi`. Load `jtag_config.json`, then verify the paths rather than assuming that a previously saved host or container path is still valid.

### Linux payload

Provide either an existing FIT in **FIT / image.ub**, or all three source files required to generate one:

| Field | Typical build artifact | Role |
| --- | --- | --- |
| Kernel Image | `build/tmp/deploy/images/versal-iwg57m/Image` | AArch64 Linux kernel. |
| Linux DTB | `build/tmp/deploy/images/versal-iwg57m/system.dtb` | Device tree passed to Linux. |
| Rootfs | `petalinux-image-minimal-versal-iwg57m.cpio.gz` | Initramfs included in the FIT. |
| FIT / image.ub | Existing or generated `image.ub` | Container consumed by U-Boot `bootm`. |

The Linux DTB is not the same file as the handoff DTB used in the firmware/U-Boot partition of the PDI.

### Reconstructed PDI inputs

Under **Reconstructed PDI Inputs**, supply:

| GUI field | Typical source | Purpose |
| --- | --- | --- |
| Base design PDI | `boot.bin-extracted/base-design.pdi` | Platform and programmable-device boot data. |
| JTAG reconstructed-PDI PLM ELF | `plmfw.elf`, `plm.elf`, or a compatible custom PLM | PLM used only in this temporary JTAG PDI. |
| PSM firmware | `boot.bin-extracted/psmfw.elf` | PSM firmware. |
| ATF / BL31 | `boot.bin-extracted/arm-trusted-firmware.elf` | Trusted Firmware-A at EL3. |
| U-Boot ELF | `boot.bin-extracted/u-boot.elf` | U-Boot at EL2. |
| Handoff DTB | `boot.bin-extracted/system-top.dtb` | Hardware handoff used by firmware and U-Boot. |

Selecting a custom PLM here changes only the reconstructed JTAG PDI. It does not modify `boot.bin` and does not persist that PLM in QSPI.

When these fields are blank, the GUI searches beside **Boot image** and under its neighboring `boot.bin-extracted` directory. Explicit paths are easier to audit and avoid selecting an unintended similarly named file.

## Addresses and outputs

Set a writable **Output directory** and verify these values:

| Setting | Normal value | Meaning |
| --- | --- | --- |
| Full-PDI `image.ub` address | `0x802000000` | RAM address where Bootgen places the FIT and U-Boot expects it. |
| Boot script address | `0x20000000` | Fixed address used by the generated BIF for `boot.scr`. |
| JTAG PDI output | `<output>/BOOT_JTAG_IMAGEUB.pdi` | Temporary PDI programmed by XSDB. |
| XSDB script output | `<output>/jtag_boot_generated.tcl` | Generated connection, reset, and program commands. |

Do not substitute the JTAG TFTP FIT address `0x08000000` for the Full-PDI address. The BIF load address and the address in `boot.scr` must agree, and the region must not overlap another payload or runtime allocation.

## What is generated

### FIT image

If `image.ub` is missing, the GUI writes an ITS that defines kernel, Linux DTB, and gzip-compressed ramdisk nodes, then runs:

```bash
mkimage -f image.ub.its image.ub
```

The ITS defines the contents and hashes inside the FIT. It does not define the Versal PDI layout or QSPI partition offsets.

### U-Boot script

The GUI first writes readable commands to `boot.cmd`. For Full JTAG PDI mode, the essential logic is:

```text
setenv fit_addr_r 0x802000000
setenv bootargs '<configured Linux command line>'
if iminfo ${fit_addr_r}; then
    bootm ${fit_addr_r}
else
    echo No valid FIT image in RAM, falling back to TFTP...
    tftpboot ${fit_addr_r} ${serverip}:image.ub && bootm ${fit_addr_r}
fi
```

It wraps those commands in a checksummed legacy U-Boot script image:

```bash
mkimage -A arm64 -T script -C none \
  -n "Full JTAG PDI boot" -d boot.cmd boot.scr
```

U-Boot's `source` command expects the `.scr` image header and checksum. The `.cmd` file remains the human-readable source; `.scr` is not a new U-Boot binary.

### Versal PDI

The GUI writes `jtag_boot_gui.bif`. Its logical partition layout is:

```text
image 0: base-design.pdi, PLM, PSM
image 1: handoff DTB at 0x1000
         TF-A / BL31 on A72-0 at EL3
         U-Boot on A72-0 at EL2
         boot.scr at 0x20000000
         image.ub at 0x802000000
```

It then invokes:

```bash
bootgen -arch versal \
  -image <output>/jtag_boot_gui.bif \
  -w -o <output>/BOOT_JTAG_IMAGEUB.pdi
```

Bootgen creates PDI headers and packages the BIF entries. It does not communicate with the target and does not choose the paths or addresses independently.

### XSDB program step

The generated TCL performs the equivalent of:

```tcl
connect -url {TCP:127.0.0.1:3121}
targets -set -nocase -filter {name =~ "*PMC*"}
rst -system
after 3000
device program "<output>/BOOT_JTAG_IMAGEUB.pdi"
```

XSDB is the tool that transfers the PDI. `hw_server` owns target discovery and the physical JTAG connection.

## Run the flow

1. Set the carrier switches for JTAG boot before power-up and connect the onboard debug/JTAG cable.
2. Open a 115200 8N1 serial console so PLM and U-Boot output are visible.
3. Start `hw_server` or verify that the GUI/container can reach the configured server URL.
4. In **JTAG Modes**, select `jtag-full-pdi` and verify every path and address.
5. Optionally select **Generate JTAG artifacts** to inspect `boot.cmd` and `boot.scr` without touching the target.
6. Select **Run selected JTAG flow**. The GUI moves to **Preview & Logs**, generates the FIT and PDI as needed, writes the XSDB script, and runs XSDB.

The UART console may remain open while XSDB uses JTAG. A serial terminal such as Minicom does not normally own the JTAG interface.

## Expected evidence

The GUI log should show, in order:

```text
Full PDI selected; skipping TFTP staging.
Writing BIF: .../jtag_boot_gui.bif
Building PDI with bootgen
bootgen complete: .../BOOT_JTAG_IMAGEUB.pdi
Programming PDI with xsdb
xsdb complete
```

The target console should show the PLM and firmware banners, U-Boot startup, and then:

```text
JTAG: Trying to boot script at 20000000
JTAG booting FIT image from RAM at 0x802000000...
## Checking Image at 802000000 ...
```

A valid FIT proceeds through `bootm` into Linux. If the log says **falling back to TFTP**, the Full-PDI result is not correct: `iminfo` did not find a valid FIT at the configured RAM address.

## Troubleshooting boundaries

| Symptom | Check |
| --- | --- |
| `Connection refused` | Nothing is accepting connections at the configured `hw_server` URL. |
| `available targets: none` | `hw_server` is reachable, but it cannot enumerate the JTAG chain; check cable, power, switch position, permissions, and any FMC JTAG path. |
| Missing PDI component | Set every reconstructed input explicitly or inspect `boot.bin-extracted`. |
| Bootgen failure | Inspect `jtag_boot_gui.bif`, file paths, and Bootgen output in **Preview & Logs**. |
| TFTP fallback | Confirm the BIF contains `image.ub`, the BIF and script use the same address, and `mkimage -l image.ub` recognizes the FIT. |
| Linux panic after `bootm` | The JTAG transport succeeded; inspect FIT contents, DTB, kernel arguments, and rootfs instead. |

For a non-destructive host-side connection check, run `./diagnose-jtag.sh`. It tests the Vitis tools, TCP port 3121, target listing, and PMC selection without programming the board.
