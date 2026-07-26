# Makeblock mBot Ranger / Me Auriga — Programming & Bluetooth Communication

Research notes compiled 2026-07-26. Focus: how to program the Me Auriga board (ATmega2560) and,
specifically, how Bluetooth communication works on it.

Everything marked **[verified]** was confirmed against primary sources (official firmware source
code, the official Auriga schematic) rather than forum hearsay.

---

## 1. Executive summary — the five things that actually matter

1. **The Auriga's Bluetooth module is not on a separate UART. It hangs on `Serial` (Serial0, pins
   D0/D1), in parallel with the CH340G USB-serial bridge.** [verified: schematic + firmware]
   This single fact explains almost everything else: any sketch that does `Serial.println(...)`
   is *already* transmitting over Bluetooth, and the stock firmware needs no `MeBluetooth` object
   at all — it just uses `Serial`.

2. **Baud rate is 115200.** The stock firmware calls `Serial.begin(115200)`, and the Bluetooth
   module's UART side is factory-set to 115200. If your own sketch uses `Serial.begin(9600)` the
   USB link will work fine but the Bluetooth link will deliver garbage. This is the single most
   common self-inflicted bug.

3. **The Ranger presents *two* Bluetooth radios**: a classic Bluetooth SPP device advertised as
   `Makeblock` and a BLE device advertised as `Makeblock_LE`. For scripting from a Linux/Windows
   PC you want the **classic SPP one** (→ `/dev/rfcomm0`, then plain pyserial). The BLE one is what
   the phone apps and Web Bluetooth use (service `0000ffe1-…`, write characteristic `0000ffe3-…`).

4. **The stock firmware speaks a documented binary protocol** (`FF 55 len idx action device …`).
   You do not have to reflash anything to drive the robot from a PC — the factory firmware is a
   command server. Full device/action tables are in §4 below.

5. **Neither of the two documents you started from covers Bluetooth.** Murray Elliot's PDF has a
   section literally titled *"Input/Output — Bluetooth"* whose entire body is *"Not yet documented -
   sorry!"*, and your own tutorial mentions Bluetooth only in passing (in the D0/D1 LED warning and
   the feature list). The material in §3–§6 below is therefore reconstructed from the firmware
   source and the schematic, which is why I flagged provenance throughout.

---

## 2. Hardware: how Bluetooth is actually wired

### 2.1 Evidence from the schematic

From `MeAuriga_Schaltplan.pdf` (mirrored on your own site,
<https://ghorwin.github.io/MakeBlockRanger/downloads/MeAuriga_Schaltplan.pdf>):

- `U2` is the BLE module. It has nets `RST_BLE` and `DTR_BLE`.
- `U3` is the `CH340G` USB-UART bridge, with `DTR_CH340` wired to `RESET`.
- Both converge on the MCU pins `PE0/RX0/PCINT8` and `PE1/TX0` — i.e. Arduino **D0 and D1**,
  which is `Serial` (a.k.a. `Serial0`).

So: **USB and Bluetooth are two physical transports onto the same UART0.** Both can assert DTR,
which pulses `RESET` — that is the mechanism behind Makeblock's "wireless firmware upgrade over
Bluetooth" feature.

### 2.2 Corroboration from Murray Elliot's reference PDF

> "D0 and D1 are connected to the Blue and Red LEDs respectively. These pins are also connected to
> the BLE (Bluetooth Low Energy) and UART modules (Universal Asynchronous Receiver/Transmitter), so
> programming these LEDs directly will disrupt these modules."

Your German tutorial states the same thing ("…mit den BLE … und UART Modulen verbunden. Wenn man
die LEDs direkt ansteuert, stört das diese Module."). Note the practical consequence: **the two
on-board status LEDs on D0/D1 are unusable if you want working Bluetooth**, and vice versa.

### 2.3 UART map of the Auriga (ATmega2560 has 4 UARTs)

| Arduino object | MCU pins | Purpose on the Ranger | Notes |
|---|---|---|---|
| `Serial`  | D0 (RX0) / D1 (TX0)  | **USB (CH340G) *and* Bluetooth module**, plus the two status LEDs | 115200 baud in stock firmware |
| `Serial1` | D19 / D18            | Used by the on-board motor driver (`EN_DIRA` / `EN_DIRB` nets share these pins) | do not use for comms |
| `Serial2` | D17 (RX2) / D16 (TX2)| **PORT_5** (light-grey RJ25 port) and the white 4-pin SERVO connector under the LED panel | free for your own use |
| `Serial3` | D15 / D14            | "extension header 4" | free for your own use |

Sources: Elliot PDF §"Input/Output - Serial ports"; port table `PORT_5 { 16, 17 }`; Makeblock
support ("PORT5 … is isolated with serial communication function only … cannot be used to update a
program but only for communication").

> ⚠️ Elliot's PDF has an off-by-one typo in its prose: it says *"referred to in the serial library
> as Serial, Serial2, Serial3 and Serial4"* and then correctly lists `Serial`/`Serial1`/`Serial2`/
> `Serial3`. The names in the table above are the correct ones.

### 2.4 Consequences / gotchas

- **You cannot flash over USB while a Bluetooth host holds the link open at a different baud**, and
  a Bluetooth client that asserts DTR will reset the board mid-upload. Disconnect the BT client
  before flashing.
- **`Serial.print()` debugging goes out over Bluetooth too.** That is often convenient (wireless
  telemetry for free) but it also means debug spam corrupts a binary protocol stream if you are
  running the stock firmware protocol on the same port.
- **PORT_5 (`Serial2`) is the clean escape hatch**: if you want a debug channel that is *not* shared
  with Bluetooth, plug a USB-TTL adapter or a second Bluetooth module into PORT_5 and use `Serial2`.

---

## 3. The two radios: classic SPP vs. BLE

The Ranger's module is a **dual-mode** part. Community reports (B4X forum, Makeblock forum) and the
Web Bluetooth write-up all agree it exposes:

| | Classic Bluetooth (BR/EDR) | Bluetooth Low Energy |
|---|---|---|
| Advertised name | `Makeblock` | `Makeblock_LE` |
| Profile | SPP (Serial Port Profile), HC-05-class | GATT |
| Service UUID | — (RFCOMM channel) | `0000ffe1-0000-1000-8000-00805f9b34fb` |
| Write characteristic | — | `0000ffe3-0000-1000-8000-00805f9b34fb` |
| Notify characteristic | — | `0000ffe2-…` (reported; `ffe3` also supports notify) |
| Best for | **PC scripting (Python/C++)** — appears as a normal serial port | phone apps, Web Bluetooth, browsers |

**Pairing advice from the field:** pair with `Makeblock`, *not* `Makeblock_LE`, when you want a
serial port. On Linux this is the blueman/`bluetoothctl` + `rfcomm` route (§6.1).

**BLE payload quirk** (from the Web Bluetooth article — worth knowing if you go the BLE route):
commands must be padded into a 16-byte buffer and written as a `Uint16Array`, i.e. bytes are packed
in pairs `bufView[i] = byte_hi << 8 | byte_lo`. This is an artefact of that particular JS
implementation, but several BLE clients report needing the padding.

---

## 4. The stock firmware protocol (this is the main event)

Reference implementation: **`Firmware_for_Auriga.ino`**, version **V09.01.016** (21/06/2017), in
the official `Makeblock-Libraries` repo. Everything in this section is read directly from that
source. [verified]

<https://github.com/Makeblock-official/Makeblock-Libraries/blob/master/examples/Firmware_for_Auriga/Firmware_for_Auriga.ino>

### 4.1 Request frame layout

The firmware's own comment (above `parseData()`):

```
ff 55 len idx action device port slot data a
0  1  2   3   4      5     6    7    8
```

| Offset | Field | Meaning |
|---|---|---|
| 0–1 | `FF 55` | fixed header |
| 2 | `len` | **number of bytes that follow the len byte** (i.e. everything from `idx` to the end of the payload) |
| 3 | `idx` | free-choice request id; echoed back in the reply so you can match responses |
| 4 | `action` | `1`=GET, `2`=RUN, `4`=RESET, `5`=START |
| 5 | `device` | device/module id — see §4.3 |
| 6 | `port` | RJ25 port number, or `0` for on-board devices, or a sub-command for `COMMON_COMMONCMD` |
| 7+ | `slot`/data | device-specific; multi-byte values are **little-endian** |

**`len` semantics** — this trips people up, so here is the parser logic verbatim from `loop()`:

```cpp
if(index == 2)      { dataLen = c; }      // len byte
else if(index > 2)  { dataLen--; }        // every subsequent byte decrements
writeBuffer(index,c);
...
if(isStart && (dataLen == 0) && (index > 3)) { isStart = false; parseData(); index = 0; }
```

So `len` counts `idx + action + device + port + slot + data…`. It does **not** include `FF 55` or
itself. There is **no checksum**. Frames longer than 51 bytes are discarded (`if(index > 51)`).

A trailing `0x0A` is commonly appended by mBlock and by most community clients. The parser ignores
it (the frame is already complete when `dataLen` hits 0), so it is optional but harmless — and
including it keeps you bug-compatible with the reference clients.

### 4.2 Response frame layout

Built from `writeHead()` / `sendXxx()` / `writeEnd()`:

```
FF 55 <idx> <type> <payload…> 0D 0A
```

`writeEnd()` is `Serial.println()`, hence the CRLF terminator. Type codes:

| Type byte | Meaning | Payload |
|---|---|---|
| `1` | byte | 1 byte |
| `2` | float | 4 bytes, little-endian IEEE-754 |
| `3` | short | 2 bytes, little-endian |
| `4` | string | 1 length byte + N chars |
| `5` | double | 4 bytes on AVR (`double` == `float` on ATmega) |
| `6` | long | 4 bytes, little-endian |

**Acknowledgement** for `RUN` / `RESET` / `START` (`callOK()`): just `FF 55 0D 0A` — header, no
index, no payload.

**Special case worth knowing:** for `ULTRASONIC_SENSOR`, `HUMITURE` and `ULTRASONIC_ARDUINO`,
`parseData()` deliberately skips writing the header, because those handlers emit their own
`writeHead(); writeSerial(command_index);`. Net effect on the wire is identical — but if you are
reading the source and wondering why there is a special case, that is why.

### 4.3 Device ID table (Auriga firmware)

Taken verbatim from `Firmware_for_Auriga.ino` lines 181–265. Note this is a **superset** of the
mBot/Orion table — IDs 23–27, 36–37, 40–41, 51–52 and 60–64 are not present in the older mBot
firmware.

| ID (dec / hex) | Constant | | ID (dec / hex) | Constant |
|---|---|---|---|---|
| 0 / 0x00 | `VERSION` | | 30 / 0x1e | `DIGITAL` |
| 1 / 0x01 | `ULTRASONIC_SENSOR` | | 31 / 0x1f | `ANALOG` |
| 2 / 0x02 | `TEMPERATURE_SENSOR` | | 32 / 0x20 | `PWM` |
| 3 / 0x03 | `LIGHT_SENSOR` | | 33 / 0x21 | `SERVO_PIN` |
| 4 / 0x04 | `POTENTIONMETER` | | 34 / 0x22 | `TONE` |
| 5 / 0x05 | `JOYSTICK` | | 35 / 0x23 | `BUTTON_INNER` |
| 6 / 0x06 | `GYRO` | | 36 / 0x24 | `ULTRASONIC_ARDUINO` |
| 7 / 0x07 | `SOUND_SENSOR` | | 37 / 0x25 | `PULSEIN` |
| 8 / 0x08 | `RGBLED` | | 40 / 0x28 | `STEPPER` |
| 9 / 0x09 | `SEVSEG` | | 41 / 0x29 | `LEDMATRIX` |
| 10 / 0x0a | `MOTOR` | | 50 / 0x32 | `TIMER` |
| 11 / 0x0b | `SERVO` | | 51 / 0x33 | `TOUCH_SENSOR` |
| 12 / 0x0c | `ENCODER` | | 52 / 0x34 | `JOYSTICK_MOVE` |
| 13 / 0x0d | `IR` | | 60 / 0x3c | `COMMON_COMMONCMD` |
| 14 / 0x0e | `IRREMOTE` | | 61 / 0x3d | `ENCODER_BOARD` |
| 15 / 0x0f | `PIRMOTION` | | 62 / 0x3e | `ENCODER_PID_MOTION` |
| 16 / 0x10 | `INFRARED` | | 63 / 0x3f | `PM25SENSOR` |
| 17 / 0x11 | `LINEFOLLOWER` | | 64 / 0x40 | `SMARTSERVO` |
| 18 / 0x12 | `IRREMOTECODE` | | | |
| 20 / 0x14 | `SHUTTER` | | | |
| 21 / 0x15 | `LIMITSWITCH` | | | |
| 22 / 0x16 | `BUTTON` | | | |
| 23 / 0x17 | `HUMITURE` | | | |
| 24 / 0x18 | `FLAMESENSOR` | | | |
| 25 / 0x19 | `GASSENSOR` | | | |
| 26 / 0x1a | `COMPASS` | | | |
| 27 / 0x1b | `TEMPERATURE_SENSOR_1` | | | |

**Sub-commands for `COMMON_COMMONCMD` (60)** — these go in the `port` byte (offset 6):

| Sub-cmd | Constant | Direction |
|---|---|---|
| `0x10` | `SET_STARTER_MODE` | RUN |
| `0x11` | `SET_AURIGA_MODE` | RUN |
| `0x12` | `SET_MEGAPI_MODE` | RUN |
| `0x70` | `GET_BATTERY_POWER` | GET → float |
| `0x71` | `GET_AURIGA_MODE` | GET → byte |
| `0x72` | `GET_MEGAPI_MODE` | GET |

**Sub-commands for `ENCODER_BOARD` (61)** — read type at offset 8:
`0x01` = `ENCODER_BOARD_POS` (→ long), `0x02` = `ENCODER_BOARD_SPEED` (→ float).

**Sub-commands for `ENCODER_PID_MOTION` (62)**:
`0x01` POS_MOTION, `0x02` SPEED_MOTION, `0x03` PWM_MOTION, `0x04` SET_CUR_POS_ZERO,
`0x05` CAR_POS_MOTION.

**Sub-commands for `SMARTSERVO` (64)**: `0x01` BREAK, `0x02` RGB, `0x03` SHAKE_HANDS, `0x04` MOVE_TO,
`0x05` MOVE, `0x06` PWM, `0x07` ZERO_DEGREES, `0x08` INIT_ANGLE, `0x09` GET_SPEED,
`0x0a` GET_TEMPERATURE, `0x0b` GET_CURRENT, `0x0c` GET_VOLTAGE, `0x0d` GET_ANGLE.

### 4.4 Auriga operating modes — read this before debugging "the robot ignores me"

The Auriga firmware has a mode variable stored in EEPROM:

| Value | Mode |
|---|---|
| `0x00` | `BLUETOOTH_MODE` ← **required for the robot to respond to protocol commands normally** |
| `0x01` | `AUTOMATIC_OBSTACLE_AVOIDANCE_MODE` |
| `0x02` | `BALANCED_MODE` |
| `0x03` | `IR_REMOTE_MODE` |
| `0x04` | `LINE_FOLLOW_MODE` |

In the non-Bluetooth modes, `loop()` continuously drives the motors itself (`ultrCarProcess()`,
`balanced_model()`, `line_model()`), so your motor commands get overwritten a few milliseconds
later. **The on-board button cycles through the modes** (`auriga_mode = auriga_mode + 1; if(...==
MAX_MODE) auriga_mode = BLUETOOTH_MODE;`), which is how users accidentally end up in the wrong mode.

Force it back with `SET_AURIGA_MODE`:

```
FF 55 05 00 02 3C 11 00        # RUN, COMMON_COMMONCMD, SET_AURIGA_MODE, BLUETOOTH_MODE
```

The value is persisted to EEPROM, so it survives a power cycle.

### 4.5 Ready-made example frames for the Ranger

All little-endian. `idx` is arbitrary — I use `00`.

**Firmware version string**
```
FF 55 04 00 01 00 00                     → FF 55 00 04 <len> "09.01.016" 0D 0A
```

**Battery voltage**
```
FF 55 04 00 01 3C 70                     → FF 55 00 02 <float32> 0D 0A
```

**Drive the on-board encoder motors** (device `ENCODER_BOARD`=0x3D, port=0, slot=1 or 2,
speed = int16 at offset 8). This is the correct way to drive a *Ranger* — the plain `MOTOR` (0x0A)
device is for mBot-style DC motors on the red RJ25 ports.
```
FF 55 07 00 02 3D 00 01 64 00            # slot 1 (left)  PWM = +100
FF 55 07 00 02 3D 00 02 64 00            # slot 2 (right) PWM = +100
FF 55 07 00 02 3D 00 01 9C FF            # slot 1 PWM = -100  (0xFF9C)
```
Each returns `FF 55 0D 0A`.

**Both motors at once** via the `JOYSTICK` device (0x05) — `leftSpeed` at offset 6, `rightSpeed` at
offset 8:
```
FF 55 06 00 02 05 64 00 64 00            # left +100, right +100
```

**Read on-board encoder position / speed** (slot at offset 7, read-type at offset 8):
```
FF 55 06 00 01 3D 00 01 01               → long   (position, slot 1)
FF 55 06 00 01 3D 00 01 02               → float  (speed,    slot 1)
```

**On-board 12× WS2812 RGB ring** (device `RGBLED`=0x08, port=0, slot=2 selects the on-board ring on
pin 44; `idx`=0 means "all LEDs", `idx`=N means "start at LED N"):
```
FF 55 09 00 02 08 00 02 00 FF 00 00      # all 12 LEDs red
FF 55 09 00 02 08 00 02 01 00 FF 00      # LED 1 green
```
Note the firmware derives the pixel count from the length byte: `pixels_len = readBuffer(2) - 6`,
so you can set several LEDs in one frame by appending more RGB triples and bumping `len` by 3 each.

**On-board sensors** (ports from the Auriga port map, §5):
```
FF 55 04 00 01 03 0B                     # light sensor 1 (PORT_11) → float
FF 55 04 00 01 03 0C                     # light sensor 2 (PORT_12) → float
FF 55 04 00 01 07 0E                     # sound sensor   (PORT_14) → float
FF 55 05 00 01 02 0D 02                  # on-board temperature (PORT_13, slot 2) → float
FF 55 05 00 01 06 00 01                  # gyro, port 0 = on-board, axis 1 (X) → float
```

**Buzzer** (device `TONE`=0x22, pin at offset 6, frequency int16 at 7, duration int16 at 9):
```
FF 55 08 00 02 22 2D 20 03 F4 01         # pin 45, 800 Hz, 500 ms
```

**RESET everything** (stops all motors, clears LEDs, zeroes encoders):
```
FF 55 02 00 04                           → FF 55 0D 0A
```

> These frames are constructed from the firmware source, not copy-pasted from a working capture.
> The layout logic is verified line-by-line against `runModule()` / `readSensor()`, but I have no
> hardware here — sanity-check the RGB and TONE ones first, they have the most offset arithmetic.

### 4.6 Cross-check against known-good captures

Two independent community captures confirm the `len` semantics above:

- B4X forum, compass read: `ff 55 04 00 01 1a 04` → len=4, idx=0, action=GET, device=0x1a
  (COMPASS), port=4. ✔ 4 bytes follow the len byte.
- B4X forum, light sensor: `ff 55 04 05 01 03 03` → len=4, idx=5, action=GET, device=3
  (LIGHT_SENSOR), port=3. ✔
- Web Bluetooth article, motor: `ff 55 09 00 02 0a 09 64 00 00 00 00 0a` → len=9, action=RUN,
  device=0x0a (MOTOR), port=9, speed=0x0064=100, then zero padding + trailing `0a`. ✔

---

## 5. Auriga port / pin map (needed to fill in the `port` byte)

From `MePort_Sig mePort[15]` (Elliot PDF, corroborated by your tutorial's pin reference chapter):

| Port | Pins (S1, S2) | Colour / function |
|---|---|---|
| PORT_0 | — | not connected |
| PORT_1 | 5, 4 | red — motor driver |
| PORT_2 | 3, 2 | red — motor driver |
| PORT_3 | 7, 6 | red — motor driver |
| PORT_4 | 9, 8 | red — motor driver |
| PORT_5 | 16, 17 | grey — **serial (`Serial2`)**, 4 pins: GND, 5V, TX2/D16, RX2/D17 |
| PORT_6 | A10, A15 | universal |
| PORT_7 | A9, A14 | universal |
| PORT_8 | A8, A13 | universal (IR receiver in stock firmware) |
| PORT_9 | A7, A12 | universal (line follower in stock firmware) |
| PORT_10 | A6, A11 | universal (ultrasonic in stock firmware) |
| PORT_11 | —, A2 | **on-board light sensor 1** |
| PORT_12 | —, A3 | **on-board light sensor 2** |
| PORT_13 | —, A0 | **on-board temperature sensor** |
| PORT_14 | —, A1 | **on-board sound sensor** |

Other on-board pins: `POWER_PORT = A4`, `BUZZER_PORT = 45`, `RGBLED_PORT = 44` (WS2812 ring, 12
LEDs), status LED on `D13`, on-board gyro on I²C address `0x69` (external gyro `0x68`).

Each RJ25 port carries 6 pins: SCL, SDA, GND, VCC, S1, S2. Red ports 1–4 output 6–12 V.

---

## 6. Host-side: talking to the robot from a PC

### 6.1 Linux (classic SPP → `/dev/rfcomm0`)

This is the path I would take on your Fedora box.

```bash
bluetoothctl
  power on
  scan on                 # look for "Makeblock" (NOT "Makeblock_LE")
  pair    <MAC>           # PIN is usually 0000 or 1234 if asked
  trust   <MAC>
  quit

sudo rfcomm bind 0 <MAC> 1        # channel 1; check with: sdptool browse <MAC>
ls -l /dev/rfcomm0
```

Then it is an ordinary serial port at 115200 8N1, no flow control. Makeblock support explicitly
documents "115200 baud, 8 bits, parity none, 1 stop bit and no control flow".

Historical note: mBlock 3 on Linux never had working native Bluetooth; the documented workaround was
exactly this — bind with blueman/rfcomm, then pick *Connect → Serial Port → /dev/rfcomm0* in mBlock.

### 6.2 Minimal Python client (pyserial)

```python
import serial, struct, time

class Ranger:
    def __init__(self, dev="/dev/rfcomm0"):          # or "/dev/ttyUSB0" over USB
        self.s = serial.Serial(dev, 115200, timeout=1)
        time.sleep(2)                                 # DTR pulse resets the board

    def _frame(self, action, device, payload=b""):
        body = bytes([0x00, action, device]) + payload   # idx=0
        return b"\xff\x55" + bytes([len(body)]) + body

    def run(self, device, payload=b""):
        self.s.write(self._frame(0x02, device, payload))

    def get(self, device, payload=b""):
        self.s.reset_input_buffer()
        self.s.write(self._frame(0x01, device, payload))
        return self.s.readline()                      # response ends with \r\n

    def motors(self, left, right):                    # JOYSTICK device drives both
        self.run(0x05, struct.pack("<hh", left, right))

    def motor(self, slot, pwm):                       # ENCODER_BOARD, slot 1|2
        self.run(0x3d, bytes([0x00, slot]) + struct.pack("<h", pwm))

    def battery(self):
        r = self.get(0x3c, bytes([0x70]))
        return struct.unpack("<f", r[4:8])[0]         # ff 55 idx type <float>

    def ring(self, r, g, b):                          # all 12 on-board LEDs
        self.run(0x08, bytes([0x00, 0x02, 0x00, r, g, b]))

bot = Ranger()
print("battery:", bot.battery(), "V")
bot.ring(0, 32, 0)
bot.motors(100, 100); time.sleep(1); bot.motors(0, 0)
```

Caveat: `readline()` is naive — a robust client should scan for `FF 55`, then read `idx` + type and
consume exactly the right number of payload bytes, because sensor float payloads can legitimately
contain `0x0A`.

### 6.3 BLE from Python (`bleak`) — sketch

```python
import asyncio, struct
from bleak import BleakScanner, BleakClient

CHAR = "0000ffe3-0000-1000-8000-00805f9b34fb"

async def main():
    dev = await BleakScanner.find_device_by_name("Makeblock_LE")
    async with BleakClient(dev) as c:
        await c.start_notify(CHAR, lambda _, d: print("rx", d.hex()))
        # RUN JOYSTICK, both motors +100
        frame = bytes.fromhex("ff5506000205") + struct.pack("<hh", 100, 100)
        await c.write_gatt_char(CHAR, frame.ljust(16, b"\x00"), response=False)
        await asyncio.sleep(2)

asyncio.run(main())
```
Untested here; the 16-byte padding is what the Web Bluetooth implementation found necessary.

### 6.4 Existing host libraries

| Project | Language | Notes |
|---|---|---|
| [`xeecos/python-for-mbot`](https://github.com/xeecos/python-for-mbot) | Python | Official-ish. `startWithSerial("COM15")` (works over the BT serial port too) or `startWithHID()` for the 2.4 G dongle. Callback-based sensor reads. Written for **mBot**, so the device IDs it uses are the mBot subset — you'll need to add the Auriga-only IDs (0x3C–0x40) yourself. |
| [`NMO13/mbot-control`](https://github.com/NMO13/mbot-control) | Python | Bluetooth remote-control for mBot. |
| [`nyuuyn/mqtt-for-mbot`](https://github.com/nyuuyn/mqtt-for-mbot) | Python | MQTT bridge built on python-for-mbot. |
| [`Ted-CAcert/mymbot` wiki](https://github.com/Ted-CAcert/mymbot/wiki/mBot-2.4G-Wireless-Serial) | docs | Good write-up of the 2.4 GHz wireless serial variant of the same protocol. |
| [`lmoellendorf/ranger`](https://github.com/lmoellendorf/ranger) | C++ (Arduino) | ⚠️ Despite the name, this is about **LEGO Mindstorms ↔ RJ25 cable adapters**, not the Bluetooth protocol. Not what you want. |
| [ViSP mBot Ranger tutorial](https://visp-doc.inria.fr/doxygen/visp-3.2.0/tutorial-mbot-vs.html) | C++ | Visual servoing on a Ranger — a real-world example of driving the board from a host. |

---

## 7. Writing your own sketch that uses Bluetooth (bypassing the stock firmware)

Because Bluetooth *is* `Serial`, this is almost anticlimactic:

```cpp
#include <MeAuriga.h>

MeEncoderOnBoard Encoder_1(SLOT1);
MeEncoderOnBoard Encoder_2(SLOT2);

void setup() {
  Serial.begin(115200);          // MUST be 115200 — the BT module's UART is fixed at this rate
  Serial.println("ranger ready");// this goes out over Bluetooth AND USB
}

void loop() {
  if (Serial.available()) {
    char c = Serial.read();
    switch (c) {
      case 'f': Encoder_1.setTarPWM(-150); Encoder_2.setTarPWM(150); break;
      case 'b': Encoder_1.setTarPWM(150);  Encoder_2.setTarPWM(-150); break;
      case 's': Encoder_1.setTarPWM(0);    Encoder_2.setTarPWM(0);    break;
    }
  }
  Encoder_1.loop();
  Encoder_2.loop();
}
```

Rules of thumb for custom sketches:

- **Do not** instantiate `MeBluetooth` for the *on-board* module. `MeBluetooth` (a `MeSerial`
  subclass, which in turn wraps `SoftwareSerial`) is for plugging a separate **Me Bluetooth Module**
  into an RJ25 port. The on-board one needs nothing but `Serial`.
- **Do not** use D0/D1 as GPIO (they are the two status LEDs) — it breaks the radio.
- If you need a private debug channel, use `Serial2` on PORT_5.
- Add a **dead-man switch**. A documented failure mode from the B4X thread: if the BT link drops
  right after a motor command, the robot keeps driving. Stop the motors if no command has arrived
  for N milliseconds.
- Keep `MeEncoderOnBoard::loop()` called every iteration — the PID for the on-board motors runs
  there.

**Restoring the factory behaviour:** reflash
`Makeblock-Libraries/examples/Firmware_for_Auriga/Firmware_for_Auriga.ino`, or use mBlock's
*Connect → Update Firmware*. Your tutorial's chapter 3.1 covers this
(<https://ghorwin.github.io/MakeBlockRanger/de/index.html#_firmware_update_installieren_zurücksetzen>).

---

## 8. Gap analysis — what is *not* documented anywhere I could find

Worth knowing before you spend time hunting:

- **The exact part number of the on-board BLE module (`U2`).** The schematic labels it only as
  "BLE 模块". No datasheet surfaced.
- **AT command set for the on-board module.** For the *pluggable* Me Bluetooth Module there are
  forum threads about changing the baud via AT commands; for the soldered-on Auriga module I found
  nothing. Assume 115200 is not changeable without risk.
- **The official Makeblock protocol page is dead.** `makeblock.com.cn/en/project/mbot-serial-port-protocol`
  now 301-redirects to `makextool.com` (an unrelated site). Likewise
  `learn.makeblock.com/en/makeblock-orion-protocol/`, referenced by the B4X thread, is gone.
  **The firmware source is now the authoritative protocol spec.**
- **`forum.makeblock.com` no longer resolves** (DNS failure as of this research). Many search
  results still point there; use Google cache or the Wayback Machine. This is a significant loss —
  most of the community protocol knowledge lived there.
- **`support.makeblock.com` returns 403 to automated fetches** but works in a normal browser.

---

## 9. Web references

### Primary / authoritative

| Ref | URL |
|---|---|
| **Firmware_for_Auriga.ino** — the de-facto protocol spec | <https://github.com/Makeblock-official/Makeblock-Libraries/blob/master/examples/Firmware_for_Auriga/Firmware_for_Auriga.ino> |
| Makeblock-Libraries repo (source for `MeAuriga.h`, `MeSerial`, `MeBluetooth`, `MeEncoderOnBoard`) | <https://github.com/Makeblock-official/Makeblock-Libraries> |
| Library ZIP download (used by your tutorial) | <https://codeload.github.com/Makeblock-official/Makeblock-Libraries/zip/master> |
| Makeblock-Firmware repo (mBot / Orion firmware — smaller device table) | <https://github.com/Makeblock-official/Makeblock-Firmware> |
| mBot firmware `.ino` (compact device-ID table) | <https://github.com/Makeblock-official/Makeblock-Firmware/blob/master/mbot_firmware/mbot_firmware.ino> |
| MegaPi firmware (same protocol, different board) | <https://github.com/Makeblock-official/Makeblock-Libraries/blob/master/examples/Firmware_for_MegaPi/Firmware_for_MegaPi.ino> |
| **Me Auriga schematic** (proves BLE ↔ D0/D1 wiring) | <https://ghorwin.github.io/MakeBlockRanger/downloads/MeAuriga_Schaltplan.pdf> |
| Me Auriga pinout PDF | <https://ghorwin.github.io/MakeBlockRanger/downloads/MeAuriga_Pinout.pdf> |
| ATmega640/1280/2560 datasheet | <https://ghorwin.github.io/MakeBlockRanger/downloads/Atmel-2549-8-bit-AVR-Microcontroller-ATmega640-1280-1281-2560-2561_datasheet.pdf> |

### Tutorials & references

| Ref | URL |
|---|---|
| **Your own tutorial** (German, v1.0, 2025-04-30) — best coverage of setup, drivers, motors/PID, RJ25. *No Bluetooth chapter.* | <https://ghorwin.github.io/MakeBlockRanger/de/index.html> |
| **Murray Elliot, "Makeblock Ranger Arduino Coding Reference"** v1.4.2/1.4.3 (May 2023) — port map, serial port map, sensor snippets. *Bluetooth section is an empty placeholder.* | <https://forum.arduino.cc/uploads/short-url/1Nq8pVFThsWRRAg1w0LhGup0DTq.pdf> |
| ↳ direct S3 link (the short-url 302-redirects here) | <https://cdck-file-uploads-europe1.s3.dualstack.eu-west-1.amazonaws.com/arduino/original/4X/0/c/9/0c9859552b7565fb4653f443ef9a00626b08ddd8.pdf> |
| Makeblock support: About Me Auriga (specs, PORT5 serial-only note) | <https://support.makeblock.com/hc/en-us/articles/4412149618327-About-Me-Auriga> |
| Makeblock support: Beginner's Guide to mBot Ranger | <https://support.makeblock.com/hc/en-us/articles/12822986175383-A-Beginner-s-Guide-to-mBot-Ranger> |
| Makeblock support: FAQs on mBot Ranger | <https://support.makeblock.com/hc/en-us/articles/1500004061681-FAQs-on-mBot-Ranger> |
| Makeblock support: mBot Ranger Bluetooth Connection Issue | <https://support.makeblock.com/hc/en-us/articles/30138040019863-mBot-Ranger-Bluetooth-Connection-Issue> |
| Makeblock support: Control mBot Ranger with the Makeblock App | <https://support.makeblock.com/hc/en-us/articles/1500003936781-Control-mBot-Ranger-with-the-Makeblock-App> |
| Me Auriga product page | <https://www.makeblock.com.cn/en/project/me-auriga> |
| ViSP: visual servoing with the mBot Ranger (C++ host control) | <https://visp-doc.inria.fr/doxygen/visp-3.2.0/tutorial-mbot-vs.html> |

### Bluetooth-specific (the useful stuff)

| Ref | URL |
|---|---|
| **B4X forum: "Using Android Bluetooth Commands to Control a Makeblock Robot"** — real captured frames, classic SPP, `Makeblock` vs `makeblock.le`, the runaway-robot warning | <https://www.b4x.com/android/forum/threads/using-android-bluetooth-commands-to-control-a-makeblock-robot.88854/> |
| **Web Bluetooth control of a Makeblock robot** (EN via Medium) — BLE UUIDs, 13-byte frames, 16-byte padding | <https://medium.com/@jean.francois.garreau/contr%C3%B4le-dun-robot-par-une-page-web-7798e5ddf3f2> |
| ↳ same article, French original on author's blog | <https://jef.binomed.fr/2016/07/22/2016-07-22-controle-d-un-robot-par-une-page-web/> |
| mBlock issue #59: Bluetooth on Linux — the blueman + `/dev/rfcomm0` workaround | <https://github.com/Makeblock-official/mBlock/issues/59> |
| Makeblock BLE module user manual (BLEV1-C, BT 4.0, 12 µA sleep) | <https://usermanual.wiki/Makeblock/BLEV1-C/html> |
| ↳ mirror | <https://www.manualshelf.com/manual/makeblock/blev1-c/user-s-manual-english.html> |
| Me Bluetooth Module (dual mode) product listing | <https://www.amazon.com/Makeblock-Bluetooth-Module-Dual-Mode/dp/B00WG3KYS2> |
| Vernier: can I program mBot via Bluetooth with mBlock 3? | <https://www.vernier.com/til/4140> |
| mBot 2.4 G wireless serial protocol notes | <https://github.com/Ted-CAcert/mymbot/wiki/mBot-2.4G-Wireless-Serial> |

### Host libraries

| Ref | URL |
|---|---|
| xeecos/python-for-mbot | <https://github.com/xeecos/python-for-mbot> |
| NMO13/mbot-control (Bluetooth controller) | <https://github.com/NMO13/mbot-control> |
| nyuuyn/mqtt-for-mbot | <https://github.com/nyuuyn/mqtt-for-mbot> |
| lmoellendorf/ranger (⚠️ LEGO cable adapters, not protocol) | <https://github.com/lmoellendorf/ranger> |
| GitHub topic: makeblock | <https://github.com/topics/makeblock> |
| nbourre/Makeblock-Libraries (community fork, referenced by your tutorial) | <https://github.com/nbourre/Makeblock-Libraries> |

### Drivers & tooling

| Ref | URL |
|---|---|
| Makeblock USB driver repo | <https://github.com/Makeblock-official/Makeblock-USB-Driver> |
| CH341 driver (Linux fork) | <https://github.com/storef/ch341.driver> |
| Signed macOS CH340 driver write-up | <http://blog.sengotta.net/signed-mac-os-driver-for-winchiphead-ch340-serial-bridge/> |
| Arduino Serial reference | <https://www.arduino.cc/reference/en/language/functions/communication/serial/> |

### Dead / broken links (recorded so you don't chase them)

| Ref | Status |
|---|---|
| `https://www.makeblock.com.cn/en/project/mbot-serial-port-protocol` | 301 → `makextool.com`, content gone |
| `http://learn.makeblock.com/en/makeblock-orion-protocol/` | gone (was the official protocol doc) |
| `https://forum.makeblock.com/…` | **DNS no longer resolves** — try the Wayback Machine |
| `https://support.makeblock.com/…` | 403 to scripts, fine in a browser |

---

## 10. Suggested next steps for your tutorial

If you want to close the Bluetooth gap in <https://ghorwin.github.io/MakeBlockRanger/>, the chapter
practically writes itself from §2, §4.4 and §7:

1. **"Wie Bluetooth am Auriga verdrahtet ist"** — the D0/D1 revelation. This is the single insight
   that makes everything else obvious, and it is currently only implicit in your LED warning.
2. **"Eigene Sketche über Bluetooth"** — the 115200 rule, the dead-man switch, PORT_5 as the
   separate debug channel.
3. **"Der Auriga-Modus"** (§4.4) — why the robot sometimes ignores commands, and the button that
   causes it. This one probably generates the most support questions from students.
4. **Optional: "Die Werksfirmware als Kommandoserver"** (§4) — since the official protocol page is
   dead, a German-language write-up of the frame format from the firmware source would be a
   genuinely unique contribution.
