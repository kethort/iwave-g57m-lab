# Configuration

On first setup, the launcher copies separate editable startup configurations to:

```text
$WORKSPACE/configs/jtag_config.json
$WORKSPACE/configs/qspi_config.json
```

They appear in the container and GUI as:

```text
/work/configs/jtag_config.json
/work/configs/qspi_config.json
```

The generated `qt-boot-gui.env` selects these files automatically. The image
also contains read-only fallback templates under `/opt/qt-boot-gui/configs`.
Existing workspace configurations are never overwritten by setup or launch.

Machine-specific launcher values are stored in the repository-local,
Git-ignored `qt-boot-gui.env`. Copy `qt-boot-gui.env.example` to create it
manually, or run `./setup-host.sh`. Explicit shell variables take precedence.

## Path Mapping

File dialogs run inside the container:

| Host path | GUI path |
| --- | --- |
| `$WORKSPACE` | `/work` |
| `$TFTP_ROOT` | `/srv/tftp` |
| `$XILINX_ROOT` | Unchanged absolute path |

Generated FIT images, PDIs, scripts, BIF files, and XSDB files should be written
under `/work/output`, which persists as `$WORKSPACE/output` on the host.

Relative paths in JSON are resolved from the JSON file's directory. Host paths
that are not mounted must be changed to `/work/...` paths or moved beneath the
workspace.

## Values To Review

- Boot mode and payload filenames
- Boot image, kernel, Linux DTB, and rootfs paths
- U-Boot server IP, board IP, netmask, gateway, and Ethernet device
- TFTP and NFS roots
- FIT, kernel, DTB, script, and verification RAM addresses
- Full-PDI component paths
- QSPI type, capacity, erase size, offsets, and slot sizes
- JTAG and QSPI custom PLM selections

Use **Save resolved configuration** from **Preview & Logs** to write the complete
current state under `/work`.
