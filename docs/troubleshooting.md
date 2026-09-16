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

## A JSON Path Is Missing

Only `$WORKSPACE`, `$TFTP_ROOT`, and `$XILINX_ROOT` are mounted. Move the file
under the workspace or deliberately choose a broader workspace. Avoid mounting
the entire home directory merely to expose one artifact.
