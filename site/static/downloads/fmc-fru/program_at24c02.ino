#include <Wire.h>
#include "fmc_fru_image.h"

// AT24C64 / AT24C256
// A2=A1=A0=GND -> 7-bit I2C address 0x50
static const uint8_t EEPROM_ADDR = 0x50;

// We only need to program the 256-byte FMC FRU,
// even though the physical EEPROM is much larger.
static const uint16_t FRU_SIZE = 256;

bool waitReady(uint16_t timeout_ms = 50)
{
    uint32_t start = millis();

    while ((millis() - start) < timeout_ms) {
        Wire.beginTransmission(EEPROM_ADDR);

        if (Wire.endTransmission() == 0)
            return true;

        delay(1);
    }

    return false;
}

bool writeByte(uint16_t memAddr, uint8_t value)
{
    Wire.beginTransmission(EEPROM_ADDR);

    // AT24C64 / AT24C256 use TWO internal address bytes.
    // MSB first, then LSB.
    Wire.write((uint8_t)(memAddr >> 8));
    Wire.write((uint8_t)(memAddr & 0xFF));
    Wire.write(value);

    if (Wire.endTransmission() != 0)
        return false;

    return waitReady();
}

bool readByte(uint16_t memAddr, uint8_t &value)
{
    Wire.beginTransmission(EEPROM_ADDR);
    Wire.write((uint8_t)(memAddr >> 8));
    Wire.write((uint8_t)(memAddr & 0xFF));

    if (Wire.endTransmission(false) != 0)
        return false;

    if (Wire.requestFrom((int)EEPROM_ADDR, 1) != 1)
        return false;

    value = Wire.read();
    return true;
}

bool probeEEPROM()
{
    Wire.beginTransmission(EEPROM_ADDR);
    return Wire.endTransmission() == 0;
}

bool programImage()
{
    Serial.println(F("Programming 256-byte FMC FRU image..."));

    for (uint16_t i = 0; i < FRU_SIZE; ++i) {
        if (!writeByte(i, fmc_fru_image[i])) {
            Serial.print(F("WRITE FAILED at 0x"));
            Serial.println(i, HEX);
            return false;
        }

        if ((i & 0x1F) == 0x1F) {
            Serial.print(F("  wrote through 0x"));
            Serial.println(i, HEX);
        }
    }

    return true;
}

bool verifyImage()
{
    Serial.println(F("Verifying..."));
    unsigned mismatches = 0;

    for (uint16_t i = 0; i < FRU_SIZE; ++i) {
        uint8_t got;

        if (!readByte(i, got)) {
            Serial.print(F("READ FAILED at 0x"));
            Serial.println(i, HEX);
            return false;
        }

        if (got != fmc_fru_image[i]) {
            ++mismatches;
            Serial.print(F("Mismatch 0x"));
            Serial.print(i, HEX);
            Serial.print(F(": expected 0x"));
            Serial.print(fmc_fru_image[i], HEX);
            Serial.print(F(", got 0x"));
            Serial.println(got, HEX);
        }
    }

    if (mismatches == 0) {
        Serial.println(F("VERIFY PASS: all 256 FRU bytes match."));
        return true;
    }

    Serial.print(F("VERIFY FAIL: mismatches = "));
    Serial.println(mismatches);
    return false;
}

void dumpEEPROM()
{
    Serial.println(F("FRU dump:"));

    for (uint16_t base = 0; base < FRU_SIZE; base += 16) {
        if (base < 0x100)
            Serial.print('0');
        if (base < 0x10)
            Serial.print('0');

        Serial.print(base, HEX);
        Serial.print(F(": "));

        for (uint8_t j = 0; j < 16; ++j) {
            uint8_t v;

            if (!readByte(base + j, v)) {
                Serial.print(F("?? "));
            } else {
                if (v < 0x10)
                    Serial.print('0');

                Serial.print(v, HEX);
                Serial.print(' ');
            }
        }

        Serial.println();
    }
}

void setup()
{
    Serial.begin(115200);
    while (!Serial) { }

    Wire.begin();
    Wire.setClock(100000);

    Serial.println();
    Serial.println(F("G57M FMC FRU programmer"));
    Serial.println(F("Target: 2-byte-address EEPROM at I2C 0x50"));

    if (!probeEEPROM()) {
        Serial.println(F("ERROR: no EEPROM ACK at 0x50"));
        return;
    }

    Serial.println(F("EEPROM found at 0x50"));

    if (!programImage())
        return;

    if (!verifyImage())
        return;

    dumpEEPROM();
    Serial.println(F("DONE"));
}

void loop()
{
}
