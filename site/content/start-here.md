+++
title = "Start Here"
description = "The hardware, software, and safety baseline used throughout this lab notebook."
+++

This site documents repeatable bring-up and recovery work on an iWave G57M platform built around AMD Versal AI Edge silicon.

## Baseline

| Component | Version |
| --- | --- |
| Board family | iWave G57M |
| Device class | Versal AI Edge VE2302 |
| Vitis and Vivado | 2025.2 |
| Host workflow | Linux, Docker, host `hw_server` |

Always confirm the board revision, flash geometry, memory addresses, and tool version before applying a procedure. Commands that erase or program QSPI can make a board temporarily unbootable.

## Recommended reading order

1. Connect serial and JTAG and verify that `hw_server` sees the PMC.
2. Establish a recoverable JTAG boot path.
3. Add TFTP or NFS for fast Linux iteration.
4. Validate a complete QSPI layout before programming persistent flash.

The downloadable GUI and container package live in the same repository as this site. AMD Vitis is not redistributed; users mount their own licensed installation.
