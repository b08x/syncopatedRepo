#!/usr/bin/env bash
set -e

declare -rx timestampe=$(date +%Y%m%d%H%M)

#########################################################################
#                             set colors                                 #
#########################################################################

declare -rx ALL_OFF="\e[1;0m"
declare -rx BBOLD="\e[1;1m"
declare -rx BLUE="${BBOLD}\e[1;34m"
declare -rx GREEN="${BBOLD}\e[1;32m"
declare -rx RED="${BBOLD}\e[1;31m"
declare -rx YELLOW="${BBOLD}\e[1;33m"

say () {
  local statement=$1
  local color=$2

  echo -e "${color}${statement}${ALL_OFF}"
}

#########################################################################
#                             set locations                             #
#########################################################################
declare -rx WORKSPACE="${HOME}/Workspace/syncopatedRepo"
declare -rx PKGBUILDS="${WORKSPACE}/pkgbuilds"
declare -rx SRCDEST="${WORKSPACE}/builds/packages/sources"
declare -rx REPOSITORY_LOCAL="${WORKSPACE}/builds/repository"
#########################################################################
#                             set functions                             #
#########################################################################

declare -rx CHROOT="/mnt/chroots/arch"

unmount_chroot() {
  if mountpoint -q $CHROOT; then sudo umount $CHROOT; fi
}

mount_chroot() {
  unmount_chroot
  sudo mount --mkdir -t tmpfs -o defaults,size=8G tmpfs $CHROOT
}

set_configs () {
  sudo chown -R $USER:$USER /usr/share/devtools
  rsync -avP --delete $WORKSPACE/makepkg.conf.d/ /usr/share/devtools/makepkg.conf.d/
  rsync -avP $WORKSPACE/pacman.conf.d/ /usr/share/devtools/pacman.conf.d/
}

cleanup() {
  echo "all set!"
  # if [[ ! $DEBUG ]]; then
  #   unmount_chroot
  #   # rm -rf $SRCDEST && mkdir -p $SRCDEST
  # fi
}

cd $WORKSPACE && git fetch && git pull

set_configs
unmount_chroot

#########################################################################
#                             Greetings                                 #
#########################################################################

declare -rx GPG="DF7A6571781ACB52FA9CF8C1EB4DFE46828DFEDD"
declare -rx MIRRORS=("bender.syncopated.net" "ec2-user@syncopated.hopto.org")

gum style \
  --foreground 014 --border-foreground 024 --border double \
  --align center --width 50 --margin "1 2" --padding "2 4" \
  'Hello.' && sleep 1 && clear

#########################################################################

cd $PKGBUILDS

say "select packages to build" $GREEN
say "-------------------------" $GREEN

if [[ "${1}" == 'all' ]]; then
  package_selection=$(fd . -t d --max-depth=1 $PKGBUILDS -x echo -e {/})
elif [[ "${1}" == 'package' ]]; then
  package_selection=$2
else
  package_selection=$(fd . -t d --max-depth=1 $PKGBUILDS -x echo -e {/} | gum filter --no-limit )
fi

say "${package_selection}" $BLUE

#########################################################################

say "Select cpu architecture" $GREEN
say "------------------------" $GREEN

architectures=$(gum choose --no-limit all "x86_64" "x86_64_v3")

if [[ $architectures == 'all' ]]; then
  architectures=("x86_64" "x86_64_v3")
fi

#########################################################################
trap cleanup SIGINT SIGTERM ERR EXIT

if [[ ${3} == 'debug' ]]; then
  declare -rx DEBUG="True"
  say "Debug...\n" $RED
fi

phrase=$(gum input --password)

for arch in ${architectures[@]}; do

  if [[ $arch == 'x86_64' ]]; then
    declare -x repo_db="syncopated.db.tar.zst"
  elif [[ $arch == 'x86_64_v3' ]]; then
    declare -x repo_db="syncopated-v3.db.tar.zst"
  fi

  mkdir -pv $SRCDEST

  export PKGDEST=$WORKSPACE/builds/packages/$arch
  export SRCPKGDEST=$WORKSPACE/builds/packages/srcpackages/$arch
  export LOGDEST=$WORKSPACE/builds/packages/makepkglogs/$arch

  for pkgname in ${package_selection[@]}; do

    mount_chroot

    cd "${PKGBUILDS}/${pkgname}"

    updpkgsums && makepkg --printsrcinfo > .SRCINFO

    extra-${arch}-build -c -r $CHROOT -- -c -n -u

    cd $WORKSPACE/builds/packages/$arch

    for pkg in *.zst; do
      echo "${phrase}" | gpg2 -v --batch --yes --detach-sign --pinentry-mode loopback --passphrase --passphrase-fd 0 --out $pkg.sig --sign $pkg
      repoctl add -P $arch -m -r ./$pkg
    done

    cd $WORKSPACE/builds/repository/$arch

    repo-add -n -k $GPG $repo_db *.pkg.tar.zst -s
  done

done

for mirror in ${MIRRORS[@]}; do
  echo -e "syncing local repository to remote ${mirror}\n"
  rsync -avP --delete  "${WORKSPACE}/builds/repository/${arch}/" "${mirror}:/usr/share/nginx/html/syncopated/repo/${arch}/" || continue
done

#gum confirm "deploy package(s) to repository?" && . deploy.sh

# end of program
