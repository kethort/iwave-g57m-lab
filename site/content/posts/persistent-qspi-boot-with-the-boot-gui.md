+++
title = "Experiment 006: Persistent QSPI Boot with the Boot GUI"
experiment = 6
date = 2026-09-22T00:00:00-07:00
description = "Provision the G57M QSPI flash so the board boots without JTAG, TFTP, or NFS after power-up."
tags = ["QSPI", "U-Boot", "MTD", "Bootgen", "Boot GUI"]
categories = ["Board Bring-Up"]
+++

This experiment moves from development boot flows into a persistent boot flow. The previous JTAG, TFTP, and NFS experiments were intentionally temporary: they were excellent for testing firmware, network settings, kernels, device trees, and userspace without committing those changes to flash. QSPI boot is different. It is the path to use when the board should power on, read its boot image from flash, and start Linux without the host pushing new payloads every time.

That makes QSPI useful for demos, regression baselines, handoff images, and bring-up checkpoints. It is not the fastest edit-test loop. If kernel, DTB, or userspace changes are still happening every few minutes, TFTP or NFS remains the better development workflow.

## What Changes In QSPI Boot

In the JTAG-assisted network flows, the GUI generated a `boot.cmd`, compiled it to `boot.scr`, loaded that script into RAM, and let U-Boot fetch payloads from the host. Nothing persisted after reset unless a separate flash operation was performed.

In the QSPI flow, the GUI still uses temporary JTAG to start a provisioning session, but the end result is persistent flash content:

{{< mermaid >}}
flowchart TD
    HOST[Host artifacts] --> BOOT[Permanent BOOT.bin]
    HOST --> CMD[qspi-boot.cmd]
    CMD -->|mkimage -T script| SCR[qspi-boot.scr]
    HOST --> PAYLOADS[Image, system.dtb, rootfs]

    BOOT --> PROVISION[Temporary JTAG provisioning session]
    SCR --> PROVISION
    PAYLOADS --> PROVISION

    PROVISION -->|U-Boot sf erase/write/read| QSPI[QSPI flash partitions]
    QSPI -->|power cycle, SW4=QSPI| ROM[BootROM]
    ROM --> PLM[PLM from QSPI BOOT.bin]
    PLM --> UBOOT[U-Boot from QSPI BOOT.bin]
    UBOOT -->|sf read or qspiboot env| LINUX[Linux from QSPI payload partitions]
{{< /mermaid >}}

After provisioning, power the carrier off, set SW4 for **QSPI**, and power the carrier back on. At that point the normal boot source is QSPI. JTAG is no longer part of the boot path unless you deliberately return to a JTAG mode.

The switch table is in the [reference page]({{< ref "/reference#sw4-boot-selection" >}}).

## Device Tree Requirement

QSPI provisioning only works if the temporary U-Boot can see the QSPI controller and SPI-NOR flash. That depends on the **handoff DTB used by the temporary JTAG-booted U-Boot**, not just the Linux `system.dtb` that Linux eventually boots with.

The U-Boot handoff DTB needs the board-appropriate QSPI controller node, enabled status, clocks, pinctrl, chip select, bus width, flash compatible string, flash frequency, and stacked or parallel topology. The U-Boot build also needs SPI controller, SPI flash, MTD, and `sf` command support.

Before any destructive flash operation, stop at U-Boot and verify the flash:

```text
dm tree
mtd list
sf probe
```

`sf probe` is the gate. If U-Boot cannot probe the flash, offsets and partition calculations do not matter yet. Fix the handoff DTB or U-Boot driver configuration before erasing or writing QSPI.

## Files Used

The QSPI flow uses several different files that are easy to confuse:

| File | Purpose | Persistent? |
| --- | --- | --- |
| `BOOT.bin` or `BOOT-custom-plm.bin` | Versal boot image at QSPI offset `0x0`. Contains boot firmware such as PLM, PSM, TF-A, and U-Boot according to the source BIF. | Yes |
| `qspi-boot.cmd` | Human-readable U-Boot commands for booting Linux payloads from QSPI. | Source artifact |
| `qspi-boot.scr` | `mkimage`-wrapped version of `qspi-boot.cmd`. Can be stored in the QSPI script slot. | Yes |
| `provision-qspi.cmd` | Human-readable one-time provisioning script. | Temporary |
| `provision-qspi.scr` | `mkimage`-wrapped provisioning script loaded by the temporary JTAG PDI. | Temporary |
| `Image` | Linux kernel payload. | Yes |
| `system.dtb` | Linux device tree payload. | Yes |
| rootfs/initramfs image | Userspace payload used by the persistent boot command. | Yes |
| `qspi.env` or exported environment | Persistent U-Boot variables such as `modeboot=qspiboot` and payload offsets. | Yes |

`bootgen` builds Versal boot images and temporary PDIs. `mkimage` builds U-Boot script images and FIT images. U-Boot `sf` commands perform the all-partitions write in the JTAG-assisted provisioning flow. Direct host-side flash operations use `program_flash`.

## BOOT Image And Custom PLM

The permanent QSPI boot image is the file written at offset `0x00000000`. If a custom PLM is selected, the GUI builds a custom BOOT image by starting from the Yocto-extracted BIF and substituting the selected `plm.elf`.

That custom PLM is baked into the resulting `BOOT-custom-plm.bin`. Changing the PLM later requires regenerating and reflashing the BOOT image. Selecting a custom PLM in a JTAG-only workflow does not automatically change the QSPI BOOT image.

## QSPI Partition Layout

The lab layout is a separate-component layout. U-Boot does not need one giant `image.ub` for this path. It reads the kernel, DTB, and rootfs from separate QSPI byte ranges.

The currently validated 256 MiB map is:

| QSPI content | Offset | Slot size |
| --- | --- | --- |
| Permanent `BOOT.bin` | `0x00000000` | `0x00a00000` |
| U-Boot environment | `0x00a00000` | `0x00010000` |
| Linux DTB | `0x00a20000` | `0x00060000` |
| Kernel `Image` | `0x00a80000` | `0x02600000` |
| Rootfs/initramfs | `0x03080000` | `0x0cf00000` |
| Permanent `qspi-boot.scr` | `0x0ff80000` | `0x00080000` |

The Linux-visible MTD table may name only the main content partitions:

| MTD name | Range |
| --- | --- |
| `BOOT.bin` | `0x00000000` through `0x009fffff` |
| `env` | `0x00a00000` through `0x00a1ffff` |
| `dtb` | `0x00a20000` through `0x00a7ffff` |
| `Image` | `0x00a80000` through `0x0307ffff` |
| `rootfs.cpio.gz.u-boot` | `0x03080000` through `0x0ff7ffff` |

The script slot at `0x0ff80000` may be a raw numeric range rather than a named Linux MTD partition. That is still usable by U-Boot because the generated scripts write and read by numeric offset.

## Why Layout Calculation Matters

Kernel and rootfs sizes change over time. A rootfs with more packages may outgrow the slot that worked last week. A smaller image may leave unused flash space that could be reclaimed. The QSPI layout generator exists to keep this mechanical sizing step repeatable.

The calculation uses:

| Input | Why it matters |
| --- | --- |
| QSPI capacity | Prevents the final partition from running past the physical device. |
| Erase size | Aligns offsets and slot sizes to erasable flash boundaries. |
| Payload file sizes | Determines the minimum space required for `BOOT.bin`, DTB, kernel, rootfs, and scripts. |
| Headroom percentage | Leaves growth room so a slightly larger future kernel or rootfs does not immediately require a new layout. |
| Reserved offsets | Keeps fixed boot and environment locations compatible with U-Boot and the board DT. |

The GUI's layout calculation should generate a new JSON configuration, such as `qspi_flash_config.generated.json`, and load it for review. It should not overwrite a known-good `qspi_config.json` unless that is an explicit save action. Review the generated offsets before provisioning.

The key rule is simple: erases use slot sizes, while writes use actual file sizes. A slot can be larger than the payload it contains, but a payload must never be larger than its slot.

## Provisioning Sequence

Use **PS JTAG** mode for provisioning because the host must temporarily start U-Boot and run the provisioning script.

1. Power off the carrier.
2. Set SW4 to **PS JTAG**.
3. Power on the carrier and open the serial console.
4. Open the Boot GUI **QSPI Provisioning** tab.
5. Load the QSPI JSON configuration.
6. Select or generate the QSPI BOOT image, including the QSPI custom PLM if needed.
7. Confirm the explicit PDI inputs: base design PDI, PLM, PSM, TF-A, U-Boot, and handoff DTB.
8. Confirm Linux payloads: `Image`, `system.dtb`, and rootfs.
9. Run layout calculation or validation and inspect the offsets.
10. Run the complete QSPI provisioning action.

The complete action builds or selects the permanent BOOT image, builds the temporary provisioning PDI, starts U-Boot over JTAG, TFTP-downloads the payloads, probes QSPI, erases and writes each slot, reads back payloads, checks CRCs, writes the persistent environment, and resets the board.

The provisioning script writes `BOOT.bin` last. That reduces the chance that an earlier failed Linux payload write destroys the previously bootable image at offset `0x0`.

For the lighter **QSPI boot install from JTAG TFTP config** path, the GUI output begins by building the custom BOOT image, generating the normal JTAG TFTP script, staging `image.ub`, and then invoking `program_flash` for the QSPI BOOT slot:

```text
[HOST] Starting QSPI boot install from JTAG TFTP config
Generated custom bootgen BIF: /work/output/bootgen-custom-plm.bif
[INFO]   : Bootimage generated successfully
Generated custom QSPI BOOT image: /work/output/BOOT-custom-plm.bin
Boot mode must remain JTAG TFTP for this install: JTAG TFTP
BOOT image to flash   : /work/output/BOOT-custom-plm.bin
QSPI flash offset     : 0x00000000
QSPI script offset    : 0x0ff80000
QSPI flash type       : qspi-x4-dual_stacked
Flash QSPI boot.scr   : yes
Writing boot.cmd
Compiling boot.scr with mkimage
Running mkimage -A arm64 -T script -C none -n JTAG TFTP boot -d /work/output/boot.cmd /work/output/boot.scr
TFTP copy complete (FIT): /srv/tftp/image.ub
Flashing BOOT/U-Boot image to QSPI.
Running program_flash -f /work/output/BOOT-custom-plm.bin -offset 0x00000000 -flash_type qspi-x4-dual_stacked -pdi /work/output/BOOT-custom-plm.bin -url TCP:127.0.0.1:3121
```

`program_flash` starts a mini U-Boot image internally and probes the flash before writing:

```text
****** Program Flash v2025.2 (64-bit)
Connected to hw_server @ TCP:127.0.0.1:3121
Using default mini u-boot image file - /development/2025.2/data/xicom/cfgmem/uboot/versal_qspi_x4_dual_stacked_2048.bin
Versal> sf probe 0 0 0
SF: Detected mt25qu02g with page size 256 Bytes, erase size 64 KiB
Sector size = 65536.
```

This log proves the host-side flash tool connected through `hw_server`, selected the Versal QSPI mini U-Boot, and saw the SPI-NOR device before programming. It is still only a provisioning step. It does not prove that the board will boot from QSPI until the board is powered down and restarted with the QSPI boot-mode switches selected.

> **Required mode change after flashing:** when the QSPI flash operation finishes successfully, power the carrier off. Set SW4 to **QSPI** using the [SW4 boot selection table]({{< ref "/reference#sw4-boot-selection" >}}). Then power the carrier back on and watch the serial console. Leaving SW4 in **PS JTAG** will continue to select JTAG boot, even though QSPI now contains a bootable image.

## First Persistent Boot

After a successful provisioning run:

1. Wait for the flash operation and verification to finish.
2. Power the carrier off.
3. Set SW4 to **QSPI**.
4. Power the carrier on.
5. Watch the serial console.

The expected boot source changes from JTAG to QSPI. U-Boot should load its persistent environment and select the QSPI boot path. The board should not need the GUI, TFTP server, NFS export, or JTAG after this point.

The first successful QSPI boot should make the mode change visible in the serial log:

```text
Loading Environment from SPIFlash... SF: Detected mt25qu02g with page size 256 Bytes, erase size 64 KiB, total 256 MiB
OK
Bootmode: QSPI_MODE_32
```

For the separate-component QSPI layout, U-Boot then reads the Linux payloads from the programmed offsets:

```text
SF: Detected mt25qu02g with page size 256 Bytes, erase size 64 KiB, total 256 MiB
device 0 offset 0xa20000, size 0x9474
SF: 38004 bytes @ 0xa20000 Read: OK
device 0 offset 0xa80000, size 0x1e80200
SF: 31982080 bytes @ 0xa80000 Read: OK
device 0 offset 0x3080000, size 0xaeda7fa
SF: 183347194 bytes @ 0x3080000 Read: OK
## Flattened Device Tree blob at 40000000
Starting kernel ...
[    0.000000] Kernel command line: console=ttyAMA0,115200 earlycon=pl011,mmio32,0xff000000 clk_ignore_unused ignore_loglevel loglevel=8 rdinit=/init
```

The key difference from the JTAG/TFTP/NFS experiments is absence of host-side payload transfer. U-Boot is reading kernel, DTB, and rootfs bytes from QSPI flash with `sf read`.

Useful U-Boot checks are:

```text
printenv bootcmd modeboot qspiboot
printenv qspi_kernel_offset qspi_dtb_offset qspi_rootfs_offset
sf probe
mtd list
```

Useful Linux checks are:

```bash
cat /proc/cmdline
cat /proc/mtd
dmesg | grep -Ei 'qspi|spi-nor|mtd'
findmnt /
```

## What Success Means

QSPI success is not just "the flash operation completed." The stronger success criteria are:

| Evidence | Meaning |
| --- | --- |
| `sf probe` detects the expected SPI-NOR capacity | U-Boot sees the QSPI hardware described by the handoff DTB. |
| Provisioning readback CRCs match | The written QSPI bytes match the downloaded payloads. |
| `modeboot=qspiboot` or equivalent boot command is active | Reset will select the persistent QSPI path. |
| SW4 set to QSPI boots without GUI/JTAG/TFTP/NFS | The image is self-contained enough for normal power-on boot. |
| Linux reaches login and `/proc/mtd` matches the expected layout | The Linux DT and persistent flash layout agree. |

At that point, the board has moved out of the rapid development path and into a reproducible persistent boot baseline.

## Failure Boundaries

| Symptom | Likely boundary |
| --- | --- |
| `sf probe` fails during provisioning | Handoff DTB, U-Boot SPI flash support, flash topology, chip select, or pinmux. |
| TFTP succeeds but QSPI write fails | Flash probe, erase alignment, locked/protected sectors, or wrong flash type. |
| CRC readback fails | Bad offset, overlap, unstable flash access, or wrong downloaded file size. |
| QSPI boot starts but loads the wrong mode | Persistent environment did not get written or U-Boot is reading environment from a different offset/backend. |
| Linux boots but MTD layout is wrong | Linux `system.dtb` partition table does not match the provisioned layout. |
| Linux kernel panics mounting root | `bootargs`, rootfs payload type, rootfs size, or `booti` ramdisk argument mismatch. |

Do not debug these as one large "QSPI failed" problem. First prove U-Boot can see the flash, then prove the bytes were written, then prove the saved environment selects the correct boot command, and only then debug the Linux handoff.

## Next Experiment

After the board can boot persistently from QSPI, the next step is to let Linux manage the RPU firmware with `remoteproc` and then attach the debugger to both the running RPU firmware and the PLM/PPU user module.

[Continue to Experiment 007: Deploying RPU Firmware with remoteproc and Debugging PPU/RPU ->]({{< ref "/posts/deploying-rpu-firmware-with-remoteproc-and-debugging-ppu-rpu" >}})
