# JTAG Workflows

The **JTAG Modes** page supports three boot paths. All three reconstruct a
temporary Versal PDI, load it over JTAG, and start U-Boot. They differ in how
the Linux payload reaches RAM after U-Boot starts.

> **JTAG is not QSPI flashing.** `bootgen` constructs a PDI on the host and
> `xsdb` transfers that PDI to the device through `hw_server`. The resulting
> boot is volatile and is lost at reset or power removal. Persistent QSPI
> writes are described in [QSPI provisioning](qspi-provisioning.md).

![JTAG networking, reconstructed PDI inputs, and execution controls](images/jtag-workflow.png)

## Tool Responsibilities

| Tool | What it does | What it does not do |
| --- | --- | --- |
| `mkimage -T script` | Wraps readable U-Boot commands in a checksummed U-Boot script image (`.scr`). | It does not build U-Boot or program the board. |
| `mkimage -f` | Builds a FIT `image.ub` from an ITS description and the selected Linux payload files. | It does not create a Versal boot PDI. |
| `bootgen` | Reads a Versal BIF and combines the listed firmware, executables, scripts, and optional payloads into a PDI. | It does not communicate with the target. |
| `xsdb` | Connects to `hw_server`, resets the target, selects the PMC, and runs `device program` on the generated PDI. | In these JTAG flows it does not write the QSPI partitions. |
| U-Boot | Executes `boot.scr`, configures its network variables and boot arguments, obtains Linux payloads, and invokes `bootm` or `booti`. | It does not regenerate host artifacts. |

## Files Used By Every JTAG Mode

The GUI resolves these files from the explicit **Reconstructed PDI Inputs** or
from the selected `boot.bin` and its neighboring `boot.bin-extracted`
directory:

| Input | Purpose in the temporary PDI |
| --- | --- |
| `base-design.pdi` or `system.pdi` | Versal platform and programmable-device boot data, included as `type=bootimage`. |
| `plmfw.elf` / `plm.elf`, or the selected custom JTAG PLM | Platform Loader and Manager, included as `type=bootloader`. |
| `psmfw.elf` / PSM ELF | Platform System Manager firmware, included with `core=psm`. |
| `system-top.dtb` or selected handoff DTB | Firmware/U-Boot hardware handoff data, loaded at `0x1000`. This is not the Linux `system.dtb` payload. |
| `arm-trusted-firmware.elf` / `bl31.elf` | TF-A/BL31, started on A72 core 0 at EL3 with TrustZone. |
| `u-boot.elf` | U-Boot, started on A72 core 0 at EL2. |
| Generated `boot.scr` | U-Boot commands loaded at `0x20000000`. |

The custom PLM on the JTAG page applies only to these reconstructed JTAG PDIs.
It is independent of the QSPI custom PLM and does not alter an existing
`BOOT.bin`.

The GUI writes these common intermediate/output files:

| Generated file | Producer | Purpose |
| --- | --- | --- |
| `boot.cmd` | GUI | Human-readable U-Boot command list for the selected mode. |
| `boot.scr` | `mkimage -T script` | Checksummed U-Boot script embedded in the temporary PDI. |
| `jtag_boot_gui.bif` | GUI | Host-side recipe listing the partitions and load addresses for `bootgen`. |
| Configured JTAG PDI output, commonly `BOOT_JTAG_IMAGEUB.pdi` | `bootgen` | Temporary image transferred over JTAG. Despite the output name, TFTP/NFS PDIs do not contain `image.ub`. |
| Configured XSDB script, commonly `jtag_boot_generated.tcl` | GUI | Connect, PMC selection, system reset, and `device program` commands. |

## Which File Defines Which Layout

There are two nested image formats in the JTAG workflows. Their layouts are
independent:

| Layout | Description file | Builder | What the layout controls |
| --- | --- | --- | --- |
| Versal PDI | `jtag_boot_gui.bif` | `bootgen` | Firmware/executable partitions, target cores, exception levels, and raw RAM load addresses. |
| Linux FIT (`image.ub`) | `image.ub.its` | `mkimage -f` | Kernel, Linux DTB, and ramdisk nodes, their hashes, and the FIT configuration that groups them. |

The BIF is the recipe that selects the PDI partitions. `bootgen` parses that
recipe and creates the PDI headers, partition metadata, and payload packaging;
it does not independently discover the files or choose the GUI's load
addresses. Similarly, the ITS is the recipe for the FIT. `mkimage` turns it
into `image.ub`, but it does not create a Versal PDI or assign QSPI offsets.

### TFTP and NFS PDI layout

For `jtag-tftp` and `jtag-nfs`, the generated BIF has this logical structure:

```text
the_ROM_image:
{
    image
    {
        { type=bootimage, file=<base-design.pdi> }
        { type=bootloader, file=<plm.elf> }
        { core=psm, file=<psmfw.elf> }
    }
    image
    {
        id=0x1c000000, name=apu_ss
        { type=raw, load=0x1000, file=<system-top.dtb> }
        { core=a72-0, exception_level=el-3, trustzone, file=<bl31.elf> }
        { core=a72-0, exception_level=el-2, file=<u-boot.elf> }
        { type=raw, load=0x20000000, file=<boot.scr> }
    }
}
```

`Image`, Linux `system.dtb`, the NFS root, and TFTP `image.ub` are deliberately
absent. They arrive over the network after this PDI has started U-Boot.

### Full-PDI layout

The Full-PDI BIF adds one raw partition to the APU image:

```text
{ type=raw, load=<full_pdi_imageub_addr>, file=<image.ub> }
```

The generated `boot.scr` uses the same address as `fit_addr_r`. This agreement
between the BIF load address and U-Boot script is what allows `iminfo` and
`bootm` to find the FIT already placed in RAM by the PDI boot process.

### Generated FIT layout

When the GUI must create `image.ub`, it writes an ITS with this structure:

```text
/ {
    images {
        kernel-1 {
            data = /incbin/("<Image>");
            type = "kernel";
            arch = "arm64";
            compression = "none";
            load = <0x00000000 <kernel-load-address>>;
            entry = <0x00000000 <kernel-entry-address>>;
            hash-1 { algo = "sha256"; };
        };
        fdt-1 {
            data = /incbin/("<system.dtb>");
            type = "flat_dt";
            hash-1 { algo = "sha256"; };
        };
        ramdisk-1 {
            data = /incbin/("<rootfs.cpio.gz>");
            type = "ramdisk";
            compression = "gzip";
            hash-1 { algo = "sha256"; };
        };
    };
    configurations {
        default = "conf-1";
        conf-1 {
            kernel = "kernel-1";
            fdt = "fdt-1";
            ramdisk = "ramdisk-1";
            hash-1 { algo = "sha256"; };
        };
    };
};
```

The FIT has image *nodes*, not QSPI partitions. The kernel node carries its
configured load and entry addresses; the generated DTB and ramdisk nodes do
not declare fixed load addresses. U-Boot interprets the selected FIT
configuration when `bootm` runs. In TFTP mode the complete FIT file is first
downloaded to `fit_addr_r`; in Full-PDI mode Bootgen places that same FIT file
at the BIF's raw-partition address.

## Why `.cmd` Is Compiled To `.scr`

`boot.cmd` is plain text so it can be inspected and edited. U-Boot's `source`
path expects a script image with a legacy image header containing architecture,
type, payload length, name, and checksums. The GUI creates that wrapper with:

```bash
mkimage -A arm64 -T script -C none \
  -n "<mode> boot" -d boot.cmd boot.scr
```

`boot.scr` is therefore not an ELF, executable machine code, or U-Boot itself.
It is the command text plus a U-Boot image header. The generated script sets
session-only variables such as `ethact`, `serverip`, `ipaddr`, `netmask`, an
optional `gatewayip`, load addresses, and `bootargs`, then issues the commands
specific to the selected mode. These JTAG scripts do not call `saveenv` and do
not replace the persistent U-Boot environment.

## `jtag-tftp`

### Linux payload files

- An existing `image.ub`, or `Image`, Linux `system.dtb`, and rootfs/initramfs
  files from which the GUI can generate `image.ub`.
- A writable host TFTP root.

If `image.ub` does not exist, the GUI writes an ITS description and runs
`mkimage -f` to package the kernel, Linux DTB, and rootfs/initramfs into one FIT
image. This is separate from the `mkimage -T script` operation used for
`boot.scr`.

### Boot command

The generated `boot.cmd` sets the U-Boot network values, `fit_addr_r`, and
`bootargs`, then performs the equivalent of:

```text
tftpboot ${fit_addr_r} ${serverip}:image.ub
bootm ${fit_addr_r}
```

If a FIT configuration name is selected, it is appended as
`${fit_addr_r}#<configuration>`.

### End-to-end sequence

1. The GUI creates `boot.cmd` and wraps it as `boot.scr`.
2. The GUI copies `image.ub` to the host TFTP root.
3. The GUI creates `jtag_boot_gui.bif` from the common PDI inputs and
   `boot.scr`. The FIT is **not** included in this PDI.
4. `bootgen -arch versal -image jtag_boot_gui.bif -w -o <output.pdi>` creates
   the temporary PDI.
5. The generated TCL connects to `hw_server`, selects the PMC, resets the
   system, and calls `device program "<output.pdi>"` through `xsdb`.
6. U-Boot starts, executes the RAM-resident `boot.scr`, downloads `image.ub`
   over TFTP, and starts it with `bootm`.

## `jtag-nfs`

### Linux payload files

- Uncompressed Linux `Image`.
- Linux `system.dtb`.
- A root filesystem exported by the host NFS server. The rootfs image file is
  not transferred by this boot flow; it must already be unpacked/exported at
  the configured NFS root.
- A writable host TFTP root for `Image` and `system.dtb`.

### Boot command

The generated `boot.cmd` sets `kernel_addr_r`, `fdt_addr_r`, and NFS-capable
`bootargs`, then performs the equivalent of:

```text
tftpboot ${kernel_addr_r} ${serverip}:Image
tftpboot ${fdt_addr_r} ${serverip}:system.dtb
booti ${kernel_addr_r} - ${fdt_addr_r}
```

The dash passed to `booti` means no initramfs is supplied. The kernel mounts its
root filesystem through NFS. The resolved command line must include a valid
`root=/dev/nfs`, `nfsroot=<server>:<export>[,<options>]`, and static or DHCP
`ip=` configuration suitable for the target network.

### End-to-end sequence

1. The GUI creates `boot.cmd` and `boot.scr`.
2. It copies `Image` and the Linux DTB to the TFTP root.
3. It reconstructs the same temporary firmware/U-Boot PDI used by TFTP mode;
   neither the kernel nor Linux DTB is embedded in it.
4. `bootgen` builds the PDI and `xsdb` loads it over JTAG.
5. U-Boot TFTP-loads the kernel and DTB and invokes `booti`.
6. Linux configures networking from `bootargs` and mounts the exported NFS
   root.

## `jtag-full-pdi`

### Linux payload files

- An existing `image.ub`, or the kernel, Linux DTB, and rootfs/initramfs inputs
  required to generate it.
- A Full-PDI `image.ub` RAM address that does not overlap the other PDI
  partitions or runtime memory.

### Boot command

The generated script sets `fit_addr_r` to the Full-PDI address, validates the
RAM image with `iminfo`, and boots it with `bootm`. The script contains a TFTP
fallback if RAM does not hold a valid FIT, but a correctly built Full-PDI flow
must find the embedded FIT and should not use that fallback.

### End-to-end sequence

1. The GUI creates `boot.cmd` and `boot.scr` and ensures `image.ub` exists.
2. It deliberately skips TFTP staging.
3. The BIF includes all common PDI inputs, `boot.scr` at `0x20000000`, and
   `image.ub` as a raw partition at the configured Full-PDI FIT address.
4. `bootgen` constructs one temporary PDI containing firmware, U-Boot, the
   script, and `image.ub`.
5. `xsdb` transfers that PDI over JTAG.
6. U-Boot validates and boots the FIT already present in RAM.

If Full PDI falls back to TFTP, check the configured FIT address, the generated
BIF, PDI build log, FIT format, and memory overlap. It indicates that the image
was absent or invalid at the address used by `iminfo`.

## U-Boot And Linux Requirements

The exact Kconfig names vary by U-Boot release, but the selected U-Boot build
must provide the commands and drivers exercised by the chosen script:

- networking and the target Ethernet driver;
- `tftpboot` for TFTP and NFS modes;
- `bootm` and FIT support for `image.ub` modes;
- `booti` and flattened-device-tree support for the NFS mode;
- `source`/legacy script-image support for `boot.scr`;
- `iminfo` for Full-PDI FIT validation.

For NFS, the Linux kernel must include the target Ethernet driver, IP
autoconfiguration, NFS client, and NFS-root support early enough to mount root.
The Linux `system.dtb` must describe that Ethernet interface correctly.

## GUI Actions

**Generate JTAG artifacts** creates `boot.cmd` and `boot.scr` and stages the
mode's network payloads. It does not create the reconstructed PDI, invoke
`bootgen`, run `xsdb`, or program a target.

**Run selected JTAG flow** performs the complete process: script generation,
payload preparation, BIF/PDI generation, XSDB script generation, and volatile
JTAG programming. Starting an operation switches to **Preview & Logs**.

![Execution log, command preview, and resolved configuration](images/execution-log.png)

## Diagnose JTAG

Run the host diagnostic independently when XSDB cannot find a target:

```bash
./diagnose-jtag.sh
```

It checks the Vitis environment, port 3121, XSDB connectivity, available target
list, and PMC selection without programming the device.

`Connection refused` means no server is listening. `Available targets: none`
means XSDB reached `hw_server`, but the server did not enumerate the JTAG chain.
