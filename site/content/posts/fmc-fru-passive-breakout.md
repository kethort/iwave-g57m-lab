+++
title = "Experiment 003: Teaching a Passive FMC Breakout to Identify Itself"
experiment = 3
slug = "teaching-a-passive-fmc-breakout-to-identify-itself"
date = 2026-09-22T00:00:00-07:00
description = "Bring up the iWave G57M safely, add an AT24C64 FMC FRU, preserve JTAG continuity, and prove that the carrier selected the intended 1.2 V VADJ rail."
tags = ["FMC", "FRU", "I2C", "JTAG", "U-Boot"]
categories = ["Board Bring-Up"]
+++

This experiment makes one controlled hardware change to the iWave G57M Versal AI Edge VE2302 SOM and G57D R2.0 carrier: add a small EEPROM that makes a passive FMC LPC breakout identifiable to the carrier.

The result is useful, but the path exposed two details that are easy to miss: the EEPROM protocol expected by this U-Boot build and the effect of FMC presence on the JTAG chain.

## Establish the unmodified baseline

iWave's [official getting-started guide](https://iwave-global.com/knowledge-base/products/get-started-with-versal-ai-edge-prime-som-development-platform/) is the source of truth for the initial carrier setup. The minimum observable baseline is:

| Check | Configuration |
| --- | --- |
| Handling | Grounded ESD-safe workspace |
| Power | Supplied 12 V supply connected at J2; SW1 controls power |
| Boot selection | SW4 set for the intended boot mode |
| Debug and JTAG | J8 USB Type-C; SW3 OFF for JTAG |
| Serial console | 115200 baud, 8 data bits, no parity, 1 stop bit, no flow control |

Do this first with the FMC breakout disconnected. Confirm that serial output appears and that the host can scan the onboard JTAG chain. That gives every later failure a useful boundary.

> **Power boundary:** do not insert or remove the SOM or FMC breakout with power applied. Set the FMC VADJ select switch before power-up. This experiment uses **1.2 V** VADJ.

## Hardware used

- iWave G57M VE2302 SOM and G57D R2.0 carrier.
- Passive [FMC LPC breakout, item 357886097671](https://www.ebay.com/itm/357886097671).
- [MusRock AT24C64 I2C EEPROM module](https://www.amazon.com/MusRock-AT24C64-EEPROM-Module-Interface/dp/B0FTFXM5CW/).
- Arduino Uno for off-board EEPROM programming.
- Optional J19 breakout: [Samtec SFSD-30-28-G-06.00-S](https://www.digikey.com/en/products/detail/samtec-inc/SFSD-30-28-G-06-00-S/8420769), used for later PS GPIO work but not required to program this FRU.

The FMC card is passive. It exposes connector signals but supplies no JTAG TAP and no FRU EEPROM of its own.

## Wire presence, FRU, and JTAG bypass

Wire the AT24C64 as follows with the carrier powered off:

| FMC signal | EEPROM or connection | Purpose |
| --- | --- | --- |
| D32 `3P3VAUX` | `VCC` | Auxiliary 3.3 V supply |
| C30 `SCL` | `SCL` | FRU I2C clock |
| C31 `SDA` | `SDA` | FRU I2C data |
| FMC ground | `GND`, `A0`, `A1`, `A2`, `WP` | Address 0x50; writes enabled |
| H2 `PRSNT_M2C_L` | FMC Ground | Assert mezzanine presence |
| D30 `JTAG TDI` | D31 `JTAG TDO` | Passive scan-chain bypass |

{{< lab-figure src="https://i.ebayimg.com/images/g/7GIAAeSwEcxpQfuR/s-l1600.webp" alt="Passive FMC LPC breakout card with labeled C, D, G, and H signal headers" caption="The passive FMC LPC breakout used for this experiment. Product photograph from the irvinebreakoutelectronics listing; the added EEPROM and jumper wiring are not shown." >}}

Grounding `PRSNT_M2C_L` made the carrier inspect the card, but it also inserted the FMC path into the JTAG chain. With no TAP on the passive breakout, the chain was open. Bridging D30 TDI directly to D31 TDO restored the onboard USB JTAG scan chain while presence remained asserted.

Do not remove this bypass unless a real JTAG-capable device is inserted into that path.

## Why AT24C64 instead of AT24C02

Capacity was not the deciding factor. This iWave U-Boot FMC implementation accessed the FRU with a **two-byte internal EEPROM offset**. An AT24C02 uses a one-byte internal address for this operation; the AT24C64 uses two bytes and matched the observed U-Boot behavior.

The distinction can be checked at the U-Boot prompt:

```text
i2c dev 3
i2c olen 50
```

For the working device at address `0x50`, `i2c olen 50` reports an offset length of 2.

## Program the 256-byte FRU

The FRU is structured identification data, not firmware. The supplied Arduino sketch writes the 256-byte VITA/IPMI FMC FRU at EEPROM offset `0x0000`, ACK-polls each write, reads every byte back, and only reports success if all bytes match.

For off-board programming, connect the Arduino Uno before installing the EEPROM on the FMC breakout:

| Arduino Uno | AT24C64 |
| --- | --- |
| A4 / SDA | SDA |
| A5 / SCL | SCL |
| GND | GND, A0, A1, A2, WP |
| Appropriate supply | VCC |

{{< download href="downloads/fmc-fru/program_at24c02.ino" label="Arduino EEPROM programmer" meta="PROGRAM_AT24C02.INO" >}}
{{< download href="downloads/fmc-fru/fmc_fru_image.h" label="256-byte FMC FRU image" meta="FMC_FRU_IMAGE.H" >}}
{{< download href="downloads/fmc-fru/g57m_fmc_lpc_fru.bin" label="Raw FRU binary" meta="256 BYTES" >}}

The sketch kept its original filename, but its transaction format is for the AT24C64: it sends the internal address most-significant byte first, then least-significant byte.

```cpp
Wire.write((uint8_t)(memAddr >> 8));
Wire.write((uint8_t)(memAddr & 0xFF));
```

The required completion message is:

```text
VERIFY PASS: all 256 FRU bytes match.
```

## Verify from U-Boot

Install the programmed EEPROM and passive bypass, set FMC VADJ to 1.2 V, then power the carrier. Interrupt autoboot and run:

```text
i2c dev 3
i2c probe
i2c olen 50
i2c md 0x50 0x0000.2 0x80
frudump 3 50
```

On the working setup, U-Boot sees the FMC FRU EEPROM at `0x50`, reports a two-byte internal offset, and can dump the first 128 bytes:

```text
IWG57M> i2c dev 3
Setting bus to 3
IWG57M> i2c probe
Valid chip addresses: 36 48 49 50 52 53 56 58 59 5E 6A 6B 70 71
IWG57M> i2c olen 50
2
IWG57M> i2c md 0x50 0x0000.2 0x80
0000: 01 00 00 01 00 08 00 f6 01 07 00 00 00 00 c6 43    ...............C
0010: 75 73 74 6f 6d d5 47 35 37 4d 20 46 4d 43 20 4c    ustom.G57M FMC L
0020: 50 43 20 42 72 65 61 6b 6f 75 74 c4 30 30 30 31    PC Breakout.0001
0030: cb 46 4d 43 2d 4c 50 43 2d 30 30 31 c0 c1 00 1f    .FMC-LPC-001....
```

The decoded FRU confirms the identity fields and the voltage records used by the carrier:

```text
IWG57M> frudump 3 50
Manufacturer    : Custom
Product Name    : G57M FMC LPC Breakout
Serial Number   : 0001
Part Number     : FMC-LPC-001
FRU File ID     : Empty Field
Custom Fields:
DC Load
  Output number: 0 (P1 VADJ)
  Nominal Volts:         1200 (mV)
  minimum voltage:       1000 (mV)
  maximum voltage:       1500 (mV)
DC Load
  Output number: 1 (P1 3P3V)
  Nominal Volts:         3300 (mV)
  minimum voltage:       3000 (mV)
  maximum voltage:       3600 (mV)
DC Load
  Output number: 2 (P1 12P0V)
  Nominal Volts:         12000 (mV)
  minimum voltage:       10800 (mV)
  maximum voltage:       13200 (mV)
Single Width Card
P1 is LPC
P1 Bank A Signals needed 68
P1 Bank B Signals needed 0
P1 GBT Transceivers needed 0
Max JTAG Clock 0
```

The important evidence is:

1. `i2c probe` finds `0x50`.
2. `i2c olen 50` reports a two-byte offset.
3. The dump begins at EEPROM address `0x0000` and contains the FRU data.
4. `frudump 3 50` parses the record.
5. JTAG enumeration still works through the D30-to-D31 bypass.

The `.2` suffix in `0x0000.2` is important: it explicitly selects the two-byte internal address used by the AT24C64.

## PetaLinux, Yocto, and U-Boot EEPROM access

The two-byte offset behavior is controlled by both the device tree that U-Boot receives from the PetaLinux/Yocto build and the U-Boot board support code that reads the FMC FRU.

In this workspace, the FMC EEPROM node comes from:

```text
sources/meta-iwave/recipes-bsp/device-tree/files/system-user.dtsi
```

The relevant node is on the FMC I2C mux channel and describes address `0x50` as a two-byte-addressed AT24-style device:

```dts
i2c@2 {
        #address-cells = <1>;
        #size-cells = <0>;
        reg = <2>;

        eeprom2: eeprom@50 {
                compatible = "atmel,24c32";
                reg = <0x50>;
                pagesize = <32>;
                address-width = <16>;
                size = <32768>;
        };
};
```

For this experiment, the important property is `address-width = <16>;`. That is what matches the `i2c olen 50` result of `2` and the `i2c md 0x50 0x0000.2 ...` access form. If the hardware were changed to a one-byte-addressed EEPROM, the PetaLinux/Yocto device tree would need to be changed accordingly and U-Boot would need to be rebuilt with the updated DTB. Do not change only the Arduino programmer; U-Boot, the EEPROM part, and the FRU image access width must agree.

There is also a C-side FRU reader added by the iWave U-Boot patch:

```text
sources/meta-iwave/recipes-bsp/u-boot/files/0001-iW-PRHRZ-SC-01-R2.2-REL1.0-SD2.0-UBoot25.01-Base.patch
```

That patch adds `drivers/misc/fru_eeprom.c`. The important call chain is:

```text
fmc_plus_power_sequence()
  -> fmc_vadj_support(FMC_PLUS_I2C_BUS, FMC_PLUS_I2C_SLAVE_ADDR, vadj_volt)
     -> read_fmc_eeprom(i2c_bus, chip_addr)
        -> parse_FRU(fmc_eeprom_buf)
```

The same reader backs the `frudump` command used above. If the EEPROM type changes, audit both the device-tree node and this U-Boot FRU reader. The shell commands are the quickest sanity check: `i2c olen 50` should report the offset width U-Boot is actually using, `i2c md ...` should dump the expected header bytes, and `frudump 3 50` should still parse the same voltage records that `fmc_plus_power_sequence()` uses before enabling FMC power.

## Proof at boot

With a valid FRU, the serial log immediately after PLM startup reports:

```text
FMC+:   FMC+ Vadj Voltage set to 1.2V
FMC+:   FMC+ Powered up
PMIC-1: LD02 (XPIO BANK 702) set to 1.200V
PMIC-1: LD03 (XPIO BANK 703) set to 1.200V
PMIC-1: LD04 (HD BANK 302) set to 1.800V
```

The validated operating point is **1.2 V for XPIO banks 702 and 703** and **1.8 V for HD bank 302**. Do not infer that every FMC card is compatible with this setting; the card design and its FRU must agree with the carrier configuration.

## What this baseline buys us

The carrier can now detect the passive mezzanine, parse its identity, select the requested VADJ, and retain a working onboard JTAG chain. Future GPIO and PL experiments can build from that state without rediscovering whether a missing target is a software problem, an open scan chain, or an unrecognized FMC card.

{{< lab-figure src="images/FMC_EEPROM.png" alt="FMC EEPROM" >}}
