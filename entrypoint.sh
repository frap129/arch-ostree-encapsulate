#!/bin/sh -l

declare IMAGE=${IMAGE:="ghcr.io/frap129/trellis:latest"}
declare OSTREE_SYS_ROOT=${OSTREE_SYS_ROOT:="/tmp/chroot"}
declare OSTREE_SYS_TREE=${OSTREE_SYS_TREE:='/tmp/rootfs'}
declare SYSTEM_BASE_NAME=${SYSTEM_BASE_NAME:="ostree-system"}
declare OUTPUT_TAR=${OUTPUT_TAR:="encapsulated.tar"}

ostree admin init-fs --sysroot="${OSTREE_SYS_ROOT}" --modern ${OSTREE_SYS_ROOT}
ostree admin stateroot-init --sysroot="${OSTREE_SYS_ROOT}" ${SYSTEM_BASE_NAME}
ostree init --repo="${OSTREE_SYS_ROOT}/ostree/repo" --mode='bare'
ostree config --repo="${OSTREE_SYS_ROOT}/ostree/repo" set sysroot.bootprefix 'true'

# Add support for overlay storage driver in LiveCD
if [[ $(df --output=fstype / | tail -n 1) = 'overlay' ]]; then
    ENV_CREATE_DEPS fuse-overlayfs
    local TMPDIR='/tmp/podman'
    local PODMAN_OPT_GLOBAL=(
        --root="${TMPDIR}/storage"
        --tmpdir="${TMPDIR}/tmp"
    )
fi

# Ostreeify: retrieve rootfs (workaround: `podman build --output local` doesn't preserve ownership)
rm -rf ${OSTREE_SYS_TREE}
mkdir -p ${OSTREE_SYS_TREE}
podman pull ${IMAGE}
podman ${PODMAN_OPT_GLOBAL[@]} export ${IMAGE} | tar -xC ${OSTREE_SYS_TREE}

# Doing it here allows the container to be runnable/debuggable and Containerfile reusable
mv ${OSTREE_SYS_TREE}/etc ${OSTREE_SYS_TREE}/usr/

rm -r ${OSTREE_SYS_TREE}/home
ln -s var/home ${OSTREE_SYS_TREE}/home

rm -r ${OSTREE_SYS_TREE}/mnt
ln -s var/mnt ${OSTREE_SYS_TREE}/mnt

rm -r ${OSTREE_SYS_TREE}/opt
ln -s var/opt ${OSTREE_SYS_TREE}/opt

rm -r ${OSTREE_SYS_TREE}/root
ln -s var/roothome ${OSTREE_SYS_TREE}/root

rm -r ${OSTREE_SYS_TREE}/srv
ln -s var/srv ${OSTREE_SYS_TREE}/srv

mkdir ${OSTREE_SYS_TREE}/sysroot
ln -s sysroot/ostree ${OSTREE_SYS_TREE}/ostree

rm -r ${OSTREE_SYS_TREE}/usr/local
ln -s ../var/usrlocal ${OSTREE_SYS_TREE}/usr/local

printf >&1 '%s\n' 'Creating tmpfiles'
echo 'd /var/home 0755 root root -' >> ${OSTREE_SYS_TREE}/usr/lib/tmpfiles.d/ostree-0-integration.conf
echo 'd /var/lib 0755 root root -' >> ${OSTREE_SYS_TREE}/usr/lib/tmpfiles.d/ostree-0-integration.conf
echo 'd /var/log/journal 0755 root root -' >> ${OSTREE_SYS_TREE}/usr/lib/tmpfiles.d/ostree-0-integration.conf
echo 'd /var/mnt 0755 root root -' >> ${OSTREE_SYS_TREE}/usr/lib/tmpfiles.d/ostree-0-integration.conf
echo 'd /var/opt 0755 root root -' >> ${OSTREE_SYS_TREE}/usr/lib/tmpfiles.d/ostree-0-integration.conf
echo 'd /var/roothome 0700 root root -' >> ${OSTREE_SYS_TREE}/usr/lib/tmpfiles.d/ostree-0-integration.conf
echo 'd /var/srv 0755 root root -' >> ${OSTREE_SYS_TREE}/usr/lib/tmpfiles.d/ostree-0-integration.conf
echo 'd /var/usrlocal 0755 root root -' >> ${OSTREE_SYS_TREE}/usr/lib/tmpfiles.d/ostree-0-integration.conf
echo 'd /var/usrlocal/bin 0755 root root -' >> ${OSTREE_SYS_TREE}/usr/lib/tmpfiles.d/ostree-0-integration.conf
echo 'd /var/usrlocal/etc 0755 root root -' >> ${OSTREE_SYS_TREE}/usr/lib/tmpfiles.d/ostree-0-integration.conf
echo 'd /var/usrlocal/games 0755 root root -' >> ${OSTREE_SYS_TREE}/usr/lib/tmpfiles.d/ostree-0-integration.conf
echo 'd /var/usrlocal/include 0755 root root -' >> ${OSTREE_SYS_TREE}/usr/lib/tmpfiles.d/ostree-0-integration.conf
echo 'd /var/usrlocal/lib 0755 root root -' >> ${OSTREE_SYS_TREE}/usr/lib/tmpfiles.d/ostree-0-integration.conf
echo 'd /var/usrlocal/man 0755 root root -' >> ${OSTREE_SYS_TREE}/usr/lib/tmpfiles.d/ostree-0-integration.conf
echo 'd /var/usrlocal/sbin 0755 root root -' >> ${OSTREE_SYS_TREE}/usr/lib/tmpfiles.d/ostree-0-integration.conf
echo 'd /var/usrlocal/share 0755 root root -' >> ${OSTREE_SYS_TREE}/usr/lib/tmpfiles.d/ostree-0-integration.conf
echo 'd /var/usrlocal/src 0755 root root -' >> ${OSTREE_SYS_TREE}/usr/lib/tmpfiles.d/ostree-0-integration.conf
echo 'd /run/media 0755 root root -' >> ${OSTREE_SYS_TREE}/usr/lib/tmpfiles.d/ostree-0-integration.conf

# Only retain information about Pacman packages in new rootfs
mv ${OSTREE_SYS_TREE}/var/lib/pacman ${OSTREE_SYS_TREE}/usr/lib/
sed -i \
    -e 's|^#\(DBPath\s*=\s*\).*|\1/usr/lib/pacman|g' \
    -e 's|^#\(IgnoreGroup\s*=\s*\).*|\1modified|g' \
    ${OSTREE_SYS_TREE}/usr/etc/pacman.conf

# Allow Pacman to store update notice id during unlock mode
mkdir ${OSTREE_SYS_TREE}/usr/lib/pacmanlocal

# OSTree mounts /ostree/deploy/${SYSTEM_BASE_NAME}/var to /var
rm -r ${OSTREE_SYS_TREE}/var/*

# Update repository and boot entries in GRUB2
ostree commit --repo="${OSTREE_SYS_ROOT}/ostree/repo" --branch="${SYSTEM_BASE_NAME}/latest" --tree=dir="${OSTREE_SYS_TREE}"
ostree admin deploy --sysroot="${OSTREE_SYS_ROOT}" --os="${SYSTEM_BASE_NAME}" --retain ${SYSTEM_BASE_NAME}/latest

# [BOOTLOADER]: FIRST BOOT
# | Todo: improve grub-mkconfig
grub-install --target='x86_64-efi' --efi-directory="${OSTREE_SYS_ROOT}/boot/efi" --boot-directory="${OSTREE_SYS_ROOT}/boot/efi/EFI" --bootloader-id="${SYSTEM_BASE_NAME}"

local OSTREE_SYS_PATH=$(ls -d ${OSTREE_SYS_ROOT}/ostree/deploy/${SYSTEM_BASE_NAME}/deploy/* | head -n 1)

rm -rfv ${OSTREE_SYS_PATH}/boot/*
mount --mkdir --rbind ${OSTREE_SYS_ROOT}/boot ${OSTREE_SYS_PATH}/boot
mount --mkdir --rbind ${OSTREE_SYS_ROOT}/ostree ${OSTREE_SYS_PATH}/sysroot/ostree

for i in /dev /proc /sys; do mount -o bind $i ${OSTREE_SYS_PATH}${i}; done
chroot ${OSTREE_SYS_PATH} /bin/bash -c 'grub-mkconfig -o /boot/efi/EFI/grub/grub.cfg'

umount --recursive ${OSTREE_SYS_ROOT}

ostree-ext-cli tar export --repo=${OSTREE_SYS_ROOT}/ostree/repo 0

mv *.tar ${OUTPUT_TAR}

# Write outputs to the $GITHUB_OUTPUT file
echo "output-path=$(ls -d $PWD/${OUTPUT_TAR})" >> "$GITHUB_OUTPUT"

exit 0
