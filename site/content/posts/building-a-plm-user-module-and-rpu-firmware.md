+++
title = "Experiment 004: Building a PLM User Module and RPU Firmware"
date = 2026-09-22T00:00:00-07:00
description = "Generate a custom Versal PLM with an IPI user module, build matching Cortex-R5 firmware, and work around the Vitis 2025.2 xilplmi user-module header bug."
tags = ["PLM", "RPU", "IPI", "Vitis", "Bootgen"]
categories = ["Board Bring-Up"]
+++

This experiment moves below Linux and U-Boot to test communication between the Versal PLM and an RPU bare-metal application. The PLM is rebuilt with a custom `xilplmi` user module. The RPU firmware sends IPI commands to that module, waits for a response interrupt, and checks that the PLM returns the expected counter value.

The practical goal is not just to prove the IPI path. It is to make the PLM user-module build repeatable, because the Vitis 2025.2 generated BSP can fail when user modules are enabled unless its generated `xilplmi` headers are patched.

## Inputs and boundaries

| Input | Value |
| --- | --- |
| Board target | Versal platform used by the G57M lab |
| Tool release | Vitis 2025.2 |
| Hardware input | Versal XSA exported with a device image |
| PLM source overlay | `plm/src/common/xplm_ipi_ping_pong_module.c` |
| RPU source | `rpu-app/src/main.c` |
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
  --rpu-source ./rpu-app/src \
  --rpu-app-name rpu_ipi_ping_pong \
  --rpu-platform-name rpu_platform \
  --rpu-processor psv_cortexr5_0 \
  --rpu-domain standalone_psv_cortexr5_0 \
  --rpu-core r5-0 \
  --symlink-sources \
  --force-regenerate \
  --embed-rpu-in-pdi
```

The script creates the PLM platform and application, overlays the maintained PLM source, registers the module init function in generated `xplm_module.c`, builds `plm.elf`, creates the RPU platform and application, overlays the RPU source, builds the RPU ELF, and then uses Bootgen to generate PDI artifacts.

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

The script creates a separate RPU platform and Vitis application. The platform name must differ from the PLM platform because the PLM platform owns the PMC domain. The RPU application is built from `rpu-app/src/main.c`.

The firmware expects:

| Requirement | Reason |
| --- | --- |
| `XIpiPsu` instance generated for the RPU | The app uses the Xilinx IPI driver. |
| PMC mask `0x00000002` | The app targets the PMC/PLM IPI endpoint. |
| Interrupt setup support | The response path is interrupt-driven. |
| Shared UART discipline | PLM and RPU prints may interleave. |

If the build fails with the source-level error about `XPAR_XIPIPSU_0_BASEADDR`, regenerate or inspect the hardware platform. The RPU domain did not receive the expected IPI instance.

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
rpu-app/src/main.c
```

Do not publish generated workspaces, board-private XSA files, extracted vendor firmware, ELFs, PDIs, or serial logs unless they have been explicitly cleared for release.
