# U-Boot Environment

The persistent U-Boot environment determines what happens after the temporary
JTAG session ends and the board resets. It must agree with the QSPI layout,
payload load addresses, boot arguments, and selected persistent boot path.

## JTAG Versus Persistent Boot

The three JTAG modes load a boot script into RAM and set the required variables
for that session. They do not require or update a saved U-Boot environment.

QSPI boot is different. After reset, U-Boot must find a valid environment in
flash and execute a command that matches the installed payload layout. A stale
environment can override correct compiled defaults and select the wrong boot
path even when every image was flashed successfully.

## Operation Behavior

| GUI operation | Persistent environment behavior |
| --- | --- |
| **JTAG boot U-Boot + provision all QSPI partitions** | Creates the environment with the running reconstructed U-Boot, writes it to the configured QSPI environment slot, and verifies it. The final path is `modeboot=qspiboot`. |
| **Prepare TFTP assets only** | Generates and stages environment files but does not write QSPI. |
| **Flash Linux components directly** | Does not install a persistent environment. The existing or compiled-default environment must already start the flashed QSPI script/layout. |
| **Provision image.ub flow** | Does not install a persistent environment. The existing or compiled-default environment must select the corresponding FIT boot script. |
| **Install QSPI TFTP boot** | Flashes BOOT.bin and the TFTP-oriented boot script, but does not replace the saved environment. The existing or compiled-default environment must select that script or its `netfitboot` path. |

For a new or unknown board state, **JTAG boot U-Boot + provision all QSPI
partitions** is the self-contained operation because it installs the persistent
environment as part of the same verified transaction.

## Component-QSPI Environment

The complete provisioning flow sets and exports an environment containing:

- `bootcmd=run $modeboot`
- `modeboot=qspiboot`
- `qspiboot`, which probes QSPI, reads the kernel, Linux DTB, and rootfs from
  their configured offsets, sets `bootargs`, and invokes `booti`
- QSPI offsets and payload sizes
- kernel, DTB, rootfs, environment, script, and verification RAM addresses
- `bootargs`
- U-Boot network variables used during provisioning

The environment is exported by the same U-Boot binary that will consume it,
including its CRC, then erased, written, read back, and CRC-verified by the
provisioning script.

The `qspi_modeboot` JSON value is used by the staged TFTP environment path. The
complete all-partitions operation deliberately installs `qspiboot` as the final
mode so Linux boots from the separate QSPI kernel, DTB, and rootfs partitions.

## U-Boot Build Requirements

The U-Boot binary inside BOOT.bin must be configured to load its environment
from the same flash device, offset, and size selected in the GUI. Depending on
the U-Boot version and board configuration, review settings such as:

- `CONFIG_ENV_IS_IN_SPI_FLASH`
- `CONFIG_ENV_OFFSET`
- `CONFIG_ENV_SIZE`
- SPI bus, chip-select, mode, and maximum-frequency environment settings
- redundant-environment settings, if enabled

The GUI currently writes one environment slot. Do not enable a redundant
environment layout unless its offsets and update behavior are deliberately
accounted for. The environment offset and size must not overlap BOOT.bin or any
payload partition.

## Post-Provision Check

After provisioning and reset, interrupt autoboot and inspect:

```text
sf probe
printenv bootcmd modeboot qspiboot
printenv bootargs
printenv kernel_addr_r fdt_addr_r ramdisk_addr_r
printenv qspi_kernel_offset qspi_dtb_offset qspi_rootfs_offset
```

For the complete component flow, `modeboot` should be `qspiboot`, and the
reported offsets and load addresses should match the generated QSPI JSON. For a
persistent network/FIT flow, confirm the selected mode command and `serverip`,
`ipaddr`, `netmask`, `gatewayip`, and `ethact` instead.

Messages such as `*** Warning - bad CRC, using default environment` indicate
that U-Boot did not accept the saved environment. Check the compiled environment
backend, offset, size, flash topology, and whether the environment was produced
by a compatible U-Boot build before changing payload offsets.
