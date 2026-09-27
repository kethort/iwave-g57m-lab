+++
title = "Experiment 008: Implementing Versal Secure Boot"
experiment = 8
slug = "experiment-008-implementing-versal-secure-boot"
date = 2026-09-27T00:00:00-07:00
description = "Convert the working G57M boot chain into a secure-boot implementation plan, separating public automation from private keys, XSA files, and signed boot artifacts."
tags = ["Secure Boot", "Bootgen", "QSPI", "PLM", "Versal"]
categories = ["Board Bring-Up"]
+++

This experiment starts from the working unsigned boot flows and turns them into a secure-boot implementation path. The development-board goal is to create and test secure-boot-style images without programming eFUSEs or permanently changing the board security state. The goal is not to publish keys or signed images. The goal is to make the boundary clear: which artifacts are public automation, which artifacts are private build inputs, which tests are reversible, and which operations would make a permanent device-security change.

The secure-boot work should happen only after the normal JTAG, QSPI, PLM, RPU, and remoteproc paths are already understood. Secure boot is a policy layer on top of that known-good boot chain. It should not be the first place to debug basic PDI construction, U-Boot handoff, QSPI layout, or PLM/RPU firmware behavior.

## What This Proves

There are four separate claims to verify:

| Claim | Evidence |
| --- | --- |
| The unsigned boot chain is reproducible | The same PLM, PSM firmware, TF-A, U-Boot, handoff DTB, and Linux payloads boot before secure-boot attributes are added. |
| Bootgen secure packaging is repeatable | The secure BIF is generated from documented inputs and can be rebuilt without manual GUI-only state. |
| Private material stays private | Keys, XSA files, generated secure images, and provisioning logs are excluded from the public repo and site. |
| The board can still be recovered | JTAG, QSPI reflash, or another recovery path is proven before any eFUSE or permanent security-state change. |

## Public And Private Boundary

The public repository may include scripts, README files, and source patches that describe how the flow is assembled. It must not include:

- private signing keys or AES keys;
- board-private XSA files;
- signed or encrypted boot images;
- generated PDIs, BOOT images, or Bootgen logs containing sensitive paths or key metadata;
- eFUSE programming files or irreversible provisioning transcripts.

Keep the private secure-boot workspace separate from the public source tree. A useful layout is:

```text
secure-boot-private/
├── keys/
├── input-artifacts/
├── bif/
├── output/
└── logs/
```

Only the public-safe automation belongs in Git. The private workspace is the place for device-specific inputs and generated secure artifacts.

## Inputs

Start with the same boot chain that already works without secure boot:

| Input | Role |
| --- | --- |
| Base design PDI or extracted platform boot image | Carries the hardware platform and programmable-device image data. |
| Custom `plm.elf` | PLM used by the platform boot image. |
| `psmfw.elf` | Platform management firmware. |
| `arm-trusted-firmware.elf` | BL31 / TF-A handoff stage. |
| `u-boot.elf` | First non-secure bootloader payload. |
| Handoff DTB | Device tree consumed by firmware/U-Boot handoff. |
| Linux payloads or FIT | Kernel, Linux DTB, and root filesystem payloads used by the selected boot mode. |
| Secure-boot keys | Private signing and optional encryption material, kept outside the public repo. |

The secure package should be built from known-good unsigned artifacts first. If the unsigned artifacts do not boot, secure boot will only make the failure harder to inspect.


## Development Variant Without eFUSEs

For a development board, the safe first variant is a no-eFUSE secure-boot exercise:

1. Generate authentication keys in a private workspace.
2. Build a signed or otherwise security-attributed Bootgen image from known-good inputs.
3. Boot it through JTAG first.
4. Program it to QSPI only after JTAG boot works.
5. Keep the board in its normal development security state and do not program PPK hashes, AES key material, revocation bits, or other security-control eFUSEs.

QSPI is persistent, but it is still reprogrammable. A bad QSPI image can normally be erased or replaced by returning to a JTAG boot/provisioning flow. The non-reversible boundary is not "using QSPI"; it is programming device security state such as eFUSE-backed root-of-trust settings or key material.

This no-eFUSE variant is useful for examples because it proves the Bootgen flow, BIF structure, key handling discipline, image layout, and recovery process. It should not be described as production-enforced secure boot. Production secure boot depends on device security state, including eFUSE-backed key or policy configuration, so an attacker cannot simply replace both the image and the public key material.

## Implemented No-eFUSE Helper

The lab repo includes a helper for the first development image:

```bash
./scripts/build-secure-boot-dev-pdi \
    --firmware-root /path/to/iwave-g57m-plm-rpu-ipi-demo
```

For this workstation, that firmware checkout is currently `/home/user/vitis_projects/secure-boot`; use that path when reproducing the local run.

The helper consumes the already-built firmware artifacts:

```text
plm/build/platform/hw/sdt/system.pdi
plm/build/plm/build/plm.elf
plm/build/rpu_ipi_ping_pong/build/rpu_ipi_ping_pong.elf
```

It writes private output under this lab repo:

```text
secure-boot-private/dev-auth/
```

That private directory is ignored by Git. It contains the development signing keys, generated BIF, authenticated PDI, Bootgen readback log, and Bootgen verification log. The expected verification result is `BootHeader Signature Verified`, `SPK Signature Verified`, and `Partition Signature Verified` for the signed PLM/RPU partitions.

## Build Strategy

Treat secure boot as a staged conversion:

1. Rebuild or collect the unsigned boot chain and prove it still boots over JTAG.
2. Generate a non-secure BIF from the exact same inputs and confirm Bootgen can reproduce the known-good image.
3. Add authentication attributes to the BIF and verify Bootgen produces the expected secure image.
4. Add encryption only after authenticated boot is understood and recoverable.
5. Program temporary or recoverable boot media first.
6. Move to persistent QSPI only after the same image boots from the temporary path.
7. Do not program eFUSEs or other permanent security state until the recovery procedure has been tested and documented.

The first image should be a lab image, not the final production policy. Keep debug and recovery paths available until the boot chain has survived power cycles, cold boots, and intentionally bad-image tests.

## Bootgen Boundary

Bootgen is the point where the normal boot image becomes a secure image. The BIF should be treated as source code for the boot policy. Keep it readable, versioned if it contains no secrets, and small enough to audit.

The local lab already uses Bootgen to rebuild PDIs from explicit inputs. Secure boot should extend that pattern rather than relying on hand-edited generated state. The secure BIF should make these choices explicit:

- which image or partitions are authenticated;
- which partitions, if any, are encrypted;
- where the PLM, PSM firmware, TF-A, U-Boot, handoff DTB, and Linux payloads enter the image;
- which key files are referenced from the private workspace;
- which output file is safe to program to the selected boot medium.

Do not commit the secure BIF if it exposes private key filenames, serial-numbered paths, or provisioning policy that should stay private. If the structure is useful publicly, publish a redacted template instead.

## JTAG Validation First

Before QSPI or any permanent provisioning, use JTAG to test the image in the least persistent way available. The test should answer:

- Does BootROM accept the image header and authentication policy?
- Does PLM start and produce expected UART output?
- Does handoff reach TF-A and U-Boot?
- Does Linux boot from the expected payload?
- Can the board be reset and recovered if the image is rejected?

For failures, separate packaging errors from board-security-state errors. A Bootgen failure is a host-side image construction issue. A BootROM authentication failure means the device rejected the image at boot time. A later U-Boot or Linux failure means secure boot likely succeeded and the normal boot chain failed later.

## QSPI Validation

After JTAG validation, repeat the test through QSPI using the same caution as the persistent-boot experiment. This is still a reversible development-board step as long as no permanent security state is programmed:

1. Write only to the intended QSPI offsets.
2. Verify readback before changing boot mode.
3. Power off before changing SW4.
4. Boot from QSPI and confirm the same UART milestones.
5. Keep a known-good recovery image and JTAG path available.

At this stage, QSPI proves persistence and recovery. It does not by itself prove a final production trust policy. That proof depends on the device key state and the exact authentication/encryption configuration used by Bootgen.

## Irreversible Device State

Any step that programs eFUSEs or otherwise changes permanent device security state belongs outside the no-eFUSE development example, or at the very end of a separate production-provisioning experiment. Before doing that, the lab should have:

- a known-good secure image;
- a known-good recovery process;
- a written key-backup and key-rotation plan;
- a record of which boot modes remain allowed;
- confirmation that the selected policy matches the board and silicon lifecycle state.

Do not use a development board as the first place to test an irreversible production policy. Prove the image construction and recovery workflow first.

## Current Status

The public lab state is ready for secure-boot implementation planning:

- the baseline Linux boot artifacts have been reproduced;
- JTAG and QSPI boot flows are documented;
- custom PLM and RPU firmware builds are reproducible;
- RPU firmware can be deployed through Linux `remoteproc`;
- PPU/RPU debugger attachment is understood.

The remaining secure-boot work is to build the private key workspace, write the secure BIF or redacted template, generate the first authenticated image, validate it through JTAG, and then test the same image from reprogrammable QSPI without touching eFUSEs.
