#!/usr/bin/env bash
set -euo pipefail

FFMPEG_REF="${1:-n8.1}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VENDOR_DIR="${ROOT_DIR}/Vendor/FFmpeg"
SOURCE_DIR="${VENDOR_DIR}/FFmpeg"

mkdir -p "${VENDOR_DIR}"

if [[ -d "${SOURCE_DIR}/.git" ]]; then
    echo "Official FFmpeg source already exists: ${SOURCE_DIR}"
    echo "Current ref: $(git -C "${SOURCE_DIR}" rev-parse --abbrev-ref HEAD || true)"
    exit 0
fi

echo "Cloning official FFmpeg ref ${FFMPEG_REF}"
git clone --depth 1 --branch "${FFMPEG_REF}" "https://github.com/FFmpeg/FFmpeg.git" "${SOURCE_DIR}"

echo "Fetched official FFmpeg source: ${SOURCE_DIR}"
echo "Next step: scripts/ffmpeg/build_ios_minimal.sh"
