+++
title = "Experiment 007: Deploying RPU Firmware with remoteproc and Debugging PPU/RPU"
experiment = 7
slug = "experiment-007-deploying-rpu-firmware-with-remoteproc-and-debugging-ppu-rpu"
date = 2026-09-22T00:00:00-07:00
description = "Load Cortex-R5 firmware from Linux with remoteproc, then attach Vitis to the running RPU and PLM/PPU firmware without resetting the board."
tags = ["remoteproc", "RPU", "PLM", "PPU", "Vitis", "XSDB"]
categories = ["Board Bring-Up"]
+++

This experiment turns the PLM/RPU firmware build from the previous note into a runtime workflow. Linux owns the board after boot, `remoteproc` loads the RPU firmware, and Vitis attaches to the already-running RPU and PPU/PLM state for debug.

The important distinction is that this is not a clean-room Vitis launch that resets the target. The debugger configuration is set to **Attach to running target**. That lets the lab prove the firmware that actually booted or was loaded by Linux is the firmware being inspected.

## What This Proves

There are three separate claims to verify:

| Claim | Evidence |
| --- | --- |
| Linux can manage the RPU | `remoteproc` exposes an R5 device, accepts an ELF from `/lib/firmware`, and reports a running state. |
| The RPU firmware is inspectable | Vitis attaches to the RPU, loads symbols from the matching ELF, and stops at a source-level breakpoint. |
| The PLM user module is inspectable | Vitis/XSDB attaches to the running PPU/PLM image, loads PLM symbols, and stops on a hardware breakpoint in the PLM command handler. |

That combination matters. Serial logs prove the path ran once; debugger attachment proves the running processors can be inspected at the point where the PLM user module and RPU firmware interact.

## Device Tree Requirements

Linux `remoteproc` does not discover the RPU firmware layout on its own. The Linux DTB must describe the R5 subsystem, the memory that Linux must not allocate, and the IPI mailboxes used for notifications.

In this build, the relevant overlay is in `sources/meta-iwave/recipes-bsp/device-tree/files/system-user.dtsi`.

The reserved-memory section protects the RPU firmware image area and the RPMsg vrings/buffer pool:

```dts
reserved-memory {
    #address-cells = <2>;
    #size-cells = <2>;
    ranges;

    rproc_0_fw_image: rpu@40000 {
        no-map;
        reg = <0x0 0x00040000 0x0 0x00100000>;
    };

    rpu0vdev0vring0: rpu0vdev0vring0@3ed40000 {
        no-map;
        reg = <0x0 0x3ed40000 0x0 0x4000>;
    };

    rpu0vdev0vring1: rpu0vdev0vring1@3ed44000 {
        no-map;
        reg = <0x0 0x3ed44000 0x0 0x4000>;
    };

    rpu0vdev0buffer: rpu0vdev0buffer@3ed48000 {
        no-map;
        compatible = "shared-dma-pool";
        reg = <0x0 0x3ed48000 0x0 0x100000>;
    };
};
```

The R5F subsystem node binds the Xilinx R5 remoteproc driver and connects the R5 core to those memory regions:

```dts
r5fss@ffe00000 {
    compatible = "xlnx,versal-r5fss";
    xlnx,cluster-mode = <0>;
    xlnx,tcm-mode = <0>;
    #address-cells = <2>;
    #size-cells = <2>;
    ranges = <0x0 0x00000000 0x0 0xffe00000 0x0 0x10000>,
             <0x0 0x00020000 0x0 0xffe20000 0x0 0x10000>;
    status = "okay";

    r5f@0 {
        compatible = "xlnx,versal-r5f";
        reg = <0x0 0x00000000 0x0 0x10000>,
              <0x0 0x00020000 0x0 0x10000>;
        reg-names = "atcm0", "btcm0";
        power-domains = <&versal_firmware 0x18110005>,
                        <&versal_firmware 0x1831800b>,
                        <&versal_firmware 0x1831800c>;
        memory-region = <&rproc_0_fw_image>,
                        <&rpu0vdev0buffer>,
                        <&rpu0vdev0vring0>,
                        <&rpu0vdev0vring1>;
        mboxes = <&ipi_0_to_ipi_1 0>, <&ipi_0_to_ipi_1 1>;
        mbox-names = "tx", "rx";
        status = "okay";
    };
};
```

The IPI mailbox nodes expose the APU-to-RPU and RPU-to-APU interrupt/message path:

```dts
&amba {
    ipi0: mailbox@ff330000 {
        compatible = "xlnx,versal-ipi-mailbox";
        interrupt-parent = <&gic>;
        interrupts = <0 30 4>;
        reg = <0x0 0xff330000 0x0 0x10000
               0x0 0xff3f0400 0x0 0x200>;
        xlnx,ipi-id = <2>;
        reg-names = "ctrl", "msg";
        status = "okay";

        ipi_0_to_ipi_1: child@ff340000 {
            compatible = "xlnx,versal-ipi-dest-mailbox";
            #mbox-cells = <1>;
            xlnx,ipi-id = <3>;
            reg = <0x0 0xff340000 0x0 0x10000
                   0x0 0xff3f0600 0x0 0x200>;
            reg-names = "ctrl", "msg";
        };
    };
};
```

The ELF linker script, the `reserved-memory` ranges, and any RPMsg resource table must agree. If the RPU ELF loads a segment outside TCM or the declared DDR firmware region, Linux may reject the firmware or overwrite memory the RPU expects to own.

## Kernel Configuration

The kernel also needs the firmware loader, mailbox, remoteproc, power-domain, and RPMsg support enabled:

```text
CONFIG_FW_LOADER=y
CONFIG_MAILBOX=y
CONFIG_ZYNQMP_IPI_MBOX=y
CONFIG_REMOTEPROC=y
CONFIG_XLNX_R5_REMOTEPROC=y
CONFIG_RPMSG=y
CONFIG_RPMSG_CHAR=m
CONFIG_RPMSG_CTRL=m
CONFIG_RPMSG_NS=y
CONFIG_RPMSG_VIRTIO=y
CONFIG_RPMSG_VIRTIO_BUF_SIZE=512
CONFIG_ZYNQMP_POWER=y
CONFIG_ZYNQMP_PM_DOMAINS=y
```

## Deploy From Linux With The Repo Script

For this run, the RPU firmware was not copied by hand from an interactive shell. It was deployed from the host with the repo helper script at:

```text
/development/xilinx-dev/iwg57m-2025-2/scripts/load_remoteproc_elf.sh
```

The command was run from the `scripts/` directory:

```bash
cd /development/xilinx-dev/iwg57m-2025-2/scripts

./load_remoteproc_elf.sh \
  --user root \
  --password root \
  --ip 192.168.0.137 \
  --remoteproc /sys/class/remoteproc/remoteproc0 \
  --firmware-name rpu_ipi_ping_pong.elf \
  --no-breakpoint \
  /home/user/vitis_projects/secure-boot/plm/build/rpu_ipi_ping_pong/build/rpu_ipi_ping_pong.elf
```

The positional argument at the end is the **local RPU ELF** built by the PLM/RPU firmware project. The `--firmware-name` option is the name that the script installs on the board under `/lib/firmware/` and then writes into the Linux `remoteproc` firmware selector.

The important options in this run were:

| Option | Meaning in this run |
| --- | --- |
| `--ip 192.168.0.137` | SSH target address of the booted Linux system on the G57M. |
| `--user root --password root` | Login used by the helper for SSH, SCP, and remote `sudo`. |
| `--remoteproc /sys/class/remoteproc/remoteproc0` | The Linux remoteproc instance controlling the R5 firmware. |
| `--firmware-name rpu_ipi_ping_pong.elf` | The filename copied to `/lib/firmware/` and selected through `remoteproc0/firmware`. |
| `--no-breakpoint` | Skip the script's optional XSDB hardware-breakpoint setup. Vitis attachment is handled separately later in this page. |
| ELF path | The local file copied to the board before `remoteproc` starts it. |

The script performs the normal Linux `remoteproc` sequence over SSH. In start/deploy mode it:

1. Resolve the local ELF and optional `main` breakpoint address.
2. Refresh or scan the board SSH host key in `~/.ssh/known_hosts`.
3. Copy the local ELF to the board with `scp`.
4. Stop the selected `remoteproc` instance by writing `stop` to `remoteproc0/state`.
5. Copy the uploaded ELF into `/lib/firmware/rpu_ipi_ping_pong.elf`.
6. Select the firmware by writing `rpu_ipi_ping_pong.elf` to `remoteproc0/firmware`.
7. Start the RPU by writing `start` to `remoteproc0/state`.
8. Read back the `state` and `firmware` files.

Internally, the remote side of the start path is equivalent to:

```sh
echo stop > /sys/class/remoteproc/remoteproc0/state 2>/dev/null || true
cp /tmp/rpu_ipi_ping_pong.elf /lib/firmware/rpu_ipi_ping_pong.elf
chmod 0644 /lib/firmware/rpu_ipi_ping_pong.elf
echo rpu_ipi_ping_pong.elf > /sys/class/remoteproc/remoteproc0/firmware
echo start > /sys/class/remoteproc/remoteproc0/state
cat /sys/class/remoteproc/remoteproc0/state
cat /sys/class/remoteproc/remoteproc0/firmware
```

The script also has an optional debugger assist path. If `--no-breakpoint` is omitted, it starts or verifies `hw_server`, uses XSDB, selects `Cortex-R5 #0`, and installs a hardware breakpoint at the resolved or supplied address before starting the firmware. This run deliberately used `--no-breakpoint` because the debugger attach flow is shown separately below.

This was the successful host-side output:

```text
Resolved main breakpoint from ELF: 0x000432c0
Board:               root@192.168.0.137
Local ELF:           /home/user/vitis_projects/secure-boot/plm/build/rpu_ipi_ping_pong/build/rpu_ipi_ping_pong.elf
Firmware name:       rpu_ipi_ping_pong.elf
Remoteproc instance: /sys/class/remoteproc/remoteproc0
HW server:           TCP:127.0.0.1:3121
Main breakpoint:     0x000432c0
Refreshing SSH host key for 192.168.0.137...
Scanning SSH host key...

Skipping breakpoint setup

Copying ELF to the board...

Stopping remoteproc and installing firmware...
Remoteproc state after stop:
offline

Starting firmware through remoteproc...

Remoteproc state:
running

Remoteproc firmware:
rpu_ipi_ping_pong.elf
```

The important proof is the final state and firmware readback. Linux accepted the ELF, associated it with `/sys/class/remoteproc/remoteproc0`, started the RPU, and reported the firmware name that is now running.

The same helper can stop the RPU without copying a new ELF:

```bash
cd /development/xilinx-dev/iwg57m-2025-2/scripts

./load_remoteproc_elf.sh --ip 192.168.0.137 --stop
```

The stop path leaves the selected firmware name intact but moves the remote processor offline:

```text
Refreshing SSH host key for 192.168.0.137...
Scanning SSH host key...

Stopping remoteproc...

Remoteproc state:
offline

Remoteproc firmware:
rpu_ipi_ping_pong.elf
```

The kernel reports the matching stop event:

```text
[ 6206.666144] remoteproc remoteproc0: stopped remote processor ffe00000.r5f
```

Starting the firmware through the script produces the matching kernel-side evidence:

```text
[ 6270.726039] remoteproc remoteproc0: powering up ffe00000.r5f
[ 6270.732767] remoteproc remoteproc0: Booting fw image rpu_ipi_ping_pong.elf, size 870672
```

After the RPU firmware starts, the serial log shows the RPU and PLM exchanging IPI requests and responses. The useful proof is the counter relationship: the RPU sends `counter=N`, the PLM reports the request, then returns `value=N+1`, and the RPU ISR receives that value.

```text
RPU (Rust): TX counter=1 sequence=1 token=0x525855B1
PLM IPI PING-PONG: received request #44 counter=1 sequence=1 token=0x525855B1
PLM IPI PING-PONG: response status=0x00000000 value=2 sequence=1 token=0xF7FD0FEB, triggering RPU
RPU (Rust): RX ISR #1 status=0x00000000 value=2 sequence=1 token=0xF7FD0FEB
RPU (Rust): ping-pong #1 complete, reply=2

RPU (Rust): TX counter=2 sequence=2 token=0x52405431
PLM IPI PING-PONG: received request #45 counter=2 sequence=2 token=0x52405431
PLM IPI PING-PONG: response status=0x00000000 value=3 sequence=2 token=0xF7E50E6B, triggering RPU
RPU (Rust): RX ISR #2 status=0x00000000 value=3 sequence=2 token=0xF7E50E6B
RPU (Rust): ping-pong #2 complete, reply=3
```

Because the PLM and RPU share the serial console, a few startup characters can interleave. The repeating request/response structure is the evidence to trust, not a perfectly formatted first line.

The equivalent manual target-side flow is still useful for debugging the setup. Install the RPU ELF into the target root filesystem firmware directory. The exact filename can vary; the name written to the `firmware` sysfs file must match the file under `/lib/firmware`.

```bash
cp rpu_ipi_ping_pong.elf /lib/firmware/

dmesg | grep -Ei 'remoteproc|r5|rpu|ipi|mailbox|rpmsg|virtio|firmware'
ls -l /sys/class/remoteproc/
cat /sys/class/remoteproc/remoteproc*/name
cat /sys/class/remoteproc/remoteproc*/state
```

Then load and start the RPU firmware:

```bash
RPROC=/sys/class/remoteproc/remoteproc0

echo stop > "$RPROC/state" 2>/dev/null || true
echo rpu_ipi_ping_pong.elf > "$RPROC/firmware"
echo start > "$RPROC/state"
cat "$RPROC/state"
```

The expected state is `running`, matching the repo-script output above. If it fails before that, check the kernel log before changing the firmware:

```bash
dmesg | tail -100
```

The most common failures are an ELF load address outside the DTS memory regions, a missing `/lib/firmware` file, a missing remoteproc driver, or an IPI/mailbox node that did not bind.

## Attach Vitis Without Resetting

Both launch configurations use **Target Setup Mode: Attach to running target**. This is the critical setting: the debugger connects to the current processor state and does not reset or initialize the board first.

{{< lab-figure src="images/rpu-debug-config.png" alt="Vitis RPU launch configuration set to attach to running target" caption="RPU launch configuration. The debugger attaches to the running Cortex-R5 target rather than resetting the board." >}}

{{< lab-figure src="images/plm-debug-config.png" alt="Vitis PLM launch configuration set to attach to running target" caption="PLM launch configuration. The same attach-to-running-target mode is used for the PPU/PLM context." >}}

## Load Symbols

After attaching, load symbols from the exact ELF that was used for the running firmware. This step maps addresses back to functions and source lines.

{{< lab-figure src="images/rpu-manage-symbols.png" alt="Vitis manage symbols dialog for the RPU firmware" caption="RPU symbols must come from the same `rpu_ipi_ping_pong.elf` that the repo script copied to the board and Linux remoteproc loaded." >}}

{{< lab-figure src="images/plm-manage-symbols.png" alt="Vitis manage symbols dialog for the PLM firmware" caption="PLM symbols must come from the matching `plm.elf`; otherwise the PPU addresses will not resolve to the user-module source correctly." >}}

## Debug The RPU From The Gutter

With RPU symbols loaded, source-level breakpoints can be placed directly in the editor gutter. This is the normal application-debug path: set the breakpoint, resume, trigger the IPI transaction, and confirm the RPU stops where expected.

{{< lab-figure src="images/rpu-debug-at-gutter.png" alt="Vitis stopped at an RPU source breakpoint set from the gutter" caption="The RPU can stop at a source-level gutter breakpoint after remoteproc starts the firmware and Vitis attaches to the running target." >}}

## Debug The PPU/PLM With A Hardware Breakpoint

The PLM case is different. The PPU is already running platform-management firmware, and a normal source gutter breakpoint may not be the reliable path. For this run, the breakpoint address was resolved from the PLM ELF and then installed as a hardware breakpoint from the XSDB console.

First find the PLM command handler address:

```bash
/development/2025.2/Vitis/gnu/microblaze/lin/bin/mb-nm \
  -n plm/build/plm/build/plm.elf \
  | grep XPlm_IpiPingCommandHandler
```

The symbol resolved to:

```text
f0240390 t XPlm_IpiPingCommandHandler
```

Then set a hardware breakpoint in XSDB:

```tcl
bpadd -addr 0xf0240390 -type hw
```

After the RPU sends the IPI command, the PPU stops in the PLM user-module handler:

{{< lab-figure src="images/plm-stopped-at-breakpoint.png" alt="Vitis stopped in PLM after XSDB hardware breakpoint at XPlm_IpiPingCommandHandler" caption="The PPU/PLM debug proof: symbols are loaded from `plm.elf`, XSDB installs a hardware breakpoint at the command-handler address, and the running PLM stops when the RPU triggers the IPI path." >}}

## What To Capture

For a reproducible record, save:

- the exact RPU ELF placed in `/lib/firmware`;
- the `load_remoteproc_elf.sh` command line and output;
- the `load_remoteproc_elf.sh --stop` output;
- the `remoteproc` name, firmware, and state from sysfs;
- `dmesg` lines showing the R5 remoteproc and IPI mailbox drivers binding;
- serial evidence showing the RPU TX, PLM handler, PLM response, and RPU ISR receive path;
- the Vitis launch configuration screenshots showing attach-to-running-target mode;
- RPU and PLM symbol-loading screenshots;
- the RPU source-level breakpoint screenshot;
- the `mb-nm` output used to resolve the PLM handler address;
- the XSDB `bpadd -addr ... -type hw` command;
- the PLM stopped-at-breakpoint screenshot.

This evidence closes the loop: Linux can deploy the RPU firmware, Vitis can inspect the RPU at source level, and XSDB can stop the running PLM user module at the exact command handler that services the RPU request.
