+++
title = "Start Here"
description = "Establish a safe, observable G57M baseline before changing boot firmware or attaching hardware."
+++

This notebook starts with an iWave G57M VE2302 SOM on the G57D R2.0 carrier. The goal is not merely to reach a Linux prompt. It is to make power, serial output, JTAG visibility, and each external connection independently testable.

## First power-up

Start with iWave's [official getting-started procedure](https://iwave-global.com/knowledge-base/products/get-started-with-versal-ai-edge-prime-som-development-platform/). In particular:

- work on a grounded ESD-safe surface;
- use the supplied 12 V power supply at J2;
- connect the combined debug UART and JTAG cable at J8;
- set SW3 to OFF for JTAG;
- select the intended boot mode at SW4 before applying power;
- configure the console for 115200 baud, 8 data bits, no parity, one stop bit, and no flow control.

> Never insert or remove the SOM or an FMC card while the carrier is powered. Verify the carrier revision and switch labels against its documentation before relying on a photograph or another revision's switch positions.

## Experiment 001: reproduce the software baseline

Before modifying the hardware, build the boot firmware, U-Boot, Linux kernel, device tree, and root filesystem from the iWave BSP. The first entry maps the current `meta-iwave` recipes and shows which generated files are required by each GUI boot flow.

[Build the G57M software baseline ->]({{< ref "/posts/building-the-iwave-petalinux-baseline" >}})

## Experiment 002: identify a passive FMC card

The second entry turns a passive FMC LPC breakout into a carrier-recognized mezzanine by adding a VITA/IPMI FRU EEPROM. It also documents a less obvious requirement discovered at the bench: asserting FMC presence placed the empty FMC JTAG path in the scan chain, so the passive card required a TDI-to-TDO bypass.

[Open the FMC FRU bring-up ->]({{< ref "/posts/fmc-fru-passive-breakout" >}})

## Working method

1. Establish power, UART, and JTAG with no experimental hardware attached.
2. Change one physical connection at a time.
3. Record both the expected output and the failure signature.
4. Keep a recovery path before writing persistent QSPI flash.
