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
- select the intended boot mode at SW4 before applying power; see the [SW4 boot selection table]({{< ref "/reference#sw4-boot-selection" >}});
- configure the console for 115200 baud, 8 data bits, no parity, one stop bit, and no flow control.

## Experiment 001: reproduce the software baseline

Build the boot firmware, U-Boot, Linux kernel, device tree, and root filesystem from the iWave BSP. This entry maps the current `meta-iwave` changes, documents the supported build commands, and identifies the deploy artifacts.

[Build the G57M software baseline ->]({{< ref "/posts/building-the-iwave-petalinux-baseline" >}})

## Experiment 002: deploy a Full JTAG PDI

Package the Versal firmware chain, U-Boot, and a Linux FIT into one temporary PDI, then load it through the GUI using Bootgen and XSDB. This entry keeps the volatile JTAG path distinct from persistent QSPI provisioning.

[Deploy a Full JTAG PDI ->]({{< ref "/posts/deploying-a-full-jtag-pdi-with-the-boot-gui" >}})

## Experiment 003: identify a passive FMC card

Turn a passive FMC LPC breakout into a carrier-recognized mezzanine by adding a VITA/IPMI FRU EEPROM. This entry also documents a less obvious requirement discovered at the bench: asserting FMC presence placed the empty FMC JTAG path in the scan chain, so the passive card required a TDI-to-TDO bypass.

[Open the FMC FRU bring-up ->]({{< ref "/posts/fmc-fru-passive-breakout" >}})
