#!/usr/bin/env bash

## A script for creating WoW64-specific Ubuntu bootstrap.
## This bootstrap will not be able to build 32-bit part of Wine.
## debootstrap and perl are required
## root rights are required
##
## About 5.5 GB of free space is required
## And additional 2.5 GB is required for Wine compilation

if [ "$EUID" != 0 ]; then
    echo "This script requires root rights!"
    exit 1
fi

if ! command -v debootstrap 1>/dev/null || ! command -v perl 1>/dev/null; then
    echo "Please install debootstrap and perl and run the script again"
    exit 1
fi

# Check disk space
required_space=8000000  # 8 GB in KB
available_space=$(df -k /opt | tail -1 | awk '{print $4}')
if [ "$available_space" -lt "$required_space" ]; then
    echo "Insufficient disk space in /opt. Required: 8 GB, Available: $((available_space / 1024)) MB"
    exit 1
fi

export CHROOT_DISTRO="noble"
export CHROOT_MIRROR="https://ftp.uni-stuttgart.de/ubuntu/"
export MAINDIR=/opt/chroots
export CHROOT_X64="${MAINDIR}/${CHROOT_DISTRO}64_chroot"

prepare_chroot() {
    CHROOT_PATH="${CHROOT_X64}"
    echo "Unmount chroot directories. Just in case."
    cleanup_chroot
    echo "Mount directories for chroot"
    mount --bind "${CHROOT_PATH}" "${CHROOT_PATH}" || exit 1
    mount -t proc /proc "${CHROOT_PATH}/proc" || exit 1
    mount --bind /sys "${CHROOT_PATH}/sys" || exit 1
    mount --make-rslave "${CHROOT_PATH}/sys" || exit 1
    mount --bind /dev "${CHROOT_PATH}/dev" || exit 1
    mount --bind /dev/pts "${CHROOT_PATH}/dev/pts" || exit 1
    mount --bind /dev/shm "${CHROOT_PATH}/dev/shm" || exit 1
    mount --make-rslave "${CHROOT_PATH}/dev" || exit 1
    echo "nameserver 8.8.8.8" > "${CHROOT_PATH}/etc/resolv.conf"
    echo "Chrooting into ${CHROOT_PATH}"
    chroot "${CHROOT_PATH}" /usr/bin/env LANG=en_US.UTF-8 TERM=xterm PATH="/bin:/sbin:/usr/bin:/usr/sbin" /opt/prepare_chroot.sh
    cleanup_chroot
}

cleanup_chroot() {
    echo "Cleaning up chroot mounts"
    for mountpoint in "${CHROOT_PATH}/dev/pts" "${CHROOT_PATH}/dev/shm" "${CHROOT_PATH}/dev" "${CHROOT_PATH}/sys" "${CHROOT_PATH}/proc" "${CHROOT_PATH}"; do
        for i in {1..3}; do
            umount "$mountpoint" 2>/dev/null && break
            sleep 1
        done
    done
}

create_build_scripts() {
    sdl2_version=${SDL2_VERSION:-"2.30.2"}
    faudio_version=${FAUDIO_VERSION:-"24.05"}
    vulkan_headers_version=${VULKAN_HEADERS_VERSION:-"1.3.285"}
    vulkan_loader_version=${VULKAN_LOADER_VERSION:-"1.3.285"}
    spirv_headers_version=${SPIRV_HEADERS_VERSION:-"sdk-1.3.283.0"}
    libpcap_version=${LIBPCAP_VERSION:-"1.10.4"}
    libxkbcommon_version=${LIBXKBCOMMON_VERSION:-"1.7.0"}
    ffmpeg_version=${FFMPEG_VERSION:-"5.1.4"}

    cat <<EOF > "${MAINDIR}/prepare_chroot.sh"
#!/bin/bash
set -e
apt-get update
apt-get -y install nano locales
echo ru_RU.UTF-8 UTF-8 >> /etc/locale.gen
echo en_US.UTF-8 UTF-8 >> /etc/locale.gen
locale-gen
echo deb '${CHROOT_MIRROR}' ${CHROOT_DISTRO} main universe > /etc/apt/sources.list
echo deb '${CHROOT_MIRROR}' ${CHROOT_DISTRO}-updates main universe >> /etc/apt/sources.list
echo deb '${CHROOT_MIRROR}' ${CHROOT_DISTRO}-security main universe >> /etc/apt/sources.list
echo deb-src '${CHROOT_MIRROR}' ${CHROOT_DISTRO} main universe >> /etc/apt/sources.list
echo deb-src '${CHROOT_MIRROR}' ${CHROOT_DISTRO}-updates main universe >> /etc/apt/sources.list
echo deb-src '${CHROOT_MIRROR}' ${CHROOT_DISTRO}-security main universe >> /etc/apt/sources.list
apt-get update
apt-get -y upgrade
apt-get -y dist-upgrade
apt-get -y install software-properties-common
apt-get update
apt-get -y build-dep wine-development libsdl2 libvulkan1
apt-get -y install cmake flex bison ccache gcc-14 g++-14 wget git gcc-mingw-w64 g++-mingw-w64
apt-get -y install libxpresent-dev libjxr-dev libusb-1.0-0-dev libgcrypt20-dev libpulse-dev libudev-dev libsane-dev libv4l-dev libkrb5-dev libgphoto2-dev liblcms2-dev libcapi20-dev
apt-get -y install libjpeg62-dev samba-dev libfreetype-dev libunwind-dev ocl-icd-opencl-dev libgnutls28-dev libx11-dev libxcomposite-dev libxcursor-dev libxfixes-dev libxi-dev libxrandr-dev
apt-get -y install libxrender-dev libxext-dev libpcsclite-dev libcups2-dev libosmesa6-dev libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev
apt-get -y install python3-pip libxcb-xkb-dev libfontconfig-dev libgl-dev
apt-get -y install meson ninja-build libxml2 libxml2-dev libxkbcommon-dev libxkbcommon0 xkb-data libxxf86vm-dev libdbus-1-dev
apt-get -y purge libvulkan-dev libvulkan1 libsdl2-dev libsdl2-2.0-0 libpcap0.8-dev libpcap0.8 --purge --autoremove
apt-get -y clean
apt-get -y autoclean
export PATH="/usr/local/bin:\${PATH}"
mkdir /opt/build_libs
cd /opt/build_libs
wget -O sdl.tar.gz https://www.libsdl.org/release/SDL2-${sdl2_version}.tar.gz
wget -O faudio.tar.gz https://github.com/FNA-XNA/FAudio/archive/${faudio_version}.tar.gz
wget -O vulkan-loader.tar.gz https://github.com/KhronosGroup/Vulkan-Loader/archive/v${vulkan_loader_version}.tar.gz
wget -O vulkan-headers.tar.gz https://github.com/KhronosGroup/Vulkan-Headers/archive/v${vulkan_headers_version}.tar.gz
wget -O spirv-headers.tar.gz https://github.com/KhronosGroup/SPIRV-Headers/archive/refs/tags/vulkan-sdk-1.3.283.0.tar.gz
wget -O libpcap.tar.gz https://www.tcpdump.org/release/libpcap-${libpcap_version}.tar.gz
wget -O libxkbcommon.tar.xz https://xkbcommon.org/download/libxkbcommon-${libxkbcommon_version}.tar.xz
wget -O ffmpeg.tar.bz2 https://ffmpeg.org/releases/ffmpeg-${ffmpeg_version}.tar.bz2
if [ -d /usr/lib/x86_64-linux-gnu ]; then wget -O wine.deb https://dl.winehq.org/wine-builds/ubuntu/dists/noble/main/binary-amd64/wine-stable_9.0.0.0~noble-1_amd64.deb; fi
wget -O vkd3d.tar.xz https://dl.winehq.org/vkd3d/source/vkd3d-1.11.tar.xz
tar xf vkd3d.tar.xz
mv vkd3d-1.11 vkd3d
tar xf sdl.tar.gz
tar xf faudio.tar.gz
tar xf vulkan-loader.tar.gz
tar xf vulkan-headers.tar.gz
tar xf spirv-headers.tar.gz
tar xf libpcap.tar.gz
tar xf libxkbcommon.tar.xz
tar xf ffmpeg.tar.bz2
export CFLAGS="-O2"
export CXXFLAGS="-O2"
mkdir build && cd build
cmake ../SDL2-${sdl2_version} && make -j$(nproc) && make install
cd ../ && rm -r build && mkdir build && cd build
cmake ../FAudio-${faudio_version} && make -j$(nproc) && make install
cd ../ && rm -r build && mkdir build && cd build
cmake ../Vulkan-Headers-${vulkan_headers_version} && make -j$(nproc) && make install
cd ../ && rm -r build && mkdir build && cd build
cmake ../Vulkan-Loader-${vulkan_loader_version} && make -j$(nproc) && make install
cd ../ && rm -r build && mkdir build && cd build
cmake ../SPIRV-Headers-vulkan-sdk-1.3.283.0 && make -j$(nproc) && make install
cd ../ && rm -r build && mkdir build && cd build
../libpcap-${libpcap_version}/configure && make -j$(nproc) && make install
cd ../ && rm -r build && mkdir build && cd build
cd ../libxkbcommon-${libxkbcommon_version}
meson setup build -Denable-docs=false
meson compile -C build
meson install -C build
cd ../ && rm -r build && mkdir build && cd build
cd ../ffmpeg-${ffmpeg_version}
./configure --prefix=/usr --enable-shared --disable-static && make -j$(nproc) && make install
cd ../ && dpkg -x wine.deb .
cp opt/wine-stable/bin/widl /usr/bin
cd vkd3d
../vkd3d/configure && make -j$(nproc) && make install
cd /opt && rm -r /opt/build_libs
EOF

    chmod +x "${MAINDIR}/prepare_chroot.sh"
    mv "${MAINDIR}/prepare_chroot.sh" "${CHROOT_X64}/opt"
}

mkdir -p "${MAINDIR}"
debootstrap --arch amd64 "$CHROOT_DISTRO" "${CHROOT_X64}" "$CHROOT_MIRROR" || exit 1
create_build_scripts
prepare_chroot
rm "${CHROOT_X64}/opt/prepare_chroot.sh"
clear
echo "Done"
