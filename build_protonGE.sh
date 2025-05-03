#!/usr/bin/env bash

########################################################################
##
## A script for Wine compilation.
## By default it uses an Ubuntu bootstrap (x64) with bubblewrap (root rights not required).
##
## This script requires: git, wget, autoconf, xz, bubblewrap, gcc-14, mingw-w64
##
## You can change the environment variables below to your desired values.
##
########################################################################

# Prevent launching as root
if [ $EUID = 0 ] && [ -z "$ALLOW_ROOT" ]; then
    echo "Do not run this script as root!"
    echo "If you really need to run it as root, set ALLOW_ROOT environment variable."
    exit 1
fi

# Wine version to compile
export WINE_VERSION="${WINE_VERSION:-latest}"

# Available branches: vanilla, staging, staging-tkg, proton, wayland
export WINE_BRANCH="${WINE_BRANCH:-staging}"

# Available proton branches
export PROTON_BRANCH="${PROTON_BRANCH:-proton_8.0}"

# Staging version
export STAGING_VERSION="${STAGING_VERSION:-}"

#######################################################################
# If building for Termux glibc, set to true
export TERMUX_GLIBC="${TERMUX_GLIBC:-true}"

# If building for proot/chroot, set to true
export TERMUX_PROOT="${TERMUX_PROOT:-false}"

# These two variables cannot be "true" at the same time
if [ "${TERMUX_GLIBC}" = "true" ] && [ "${TERMUX_PROOT}" = "true" ]; then
    echo "ERROR: TERMUX_GLIBC and TERMUX_PROOT cannot both be true!"
    exit 1
fi
#######################################################################

# Specify custom arguments for Staging's patchinstall.sh
export STAGING_ARGS="${STAGING_ARGS:-}"

# Enable 64-bit Wine builds with WoW64 mode (32-on-64)
export EXPERIMENTAL_WOW64="${EXPERIMENTAL_WOW64:-true}"

# Set to true to download and prepare source code without compiling
export DO_NOT_COMPILE="${DO_NOT_COMPILE:-false}"

# Set to true to use ccache for faster recompilation
export USE_CCACHE="${USE_CCACHE:-false}"

# Wine build options
export WINE_BUILD_OPTIONS="--disable-winemenubuilder --disable-win16 --enable-win64 --disable-tests --without-capi --without-coreaudio --without-cups --without-gphoto --without-osmesa --without-oss --without-pcap --without-pcsclite --without-sane --without-udev --without-unwind --without-usb --without-v4l2 --without-wayland --without-xinerama"

# Temporary directory for Wine source code
export BUILD_DIR="${BUILD_DIR:-${HOME}/build_wine}"

# Create BUILD_DIR
mkdir -p "${BUILD_DIR}" || {
    echo "ERROR: Failed to create BUILD_DIR: ${BUILD_DIR}"
    exit 1
}

# WoW64-specific configuration
if [ "${EXPERIMENTAL_WOW64}" = "true" ]; then
    export BOOTSTRAP_X64="${BOOTSTRAP_X64:-/opt/chroots/noble64_chroot}"
    export scriptdir="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
    export CC="${CC:-gcc-14}"
    export CXX="${CXX:-g++-14}"
    export CROSSCC_X64="${CROSSCC_X64:-x86_64-w64-mingw32-gcc}"
    export CROSSCXX_X64="${CROSSCXX_X64:-x86_64-w64-mingw32-g++}"
    export CFLAGS_X64="-march=x86-64 -msse3 -mfpmath=sse -O3 -ftree-vectorize -pipe"
    export LDFLAGS="-Wl,-O1,--sort-common,--as-needed"
    export CROSSCFLAGS_X64="${CFLAGS_X64}"
    export CROSSLDFLAGS="${LDFLAGS}"

    if [ "${USE_CCACHE}" = "true" ]; then
        export CC="ccache ${CC}"
        export CXX="ccache ${CXX}"
        export CROSSCC_X64="ccache ${CROSSCC_X64}"
        export CROSSCXX_X64="ccache ${CROSSCXX_X64}"
        export XDG_CACHE_HOME="${XDG_CACHE_HOME:-${HOME}/.cache}"
        mkdir -p "${XDG_CACHE_HOME}/ccache" "${HOME}/.ccache" || {
            echo "ERROR: Failed to create ccache directories"
            exit 1
        }
    fi

    build_with_bwrap() {
        local BOOTSTRAP_PATH="${BOOTSTRAP_X64}"
        bwrap --ro-bind "${BOOTSTRAP_PATH}" / --dev /dev --ro-bind /sys /sys \
            --proc /proc --tmpfs /tmp --tmpfs /home --tmpfs /run --tmpfs /var \
            --tmpfs /mnt --tmpfs /media --bind "${BUILD_DIR}" "${BUILD_DIR}" \
            --bind-try "${XDG_CACHE_HOME}/ccache" "${XDG_CACHE_HOME}/ccache" \
            --bind-try "${HOME}/.ccache" "${HOME}/.ccache" \
            --setenv PATH "/bin:/sbin:/usr/bin:/usr/sbin" \
            "$@" || {
            echo "ERROR: bwrap command failed: $@"
            exit 1
        }
    }
else
    echo "ERROR: Non-WoW64 mode is not supported in this configuration!"
    exit 1
fi

# Debug: Log environment
echo "Current directory: $(pwd)"
echo "BUILD_DIR: ${BUILD_DIR}"
echo "Wine source directory: ${BUILD_DIR}/wine"
echo "Bootstrap directory: ${BOOTSTRAP_X64}"
echo "Compiler: ${CC}, ${CXX}, ${CROSSCC_X64}, ${CROSSCXX_X64}"

# Check if wine source directory exists
if [ ! -d "${BUILD_DIR}/wine" ]; then
    echo "ERROR: No Wine source code found in ${BUILD_DIR}/wine!"
    echo "Ensure the Wine/Proton source is placed in ${BUILD_DIR}/wine."
    exit 1
fi

# Navigate to wine directory
cd "${BUILD_DIR}/wine" || {
    echo "ERROR: Failed to change to ${BUILD_DIR}/wine"
    exit 1
}
echo "Changed to wine directory: $(pwd)"

# Check for critical files
echo "Checking for critical source files..."
for file in configure.ac dlls/winevulkan/make_vulkan tools/make_requests tools/make_specfiles; do
    if [ ! -f "${file}" ]; then
        echo "WARNING: ${file} not found, skipping related step"
    fi
done

# Generate necessary files (skip if missing)
[ -f "dlls/winevulkan/make_vulkan" ] && {
    dlls/winevulkan/make_vulkan || echo "WARNING: Failed to run make_vulkan"
}
[ -f "tools/make_requests" ] && {
    tools/make_requests || echo "WARNING: Failed to run make_requests"
}
[ -f "tools/make_specfiles" ] && {
    tools/make_specfiles || echo "WARNING: Failed to run make_specfiles"
}
[ -f "configure.ac" ] && {
    autoreconf -f || {
        echo "ERROR: autoreconf failed"
        exit 1
    }
} || {
    echo "ERROR: configure.ac not found, cannot proceed"
    exit 1
}

# Check for configure script
if [ ! -f "configure" ]; then
    echo "ERROR: configure script not found after autoreconf!"
    exit 1
}

# Navigate back to BUILD_DIR
cd "${BUILD_DIR}" || {
    echo "ERROR: Failed to change to ${BUILD_DIR}"
    exit 1
}
echo "Changed to BUILD_DIR: $(pwd)"

# Exit if DO_NOT_COMPILE is true
if [ "${DO_NOT_COMPILE}" = "true" ]; then
    echo "DO_NOT_COMPILE is set to true, exiting"
    exit 0
fi

# Check for bubblewrap
if ! command -v bwrap >/dev/null 2>&1; then
    echo "ERROR: Bubblewrap is not installed!"
    echo "Install it with: sudo apt install bubblewrap"
    exit 1
fi

# Check bootstrap directory
if [ ! -d "${BOOTSTRAP_X64}" ]; then
    echo "ERROR: Bootstrap directory ${BOOTSTRAP_X64} not found!"
    exit 1
fi

# Configure and compile
if [ "${EXPERIMENTAL_WOW64}" = "true" ]; then
    export CROSSCC="${CROSSCC_X64}"
    export CROSSCXX="${CROSSCXX_X64}"
    export CFLAGS="${CFLAGS_X64}"
    export CXXFLAGS="${CFLAGS_X64}"
    export CROSSCFLAGS="${CROSSCFLAGS_X64}"
    export CROSSCXXFLAGS="${CROSSCFLAGS_X64}"
    rm -rf "${BUILD_DIR}/build"
    mkdir -p "${BUILD_DIR}/build" || {
        echo "ERROR: Failed to create ${BUILD_DIR}/build"
        exit 1
    }
    cd "${BUILD_DIR}/build" || {
        echo "ERROR: Failed to change to ${BUILD_DIR}/build"
        exit 1
    }
    echo "Changed to build directory: $(pwd)"
    build_with_bwrap "${BUILD_DIR}/wine/configure" --enable-archs=i386,x86_64 ${WINE_BUILD_OPTIONS} --prefix "${BUILD_DIR}/wine-protonGE-amd64"
    build_with_bwrap make -j8
    build_with_bwrap make install
fi

echo
echo "Compilation complete"
echo "Creating and compressing archives..."

# Navigate to BUILD_DIR
cd "${BUILD_DIR}" || {
    echo "ERROR: Failed to change to ${BUILD_DIR}"
    exit 1
}
echo "Changed to BUILD_DIR for archiving: $(pwd)"

# Check write permissions
if touch "${scriptdir}/write_test"; then
    rm -f "${scriptdir}/write_test"
    result_dir="${scriptdir}"
else
    result_dir="${HOME}"
fi

# Create archive
export XZ_OPT="-9"
mkdir -p results || {
    echo "ERROR: Failed to create results directory"
    exit 1
}
if [ -d "wine-protonGE-amd64" ]; then
    mv wine-protonGE-amd64 results/wine
    if [ -d "results/wine" ]; then
        rm -rf results/wine/include results/wine/share/applications results/wine/share/man
        if [ -f "wine/wine-tkg-config.txt" ]; then
            cp wine/wine-tkg-config.txt results/wine
        fi
        cd results || {
            echo "ERROR: Failed to change to results directory"
            exit 1
        }
        echo "Changed to results directory: $(pwd)"
        tar -Jcf "wine-action-protonGE.tar.xz" wine
        mv wine-action-protonGE.tar.xz "${result_dir}"
        cd - || exit 1
    else
        echo "ERROR: Failed to move wine-protonGE-amd64 to results/wine"
        exit 1
    fi
else
    echo "ERROR: wine-protonGE-amd64 directory not found!"
    exit 1
fi

echo
echo "Done"
echo "The build output is in ${result_dir}/wine-action-protonGE.tar.xz"
