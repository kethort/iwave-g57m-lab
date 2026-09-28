+++
title = "Experiment 009: Implementing Versal Secure Boot"
experiment = 9
slug = "experiment-009-implementing-versal-secure-boot"
date = 2026-09-27T00:00:00-07:00
description = "Build and verify a no-eFUSE authenticated Versal PDI from the PLM/RPU firmware artifacts while keeping keys and signed images private."
tags = ["Secure Boot", "Bootgen", "QSPI", "PLM", "Versal"]
categories = ["Board Bring-Up"]
+++

This experiment starts from the working unsigned boot flows and turns them into a secure-boot implementation path. The development-board goal is to create and test secure-boot-style images without programming eFUSEs or permanently changing the board security state. The goal is not to publish keys or signed images. The goal is to make the boundary clear: which artifacts are public automation, which artifacts are private build inputs, which tests are reversible, and which operations would make a permanent device-security change.

The secure-boot work should happen only after the normal JTAG, QSPI, PLM, RPU, remoteproc, and DMA-backed PLM/RPU payload paths are already understood. Secure boot is a policy layer on top of that known-good boot chain. It should not be the first place to debug basic PDI construction, U-Boot handoff, QSPI layout, or PLM/RPU firmware behavior.

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

## Tutorial: Build A No-eFUSE Authenticated PDI

This tutorial creates a signed development PDI without programming eFUSEs or changing the board security state. It signs the custom PLM and RPU partitions, enables Boot Header authentication metadata, and verifies the authentication certificates with Bootgen.

Required repositories:

| Repo | Used for |
| --- | --- |
| [Versal Boot GUI lab repo](https://github.com/kethort/iwave-g57m-lab) | This experiment page and the surrounding lab documentation. |
| [PLM/RPU IPI demo firmware repo](https://github.com/kethort/iwave-g57m-plm-rpu-ipi-demo) | The custom PLM source, Rust RPU firmware, generated Vitis workspace, and `scripts/build-secure-boot-dev-pdi` helper. |

On this workstation, the firmware repo is currently checked out at:

```text
/home/user/vitis_projects/secure-boot
```

### 1. Build the unsigned PLM/RPU workspace first

From the firmware repo, build the normal PLM/RPU artifacts exactly as in Experiment 006. The secure-boot helper consumes these generated files; it does not rebuild the Vitis workspace for you.

The expected inputs are:

```text
plm/build/platform/hw/sdt/system.pdi
plm/build/plm/build/plm.elf
plm/build/rpu_ipi_ping_pong/build/rpu_ipi_ping_pong.elf
```

Confirm they exist before continuing:

```bash
cd /home/user/vitis_projects/secure-boot
find plm/build -type f \
  \( -path '*/platform/hw/sdt/system.pdi' \
     -o -path '*/plm/build/plm.elf' \
     -o -path '*/rpu_ipi_ping_pong/build/rpu_ipi_ping_pong.elf' \) \
  -print
```

### 2. Generate the authenticated development PDI

Run the secure-boot helper from the firmware repo:

```bash
cd /home/user/vitis_projects/secure-boot

./scripts/build-secure-boot-dev-pdi
```

The helper writes all private/generated output under the firmware repo:

```text
secure-boot-private/dev-auth/
```

That directory is ignored by Git. It contains development signing keys, generated BIF files, the authenticated PDI, and Bootgen logs.

### 3. Inspect the generated BIF

The generated BIF is:

```text
secure-boot-private/dev-auth/secure-dev-pdi.bif
```

The important pieces are:

```text
boot_config { bh_auth_enable }
pskfile = ".../keys/primary.pem"
sskfile = ".../keys/secondary.pem"

partition
{
    type = bootloader
    authentication = rsa
    file = ".../plm.elf"
}

partition
{
    core = r5-0
    authentication = rsa
    file = ".../rpu_ipi_ping_pong.elf"
}
```

This proves the example is applying authentication to the custom PLM and RPU firmware. The base design PDI is reused as a `type = bootimage` input so the secure-boot exercise stays close to the already-working PLM/RPU PDI flow.

### 4. Verify the authentication certificates

The helper runs `bootgen -verify` automatically. The verification log is:

```text
secure-boot-private/dev-auth/SECURE_DEV_PLM_RPU_JTAG.verify.txt
```

The expected result is:

```text
Verifying Partition pmc_subsys.0
    BootHeader Signature Verified
    SPK Signature Verified
    Partition Signature Verified

Verifying Partition def_subsystem.0
    SPK Signature Verified
    Partition Signature Verified

Verifying Partition def_subsystem.1
    SPK Signature Verified
    Partition Signature Verified

Authentication is verified on bootimage .../SECURE_DEV_PLM_RPU_JTAG.pdi
```

If this step fails, fix the BIF, key paths, or input artifacts before trying to boot the image.

### 5. Inspect Bootgen readback

The readback log is:

```text
secure-boot-private/dev-auth/SECURE_DEV_PLM_RPU_JTAG.read.txt
```

Useful checks are:

```bash
rg -n 'bh_auth|auth_header|ac_offset|pmc_subsys|def_subsystem' \
  secure-boot-private/dev-auth/SECURE_DEV_PLM_RPU_JTAG.read.txt
```

Look for `bh_auth [enabled]` and nonzero authentication-certificate offsets on the signed PLM/RPU partitions.

### 6. Optional: load the PDI over JTAG

Only do this after the unsigned PLM/RPU image has already booted successfully. Set SW4 for PS JTAG, start `hw_server`, open a serial console, and program the generated PDI with XSDB:

```tcl
connect -url TCP:127.0.0.1:3121
targets -set -filter {name =~ "Versal*"}
device program /home/user/vitis_projects/secure-boot/secure-boot-private/dev-auth/SECURE_DEV_PLM_RPU_JTAG.pdi
```

The useful UART evidence is the same as the PLM/RPU experiment: PLM starts, the custom user module registers, and the RPU ping-pong path runs. This JTAG test does not program QSPI and does not make the board secure-boot-only.

### 7. Keep the private artifacts private

Before committing or publishing, verify that private output is ignored:

```bash
git check-ignore -v \
  secure-boot-private/dev-auth/SECURE_DEV_PLM_RPU_JTAG.pdi \
  secure-boot-private/dev-auth/keys/primary.pem
```

Do not publish:

- `secure-boot-private/`;
- private keys;
- generated signed PDIs or BOOT images;
- board-private XSA files;
- eFUSE provisioning files or transcripts.

## What This Does Not Do

This tutorial does **not** program PPK hashes, AES key material, revocation bits, BBRAM, or any other irreversible device-security state. It is a no-eFUSE development flow that proves Bootgen authentication packaging and verification. Production-enforced secure boot is a separate provisioning step that depends on device security state, key policy, lifecycle assumptions, and recovery planning.

## Next Steps

After the JTAG PDI boots, the next reversible step is to adapt the same authenticated-image pattern to the QSPI provisioning flow. QSPI is persistent but recoverable; the irreversible boundary remains eFUSE or equivalent permanent security-state programming, not merely writing a new image to flash.
