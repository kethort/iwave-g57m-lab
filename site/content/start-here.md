+++
title = "Start Here"
description = "Establish a safe, observable G57M baseline before changing boot firmware or attaching hardware."
+++

This notebook starts with an iWave G57M VE2302 SOM on the G57D R2.0 carrier. The goal is not merely to reach a Linux prompt. It is to make power, serial output, JTAG visibility, and each external connection independently testable.

These are independent lab notes, not vendor documentation. Use the vendor's released BSPs, manuals, and licensed tools as the source of truth, and treat this site as a reproducible record of one bench setup.

## First power-up

Start with iWave's [official getting-started procedure](https://iwave-global.com/knowledge-base/products/get-started-with-versal-ai-edge-prime-som-development-platform/). In particular:

- work on a grounded ESD-safe surface;
- use the supplied 12 V power supply at J2;
- connect the combined debug UART and JTAG cable at J8;
- set SW3 to OFF for JTAG;
- select the intended boot mode at SW4 before applying power; see the [SW4 boot selection table]({{< ref "/reference#sw4-boot-selection" >}});
- configure the console for 115200 baud, 8 data bits, no parity, one stop bit, and no flow control.

## First experiment

Begin by reproducing the software baseline. Build the boot firmware, U-Boot, Linux kernel, device tree, and root filesystem from the iWave BSP before changing PLM behavior, attaching extra hardware, or provisioning flash.

[Build the G57M software baseline ->]({{< ref "/posts/building-the-iwave-petalinux-baseline" >}})

## Why this page stays short

The lab notes page is the complete index. This page is only the safe entry point: confirm power, serial, JTAG visibility, and boot-mode switches, then move into the first reproducible build.
