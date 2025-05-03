#!/usr/bin/env bash

########################################################################
##
## A script for Wine compilation.
## By default it uses two Ubuntu bootstraps (x32 and x64), which it enters
## with bubblewrap (root rights are not required).
##
## This script requires: git, wget, autoconf, xz, bubblewrap
##
## You can change the environment variables below to your desired values.
##
########################################################################

# Prevent launching as root
if [ $EUID = 0 ] && [ -z "$ALLOW_ROOT" ]; then
    echo "Do not run this script as root!"
    echo "If you really need to run it as root and you know what you are doing,"
    echo "set the ALLOW_ROOT environment variable."
    exit 1
fi

# Wine version to compile.
export WINE_VERSION="${WINE_VERSION:-latest}"

# Available branches: vanilla, staging, staging-tkg, proton, wayland
export WINE_BRANCH="${WINE_BRANCH:-staging}"

# Available proton branches
export PROTON_BRANCH="${PROTON_BRANCH:-proton_8.0}"

# Staging version
export STAGING_VERSION="${STAGING_VERSION:-}"

#######################################################################
# If you're building specifically for Termux glibc, set this to true.
export TERMUX_GLIBC="true"

# If you want to build Wine for proot/chroot, set this to true.
export TERMUX_PROOT="false"

# These two variables cannot be "true" at the same time
#######################################################################

# Specify custom arguments for the Staging's patchinstall.sh script.
export STAGING_ARGS="${STAGING_ARGS:-}"

# Make 64-bit Wine builds with the new WoW64 mode (32-on-64)
export EXPERIMENTAL_WOW64="true"

# Set to true to download and prepare the source code, but do not compile it.
export DO_NOT_COMPILE="false"

# Set to true to use ccache to speed up subsequent compilations.
export USE_CCACHE="${USE_CCACHE:-false}"

export WINE_BUILD_OPTIONS="--disable-winemenubuilder --disable-win16 --enable-win64 --disable-tests --without-capi --without-coreaudio --without-cups --without-gphoto --without-osmesa --without-oss --without-pcap --without-pcsclite --without-sane --without-udev --without-unwind --without-usb --without-v4l2 --without-wayland --without-xinerama"

# A temporary directory where the Wine source code will be stored.
export BUILD_DIR="${HOME}/build_wine"

# Create BUILD_DIR if it doesn't exist
mkdir -p "${BUILD_DIR}" || {
    echo "Failed to create BUILD_DIR: ${BUILD_DIR}"
    exit 1
}

# Implement a new WoW64 specific check
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
        if [ -z "${XDG_CACHE_HOME}" ]; then
            export XDG_CACHE_HOME="${HOME}/.cache"
        fi
        mkdir -p "${XDG_CACHE_HOME}/ccache" "${HOME}/.ccache"
    fi

    build_with_bwrap() {
        BOOTSTRAP_PATH="${BOOTSTRAP_X64}"
        bwrap --ro-bind "${BOOTSTRAP_PATH}" / --dev /dev --ro-bind /sys /sys \
            --proc /proc --tmpfs /tmp --tmpfs /home --tmpfs /run --tmpfs /var \
            --tmpfs /mnt --tmpfs /media --bind "${BUILD_DIR}" "${BUILD_DIR}" \
            --bind-try "${XDG_CACHE_HOME}/ccache" "${XDG_CACHE_HOME}/ccache" \
            --bind-try "${HOME}/.ccache" "${HOME}/.ccache" \
            --setenv PATH "/bin:/sbin:/usr/bin:/usr/sbin" \
            "$@"
    }
else
    export BOOTSTRAP_X64=/opt/chroots/bionic64_chroot
    export BOOTSTRAP_X32=/opt/chroots/bionic32_chroot
    export scriptdir="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
    export CC="gcc-9"
    export CXX="g++-9"
    export CROSSCC_X32="i686-w64-mingw32-gcc"
    export CROSSCXX_X32="i686-w64-mingw32-g++"
    export CROSSCC_X64="x86_64-w64-mingw32-gcc"
    export CROSSCXX_X64="x86_64-w64-mingw32-g++"
    export CFLAGS_X32="-march=i686 -msse2 -mfpmath=sse -O3 -ftree-vectorize -pipe"
    export CFLAGS_X64="-march=x86-64 -msse3 -mfpmath=sse -O3 -ftree-vectorize -pipe"
    export LDFLAGS="-Wl,-O1,--sort-common,--as-needed"
    export CROSSCFLAGS_X32="${CFLAGS_X32}"
    export CROSSCFLAGS_X64="${CFLAGS_X64}"
    export CROSSLDFLAGS="${LDFLAGS}"

    if [ "$USE_CCACHE" = "true" ]; then
        export CC="ccache ${CC}"
        export CXX="ccache ${CXX}"
        export CROSSCC_X32="ccache ${CROSSCC_X32}"
        export CROSSCXX_X32="ccache ${CROSSCXX_X32}"
        export CROSSCC_X64="ccache ${CROSSCC_X64}"
        export CROSSCXX_X64="ccache ${CROSSCXX_X64}"
        if [ -z "${XDG_CACHE_HOME}" ]; then
            export XDG_CACHE_HOME="${HOME}/.cache"
        fi
        mkdir -p "${XDG_CACHE_HOME}/ccache" "${HOME}/.ccache"
    fi

    build_with_bwrap() {
        if [ "${1}" = "32" ]; then
            BOOTSTRAP_PATH="${BOOTSTRAP_X32}"
        else
            BOOTSTRAP_PATH="${BOOTSTRAP_X64}"
        fi
        if [ "${1}" = "32" ] || [ "${1}" = "64" ]; then
            shift
        fi
        bwrap --ro-bind "${BOOTSTRAP_PATH}" / --dev /dev --ro-bind /sys /sys \
            --proc /proc --tmpfs /tmp --tmpfs /home --tmpfs /run --tmpfs /var \
            --tmpfs /mnt --tmpfs /media --bind "${BUILD_DIR}" "${BUILD_DIR}" \
            --bind-try "${XDG_CACHE_HOME}/ccache" "${XDG_CACHE_HOME}/ccache" \
            --bind-try "${HOME}/.ccache" "${HOME}/.ccache" \
            --setenv PATH "/bin:/sbin:/usr/bin:/usr/sbin" \
            "$@"
    }
fi

# Debug: Log current directory
echo "Current directory: $(pwd)"
echo "BUILD_DIR: ${BUILD_DIR}"

# Check if wine source directory exists
if [ ! -d "${BUILD_DIR}/wine" ]; then
    echo "No Wine source code found in ${BUILD_DIR}/wine!"
    echo "Make sure the Wine source is placed in ${BUILD_DIR}/wine."
    exit 1
fi

# Navigate to wine directory
cd "${BUILD_DIR}/wine" || {
    echo "Failed to change to ${BUILD_DIR}/wine"
    exit 1
}

# Debug: Log current directory
echo "Changed to wine directory: $(pwd)"

# Generate necessary files
dlls/winevulkan/make_vulkan
tools/make_requests
tools/make_specfiles
autoreconf -f

# Navigate back to BUILD_DIR
cd "${BUILD_DIR}" || {
    echo "Failed to change to ${BUILD_DIR}"
    exit 1
}

# Debug: Log current directory
echo "Changed to BUILD_DIR: $(pwd)"

if [ "${DO_NOT_COMPILE}" = "true" ]; then
    echo "DO_NOT_COMPILE is set to true"
    echo "Force exiting"
    exit 0
fi

if ! command -v bwrap >/dev/null 2>&1; then
    echo "Bubblewrap is not installed on your system!"
    echo "Please install it and run the script again"
    exit 1
fi

if [ "${EXPERIMENTAL_WOW64}" = "true" ]; then
    if [ ! -d "${BOOTSTRAP_X64}" ]; then
        echo "Bootstrap directory ${BOOTSTRAP_X64} not found!"
        exit 1
    fi
else
    if [ ! -d "${BOOTSTRAP_X64}" ] || [ ! -d "${BOOTSTRAP_X32}" ]; then
        echo "Bootstrap directories ${BOOTSTRAP_X64} and/or ${BOOTSTRAP_X32} not found!"
        exit 1
    fi
fi

if [ "${EXPERIMENTAL_WOW64}" = "true" ]; then
    BWRAP64="build_with_bwrap"
else
    BWRAP64="build_with_bwrap 64"
    BWRAP32="build_with_bwrap 32"
fi

if [ "${EXPERIMENTAL_WOW64}" = "true" ]; then
    export CROSSCC="${CROSSCC_X64}"
    export CROSSCXX="${CROSSCXX_X64}"
    export CFLAGS="${CFLAGS_X64}"
    export CXXFLAGS="${CFLAGS_X64}"
    export CROSSCFLAGS="${CROSSCFLAGS_X64}"
    export CROSSCXXFLAGS="${CROSSCFLAGS_X64}"
    rm -rf "${BUILD_DIR}/build"
    mkdir -p "${BUILD_DIR}/build" || {
        echo "Failed to create ${BUILD_DIR}/build"
        exit 1
    }
    cd "${BUILD_DIR}/build" || {
        echo "Failed to change to ${BUILD_DIR}/build"
        exit 1
    }
    # Debug: Log current directory
    echo "Changed to build directory: $(pwd)"
    ${BWRAP64} "${BUILD_DIR}/wine/configure" --enable-archs=i386,x86_64 ${WINE_BUILD_OPTIONS} --prefix "${BUILD_DIR}/wine-protonGE-amd64"
    ${BWRAP64} make -j8
    ${BWRAP64} make install
fi

echo
echo "Compilation complete"
echo "Creating and compressing archives..."

# Navigate to BUILD_DIR
cd "${BUILD_DIR}" || {
    echo "Failed to change to ${BUILD_DIR}"
    exit 1
}

# Debug: Log current directory
echo "Changed to BUILD_DIR for archiving: $(pwd)"

if touch "${scriptdir}/write_test"; then
    rm -f "${scriptdir}/write_test"
    result_dir="${scriptdir}"
else
    result_dir="${HOME}"
fi

export XZ_OPT="-9"
mkdir -p results
mv wine-protonGE-amd64 results/wine

if [ -d "results/wine" ]; then
    rm -rf results/wine/include results/wine/share/applications results/wine/share/man
    if [ -f wine/wine-tkg-config.txt ]; then
        cp wine/wine-tkg-config.txt results/wine
    fi
    cd results || {
        echo "Failed to change to results directory"
        exit 1
    }
    # Debug: Log current directory
    echo "Changed to results directory: $(pwd)"
    tar -Jcf "wine-action-protonGE.tar.xz" wine
    mv wine-action-protonGE.tar.xz "${result_dir}"
    cd - || exit 1
fi

echo
echo "Done"
echo "The builds should be in ${result_dir}"
