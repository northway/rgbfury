#!/usr/bin/env bash
#
# Kingston FURY Beast RGB Controller – multi-stick version
# Based on https://github.com/ChuckNorrison/rgbfury (MIT)
#
# Changes vs. original:
# - I2C bus and installed sticks are auto-detected (any number of sticks, any slots)
# - All sticks are applied in a loop
# - Each register write is retried, and ANY failure is reported
# - Slightly longer delay between writes
# - New "status" command: sudo ./rgbfury.sh status  (shows the detected bus and sticks)
#
# Auto-detection can be overridden, e.g.: sudo I2C_BUS=3 RAM_STICKS="0x61 0x63" ./rgbfury.sh red

I2C_BUS="${I2C_BUS:-}"             # empty = auto-detect (scans the motherboard SMBus adapters)
read -ra RAM_STICKS <<< "${RAM_STICKS:-}"   # empty = auto-detect
SLOT_ADDRS="0x60 0x67"             # RGB controller address range, one address per DIMM slot
STEP_DELAY=0.05                    # original was 0.02
RETRIES=3                          # retry each register write this many times on failure

BRIGHTNESS_MAX=0x63
DEFAULT_BRIGHTNESS=100

ESC=$(printf "\033")
UP=$'\e[A'
DOWN=$'\e[B'
HIDE_CURSOR=$'\e[?25l'
SHOW_CURSOR=$'\e[?25h'
CURSOR_HOME=$'\e[H'
CURSOR_UP_ONE=$'\e[1A'
CLEAR_LINE=$'\e[2K'

profiles=("off" "red" "green" "blue" "white" "purple" "cyan" "yellow" "magenta" "orange" "pink" "ice" "rainbow")
profile_count=${#profiles[@]}

declare -A profile_rgb
profile_rgb["off"]="00 00 00"
profile_rgb["red"]="ff 00 00"
profile_rgb["green"]="00 ff 00"
profile_rgb["blue"]="00 00 ff"
profile_rgb["white"]="ff ff ff"
profile_rgb["purple"]="80 00 ff"
profile_rgb["cyan"]="00 ff ff"
profile_rgb["yellow"]="ff ff 00"
profile_rgb["magenta"]="ff 00 ff"
profile_rgb["orange"]="ff 80 00"
profile_rgb["pink"]="ff 40 80"
profile_rgb["ice"]="00 cc ff"
profile_rgb["rainbow"]="ff 00 ff"

# Print the RGB controller addresses that answer on bus $1 (same probe as `i2cdetect`).
probe_bus() {
    i2cdetect -y "$1" $SLOT_ADDRS 2>/dev/null |
        awk '/^60:/ { for (i = 2; i <= NF; i++) if ($i ~ /^[0-9a-f][0-9a-f]$/) printf "0x%s ", $i }'
}

# Fill in I2C_BUS and RAM_STICKS unless they were given by the user.
detect_sticks() {
    local buses bus found
    if [ -n "$I2C_BUS" ]; then
        buses=("$I2C_BUS")
    else
        # Only the motherboard SMBus (AMD PIIX4 / Intel I801) – never touch GPU or other i2c buses
        mapfile -t buses < <(i2cdetect -l 2>/dev/null |
            awk -F'\t' '$3 ~ /SMBus (PIIX4|I801)/ { sub("i2c-", "", $1); print $1 }')
    fi
    [ ${#RAM_STICKS[@]} -gt 0 ] && [ -n "$I2C_BUS" ] && return 0
    for bus in "${buses[@]}"; do
        found=$(probe_bus "$bus")
        if [ -n "$found" ]; then
            I2C_BUS=$bus
            [ ${#RAM_STICKS[@]} -eq 0 ] && read -ra RAM_STICKS <<< "$found"
            return 0
        fi
    done
    echo "No FURY RGB controllers found at ${SLOT_ADDRS/ /-} on SMBus bus(es): ${buses[*]:-none}"
    [ "$(id -u)" -ne 0 ] && echo "Run as root (sudo)."
    echo "Check with: sudo i2cdetect -l   and   sudo i2cdetect -y <bus>"
    return 1
}

# Write one register, retrying on failure. Prints nothing on success.
write_reg() {
    local addr=$1 reg=$2 val=$3 try err
    for ((try = 1; try <= RETRIES; try++)); do
        if err=$(i2cset -y "$I2C_BUS" "$addr" "$reg" "$val" 2>&1); then
            sleep "$STEP_DELAY"
            return 0
        fi
        sleep 0.1
    done
    echo "stick $addr: write $reg=$val failed after $RETRIES tries: $err"
    return 1
}

set_color() {
    local addr=$1 r=$2 g=$3 b=$4 bright=$5
    local failed=0
    write_reg "$addr" 0x08 0x53      || ((failed++))   # begin transfer
    write_reg "$addr" 0x09 0x00      || ((failed++))   # static mode
    write_reg "$addr" 0x31 0x"$r"    || ((failed++))
    write_reg "$addr" 0x32 0x"$g"    || ((failed++))
    write_reg "$addr" 0x33 0x"$b"    || ((failed++))
    write_reg "$addr" 0x20 0x"$bright" || ((failed++))
    write_reg "$addr" 0x08 0x44      || ((failed++))   # end transfer / apply
    return $(( failed > 0 ))
}

# Apply to every stick; print a one-line summary of failures (if any).
apply_all() {
    local r=$1 g=$2 b=$3 bright=$4 addr out bad=()
    for addr in "${RAM_STICKS[@]}"; do
        out=$(set_color "$addr" "$r" "$g" "$b" "$bright") || bad+=("$addr")
        [ -n "$out" ] && LAST_ERRORS+="$out"$'\n'
    done
    if [ ${#bad[@]} -gt 0 ]; then
        echo "Errors on stick(s): ${bad[*]}"
        return 1
    fi
    return 0
}

# The controllers don't return register contents to plain byte reads (always 0x5a),
# so only report what was detected.
show_status() {
    echo "Found ${#RAM_STICKS[@]} stick(s) on bus $I2C_BUS: ${RAM_STICKS[*]}"
}

draw_menu() {
    printf "${CURSOR_HOME}${HIDE_CURSOR}"
    echo "┌────────────────────────────────────────────────────────────┐"
    printf "│ FURY Beast RGB   Brightness: %3d%%   Sticks: %d on bus %-3s   │\n" "$current_brightness" "${#RAM_STICKS[@]}" "$I2C_BUS"
    echo "└────────────────────────────────────────────────────────────┘"
    echo " ↑ ↓ navigate • Enter select • q quit"
    echo ""
    local i name color_code
    for i in "${!profiles[@]}"; do
        name="${profiles[$i]}"
        color_code=""
        [ $i -eq $selected ] && color_code=$'\e[96m'
        [ $i -eq $last_activated ] && color_code=$'\e[32m'
        printf " %s%-52s%s\n" "$color_code" "$name" $'\e[0m'
    done
    color_code=""
    [ $profile_count -eq $selected ] && color_code=$'\e[96m'
    [ $profile_count -eq $last_activated ] && color_code=$'\e[32m'
    printf " %s%-52s%s\n" "$color_code" "Set brightness (${current_brightness}%)" $'\e[0m'
    printf "${CLEAR_LINE} %s\n" "$status_line"
}

detect_sticks || exit 1

# ────────────────────────────────────────────
# Direct mode / automation
if [ $# -ge 1 ]; then
    if [ "$1" = "status" ]; then
        show_status
        exit 0
    fi

    input="$1"
    brightness_input="${2:-$DEFAULT_BRIGHTNESS}"
    if [[ -n "${profile_rgb[$input]}" ]]; then
        read r g b <<< "${profile_rgb[$input]}"
    else
        r="$1" g="$2" b="$3"
        brightness_input="${4:-$DEFAULT_BRIGHTNESS}"
        if [ $# -lt 3 ] || ! [[ $r =~ ^[0-9a-fA-F]{2}$ ]] || ! [[ $g =~ ^[0-9a-fA-F]{2}$ ]] || ! [[ $b =~ ^[0-9a-fA-F]{2}$ ]]; then
            echo "Usage: $0 <profile> [brightness] | $0 rr gg bb [brightness] | $0 status"
            echo "Profiles: ${profiles[*]}"
            exit 1
        fi
    fi
    hex=$(printf "%02x" $(( (brightness_input * BRIGHTNESS_MAX) / 100 )))
    LAST_ERRORS=""
    apply_all "$r" "$g" "$b" "$hex"
    rc=$?
    [ -n "$LAST_ERRORS" ] && printf "%s" "$LAST_ERRORS"
    exit $rc
fi

# ────────────────────────────────────────────
# Interactive mode
selected=0
last_activated=-1
total_items=$((profile_count + 1))
current_brightness=$DEFAULT_BRIGHTNESS
last_r="00"; last_g="00"; last_b="00"
status_line=""

trap 'tput cnorm 2>/dev/null; printf "%s" "$SHOW_CURSOR"' EXIT
tput civis 2>/dev/null || true
clear

while true; do
    draw_menu
    IFS= read -rsn1 key
    if [ "$key" = "$ESC" ]; then
        read -rsn2 -t 0.1 rest 2>/dev/null
        case "${key}${rest}" in
            "$UP")   ((selected--)); (( selected < 0 )) && selected=$((total_items - 1)) ;;
            "$DOWN") ((selected++)); (( selected >= total_items )) && selected=0 ;;
        esac
    elif [ "$key" = $'\n' ] || [ -z "$key" ]; then
        if [ $selected -lt $profile_count ]; then
            prof=${profiles[$selected]}
            read r g b <<< "${profile_rgb["$prof"]}"
            hex=$(printf "%02x" $(( (current_brightness * BRIGHTNESS_MAX) / 100 )))
            LAST_ERRORS=""
            status_line=$(apply_all "$r" "$g" "$b" "$hex") || true
            last_activated=$selected
            last_r="$r"; last_g="$g"; last_b="$b"
        else
            printf "New brightness (0-100): "
            printf "%s" "$SHOW_CURSOR"
            read new_val
            printf "${CURSOR_UP_ONE}${CLEAR_LINE}"
            if [[ "$new_val" =~ ^[0-9]+$ ]] && (( new_val >= 0 && new_val <= 100 )); then
                current_brightness=$new_val
                last_activated=$profile_count
                hex=$(printf "%02x" $(( (current_brightness * BRIGHTNESS_MAX) / 100 )))
                status_line=$(apply_all "$last_r" "$last_g" "$last_b" "$hex") || true
            else
                status_line="Invalid value – keeping $current_brightness%"
            fi
        fi
    elif [ "$key" = "q" ] || [ "$key" = "Q" ]; then
        clear
        echo "Exited."
        exit 0
    fi
done
