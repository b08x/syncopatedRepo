#!/usr/bin/env bash
#


export CHROOT="/mnt/chroots/arch"

packages="$HOME/Workspace/syncopatedRepo/packages"

pkg=$1

sudo mount --mkdir -t tmpfs -o defaults,size=8G tmpfs $CHROOT

cd ${packages}/${pkg}

ls -lah
