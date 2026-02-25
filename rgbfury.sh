#!/usr/bin/env bash
#
# Kingston FURY Beast RGB Controller – Final working version
# Features:
# - Interactive menu with arrow keys
# - Brightness applied immediately
# - Last color preserved when changing brightness
# - Selected: light cyan (\e[96m)
# - Last activated: green (\e[32m)
# - Only real errors shown
# - Default brightness 100%

I2C_BUS=2
RAM_STICK_1=0x61
RAM_STICK_2=0x63

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

set_color() {
    local addr=$1 r=$2 g=$3 b=$4 bright=$5
    local failed=0

    i2cset -y "$I2C_BUS" "$addr" 0x08 0x53 >/dev/null 2>&1 || ((failed++))
    sleep 0.02
    i2cset -y "$I2C_BUS" "$addr" 0x09 0x00 >/dev/null 2>&1 || ((failed++))
    sleep 0.02
    i2cset -y "$I2C_BUS" "$addr" 0x31 0x"$r" >/dev/null 2>&1 || ((failed++))
    sleep 0.02
    i2cset -y "$I2C_BUS" "$addr" 0x32 0x"$g" >/dev/null 2>&1 || ((failed++))
    sleep 0.02
    i2cset -y "$I2C_BUS" "$addr" 0x33 0x"$b" >/dev/null 2>&1 || ((failed++))
    sleep 0.02
    i2cset -y "$I2C_BUS" "$addr" 0x20 "$bright" >/dev/null 2>&1 || ((failed++))
    sleep 0.02
    i2cset -y "$I2C_BUS" "$addr" 0x08 0x44 >/dev/null 2>&1 || ((failed++))

    if [ "$failed" -ge 3 ]; then
        echo "Error applying color on stick $addr"
        return 1
    fi
    return 0
}

draw_menu() {
    printf "${CURSOR_HOME}${HIDE_CURSOR}"

    echo "┌────────────────────────────────────────────────────────────┐"
    printf "│ FURY Beast RGB          Brightness: %3d%%                 │\n" "$current_brightness"
    echo "└────────────────────────────────────────────────────────────┘"
    echo " ↑ ↓ navigate • Enter select • q quit"
    echo ""

    local i name color_code
    for i in "${!profiles[@]}"; do
        name="${profiles[$i]}"
        color_code=""

        if [ $i -eq $selected ]; then
            color_code=$'\e[96m'
        fi
        if [ $i -eq $last_activated ]; then
            color_code=$'\e[32m'
        fi

        printf " %s%-52s%s\n" "$color_code" "$name" $'\e[0m'
    done

    color_code=""
    if [ $profile_count -eq $selected ]; then
        color_code=$'\e[96m'
    fi
    if [ $profile_count -eq $last_activated ]; then
        color_code=$'\e[32m'
    fi

    printf " %s%-52s%s\n" "$color_code" "Set brightness (${current_brightness}%)" $'\e[0m'
    echo ""
}

# Direct mode / automation
if [ $# -ge 1 ]; then
    input="$1"
    brightness_input="${2:-$DEFAULT_BRIGHTNESS}"

    if [[ -n "${profile_rgb[$input]}" ]]; then
        rgb="${profile_rgb[$input]}"
        read r g b <<< "$rgb"
    else
        r="$1" g="$2" b="$3"
        brightness_input="${4:-$DEFAULT_BRIGHTNESS}"
        if [ $# -lt 3 ] || ! [[ $r =~ ^[0-9a-fA-F]{2}$ ]] || ! [[ $g =~ ^[0-9a-fA-F]{2}$ ]] || ! [[ $b =~ ^[0-9a-fA-F]{2}$ ]]; then
            echo "Usage: $0 <profile> [brightness]  or  $0 rr gg bb [brightness]"
            echo "Profiles: ${profiles[*]}"
            exit 1
        fi
    fi

    hex=$(printf "%02x" $(( (brightness_input * BRIGHTNESS_MAX) / 100 )))

    set_color "$RAM_STICK_1" "$r" "$g" "$b" "$hex"
    set_color "$RAM_STICK_2" "$r" "$g" "$b" "$hex"
    exit 0
fi

# ────────────────────────────────────────────
# Interactive mode
selected=0
last_activated=-1
total_items=$((profile_count + 1))
current_brightness=$DEFAULT_BRIGHTNESS
last_r="00"   # Remember last color components
last_g="00"
last_b="00"

tput civis 2>/dev/null || true
clear

while true; do
    draw_menu

    IFS= read -rsn1 key

    if [ "$key" = "$ESC" ]; then
        read -rsn2 -t 0.1 rest 2>/dev/null
        fullkey="${key}${rest}"

        case "$fullkey" in
            "$UP")
                ((selected--))
                (( selected < 0 )) && selected=$((total_items - 1))
                ;;
            "$DOWN")
                ((selected++))
                (( selected >= total_items )) && selected=0
                ;;
        esac
    elif [ "$key" = $'\n' ] || [ -z "$key" ]; then   # Enter
        if [ $selected -lt $profile_count ]; then
            prof=${profiles[$selected]}
            rgb="${profile_rgb["$prof"]}"
            read r g b <<< "$rgb"
            hex=$(printf "%02x" $(( (current_brightness * BRIGHTNESS_MAX) / 100 )))

            set_color "$RAM_STICK_1" "$r" "$g" "$b" "$hex" >/dev/null 2>&1 || echo "Error applying $prof (stick 1)"
            set_color "$RAM_STICK_2" "$r" "$g" "$b" "$hex" >/dev/null 2>&1 || echo "Error applying $prof (stick 2)"

            last_activated=$selected
            last_r="$r"
            last_g="$g"
            last_b="$b"
        else
            printf "New brightness (0-100): "
            read new_val
            printf "${CURSOR_UP_ONE}${CLEAR_LINE}"

            if [[ "$new_val" =~ ^[0-9]+$ ]] && (( new_val >= 0 && new_val <= 100 )); then
                current_brightness=$new_val
                last_activated=$profile_count

                # Apply immediately using last known color
                r="$last_r"
                g="$last_g"
                b="$last_b"

                hex=$(printf "%02x" $(( (current_brightness * BRIGHTNESS_MAX) / 100 )))
                set_color "$RAM_STICK_1" "$r" "$g" "$b" "$hex" >/dev/null 2>&1 || echo "Error applying brightness (stick 1)"
                set_color "$RAM_STICK_2" "$r" "$g" "$b" "$hex" >/dev/null 2>&1 || echo "Error applying brightness (stick 2)"
            else
                echo "Invalid value – keeping $current_brightness%"
            fi
        fi
    elif [ "$key" = "q" ] || [ "$key" = "Q" ]; then
        clear
        tput cnorm 2>/dev/null || true
        echo "Exited."
        exit 0
    fi
done

