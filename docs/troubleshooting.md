# Troubleshooting

## Vitis Tools Are Missing

```bash
QT_BOOT_GUI_CHECK_ONLY=1 ./run-container.sh
```

Confirm `VITIS_SETTINGS` names a readable Vitis 2025.2 `settings64.sh` and that
the discovered installation root contains both `Vitis/` and `Vivado/`.

## JTAG Connection Fails

```bash
./diagnose-jtag.sh
ss -ltn | grep 3121
```

The launcher normally starts `hw_server`. Its log is stored at
`~/.qt-boot-gui-container/hw_server.log`.

- `Connection refused`: no server is listening at the configured URL.
- `Available targets: none`: the server is reachable but sees no JTAG chain.
- PMC selection failure: inspect the diagnostic's complete target list.

## The GUI Does Not Appear

```bash
printf 'DISPLAY=%s\n' "$DISPLAY"
ls -l "${XAUTHORITY:-$HOME/.Xauthority}"
ls -ld /tmp/.X11-unix
```

If necessary, grant X11 access to the current local user:

```bash
xhost +SI:localuser:"$(id -un)"
```

## TFTP Staging Fails

The container runs as the host UID/GID. Ensure `TFTP_ROOT` exists and is writable
by that user or its group:

```bash
test -w /srv/tftp && echo writable
```

## U-Boot Cannot Download A Payload

Confirm that:

- the host TFTP daemon serves the same directory mounted at `/srv/tftp`;
- staged filenames match the generated U-Boot commands;
- `serverip`, `ipaddr`, netmask, gateway, and `ethact` are correct;
- the host firewall permits TFTP traffic;
- the board and host have a valid network route.

## U-Boot Cannot Detect QSPI

Stop before erasing or writing flash and test from the U-Boot prompt:

```text
sf probe
```

If probing fails, confirm that:

- the handoff DTB in **Explicit PDI Components** enables and describes the QSPI
  controller and flash;
- the temporary JTAG provisioning PDI was rebuilt after changing that DTB;
- U-Boot includes the required SPI controller and SPI flash drivers;
- pinctrl, clocks, compatible strings, chip-selects, bus width, frequency, and
  stacked/parallel flash properties match the board;
- the detected capacity and topology match the layout selected in the GUI.

The Linux DTB payload is not used to initialize QSPI for the provisioning U-Boot.
Updating only that DTB will not fix an `sf probe` failure.

## QSPI Images Are Present But The Wrong Mode Boots

Interrupt autoboot and inspect the persistent selection:

```text
printenv bootcmd modeboot qspiboot
```

The complete component provisioning flow expects `bootcmd=run $modeboot` and
`modeboot=qspiboot`. If U-Boot reports a bad environment CRC, falls back to its
defaults, or selects `netfitboot`, verify that its compiled environment backend,
offset, and size match the GUI's environment partition. Also confirm that the
chosen GUI operation actually installs an environment; several direct-flash
operations intentionally preserve the existing one.

See [U-Boot environment](u-boot-environment.md) for the operation matrix and
post-provision checks.

## A JSON Path Is Missing

Only `$WORKSPACE`, `$TFTP_ROOT`, and `$XILINX_ROOT` are mounted. Move the file
under the workspace or deliberately choose a broader workspace. Avoid mounting
the entire home directory merely to expose one artifact.
