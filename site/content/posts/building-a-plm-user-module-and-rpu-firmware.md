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

## The user-module build bug

The failure appears after enabling `XILPLMI_user_modules_count`. Vitis 2025.2 can generate xilplmi BSP headers such that `xplmi_cmd.h` needs `XPLMI_USER_MODULE_START_INDEX` before that macro is visible from `xplmi_modules.h`. The platform build can fail before the PLM application reaches the normal compile stage.

This is documented here as a **Vitis 2025.2 generated-workspace problem**, not as a permanent rule about PLM user modules. The issue is the order and guarding of generated xilplmi header content in the local BSP output. Later Vitis revisions may generate the headers differently or may already contain a fix. In that case, this workaround should become unnecessary and should not be carried forward blindly.

The lab stays pinned to 2025.2 because the current iWave G57M manufacturer BSP and development material used here cover that release. Mixing a newer Vitis release with a 2025.2 board support stack may introduce unrelated changes in generated platforms, firmware libraries, device-tree output, Bootgen behavior, or handoff assumptions. Until the vendor baseline moves forward, this note treats 2025.2 as the reproducible target and patches only the generated files needed to make that release build the requested PLM user module.

The symptom that identifies this specific problem is a compile failure in generated xilplmi headers around `XPLMI_USER_MODULE_START_INDEX`, before the custom user-module source itself is the meaningful failure point. If a future release builds without that failure, leave the generated headers alone and remove or disable the patch step for that build.

The same failure path can appear without this lab automation. With the 2025.2 iWave BSP, even a PLM-oriented example driven directly from the Vitis IDE can trip the generated-header dependency loop while the IDE is building or programming through the generated platform. That is the important clue: the script is not creating a new PLM circular dependency. It is exposing the same generated BSP ordering problem that the IDE can encounter once PLM user-module support is involved.

When this happens in the IDE, the useful evidence is not the active editor tab or the bare-metal example source. Look at the Vitis messages and generated `libsrc/xilplmi` paths. If the failure is in generated PLM/xilplmi files before application-specific code is the meaningful compile failure, treat it as this 2025.2 generated-workspace issue.

{{< lab-figure src="images/vitis-2025-2-PLM-bsp-bug.png" alt="Vitis IDE 2025.2 showing generated PLM source and xilplmi build errors" caption="Vitis IDE 2025.2 can hit the same generated PLM/xilplmi dependency problem from an IDE-driven PLM workflow. The failure is in the generated BSP workspace, not in the user module source." >}}

The build script fixes the generated workspace, not the AMD installed tool tree:

1. Set the `xilplmi` library parameter `XILPLMI_user_modules_count`.
2. Generate or build the platform far enough for the BSP headers to exist.
3. Patch generated `xplmi_cmd.h` locations with a guarded `XPLMI_USER_MODULE_START_INDEX` definition derived from `XPLMI_MAX_MODULES`.
4. Guard the generated definition in `xplmi_modules.h` where needed.
5. Retry the platform build once if the first attempt failed before the patch landed.

That workaround is intentionally narrow. It is applied only under the generated Vitis workspace and only when user modules are requested.

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
