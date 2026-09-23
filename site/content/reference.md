+++
title = "Reference"
description = "Known-good G57M carrier connections and fast checks used at the bench."
+++

## Platform baseline

| Item | Known-good value |
| --- | --- |
| SOM | iWave G57M, Versal AI Edge VE2302 |
| Carrier | iWave G57D R2.0 |
| Debug/JTAG | J8 USB Type-C; SW3 OFF for JTAG |
| Serial | 115200 8N1, no flow control |
| Power | Supplied 12 V supply at J2 |
| FMC connector | J20 FMC+ HSPC |
| FMC VADJ | Carrier VADJ switch ON, 1.2 V |

## SW4 boot selection

Set SW4 before applying power. The Boot GUI JTAG flows require **PS JTAG** so XSDB can load a temporary PDI through the PMC. Persistent flash tests require **QSPI** so the board boots from the programmed QSPI contents after reset.

| Boot device | SW4.1 / PS Mode 0 | SW4.2 / PS Mode 1 | SW4.3 / PS Mode 2 | Use in these notes |
| --- | --- | --- | --- | --- |
| PS JTAG | ON | ON | ON | Full JTAG PDI, JTAG TFTP, JTAG NFS, temporary JTAG-assisted QSPI provisioning |
| SD1 | OFF | ON | OFF | SD-card experiments |
| QSPI | ON | OFF | ON | Normal persistent QSPI boot |
| eMMC | OFF | OFF | ON | eMMC boot experiments |

The carrier switch block also has a fourth physical position in the package photo. The documented boot selection for these modes is controlled by SW4.1 through SW4.3.

## FMC breakout signals

| Signal | FMC position | Use |
| --- | --- | --- |
| SCL | C30 | FRU EEPROM I2C clock |
| SDA | C31 | FRU EEPROM I2C data |
| 3P3VAUX | D32 | FRU EEPROM supply |
| PRSNT_M2C_L | H2 | Tie to ground to assert presence |
| Ground | H3 or another FMC ground | Common return |
| JTAG TDI | D30 | Tie to D31 on the passive card |
| JTAG TDO | D31 | Tie to D30 on the passive card |

Do not remove the D30-to-D31 bypass unless a real JTAG-capable device is inserted in the FMC path.

## FRU checks in U-Boot

```text
i2c dev 3
i2c probe
i2c olen 50
i2c md 0x50 0x0000.2 0x80
frudump 3 50
```

The EEPROM should ACK at `0x50`; `i2c olen 50` should report an offset length of 2. The `.2` in `0x0000.2` selects a two-byte internal EEPROM address.

## Related hardware

- [Samtec SFSD-30-28-G-06.00-S J19 cable](https://www.digikey.com/en/products/detail/samtec-inc/SFSD-30-28-G-06-00-S/8420769)
- [Passive FMC LPC breakout, eBay item 357886097671](https://www.ebay.com/itm/357886097671)
- [MusRock AT24C64 I2C EEPROM module](https://www.amazon.com/MusRock-AT24C64-EEPROM-Module-Interface/dp/B0FTFXM5CW/)
