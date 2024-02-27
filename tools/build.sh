#!/usr/bin/env bash
set -e

##########################################################################
#                                                                        #
#                   ___  _     _ _   _      _                           #
#                  / _ \| |__ (_) |_| |__  (_) ___                      #
#                 | | | | '_ \| | __| '_ \ | |/ _ \                     #
#                 | |_| | |_) | | |_| | | || |  __/                     #
#                  \___/|_.__// |\__|_| |_|/ |\___|                     #
#                          |__/          |__/                           #
#                                                                        #
#   This script automates the process of building packages for the      #
#   Arch Linux distribution. It handles updating package                #
#   checksums, generating the .SRCINFO file, building packages for      #
#   multiple architectures, and syncing the local repository with       #
#   remote hosts.                                                       #
#                                                                        #
##########################################################################

# Set colors
declare -rx ALL_OFF="\e[1;0m"
declare -rx BBOLD="\e[1;1m"
declare -rx BLUE="${BBOLD}\e[1;34m"
declare -rx GREEN="${BBOLD}\e[1;32m"
declare -rx RED="${BBOLD}\e[1;31m"
declare -rx YELLOW="${BBOLD}\e[1;33m"

# Function to print styled text
say() {
	local statement=$1
	local color=$2

	echo -e "${color}${statement}${ALL_OFF}"
}

##########################################################################
#                                                                        #
#   Declare variables for directories and settings used in the script.   #
#                                                                        #
##########################################################################

# Define the workspace and package build directories
declare -rx WORKSPACE="/mnt/soundbot/Workspace/syncopatedRepo"
declare -rx PKGBUILDS="${WORKSPACE}/pkgbuilds"
declare -rx REPOCTL_CONFIG="${WORKSPACE}/repoctl/config.toml"

declare -rx BUILDS="/srv/builds"
declare -rx REPOSITORY_LOCAL="$BUILDS/repository"
declare -rx SRCDEST="${BUILDS}/packages/sources"
declare -rx CHROOT="/mnt/chroots/arch"

# Other settings
declare -rx PACKAGER="Robert Pannick <rwpannick@gmail.com>"
declare -rx GPGKEY="DF7A6571781ACB52FA9CF8C1EB4DFE46828DFEDD"

# Mirror locations
declare -rx MIRRORS=("bender.syncopated.net" "ec2-user@syncopated.hopto.org")

# Debug mode
if [[ ${1} == 'debug' ]]; then
	declare -rx DEBUG="True"
	say "Debug mode enabled." $RED
fi

##########################################################################
#                                                                        #
#   Unmount the chroot if it's mounted.                                  #
#                                                                        #
##########################################################################

unmount_chroot() {
	if mountpoint -q $CHROOT; then sudo umount $CHROOT; fi
}

##########################################################################
#                                                                        #
#   Create a fresh chroot filesystem using tmpfs                         #
#                                                                        #
##########################################################################

mount_chroot() {
	unmount_chroot
	sudo mount --mkdir -t tmpfs -o defaults,size=8G tmpfs $CHROOT
}

##########################################################################
#                                                                        #
#   Set the makepkg and pacman configurations for building packages.     #
#                                                                        #
##########################################################################

set_configs() {
	sudo chown -R $USER:$USER /usr/share/devtools
	rsync -a --delete $WORKSPACE/makepkg.conf.d/ /usr/share/devtools/makepkg.conf.d/
	rsync -a $WORKSPACE/pacman.conf.d/ /usr/share/devtools/pacman.conf.d/
	cp -f $REPOCTL_CONFIG $HOME/.config/repoctl/config.toml
}

##########################################################################
#                                                                        #
#   Clean up resources and exit gracefully.                              #
#                                                                        #
##########################################################################

cleanup() {
	if [[ ! $DEBUG ]]; then
		unmount_chroot && echo "chroot umounted"
	fi
	echo "All set!"
}

# Trap signals for cleanup
trap cleanup SIGINT SIGTERM ERR EXIT

# Create necessary directories
mkdir -pv $BUILDS/{packages/sources,repository}

##########################################################################
#                                                                        #
#   Greet the user with a stylish message.                               #
#                                                                        #
##########################################################################

say "Greetings!" $GREEN

##########################################################################
#                                                                        #
#   Change directory to the Workspace folder and fetch the latest        #
#   commits. Rsync makepkg and pacman configs to devtools directory.    #
#   Change into the pkgbuild folder and run `fd` with gum filter to      #
#   select packages for building.                                       #
#                                                                        #
##########################################################################

cd $WORKSPACE && git fetch && git pull

set_configs && cd $PKGBUILDS

say "Select packages to build" $GREEN
say "-------------------------" $GREEN

if [[ "${1}" == 'all' ]]; then
	package_selection=$(fd . -t d --max-depth=1 $PKGBUILDS -x echo -e {/})
elif [[ "${1}" == '-p' ]]; then
	package_selection=$2
else
	package_selection=$(fd . -t d --max-depth=1 $PKGBUILDS -x echo -e {/} | gum filter --no-limit)
fi

say "${package_selection}" $BLUE && sleep 1

##########################################################################
#                                                                        #
#   Update package checksums and generate the .SRCINFO file, which       #
#   contains metadata about the package, such as its name, version,      #
#   description, and supported architectures. We then parse the          #
#   supported architectures from the .SRCINFO file and assign them to    #
#   the 'architectures' array for building.                              #
#                                                                        #
##########################################################################

for pkgname in ${package_selection[@]}; do
	cd "${PKGBUILDS}/${pkgname}"

	updpkgsums && makepkg --printsrcinfo >.SRCINFO

	srcinfo=$(grep -E '^\s*arch\s*=' .SRCINFO | choose 2 | grep -E 'x86_64|v3|any' | xargs)

	# Check if the arch is "any" and assign the array accordingly
	if [ "$srcinfo" = "any" ]; then
		architectures=("x86_64" "x86_64_v3")
	else
		architectures=("$srcinfo")
	fi

	##########################################################################
	#                                                                        #
	#   Build the package for each available architecture.                  #
	#                                                                        #
	##########################################################################

	for arch in ${architectures[@]}; do

		say "Building ${pkgname}-${arch}" $YELLOW && sleep 1

		# Set package destinations
		declare -x PKGDEST=$BUILDS/packages/$arch && mkdir -p $PKGDEST
		declare -x SRCPKGDEST=$BUILDS/packages/srcpackages/$arch && mkdir -p $SRCPKGDEST
		declare -x LOGDEST=$BUILDS/packages/makepkglogs/$arch && mkdir -p $LOGDEST

		# Mount chroot
		mount_chroot

		# Build the package
		extra-${arch}-build -c -r $CHROOT -- -c -n -u || break

		# Change into the package destination folder
		cd $PKGDEST

		# Sign the package(s)
		for pkg in *.zst; do
			echo $(cat /tmp/phrase) | gpg2 -v --batch \
				--yes --detach-sign --pinentry-mode loopback \
				--passphrase --passphrase-fd 0 \
				--out $pkg.sig --sign $pkg &&
				repoctl add -P $arch -m -r ./$pkg
		done

		# Add package(s) to repository
		cd $BUILDS/repository/$arch

		if [[ $arch == 'x86_64' ]]; then
			declare -x repo_db="syncopated.db.tar.zst"
		elif [[ $arch == 'x86_64_v3' ]]; then
			declare -x repo_db="syncopated-v3.db.tar.zst"
		fi

		repo-add -n -k $GPGKEY $repo_db *.pkg.tar.zst -s

		cd "${PKGBUILDS}/${pkgname}"
	done # end loop
done  # end loop

##########################################################################
#                                                                        #
#   If packages are successfully added to the repository database,       #
#   then the local repository is synced with a local NAS and a remote    #
#   VPS.                                                                 #
#                                                                        #
##########################################################################

for mirror in ${MIRRORS[@]}; do
	echo -e "Syncing local repository to remote ${mirror}\n"
	rsync -avP --delete "${BUILDS}/repository/" "${mirror}:/usr/share/nginx/html/syncopated/repo/" || continue
done

say "End of Program." $GREEN && sleep 1
