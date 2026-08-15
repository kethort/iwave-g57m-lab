+++
title = "Containerized JTAG Without Giving Docker the USB Cable"
date = 2026-08-15T00:00:00-07:00
description = "Run XSDB in a portable Qt container while the host hw_server safely owns the local JTAG cable."
tags = ["JTAG", "Docker", "XSDB", "Vitis 2025.2"]
categories = ["Board Bring-Up"]
+++

## Objective

Run the Versal Boot GUI and XSDB inside Docker without using `--privileged` or exposing the host USB bus to the container.

## Architecture

```text
Qt GUI + XSDB in Docker
          |
          | TCP:127.0.0.1:3121 (--network host)
          v
host hw_server
          |
          v
local USB JTAG cable -> Versal PMC
```

The host launcher starts Vitis 2025.2 `hw_server` when port 3121 is unused, waits for it to become ready, and stops only the instance it started when the GUI exits.

## Verify the hardware boundary

Before debugging generated PDIs, prove that the host can enumerate the target:

```bash
export VITIS_SETTINGS=/development/2025.2/Vitis/settings64.sh
./diagnose-jtag.sh
```

Success ends with:

```text
PASS: PMC target is available and selectable.
```

## Launch

```bash
export VITIS_SETTINGS=/development/2025.2/Vitis/settings64.sh
export WORKSPACE=$HOME/versal-lab-data
export TFTP_ROOT=/srv/tftp
./run-container.sh
```

The container receives the artifact workspace at `/work`, while generated files are written to `/work/output`.

## Failure boundaries

`Connection refused` means no process is listening at the configured `hw_server` URL. `Available targets: none` means the TCP connection succeeded but the server cannot see a JTAG chain. These are host connectivity problems, not Bootgen failures.

Do not move USB ownership into Docker to solve a TCP error. First inspect `~/.qt-boot-gui-container/hw_server.log` and run the diagnostic independently.
