# Set the base image to use for subsequent instructions
FROM ghcr.io/ublue-os/arch-distrobox:latest


# Create build user
RUN useradd -m --shell=/bin/bash build && usermod -L build && \
    echo "build ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers && \
    echo "root ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

# Add paru and install packages
USER build
WORKDIR /home/build
# Install custom packages
ADD --chown=build:build pkgbuilds /home/build/pkgbuilds
RUN git clone https://aur.archlinux.org/paru-bin.git --single-branch && \
    cd paru-bin && \
    makepkg -si --noconfirm && \
    cd .. && \
    rm -drf paru-bin && \
    ls -d /home/build/pkgbuilds/* | xargs paru -B --noconfirm --removemake=yes --nokeepsrc --mflags -i

USER root

# Set the working directory inside the container
WORKDIR /usr/src

# Cleanup pkgbuild
RUN userdel -r build && \
    rm -drf /home/build && \
    sed -i '/build ALL=(ALL) NOPASSWD: ALL/d' /etc/sudoers && \
    sed -i '/root ALL=(ALL) NOPASSWD: ALL/d' /etc/sudoers && \
    rm -rf \
        /tmp/* \
        /var/cache/pacman/pkg/*d a user for it

# Copy any source file(s) required for the action
COPY entrypoint.sh .

# Configure the container to be run as an executable
ENTRYPOINT ["/usr/src/entrypoint.sh"]
