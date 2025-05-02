#!/usr/bin/env bash

########################################################################
##
## A script for Proton compilation with WoW64 support.
## Uses an Ubuntu 64-bit bootstrap with bubblewrap (no root required).
##
## Requires: git, wget, autoconf, xz, bubblewrap, gcc-14, g++-14,
## x86_64-w64-mingw32-gcc, libvulkan-dev, libfreetype6-dev, etc.
##
## Environment variables can be adjusted below.
##
########################################################################

# Prevent launching as root
if [ $EUID = 0 ] && [ -z "$ALLOW_ROOT" ]; then
    echo "Do not run this script as root!"
    echo "Set ALLOW_ROOT environment variable if needed."
    exit 1
fi

# Configuration variables
export WINE_VERSION="${WINE_VERSION:-latest}"
export WINE_BRANCH="${WINE_BRANCH:-proton}"
export PROTON_BRANCH="${PROTON_BRANCH:-proton_10.0}"
export STAGING_VERSION="${STAGING_VERSION:-}"
export TERMUX_GLIBC="${TERMUX_GLIBC:-true}"
export TERMUX_PROOT="${TERMUX_PROOT:-false}"
export EXPERIMENTAL_WOW64="${EXPERIMENTAL_WOW64:-true}"
export STAGING_ARGS="${STAGING_ARGS:-}"
export CUSTOM_SRC_PATH=""
export DO_NOT_COMPILE="${DO_NOT_COMPILE:-false}"
export USE_CCACHE="${USE_CCACHE:-false}"
export BUILD_DIR="${HOME}/build_wine"

# Build options optimized for Proton
export WINE_BUILD_OPTIONS="--disable-winemenubuilder --disable-win16 --enable-win64 \
    --disable-tests --with-vulkan --with-freetype --with-fontconfig \
    --without-capi --without-coreaudio --without-cups --without-gphoto \
    --without-osmesa --without-oss --without-pcap --without-pcsclite \
    --without-sane --without-udev --without-unwind --without-usb \
    --without-v4l2 --without-wayland --without-xinerama"

# WoW64 configuration
if [ "${EXPERIMENTAL_WOW64}" = "true" ]; then
    export BOOTSTRAP_X64=/opt/chroots/noble64_chroot
    export scriptdir="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
    export CC="gcc-14"
    export CXX="g++-14"
    export CROSSCC_X64="x86_64-w64-mingw32-gcc"
    export CROSSCXX_X64="x86_64-w64-mingw32-g++"
    export CFLAGS_X64="-march=x86-64 -msse3 -mfpmath=sse -O3 -ftree-vectorize -pipe"
    export LDFLAGS="-Wl,-O1,--sort-common,--as-needed"
    export CROSSCFLAGS_X64="${CFLAGS_X64}"
    export CROSSLDFLAGS="${LDFLAGS}"

    if [ "$USE_CCACHE" = "true" ]; then
        export CC="ccache ${CC}"
        export CXX="ccache ${CXX}"
        export CROSSCC_X64="ccache ${CROSSCC_X64}"
        export CROSSCXX_X64="ccache ${CROSSCXX_X64}"
        [ -z "${XDG_CACHE_HOME}" ] && export XDG_CACHE_HOME="${HOME}/.cache"
        mkdir -p "${XDG_CACHE_HOME}/ccache" "${HOME}/.ccache"
    fi

    build_with_bwrap() {
        bwrap --ro-bind "${BOOTSTRAP_X64}" / --dev /dev --ro-bind /sys /sys \
            --proc /proc --tmpfs /tmp --tmpfs /home --tmpfs /run --tmpfs /var \
            --tmpfs /mnt --tmpfs /media --bind "${BUILD_DIR}" "${BUILD_DIR}" \
            --bind-try "${XDG_CACHE_HOME}/ccache" "${XDG_CACHE_HOME}/ccache" \
            --bind-try "${HOME}/.ccache" "${HOME}/.ccache" \
            --setenv PATH "/bin:/sbin:/usr/bin:/usr/sbin" "$@"
    }
else
    echo "This script is configured for WoW64 mode only. Set EXPERIMENTAL_WOW64=true."
    exit 1
fi

# Environment checks
if [ "$TERMUX_PROOT" = "true" ] && [ "$TERMUX_GLIBC" = "true" ]; then
    echo "TERMUX_PROOT and TERMUX_GLIBC cannot both be true."
    exit 1
fi

echo "Building for ${TERMUX_GLIBC:+Termux glibc }environment"
echo "WoW64 mode: ${EXPERIMENTAL_WOW64}"
echo "Wine branch: ${WINE_BRANCH}, Proton branch: ${PROTON_BRANCH}"

# Dependency checks
for cmd in git autoconf wget xz bwrap; do
    command -v "$cmd" >/dev/null || {
        echo "Please install $cmd and run the script again."
        exit 1
    }
done

# Bootstrap validation
if [ ! -d "${BOOTSTRAP_X64}" ]; then
    echo "Bootstrap directory ${BOOTSTRAP_X64} not found!"
    exit 1
fi

# Install dependencies in bootstrap
sudo chroot "${BOOTSTRAP_X64}" /bin/bash -c "
    apt update && apt install -y \
        gcc-14 g++-14 x86_64-w64-mingw32-gcc x86_64-w64-mingw32-g++ \
        build-essential autoconf flex bison pkg-config \
        libvulkan-dev libfreetype6-dev libfontconfig1-dev libx11-dev \
        libpng-dev libjpeg-dev libtiff-dev libxml2-dev libxslt1-dev
" || {
    echo "Failed to install dependencies in ${BOOTSTRAP_X64}."
    exit 1
}

# Replace "latest" with actual Wine version
if [ "${WINE_VERSION}" = "latest" ] || [ -z "${WINE_VERSION}" ]; then
    WINE_VERSION="$(wget -q -O - "https://raw.githubusercontent.com/wine-mirror/wine/master/VERSION" | tail -c +14)"
fi

# Prepare build directory
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}" || exit 1

echo "Downloading Proton source code..."

# Clone Proton source
if [ -n "${CUSTOM_SRC_PATH}" ]; then
    if [[ "${CUSTOM_SRC_PATH}" =~ ^(git://|https:) ]]; then
        git clone "${CUSTOM_SRC_PATH}" wine || exit 1
    else
        [ -f "${CUSTOM_SRC_PATH}/configure" ] || {
            echo "Invalid CUSTOM_SRC_PATH: ${CUSTOM_SRC_PATH}"
            exit 1
        }
        cp -r "${CUSTOM_SRC_PATH}" wine
    fi
    WINE_VERSION="$(cat wine/VERSION | tail -c +14)"
    BUILD_NAME="${WINE_VERSION}-custom"
elif [ "$WINE_BRANCH" = "proton" ]; then
    git clone https://github.com/ValveSoftware/wine -b "${PROTON_BRANCH}" wine || exit 1
    WINE_VERSION="$(cat wine/VERSION | tail -c +14)-$(git -C wine rev-parse --short HEAD)"
    [[ "${PROTON_BRANCH}" == "experimental_"* ]] || [ "${PROTON_BRANCH}" = "bleeding-edge" ] && \
        BUILD_NAME=proton-exp-"${WINE_VERSION}" || BUILD_NAME=proton-"${WINE_VERSION}"
else
    echo "This script is configured for Proton branch only. Set WINE_BRANCH=proton."
    exit 1
fi

cd wine || exit 1

# Apply Proton-specific patches
if [ "$TERMUX_GLIBC" = "true" ] && [ "$WINE_BRANCH" = "proton" ]; then
    echo "Applying Termux glibc patches for Proton..."
    for patch in esync.patch termux-wine-fix.patch pathfix-10.patch; do
        patch -Np1 < "${scriptdir}/${patch}" || {
            echo "Failed to apply ${patch}. Check patch compatibility with proton_10.0."
            exit 1
        }
    done
fi

# Additional patches
echo "Applying Input Bridge and CPU topology patches..."
patch -p1 -R < "${scriptdir}/inputbridgefix.patch" || {
    echo "Failed to revert Input Bridge patch."
    exit 1
}
patch -p1 < "${scriptdir}/wine-cpu-topology-wine-9.22.patch" || {
    echo "Failed to apply CPU topology patch."
    exit 1
}

# Prepare source
dlls/winevulkan/make_vulkan
tools/make_requests
tools/make_specfiles
autoreconf -f
cd "${BUILD_DIR}" || exit 1

if [ "${DO_NOT_COMPILE}" = "true" ]; then
    echo "DO_NOT_COMPILE is true. Exiting."
    exit 0
fi

# Build and install
export CROSSCC="${CROSSCC_X64}"
export CROSSCXX="${CROSSCXX_X64}"
export CFLAGS="${CFLAGS_X64}"
export CXXFLAGS="${CFLAGS_X64}"
export CROSSCFLAGS="${CROSSCFLAGS_X64}"
export CROSSCXXFLAGS="${CROSSCFLAGS_X64}"

mkdir "${BUILD_DIR}/build64"
cd "${BUILD_DIR}/build64" || exit 1
build_with_bwrap "${BUILD_DIR}/wine/configure" --enable-archs=i386,x86_64 ${WINE_BUILD_OPTIONS} \
    --prefix "${BUILD_DIR}/wine-${BUILD_NAME}-amd64" || {
    echo "Configure failed. Check for missing dependencies."
    exit 1
}
build_with_bwrap make -j8 || {
    echo "Make failed."
    exit 1
}
build_with_bwrap make install || {
    echo "Make install failed."
    exit 1
}

# Debug: Check installation
echo "Installation directory contents:"
ls -l "${BUILD_DIR}/wine-${BUILD_NAME}-amd64"
echo "Bin folder contents:"
ls -l "${BUILD_DIR}/wine-${BUILD_NAME}-amd64/bin"

# Post-processing
echo "Creating and compressing archive..."
cd "${BUILD_DIR}" || exit 1

if touch "${scriptdir}/write_test"; then
    rm -f "${scriptdir}/write_test"
    result_dir="${scriptdir}"
else
    result_dir="${HOME}"
fi

export XZ_OPT="-9"
mkdir results
mv wine-${BUILD_NAME}-amd64 results/wine

if [ -d "results/wine" ]; then
    echo "Contents of results/wine before cleanup:"
    ls -l results/wine
    rm -rf results/wine/include results/wine/share/applications results/wine/share/man
    echo "Contents of results/wine after cleanup:"
    ls -l results/wine
    echo "Bin folder contents after cleanup:"
    ls -l results/wine/bin
    cd results
    tar -Jcf "wine-action-${WINE_BRANCH}.tar.xz" wine
    mv "wine-action-${WINE_BRANCH}.tar.xz" "${result_dir}"
    cd -
else
    echo "Error: results/wine directory not found."
    exit 1
fi

rm -rf "${BUILD_DIR}"

echo "Done. Builds are in ${result_dir}"
