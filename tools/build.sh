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

say() {
	local statement=$1
	local color=$2

	echo -e "${color}${statement}${ALL_OFF}"
}

#########################################################################
#                             set locations                             #
#########################################################################
declare -rx SOUDNDBOT="/mnt/soundbot"
declare -rx BUILDS="/srv/builds"

declare -rx WORKSPACE="${SOUDNDBOT}/Workspace/syncopatedRepo"
declare -rx PKGBUILDS="${WORKSPACE}/pkgbuilds"

declare -rx REPOSITORY_LOCAL="$BUILDS/repository"
declare -rx REPOCTL_CONFIG="${WORKSPACE}/repoctl/config.toml"

declare -rx MIRRORS=("bender.syncopated.net" "ec2-user@syncopated.hopto.org")

declare -rx SRCDEST=$BUILDS/packages/sources

declare -rx CHROOT="/mnt/chroots/arch"

declare -rx PACKAGER="Robert Pannick <rwpannick@gmail.com>"
declare -rx GPGKEY="DF7A6571781ACB52FA9CF8C1EB4DFE46828DFEDD"
#########################################################################
#                             set functions                             #
#########################################################################
unmount_chroot() {
	if mountpoint -q $CHROOT; then sudo umount $CHROOT; fi
}

mount_chroot() {
	unmount_chroot
	sudo mount --mkdir -t tmpfs -o defaults,size=8G tmpfs $CHROOT
}

set_configs() {
	sudo chown -R $USER:$USER /usr/share/devtools
	rsync -a --delete $WORKSPACE/makepkg.conf.d/ /usr/share/devtools/makepkg.conf.d/
	rsync -a $WORKSPACE/pacman.conf.d/ /usr/share/devtools/pacman.conf.d/
	cp -f $REPOCTL_CONFIG $HOME/.config/repoctl/config.toml
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
elif [[ "${1}" == '-p' ]]; then
	package_selection=$2
else
	package_selection=$(fd . -t d --max-depth=1 $PKGBUILDS -x echo -e {/} | gum filter --no-limit)
fi

say "${package_selection}" $BLUE

#########################################################################
trap cleanup SIGINT SIGTERM ERR EXIT

if [[ ${3} == 'debug' ]]; then
	declare -rx DEBUG="True"
	say "Debug...\n" $RED
fi

#phrase=$(gum input --password)

phrase=$(cat /tmp/pkgbuilding)

mkdir -pv $SRCDEST
mkdir -pv $BUILDS/{packages,repository}

for pkgname in ${package_selection[@]}; do

	mount_chroot

	cd "${PKGBUILDS}/${pkgname}"

	updpkgsums && makepkg --printsrcinfo >.SRCINFO

	srcinfo=$(grep -E '^\s*arch\s*=' .SRCINFO | choose 2 | grep -E 'x86_64|v3|any' | xargs)

	# Check if the arch is "any" and assign the array accordingly
	if [ "$srcinfo" = "any" ]; then
		architectures=("x86_64" "x86_64_v3")
	else
		architectures=("$srcinfo")
	fi

	for arch in ${architectures[@]}; do

		gum style \
			--foreground 014 --border-foreground 024 --border double \
			--align center --width 50 --margin "1 2" --padding "2 4" \
			"Building ${pkgname}-${arch}" && sleep 1 && clear

		declare -x PKGDEST=$BUILDS/packages/$arch
		declare -x SRCPKGDEST=$BUILDS/packages/srcpackages/$arch
		declare -x LOGDEST=$BUILDS/packages/makepkglogs/$arch

		mkdir -p $PKGDEST
		mkdir -p $SRCPKGDEST
		mkdir -p $LOGDEST

		extra-${arch}-build -c -r $CHROOT -- -c -n -u

		cd $PKGDEST

		for pkg in *.zst; do
			echo "${phrase}" | gpg2 -v --batch --yes --detach-sign --pinentry-mode loopback --passphrase --passphrase-fd 0 --out $pkg.sig --sign $pkg
			repoctl add -P $arch -m -r ./$pkg
		done

		cd $BUILDS/repository/$arch

		if [[ $arch == 'x86_64' ]]; then
			declare -x repo_db="syncopated.db.tar.zst"
		elif [[ $arch == 'x86_64_v3' ]]; then
			declare -x repo_db="syncopated-v3.db.tar.zst"
		fi

		repo-add -n -k $GPGKEY $repo_db *.pkg.tar.zst -s

		cd "${PKGBUILDS}/${pkgname}"
	done

done

for mirror in ${MIRRORS[@]}; do
	echo -e "syncing local repository to remote ${mirror}\n"
	rsync -avP --delete "${BUILDS}/repository/" "${mirror}:/usr/share/nginx/html/syncopated/repo/" || continue
done

gum style \
	--foreground 014 --border-foreground 024 --border double \
	--align center --width 50 --margin "1 2" --padding "2 4" \
	'Enf of Program.' && sleep 1 && clear
