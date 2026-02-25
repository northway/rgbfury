# Kingston FURY Beast RGB Controller for Linux

A lightweight, dependency-free Bash script to control the RGB LEDs on **Kingston FURY Beast DDR5** RAM modules directly via SMBus/i2c under Linux.

Works great when OpenRGB fails to detect the modules or on AMD systems where spd5118 blocks access.

### Features
- Interactive terminal menu with arrow-key navigation
- Real-time color selection + brightness control (0–100%)
- Remembers last selected color when changing brightness
- Immediate application of brightness changes
- Direct/scriptable mode for automation (e.g. cron, startup scripts)
- Only shows real errors – clean output
- No external dependencies except i2c-tools

### Quick Start
```bash
# Install i2c-tools (once)
sudo apt install i2c-tools

# Blacklist blocker module (recommended)
echo "blacklist spd5118" | sudo tee /etc/modprobe.d/blacklist-spd5118.conf
sudo update-initramfs -u
sudo reboot

# Run interactive mode
sudo ./rgbram.sh

# Set static color directly (examples)
sudo ./rgbram.sh purple 80
sudo ./rgbram.sh ff 00 00 50     # bright red at 50%
sudo ./rgbram.sh off
```

### Troubleshooting: Finding the correct I2C bus

If the script doesn't work or shows no effect, the I2C bus number (`I2C_BUS=2` in the script) might be different on your system.

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
4. Update the script

   Change the line at the top:
   ```bash
   I2C_BUS=2     # ← change to your detected bus number, e.g. I2C_BUS=3
   ```




