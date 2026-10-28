# Kingston FURY Beast RGB Controller for Linux

A lightweight, dependency-free Bash script to control the RGB LEDs on **Kingston FURY Beast DDR5** RAM modules directly via SMBus/i2c under Linux.

Works great when OpenRGB fails to detect the modules or on AMD systems where spd5118 blocks access.

## Features
- Interactive terminal menu with arrow-key navigation
- Real-time color selection + brightness control (0–100%)
- Remembers last selected color when changing brightness
- Immediate application of brightness changes
- Direct/scriptable mode for automation (e.g. cron, startup scripts)
- Only shows real errors – clean output
- No external dependencies except i2c-tools

## Configuration

### Install i2c-tools (once)

```bash
sudo apt install i2c-tools
```

### Blacklist blocker module (recommended)

```bash
echo "blacklist spd5118" | sudo tee /etc/modprobe.d/blacklist-spd5118.conf
sudo update-initramfs -u
sudo reboot
```

### Check the RAM status

Before installing, check that the script can see your RAM sticks. Run this from the downloaded folder:

```bash
sudo ./rgbfury.sh status
```

**Sticks found:** the script can control your RAM, so you can go ahead and install it.

```
Found 4 stick(s) on bus 3: 0x60 0x61 0x62 0x63
```

Each address is one RAM stick, and the address depends on which slot the stick is in. With 2 sticks you'll typically see 2 addresses, e.g. `0x61 0x63`. The number of sticks found should match the number of FURY Beast RGB sticks in your PC.

**No sticks found:** the script can't see your RAM.

```
No FURY RGB controllers found at 0x60-0x67 on SMBus bus(es): 3
Check with: sudo i2cdetect -l   and   sudo i2cdetect -y <bus>
```

- If the output also says `Run as root (sudo).`, you forgot `sudo`. Run the command again with it.
- If it says `bus(es): none`, the script didn't find a motherboard SMBus adapter (AMD `SMBus PIIX4` or Intel `SMBus I801`).

> [!WARNING]
> **Don't install the script or the systemd unit if no sticks are found, or if fewer sticks are found than you have installed.** It can't change the colors of RAM it doesn't see. Go to the [Troubleshooting](#troubleshooting) section first, and make sure the `spd5118` module is blacklisted (see above) and that you rebooted afterwards.

### Install the script

```bash
sudo cp rgbfury.sh /usr/local/bin/rgbfury.sh
sudo chmod 755 /usr/local/bin/rgbfury.sh
```

### Run interactive mode

```bash
sudo ./rgbfury.sh
```

The script auto-detects the I2C bus and the installed sticks (1–8 sticks, in any slots), so no editing is needed when you add or remove RAM. It only scans the motherboard SMBus adapters (AMD `SMBus PIIX4` / Intel `SMBus I801`) for RGB controllers at `0x60`–`0x67`.

**If the script doesn't work, check the troubleshooting down below.**

### Set static color directly (examples)

```bash
sudo ./rgbfury.sh purple 80
sudo ./rgbfury.sh ff 00 00 50     # Color HEX code (red) then brightness to50%
sudo ./rgbfury.sh off
```

## Autostart (systemd)

Use the `rgbfury.service` systemd unit to autostart the script and don't forget to change the **default value at [line 8](rgbfury.service#L8)** (`ExecStart=/usr/local/bin/rgbfury.sh red 100`): replace `red 100` with the color and brightness you want at startup.

```bash
nano rgbfury.service
sudo cp rgbfury.service /etc/systemd/system/rgbfury.service
sudo systemctl daemon-reload
sudo systemctl enable --now rgbfury.service
systemctl status rgbfury.service
```

The `suspend.target` entries make it run again after waking from sleep. The 2-second delay gives the SMBus time to settle.

## Troubleshooting

### Finding the correct I2C bus

If the script reports `No FURY RGB controllers found`, or shows no effect, auto-detection may have missed your bus.

Most AMD motherboards use one of the `SMBus PIIX4` adapters (often bus 2, 3 or 4). Here's how to find the right one:

1. Install i2c-tools if not already done  
  
   ```bash
   sudo apt update
   sudo apt install i2c-tools
   ```

2. List all I²C/SMBus adapters  bash

   ```bash
   sudo i2cdetect -l
   ```

3. Scan each candidate bus

   ```bash
   sudo i2cdetect -y 2
   sudo i2cdetect -y 3
   sudo i2cdetect -y 4
   ```
   Look for addresses around 0x61 and/or 0x63 (the RGB controllers of FURY Beast DDR5):

   ```bash
       0  1  2  3  4  5  6  7  8  9  a  b  c  d  e  f
    00:          -- -- -- -- -- -- -- -- 
    ...
    60: -- 61 -- 63 -- -- -- -- -- -- -- -- -- -- -- --
   ```

4. Override the auto-detection

   Pass the bus (and optionally the sticks) as environment variables, no need to edit the script:
   ```bash
   sudo I2C_BUS=3 ./rgbfury.sh red
   sudo I2C_BUS=3 RAM_STICKS="0x61 0x63" ./rgbfury.sh red
   ```
   For the systemd unit, add `Environment=I2C_BUS=3` under `[Service]`.

### Changing hardware

Adding or removing RAM sticks, or a bus number shifting between boots (e.g. after a kernel update), is handled automatically: the sticks are detected on every run. `sudo ./rgbfury.sh status` shows which sticks were found.

## About

This is a modified version the original code from https://github.com/ChuckNorrison/rgbfury
