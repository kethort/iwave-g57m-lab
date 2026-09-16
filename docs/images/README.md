# Screenshot Capture List

Place the final PNG files in this directory. Use the same application window
width for every capture and crop away the desktop, terminal, and excess window
chrome.

## `overview.png`

- Recommended size: about 1440 x 900
- Active page: **JTAG Modes**
- Show: application header, all three workflow tabs, JTAG Configuration, and
  the first portion of Boot Artifacts
- Purpose: README hero image and immediate product overview

## `jtag-workflow.png`

- Recommended size: about 1440 x 900
- Active page: **JTAG Modes**
- Scroll to show: U-Boot Networking & Boot Arguments, Reconstructed PDI Inputs,
  and the JTAG operation buttons
- Purpose: show the inputs involved in a complete JTAG operation

## `qspi-workflow.png`

- Recommended size: about 1440 x 900
- Active page: **QSPI Provisioning**
- Show: custom PLM, Explicit PDI Components, and enough of QSPI Partition Layout
  or QSPI Operations to make the provisioning path clear
- Purpose: show that QSPI uses separate payloads and a dedicated PLM

## `execution-log.png`

- Recommended size: about 1440 x 900
- Active page: **Preview & Logs**
- Show: a successful operation banner, meaningful `bootgen` or XSDB output, and
  the beginning of Command Preview
- Purpose: demonstrate live progress and diagnosable command output

## Optional `workflow.gif`

A short recording may show loading a JSON file, switching workflows, starting
an operation, and the automatic transition to **Preview & Logs**. Keep it under
10 MB; static PNGs should remain the primary documentation.
