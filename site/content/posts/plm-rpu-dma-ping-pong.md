+++
title = "Experiment 008: Replacing IPI Message Buffers with DMA"
experiment = 8
slug = "experiment-008-replacing-ipi-message-buffers-with-dma"
date = 2026-09-27T00:00:00-07:00
description = "Move the PLM/RPU ping-pong payload out of the IPI message buffer and into DMA-visible memory while keeping IPI as the interrupt and command doorbell."
tags = ["PLM", "RPU", "IPI", "DMA", "Vitis"]
categories = ["Board Bring-Up"]
+++

This experiment updates the PLM/RPU ping-pong demo from a small IPI-message-buffer exchange to a DMA-backed exchange. The IPI interrupt is still part of the design. What changed is the payload path: IPI now carries the command, shared-buffer addresses, transfer length, sequence number, and token; the actual request and response data move through memory copied by DMA-capable paths on each side.

The firmware change is in the [PLM/RPU IPI demo firmware repo](https://github.com/kethort/iwave-g57m-plm-rpu-ipi-demo), commit `0cf72ff` (`Add PLM RPU DMA ping-pong test`).

## What Changed

The earlier PLM/RPU test used the IPI message buffer itself as the data path. The RPU wrote a short command payload to the PMC IPI buffer, triggered the PLM, and waited for the PLM to write the response buffer and trigger the RPU interrupt.

That small IPI ping is still present as API `1`, but the new DMA path adds API `2`:

| Path | API | Data path | IPI role |
| --- | --- | --- | --- |
| Original ping | `1` | IPI request and response words | Command delivery and completion interrupt. |
| DMA ping-pong | `2` | Shared request/response buffers copied through DMA paths | Doorbell, metadata transfer, PLM response, and RPU completion interrupt. |

This is an important distinction. The experiment does **not** remove IPI. It removes the bulk payload from the IPI message buffer so larger or more realistic transfers can use memory instead of mailbox words.

## Firmware Changes

The commit changes three areas:

| File | Purpose |
| --- | --- |
| `plm/src/common/xplm_ipi_ping_pong_module.c` | Adds the PLM DMA command handler and registers API `2`. |
| `plm/rpu-app/rpu_ipi_ping_pong/src/main.rs` | Adds aligned DMA buffers, request/response validation, and the RPU-side DMA transaction before each normal ping. |
| `plm/rpu-app/bsp_bindings/*` | Exposes RPU-side DMA helpers, cache maintenance, UART idle waiting, and the `xzdma` BSP binding to Rust. |

The PLM module now initializes as:

```text
PLM IPI PING-PONG: custom module initialized (PING + DMA)
```

That line is the first useful proof that the running PLM is the newer build, not the previous IPI-only version.

## DMA Command Contract

The RPU sends an IPI command for API `2` with five payload words:

| Word | Meaning |
| --- | --- |
| `0` | Request buffer address. |
| `1` | Response buffer address. |
| `2` | Transfer size in bytes. |
| `3` | Sequence number. |
| `4` | Request token derived from address, length, and sequence. |

The command still uses the normal PLMI user-module command header. In the Rust app, the API `2` command header is built from:

```text
module = 0x80
api    = 2
words  = 5
```

The current transfer is deliberately small and inspectable:

```text
DMA words  = 16
DMA bytes  = 64
request magic  = 0x444D4131
response magic = 0x444D4132
```

The fixed 64-byte size keeps cache alignment and debug inspection straightforward while proving the control pattern.

## RPU Side

The RPU allocates four 64-byte aligned buffers:

```text
DMA_LOCAL_TX
DMA_SHARED_REQUEST
DMA_SHARED_RESPONSE
DMA_LOCAL_RX
```

The transaction sequence is:

1. Fill `DMA_LOCAL_TX` with a deterministic request pattern.
2. Compute the request checksum.
3. Copy `DMA_LOCAL_TX` to `DMA_SHARED_REQUEST` using `RpuDmaCopy`.
4. Verify the shared request buffer checksum.
5. Send the PLM API `2` IPI command with request/response addresses and byte length.
6. Wait for the RPU IPI interrupt from PLM.
7. Validate the PLMI response status, checksum, sequence, and token.
8. Invalidate and copy `DMA_SHARED_RESPONSE` into `DMA_LOCAL_RX`.
9. Verify the response magic, sequence, and checksum.
10. Run the original API `1` ping as a small control transaction.

The RPU-side BSP wrapper also enables and configures ZDMA, flushes source cache lines, invalidates destination cache lines, and reports transfer status. The debug output includes lines like:

```text
RPU ZDMA: src=... dst=... len=64 state=... isr=... bytes=64
RPU DMA: TX seq=... local=... shared=... resp=... checksum=...
RPU DMA: RX ISR #... status=0x00000000 checksum=... sequence=... token=...
RPU DMA: DMA ping-pong seq=... complete, response count=...
```

## PLM Side

The PLM handler for API `2` receives the metadata through the IPI payload, then copies through PLM memory services:

1. Validate payload length, byte count, and request token.
2. Copy the request buffer into an aligned PLM scratch buffer with `XPlmi_MemCpy64`.
3. Validate request magic, sequence, and word count.
4. Compute a checksum over the request.
5. Fill an aligned PLM response scratch buffer with a deterministic transformed response.
6. Copy the response scratch buffer back to the RPU-provided response address.
7. Send the PLMI response words.
8. Trigger the RPU IPI interrupt so the RPU knows the response is ready.

The expected PLM-side DMA log looks like:

```text
PLM DMA: request #... seq=... status=0x00000000 bytes=64 checksum=...
```

The PLM still explicitly sends the response before triggering the RPU. That preserves the rule established in the previous experiment: the RPU interrupt means the response buffer is ready to inspect.

## Why This Matters

IPI mailboxes are good for small control messages. They are not the place to grow a protocol that needs larger payloads, structured buffers, or data movement that looks more like a real firmware service. This DMA version separates the two jobs:

- IPI remains the synchronization and command mechanism.
- DMA-visible memory becomes the payload mechanism.

That makes the PLM/RPU demo a better model for later services where the RPU asks PLM to process or transform a buffer instead of only incrementing a counter.

## Rebuild The Firmware

From the firmware repo, rebuild the same PLM/RPU workspace used in Experiments 006 and 007:

```bash
cd /home/user/vitis_projects/secure-boot

vitis -s ./plm/build-plm \
    ./plm/build \
    --xsa ./system.xsa \
    --custom-source-dir ./plm/src \
    --register-module xplm_ipi_ping_pong_module.h:XPlm_IpiPingPongModuleInit \
    --user-modules-count 1 \
    --rpu-source ./plm/rpu-app \
    --rpu-app-name rpu_ipi_ping_pong \
    --rpu-cargo-package rpu_ipi_ping_pong \
    --rpu-platform-name rpu_platform \
    --rpu-processor psv_cortexr5_0 \
    --rpu-domain standalone_psv_cortexr5_0 \
    --rpu-core r5-0 \
    --symlink-sources \
    --force-regenerate \
    --launch-vitis
```

The important outputs remain:

```text
plm/build/plm/build/plm.elf
plm/build/rpu_ipi_ping_pong/build/rpu_ipi_ping_pong.elf
```

Use the matching pair when loading symbols. A DMA-capable RPU ELF with an older PLM will fail because API `2` is not registered in the older module.

## Deploy With remoteproc

Boot Linux as in Experiment 007, then deploy the new RPU ELF with the existing helper:

```bash
cd /development/xilinx-dev/iwg57m-2025-2/scripts

./load_remoteproc_elf.sh \
  --user root \
  --password root \
  --ip 192.168.0.137 \
  --remoteproc /sys/class/remoteproc/remoteproc0 \
  --firmware-name rpu_ipi_ping_pong.elf \
  --no-breakpoint \
  /home/user/vitis_projects/secure-boot/plm/build/rpu_ipi_ping_pong/build/rpu_ipi_ping_pong.elf
```

Then confirm Linux reports the RPU firmware running:

```bash
ssh root@192.168.0.137 \
  'cat /sys/class/remoteproc/remoteproc0/state; cat /sys/class/remoteproc/remoteproc0/firmware'
```

## Evidence To Capture

For this experiment, save evidence that proves both halves of the change:

- firmware repo commit `0cf72ff` or later;
- the rebuilt `plm.elf` and `rpu_ipi_ping_pong.elf` paths and checksums;
- PLM UART output showing `custom module initialized (PING + DMA)`;
- RPU UART output showing `RPU ZDMA`, `RPU DMA: TX`, `RPU DMA: RX ISR`, and `DMA ping-pong ... complete`;
- PLM UART output showing `PLM DMA: request ... status=0x00000000 bytes=64`;
- the original `RPU (Rust): ping-pong ... complete` lines still running after each DMA transfer;
- Vitis or XSDB debugger evidence, if captured, showing the API `2` PLM handler and RPU `send_dma_command` path.

The key proof is not just that an interrupt fired. The proof is that the request buffer checksum survives the RPU DMA copy, the PLM reads and transforms the request through its DMA-capable copy path, the response buffer is copied back, and the RPU receives the IPI interrupt only after the response metadata and buffer are ready.

## Failure Boundaries

Common failure boundaries are now different from the IPI-only test:

| Symptom | Likely area |
| --- | --- |
| API `2` returns failure immediately | PLM module mismatch, bad command length, bad token, or wrong byte count. |
| RPU ZDMA timeout or error | RPU DMA initialization, clocking, address reachability, or cache maintenance. |
| PLM DMA status is nonzero | PLM cannot copy from or to the supplied buffer addresses. |
| Checksum mismatch | Cache maintenance, wrong buffer address, stale response data, or mismatched firmware pair. |
| Original API `1` ping still works but DMA fails | IPI wiring is good; focus on DMA-visible memory and cache/DMA setup. |

Keep the original IPI ping in the loop while debugging. It is a useful control path: if API `1` works and API `2` fails, the doorbell and interrupt path are alive and the failure is in the new DMA payload path.
