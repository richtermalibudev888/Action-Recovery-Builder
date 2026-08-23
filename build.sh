#!/bin/bash

# Scripts by: @archer0305

# This scripts made for samsung device only! 

# Unauthorized!

set -e

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Message helpers
info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Display script author info
info "Scripts by @archer0305"

usage() {
    cat <<EOF
${YELLOW}Usage:${NC} $0 <device_codename> <target> or $0 clean

Valid targets:
  1 (recoveryimage)      → recovery.img
  2 (bootimage)          → boot.img
  3 (vendorbootimage)    → vendor_boot.img

Examples:
  $0 lavender recoveryimage
  $0 lavender 1
  $0 clean
EOF
    exit 1
}

clean_out() {
    info "Cleaning output directory..."
    rm -rf out/
    info "Done cleaning."
}

choose_target() {
    local options=("recoveryimage → recovery.img" "bootimage → boot.img" "vendorbootimage → vendor_boot.img" "Cancel")
    local values=("recoveryimage" "bootimage" "vendorbootimage" "Cancel")

    echo -e "${YELLOW}Please choose a build target by number:${NC}"
    for i in "${!options[@]}"; do
        printf "  %d. %s\n" "$((i+1))" "${options[i]}"
    done

    while true; do
        printf "Enter choice [1-%d]: " "${#options[@]}"
        read choice
        if [[ "$choice" =~ ^[1-9][0-9]*$ ]] && (( choice >= 1 && choice <= ${#values[@]} )); then
            selected="${values[$((choice-1))]}"
            [[ "$selected" == "Cancel" ]] && echo "Cancelled." && exit 0
            info "Selected target: $selected"
            TARGET="$selected"
            break
        else
            echo "Invalid choice. Enter a number between 1 and ${#values[@]}."
        fi
    done
}

compress_image() {
    local image_name="$1"
    local input_path="out/target/product/${DEVICE}/${image_name}.img"
    local output_dir="out/target/product/${DEVICE}"
    local output_path="${output_dir}/${image_name}.img.lz4"

    if [[ -f "$input_path" ]]; then
        mkdir -p "$output_dir"
        rm -f "$output_path"
        lz4 -B6 --content-size "$input_path" "$output_path" > /dev/null 2>&1 || error "Compression failed for ${image_name}.img"
    else
        warn "Missing file: $input_path, skipping compression"
    fi
}

pack_tar() {
    local image_name="$1"
    local output_dir="out/target/product/${DEVICE}"
    local tar_name="twrp-3.7.1_12-0-${DEVICE}.img.tar"
    local main_lz4="${output_dir}/${image_name}.img.lz4"
    local vbmeta_lz4="patch_vb/${DEVICE}/vbmeta.img.lz4"

    # Check target image
    if [[ ! -f "$main_lz4" ]]; then
        warn "Missing .lz4 file for ${image_name}, skipping tar creation"
        return
    fi

    # Warn if vbmeta missing
    [[ ! -f "$vbmeta_lz4" ]] && warn "Missing vbmeta.img.lz4, will skip adding vbmeta"

    # Create tar with target image
    tar cvf "$tar_name" -C "$output_dir" "$(basename "$main_lz4")" > /dev/null 2>&1

    # Add vbmeta if exists
    [[ -f "$vbmeta_lz4" ]] && tar rvf "$tar_name" -C "patch_vb/${DEVICE}" "$(basename "$vbmeta_lz4")" > /dev/null 2>&1
}

# --- Main Logic ---

[[ "$1" == "--help" || "$1" == "-h" ]] && usage
[[ "$1" == "clean" ]] && clean_out && exit 0

[[ $# -eq 0 ]] && { echo -e "${RED}Error: Missing arguments.${NC}"; echo "Run: $0 <device_codename> [<target>]"; exit 1; }
[[ $# -gt 2 ]] && { echo -e "${RED}Error: Too many arguments.${NC}"; echo "Run: $0 <device_codename> [<target>]"; exit 1; }

DEVICE="$1"

if [[ $# -eq 1 ]]; then
    choose_target
else
    case "$2" in
        1) TARGET="recoveryimage" ;;
        2) TARGET="bootimage" ;;
        3) TARGET="vendorbootimage" ;;
        *) TARGET="$2" ;;
    esac
fi

VALID_TARGETS=("recoveryimage" "bootimage" "vendorbootimage")
[[ ! " ${VALID_TARGETS[@]} " =~ " ${TARGET} " ]] && error "Invalid target: $TARGET"

info "Setting up build environment..."
[[ -f build/envsetup.sh ]] || error "Missing build/envsetup.sh"
source build/envsetup.sh || error "Failed to source build environment."

info "Lunching target: twrp_${DEVICE}-eng"
lunch "twrp_${DEVICE}-eng" || error "Lunch failed for device: $DEVICE"

info "Building: $TARGET"
make -j"$(nproc)" "$TARGET" || error "Build failed for target: $TARGET"

# Compress and package
case "$TARGET" in
    recoveryimage) compress_image "recovery"; pack_tar "recovery" ;;
    bootimage) compress_image "boot"; pack_tar "boot" ;;
    vendorbootimage) compress_image "vendor_boot"; pack_tar "vendor_boot" ;;
esac
