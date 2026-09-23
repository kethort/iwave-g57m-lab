+++
title = "Experiment 005: Deploying Linux with TFTP and NFS"
experiment = 5
date = 2026-09-22T00:00:00-07:00
description = "Set up host TFTP and NFS services, boot the G57M over the network, and configure U-Boot so FIT, component TFTP, or NFS-root flows can run automatically."
tags = ["TFTP", "NFS", "U-Boot", "PetaLinux", "Networking"]
categories = ["Board Bring-Up"]
+++

This experiment turns the host into a network boot server for the iWave G57M. TFTP moves boot payloads into RAM; NFS lets Linux mount its root filesystem from the host. Together they make bring-up much faster than repeatedly rebuilding and reflashing QSPI or SD media.

There are two related workflows:

- **JTAG-assisted network boot:** the Boot GUI loads a temporary U-Boot session over JTAG, then U-Boot downloads the Linux payloads from the host.
- **Automatic U-Boot network boot:** the U-Boot environment selects a network boot command at reset, without the GUI loading a temporary script.

Both paths depend on the same network facts: the host IP, the board IP, the Ethernet device selected by U-Boot, the TFTP root, and, for NFS, an exported root filesystem.

## Why use each mode

| Mode | What moves over TFTP | Root filesystem | Best use |
| --- | --- | --- | --- |
| FIT TFTP | One `image.ub` FIT containing kernel, DTB, and initramfs | Initramfs inside the FIT | Fast, self-contained boot tests where one file represents the Linux payload. |
| Component TFTP | `Image`, `system.dtb`, and `rootfs.cpio.gz.u-boot` | Initramfs loaded into RAM | Debugging individual payloads without rebuilding a FIT. |
| TFTP + NFS root | `Image` and `system.dtb` | Host-exported directory mounted over NFS | Iterating on rootfs contents, services, scripts, and userspace without repackaging the rootfs. |

NFS is the most useful mode once the kernel and DTB are basically correct. For example, a systemd service can be edited under `/export/versal-rootfs`, the board can be rebooted, and the next Linux boot sees the change immediately. No `cpio.gz`, FIT, QSPI write, or SD-card update is required.

## Baseline network values

The examples below use the same values as the lab configuration:

| Setting | Value |
| --- | --- |
| Host interface IP | `192.168.1.10` |
| Board U-Boot IP | `192.168.1.20` |
| Netmask | `255.255.255.0` |
| U-Boot Ethernet device | `ethernet@ff0c0000` |
| TFTP root | `/srv/tftp` |
| NFS export | `/export/versal-rootfs` |
| NFS options in U-Boot | `tcp,v3` |

The host and board must be on the same L2 network for the simple static examples. If Linux later uses DHCP, that is separate from the static U-Boot network configuration used before the kernel starts.

## Host TFTP setup

Install and enable a TFTP server on the host. On Ubuntu-style hosts, the service package is commonly `tftpd-hpa`:

```bash
sudo apt install tftpd-hpa
sudo mkdir -p /srv/tftp
sudo chmod 755 /srv/tftp
```

Stage the files expected by each boot mode:

```bash
DEPLOY=/development/xilinx-dev/iwg57m-2025-2/build/tmp/deploy/images/versal-iwg57m

sudo cp "$DEPLOY/image.ub" /srv/tftp/image.ub
sudo cp "$DEPLOY/Image" /srv/tftp/Image
sudo cp "$DEPLOY/system.dtb" /srv/tftp/system.dtb
sudo cp "$DEPLOY/petalinux-image-minimal-versal-iwg57m.cpio.gz.u-boot" \
  /srv/tftp/rootfs.cpio.gz.u-boot
```

The Boot GUI can stage some of these files for JTAG TFTP and JTAG NFS flows. For persistent U-Boot network boot, it is still useful to know the exact filenames because U-Boot is literal: `fit_file=image.ub`, `kernel_file=Image`, and `fdt_file=system.dtb` must match the TFTP root.

From the U-Boot prompt, a quick TFTP test is:

```text
setenv ethact ethernet@ff0c0000
setenv serverip 192.168.1.10
setenv ipaddr 192.168.1.20
ping ${serverip}
tftpboot ${fdt_addr_r} ${serverip}:system.dtb
```

If `ping` works but `tftpboot` fails, check the host firewall, TFTP service status, file permissions, and the exact filename.

## Host NFS setup

NFS-root boot needs an unpacked root filesystem, not the compressed rootfs image itself. One common setup is:

```bash
sudo apt install nfs-kernel-server
sudo mkdir -p /export/versal-rootfs
```

Unpack the rootfs as root so device nodes, ownership, and permissions survive:

```bash
DEPLOY=/development/xilinx-dev/iwg57m-2025-2/build/tmp/deploy/images/versal-iwg57m

sudo tar -C /export/versal-rootfs -xf \
  "$DEPLOY/petalinux-image-minimal-versal-iwg57m.tar.gz"
```

If the deploy directory only contains a `cpio.gz`, unpack it with:

```bash
sudo sh -c "cd /export/versal-rootfs && gzip -dc '$DEPLOY/petalinux-image-minimal-versal-iwg57m.cpio.gz' | cpio -idmv"
```

Export the directory to the board subnet:

```text
/export/versal-rootfs 192.168.1.0/24(rw,sync,no_subtree_check,no_root_squash)
```

Put that line in `/etc/exports`, then reload:

```bash
sudo exportfs -ra
sudo exportfs -v
```

The `no_root_squash` option is convenient for an embedded development rootfs because the target boots as root and needs normal root permissions inside the export. Do not use that casually on an untrusted network.

## Boot with the GUI

For **JTAG TFTP**, open **JTAG Modes**, select `jtag-tftp`, and provide either:

- `image.ub`; or
- `Image`, `system.dtb`, and the compressed rootfs so the GUI can generate `image.ub`.

The generated script performs the essential U-Boot operation:

```text
tftpboot ${fit_addr_r} ${serverip}:image.ub
bootm ${fit_addr_r}
```

For **JTAG NFS**, select `jtag-nfs` and provide:

- `Image`;
- Linux `system.dtb`;
- TFTP root;
- host `serverip`, board `ipaddr`, `netmask`, `ethact`;
- `nfsroot=/export/versal-rootfs`;
- `nfs_options=tcp,v3`.

The generated script loads the kernel and DTB by TFTP, but does not load a ramdisk:

```text
tftpboot ${kernel_addr_r} ${serverip}:Image
tftpboot ${fdt_addr_r} ${serverip}:system.dtb
booti ${kernel_addr_r} - ${fdt_addr_r}
```

The dash in `booti` is intentional. It tells U-Boot there is no initramfs. Linux must mount its root filesystem through NFS using the kernel command line.

The corresponding kernel arguments include:

```text
root=/dev/nfs rw rootwait
nfsroot=192.168.1.10:/export/versal-rootfs,tcp,v3
ip=192.168.1.20:192.168.1.10:192.168.1.1:255.255.255.0:versal:eth0:off
```

If the kernel reaches `VFS: Cannot open root device` or tries `/dev/root`, inspect the printed `Kernel command line` first. That usually means the NFS `bootargs` did not reach Linux or the selected U-Boot command was not the NFS command.

## Automatic U-Boot boot modes

The lab U-Boot layer adds named boot commands so the board can boot over the network directly from U-Boot. The relevant files are:

| File | Role |
| --- | --- |
| `sources/meta-iwave/recipes-bsp/u-boot/u-boot-xlnx_%.bbappend` | Adds the iWave base patch, automatic boot-method patch, and board config fragment. |
| `sources/meta-iwave/recipes-bsp/u-boot/files/0002-iwg57m-automatic-boot-methods.patch` | Adds `netfitboot`, `nfsboot`, QSPI script fallback, filenames, and default network variables. |
| `sources/meta-iwave/recipes-bsp/u-boot/files/versal_iwg57m.cfg` | Enables U-Boot commands and sets `CONFIG_BOOTCOMMAND="run $modeboot"`. |

The important Kconfig settings include:

```text
CONFIG_BOOTCOMMAND="run $modeboot"
CONFIG_FIT=y
CONFIG_CMD_NFS=y
CONFIG_BOOTP_MAY_FAIL=y
CONFIG_CMD_TFTPPUT=y
CONFIG_TFTP_BLOCKSIZE=4096
CONFIG_ENV_SIZE=0x10000
CONFIG_ENV_OFFSET=0x00a00000
CONFIG_ENV_IS_IN_SPI_FLASH=y
```

The patch adds these network defaults and command targets:

```text
serverip=192.168.1.10
ipaddr=192.168.1.20
netmask=255.255.255.0
gatewayip=192.168.1.1
ethact=ethernet@ff0c0000
fit_file=image.ub
kernel_file=Image
fdt_file=system.dtb
nfsroot=/export/versal-rootfs
nfs_options=tcp,v3
```

To choose the automatic flow, set `modeboot`:

| `modeboot` value | Automatic behavior |
| --- | --- |
| `netfitboot` | TFTP `image.ub`, then `bootm ${fit_addr_r}`. |
| `tftpboot` | TFTP `system.dtb`, `Image`, and `rootfs.cpio.gz.u-boot`, then `booti`. |
| `nfsboot` | TFTP `Image` and `system.dtb`, then boot Linux with `root=/dev/nfs`. |
| `qspiboot` | Use the QSPI boot script or QSPI component fallback. This remains the persistent default for flashed systems. |

At a U-Boot prompt, the temporary test is:

```text
setenv modeboot nfsboot
run modeboot
```

For a persistent environment, save it only after confirming the command works:

```text
setenv modeboot nfsboot
setenv serverip 192.168.1.10
setenv ipaddr 192.168.1.20
setenv netmask 255.255.255.0
setenv gatewayip 192.168.1.1
setenv ethact ethernet@ff0c0000
setenv nfsroot /export/versal-rootfs
setenv nfs_options tcp,v3
saveenv
```

If the board is using a generated QSPI environment image instead of interactive `saveenv`, put the same values in the environment recipe or provisioning JSON and regenerate the environment artifact.

## NFS iteration example

One practical NFS loop is service development:

1. Boot once with `modeboot=nfsboot`.
2. Edit a file under the host export, for example `/export/versal-rootfs/etc/systemd/system/my-test.service`.
3. Reboot the board.
4. Watch the serial console or SSH into the target and run `systemctl status my-test.service`.

The kernel and DTB still come from TFTP, so kernel changes require replacing `/srv/tftp/Image` or `/srv/tftp/system.dtb`. Userspace changes usually require only a target reboot, and sometimes only a service restart:

```bash
systemctl daemon-reload
systemctl restart my-test.service
```

That makes NFS root ideal for debugging init scripts, systemd units, application deployment, network fallback behavior, and driver userspace tools.

## Troubleshooting boundaries

| Symptom | Likely boundary |
| --- | --- |
| U-Boot cannot ping the host | Wrong cable, wrong U-Boot `ethact`, mismatched subnet, host firewall, or link not up. |
| `tftpboot` times out | TFTP service, firewall, root directory, permissions, or filename mismatch. |
| Kernel starts but panics on root mount | `bootargs`, NFS export, NFS protocol version, or rootfs contents. |
| Linux has no IP after NFS boot | Check the `ip=` argument and whether the kernel renamed the interface differently than expected. |
| Automatic boot still uses QSPI | The active environment still has `modeboot=qspiboot`, or U-Boot did not load the environment you modified. |

Keep the serial console open during every network boot test. U-Boot proves whether payload transfer worked; the Linux kernel command line proves whether the selected rootfs strategy reached the kernel.
