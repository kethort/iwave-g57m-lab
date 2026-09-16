# Configuration

The image contains separate startup templates for JTAG and QSPI:

```text
/opt/qt-boot-gui/configs/jtag_config.json
/opt/qt-boot-gui/configs/qspi_config.json
```

They are loaded automatically and are read-only. To load editable host files at
startup, place them under `WORKSPACE` and export container-visible paths:

```bash
export QT_BOOT_GUI_JTAG_CONFIG=/work/configs/jtag_config.json
export QT_BOOT_GUI_QSPI_CONFIG=/work/configs/qspi_config.json
./run-container.sh
```

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
