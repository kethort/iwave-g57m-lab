+++
title = "Experiment 004: Building a PLM User Module and RPU Firmware"
experiment = 4
date = 2026-09-22T00:00:00-07:00
description = "Generate a custom Versal PLM with an IPI user module, build matching Cortex-R5 firmware, and work around the Vitis 2025.2 xilplmi user-module header bug."
tags = ["PLM", "RPU", "IPI", "Vitis", "Bootgen"]
categories = ["Board Bring-Up"]
+++

This experiment moves below Linux and U-Boot to test communication between the Versal PLM and an RPU bare-metal application. The PLM is rebuilt with a custom `xilplmi` user module. The RPU firmware sends IPI commands to that module, waits for a response interrupt, and checks that the PLM returns the expected counter value.

The practical goal is not just to prove the IPI path. It is to make the PLM user-module build repeatable, because the Vitis 2025.2 generated BSP can fail when user modules are enabled unless its generated `xilplmi` headers are patched.

## Preliminary: Versal boot and programmable cores

It is tempting to describe this experiment as programming a third processor after Linux on the APU and firmware on the RPU. That is close enough for the lab workflow, but it needs one caveat: the PPU is not a general-purpose application processor in the same sense as the APU or RPU. The PPU is the PMC MicroBlaze that runs the Platform Loader and Manager, so user code reaches it by building a custom PLM with a registered user module.

For this lab, the practical firmware domains are:

| Domain | Processor | Typical software | User-programmable path |
| --- | --- | --- | --- |
| APU | Cortex-A72 cluster | TF-A, U-Boot, Linux | Normal Linux/U-Boot/application development. |
| RPU | Cortex-R5 cluster | Bare-metal, RTOS, or remoteproc firmware | Vitis standalone app, Rust/C firmware, or Linux remoteproc deployment. |
| PMC / PPU | MicroBlaze inside the PMC | PLM | Custom PLM build with `xilplmi` user modules. |
| PSM | Platform management MicroBlaze | PSM firmware | Board/platform firmware component; usually treated as platform support, not as the application target for this lab. |

So the PPU is the next interesting programmable control processor in this series, but not literally the last programmable processor-like block in every Versal design. There is also PSM firmware, and the programmable logic can contain additional MicroBlaze or custom soft processors. The distinction is useful: this experiment is about extending the boot and platform-management firmware path, not launching a normal standalone application on another user CPU.

## Preliminary: SOM boot sequence

The G57M boot flow is staged. Each stage proves enough hardware state to load the next one:

1. **BootROM** runs from immutable on-chip ROM in the Versal device. It samples the boot mode pins selected by SW4, locates the boot source such as PS JTAG or QSPI, authenticates or validates the boot header as configured, and starts the platform boot image.
2. **PLM** starts on the PMC PPU MicroBlaze. It owns early platform loading, device image processing, error handling, power-up sequencing, and handoff orchestration. In this experiment, the PLM also contains a custom user module.
3. **PSM firmware** runs on the platform management controller side and handles platform-management services needed after the earliest boot stage.
4. **TF-A / BL31** starts on the APU at EL3 and prepares the secure monitor environment used before non-secure software runs.
5. **U-Boot** starts on the APU at EL2. It handles board-level boot policy, networking, scripts, FIT loading, QSPI commands, and Linux handoff.
6. **Linux** starts on the APU. Linux may later load or manage RPU firmware through remoteproc, but this experiment can also package the RPU firmware directly into a PDI so PLM hands it off during boot.

The custom PLM in this page therefore sits very early in the chain. If the PLM user module is wrong, the system may fail before U-Boot or Linux has any chance to report a normal software error.

The same boot sequence is shown as a [Mermaid diagram in the reference page]({{< ref "/reference#versal-boot-chain-and-programmable-firmware-domains" >}}).

## Inputs and boundaries

| Input | Value |
| --- | --- |
| Board target | Versal platform used by the G57M lab |
| Tool release | Vitis 2025.2 |
| Hardware input | Versal XSA exported with a device image |
| PLM source overlay | `plm/src/common/xplm_ipi_ping_pong_module.c` |
| RPU source | `rpu-app/rpu_ipi_ping_pong/src/main.rs` |
| PLM processor/domain | `psv_pmc_0` / `standalone_psv_pmc_0` |
| RPU processor/domain | `psv_cortexr5_0` / `standalone_psv_cortexr5_0` |

The public firmware source for this experiment is kept separate from generated Vitis output. XSA files, generated platforms, BSP products, ELFs, and PDIs are board-local artifacts and should not be treated as source.

## What is being built

The PLM user module registers a user module ID and a single API command. The RPU sends a counter over IPI to the PMC, triggers the PLM, and waits for the PLM to return an incremented value.

The important runtime detail is that the PLM command handler sends the PLMI response before triggering the RPU interrupt. That keeps the RPU firmware interrupt-driven: the interrupt means the response buffer is ready, not merely that the PLM saw the request.

The RPU application intentionally waits a few seconds after boot before starting the ping-pong loop. In a combined PDI, PLM can hand off the RPU image before every PLM service path has settled into its command loop.

## Build command

Run the automation through Vitis from the firmware repository root:

```bash
vitis -s ./plm/build-plm \
  ./build \
  --xsa ./system.xsa \
  --custom-source-dir ./plm/src \
  --register-module xplm_ipi_ping_pong_module.h:XPlm_IpiPingPongModuleInit \
  --user-modules-count 1 \
  --rpu-source ./rpu-app \
  --rpu-app-name rpu_ipi_ping_pong \
  --rpu-cargo-package rpu_ipi_ping_pong \
  --rpu-platform-name rpu_platform \
  --rpu-processor psv_cortexr5_0 \
  --rpu-domain standalone_psv_cortexr5_0 \
  --rpu-core r5-0 \
  --symlink-sources \
  --force-regenerate \
  --embed-rpu-in-pdi
```

The script creates the PLM platform and application, overlays the maintained PLM source, registers the module init function in generated `xplm_module.c`, builds `plm.elf`, creates the RPU platform and application, exposes the Rust RPU workspace to the generated component, builds the RPU ELF with Cargo, and then uses Bootgen to generate PDI artifacts.

## Expected outputs

Typical generated files are:

```text
build/plm/build/plm.elf
build/rpu_ipi_ping_pong/build/rpu_ipi_ping_pong.elf
build/PLM_CUSTOM_JTAG.pdi
build/PLM_RPU_PRODUCTION.pdi
```

`PLM_CUSTOM_JTAG.pdi` is the PLM-only launch image used for PLM debug in Vitis. It does not load the RPU. When `--embed-rpu-in-pdi` is selected, `PLM_RPU_PRODUCTION.pdi` packages both the custom PLM and the RPU ELF so the RPU starts from the programmed image.

Keep these generated outputs out of the source repository. The repeatable inputs are the script, the custom PLM source, the RPU source, the XSA checksum, and the exact Vitis release.

## Boot evidence

A successful custom PLM is visible before U-Boot starts. In this run, the user module initialized immediately after the PLM banner and before the boot PDI load:

```text
[0.061]Xilinx Versal Platform Loader and Manager
[0.108]Release 2025.2   Sep 23 2026  -  00:18:59
[0.531]Non Secure Boot
[0.560]PLM IPI PING-PONG: module initialization started
[0.612]PLM IPI PING-PONG: registered module ID=0x80, API=1
[4.533]***********Boot PDI Load: Started***********
```

That placement matters. These lines prove that the custom `plm.elf` is the PLM running on the PMC PPU, not just a file that was built on the host. The module registers before TF-A, U-Boot, or Linux can print anything, so this is the earliest practical serial evidence that the custom PLM image is active.

## The user-module build bug

Enabling `XILPLMI_user_modules_count` can expose a Vitis 2025.2 generated-BSP issue in the AMD/Xilinx `xilplmi` library. The generated `xplmi_cmd.h` can reference `XPLMI_USER_MODULE_START_INDEX` before that macro is made visible from `xplmi_modules.h`, so the platform build fails inside generated PLM support code before the custom user-module source is the meaningful failure point.

This is treated as a **Vitis 2025.2 generated-workspace problem**, not as a permanent limitation of PLM user modules and not as a board-specific source bug. The lab remains pinned to 2025.2 because the current iWave G57M material targets that release, but the workaround should be removed if a later Vitis release generates the `xilplmi` headers correctly.

The same symptom can appear from an IDE-driven PLM workflow as well as from this script. The useful clue is where the failure occurs: if Vitis reports errors in generated `libsrc/xilplmi` files around `XPLMI_USER_MODULE_START_INDEX`, the build is failing in generated BSP code before the user module itself is the primary suspect.

{{< lab-figure src="images/vitis-2025-2-PLM-bsp-bug.png" alt="Vitis IDE 2025.2 showing generated PLM source and xilplmi build errors" caption="Vitis IDE 2025.2 can hit the same generated PLM/xilplmi dependency problem from an IDE-driven PLM workflow. The failure is in the generated BSP workspace, not in the user module source." >}}

The build script patches only the generated workspace, not the AMD installed tool tree:

1. Set the `xilplmi` library parameter `XILPLMI_user_modules_count`.
2. Generate or build the platform far enough for the BSP headers to exist.
3. Patch generated `xplmi_cmd.h` locations with a guarded `XPLMI_USER_MODULE_START_INDEX` definition derived from `XPLMI_MAX_MODULES`.
4. Guard the generated definition in `xplmi_modules.h` where needed.
5. Retry the platform build once if the first attempt failed before the patch landed.

That workaround is intentionally narrow and is applied only when PLM user modules are requested.

## PLM source overlay

The custom source directory is mapped into the generated PLM component:

```text
plm/src/common/ -> build/plm/src/common/
```

With `--symlink-sources`, the Vitis component points back to the maintained files rather than creating a hidden copy. The script then updates `UserConfig.cmake` so the extra C files are compiled and applies debug-friendly compile properties to those overlaid user sources only. Avoiding target-wide `-fno-lto` matters because a full PLM no-LTO build can exceed PPU TMR memory.

`--register-module` patches generated `xplm_module.c` to include the custom header and call `XPlm_IpiPingPongModuleInit()` before the function's `END:` error path label. If the init function fails, normal PLM status handling still sees the failure.

## RPU firmware path

The script creates a separate RPU platform and Vitis application. The platform name must differ from the PLM platform because the PLM platform owns the PMC domain. The RPU application is built from the Cargo package at `rpu-app/rpu_ipi_ping_pong/src/main.rs`.

In Vitis, the generated RPU application component is still useful for launch and debug metadata, but it is not the source of truth for the firmware source. For Rust builds, `build-plm` removes the generated empty-application C template, exposes the Cargo workspace under the component, builds with Cargo, and copies the resulting ELF into `build/rpu_ipi_ping_pong/build/rpu_ipi_ping_pong.elf`.

The firmware expects:

| Requirement | Reason |
| --- | --- |
| `XIpiPsu` instance generated for the RPU | The Rust app binds to the Xilinx IPI driver. |
| PMC mask `0x00000002` | The app targets the PMC/PLM IPI endpoint. |
| Interrupt setup support | The response path is interrupt-driven. |
| Shared UART discipline | PLM and RPU prints may interleave. |

The Cargo build uses generated BSP bindings and links against the Vitis standalone BSP archives. If binding generation fails around `XPAR_XIPIPSU_0_BASEADDR`, regenerate or inspect the hardware platform. The RPU domain did not receive the expected IPI instance.

The Rust package includes an optional minimal remoteproc resource table. The build script enables the `remoteproc` feature for Rust RPU builds, so Linux remoteproc can recognize the ELF even though this demo does not allocate RPMsg vrings or carveouts.

## Evidence to capture

For a useful lab record, save:

- the Vitis version and XSA checksum;
- the build command and complete script log;
- the paths and checksums for `plm.elf`, `rpu_ipi_ping_pong.elf`, and any generated PDI;
- Bootgen `-read` output for a combined PDI;
- UART output showing PLM module registration and RPU ping-pong completion.

The result to look for is repeated RPU messages showing a successful response interrupt and incremented counter, paired with PLM messages showing the user-module command handler receiving and responding to requests.

The next step is to prove the same behavior from the debugger, not only from UART. Capture XSDB or Vitis debugger sessions that attach to the already-running PPU/PLM and RPU firmware without resetting the board. The useful evidence is:

- the selected PPU and RPU targets in the debugger target list;
- symbols loaded from the exact `plm.elf` and `rpu_ipi_ping_pong.elf` used to boot;
- program counters, stack pointers, and key registers showing both processors in expected runtime state;
- breakpoints or watchpoints in the PLM user-module command handler and the RPU IPI response path;
- memory views of the IPI request and response buffers before and after a ping-pong transaction;
- a log showing that attaching the debugger did not require rebuilding, reflashing, or restarting the system.

That debugger capture is important because it separates "the firmware printed something once" from "the expected PPU and RPU code is alive, symbolized, inspectable, and synchronized while the system is running."

## Publishing the firmware source

The public source repo should contain the automation and maintained source only:

```text
README.md
.gitignore
plm/build-plm
plm/src/common/xplm_ipi_ping_pong_module.c
plm/src/common/xplm_ipi_ping_pong_module.h
rpu-app/Cargo.toml
rpu-app/Cargo.lock
rpu-app/.cargo/config.toml
rpu-app/bsp_bindings/
rpu-app/rpu_ipi_ping_pong/src/main.rs
rpu-app/rpu_ipi_ping_pong/src/remoteproc.rs
```

Do not publish generated workspaces, board-private XSA files, extracted vendor firmware, ELFs, PDIs, or serial logs unless they have been explicitly cleared for release.
