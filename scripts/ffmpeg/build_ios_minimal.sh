#!/usr/bin/env bash
set -euo pipefail

IOS_MIN="${IOS_MIN:-16.0}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FFMPEG_DIR="${ROOT_DIR}/Vendor/FFmpeg/FFmpeg"
INSTALL_ROOT="${FFMPEG_DIR}/ios-build"

LIB_NAMES=(
    libavcodec.a
    libavdevice.a
    libavfilter.a
    libavformat.a
    libavutil.a
    libswresample.a
    libswscale.a
    libcatmediafftools.a
)

if [[ ! -d "${FFMPEG_DIR}" ]]; then
    echo "Official FFmpeg source not found at ${FFMPEG_DIR}" >&2
    echo "Run scripts/ffmpeg/fetch_official_ffmpeg.sh first." >&2
    exit 1
fi

cd "${FFMPEG_DIR}"

create_fftools_bridge_lib() {
    local sdk_path="$1"
    local arch="$2"
    local cc_tool="$3"
    local ar_tool="$4"
    local ranlib_tool="$5"
    local out_lib="$6"
    local min_flag="$7"

    local bridge_dir="${FFMPEG_DIR}/.catmedia-bridge-${arch}"
    rm -rf "${bridge_dir}"
    mkdir -p "${bridge_dir}"

    cat > "${bridge_dir}/ffmpeg_main.c" <<'EOF'
#define main ffmpeg_main
#define program_name ffmpeg_program_name
#define program_birth_year ffmpeg_program_birth_year
#include "fftools/ffmpeg.c"

#undef program_name
#undef program_birth_year
const char program_name[] = "ffmpeg";
const int program_birth_year = ffmpeg_program_birth_year;
EOF

    cat > "${bridge_dir}/ffprobe_main.c" <<'EOF'
#define main ffprobe_main
#define program_name ffprobe_program_name
#define program_birth_year ffprobe_program_birth_year
#define show_help_default ffprobe_show_help_default
#define show_help_default_terminated ffprobe_show_help_default_terminated
#include "fftools/ffprobe.c"
EOF

    "${cc_tool}" -c -arch "${arch}" -isysroot "${sdk_path}" "${min_flag}" -I. -Ifftools \
        "${bridge_dir}/ffmpeg_main.c" -o "${bridge_dir}/ffmpeg_main.o"
    "${cc_tool}" -c -arch "${arch}" -isysroot "${sdk_path}" "${min_flag}" -I. -Ifftools \
        "${bridge_dir}/ffprobe_main.c" -o "${bridge_dir}/ffprobe_main.o"

    local extra_objects=()
    while IFS= read -r object_file; do
        extra_objects+=("${object_file}")
    done < <(find "fftools" -type f -name "*.o" ! -name "ffmpeg.o" ! -name "ffprobe.o" | sort)

    "${ar_tool}" -rcs "${out_lib}" "${bridge_dir}/ffmpeg_main.o" "${bridge_dir}/ffprobe_main.o" "${extra_objects[@]}"
    "${ranlib_tool}" "${out_lib}"
}

build_one_slice() {
    local sdk="$1"
    local arch="$2"
    local install_dir="$3"

    local sdk_path
    local cc
    local ar_tool
    local ranlib_tool
    local min_flag
    local cpu_flag=""
    local asm_flag=""

    sdk_path="$(xcrun --sdk "${sdk}" --show-sdk-path)"
    cc="$(xcrun --sdk "${sdk}" -f clang)"
    ar_tool="$(xcrun --sdk "${sdk}" -f ar)"
    ranlib_tool="$(xcrun --sdk "${sdk}" -f ranlib)"
    if [[ "${sdk}" == "iphoneos" ]]; then
        min_flag="-miphoneos-version-min=${IOS_MIN}"
    else
        min_flag="-mios-simulator-version-min=${IOS_MIN}"
    fi

    if [[ "${arch}" == "arm64" ]]; then
        cpu_flag="--cpu=armv8"
    elif [[ "${arch}" == "x86_64" ]]; then
        asm_flag="--disable-x86asm"
    fi

    if [[ -f Makefile ]]; then
        make distclean >/dev/null 2>&1 || make clean >/dev/null 2>&1 || true
    fi

    ./configure \
    --prefix="${install_dir}" \
    --target-os=darwin \
    --arch="${arch}" \
    ${cpu_flag} \
    --cc="${cc}" \
    --ar="${ar_tool}" \
    --ranlib="${ranlib_tool}" \
    --sysroot="${sdk_path}" \
    --extra-cflags="-arch ${arch} ${min_flag}" \
    --extra-ldflags="-arch ${arch} ${min_flag}" \
    --enable-cross-compile \
    --enable-static \
    --disable-shared \
    --disable-debug \
    --disable-doc \
    --disable-autodetect \
    --disable-network \
    ${asm_flag} \
    --enable-ffmpeg \
    --enable-ffprobe \
    --enable-protocol=file \
    --enable-protocol=pipe \
    --enable-demuxer=mov \
    --enable-muxer=mp4 \
    --enable-muxer=matroska

    make -j"$(sysctl -n hw.ncpu)"
    make install

    create_fftools_bridge_lib "${sdk_path}" "${arch}" "${cc}" "${ar_tool}" "${ranlib_tool}" "${install_dir}/lib/libcatmediafftools.a" "${min_flag}"
}

merge_simulator_slices() {
    local arm64_dir="$1"
    local x86_64_dir="$2"
    local out_dir="$3"

    rm -rf "${out_dir}"
    mkdir -p "${out_dir}/lib" "${out_dir}/include"

    rsync -a --delete "${arm64_dir}/include/" "${out_dir}/include/"

    for lib in "${LIB_NAMES[@]}"; do
        lipo -create \
            "${arm64_dir}/lib/${lib}" \
            "${x86_64_dir}/lib/${lib}" \
            -output "${out_dir}/lib/${lib}"
    done
}

mkdir -p "${INSTALL_ROOT}"

DEVICE_DIR="${INSTALL_ROOT}/iphoneos"
SIM_ARM64_DIR="${INSTALL_ROOT}/iphonesimulator-arm64"
SIM_X86_64_DIR="${INSTALL_ROOT}/iphonesimulator-x86_64"
SIM_UNIVERSAL_DIR="${INSTALL_ROOT}/iphonesimulator"

build_one_slice iphoneos arm64 "${DEVICE_DIR}"
build_one_slice iphonesimulator arm64 "${SIM_ARM64_DIR}"
build_one_slice iphonesimulator x86_64 "${SIM_X86_64_DIR}"
merge_simulator_slices "${SIM_ARM64_DIR}" "${SIM_X86_64_DIR}" "${SIM_UNIVERSAL_DIR}"

mkdir -p "${INSTALL_ROOT}/include"
rsync -a --delete "${DEVICE_DIR}/include/" "${INSTALL_ROOT}/include/"

cat <<EOF
Build complete.

Install root:
- ${INSTALL_ROOT}

Add to Xcode:
- Header Search Paths: \$(PROJECT_DIR)/Vendor/FFmpeg/FFmpeg/ios-build/include
- Library Search Paths: \$(PROJECT_DIR)/Vendor/FFmpeg/FFmpeg/ios-build/\$(PLATFORM_NAME)/lib
- Other Linker Flags: -lcatmediafftools -lavdevice -lavfilter -lavcodec -lavformat -lavutil -lswresample -lswscale -lz -lbz2 -liconv -lc++
EOF
