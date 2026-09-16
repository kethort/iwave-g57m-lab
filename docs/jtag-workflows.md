# JTAG Workflows

The **JTAG Modes** page supports three independent boot paths.

| Mode | Linux payload path |
| --- | --- |
| `jtag-tftp` | U-Boot downloads a FIT or individual payloads from the host TFTP server. |
| `jtag-nfs` | U-Boot downloads the kernel and DTB, then Linux mounts an NFS root. |
| `jtag-full-pdi` | Bootgen reconstructs a PDI containing the selected boot components and RAM-resident payload. |

![JTAG networking, reconstructed PDI inputs, and execution controls](images/jtag-workflow.png)

## Before Running

1. Connect the board and JTAG cable.
2. Launch the application through `run-container.sh`.
3. Load the JTAG configuration on the **JTAG Modes** page.
4. Select the boot mode.
5. Verify artifact paths, U-Boot networking, load addresses, and PDI inputs.
6. Select a custom JTAG PLM only when the reconstructed flow requires it.

The JTAG PLM is independent from the QSPI PLM. Changing one does not alter the
other workflow.

## Run The Flow

**Generate JTAG artifacts** creates the boot command, boot script, PDI, and XSDB
script without programming the target. **Run selected JTAG flow** generates the
required artifacts and invokes XSDB.

Starting either operation switches to **Preview & Logs**. Review:

- the operation banner and resolved paths;
- output from `mkimage` and `bootgen`;
- the generated XSDB target-selection commands;
- target connection and programming results.

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
