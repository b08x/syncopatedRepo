#!/bin/bash
set -e

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

declare -rx PACKAGE_LIST="${WORKSPACE}/tools/aur.txt"

declare -rx TMP="/tmp/aur"

if [[ -d $TMP ]]; then
  echo "tmp folder already populated. re-creating ..."
  rm -rf $TMP && mkdir -pv $TMP
else
  echo "tmp folder does not exist. creating ..."
  mkdir -pv $TMP
fi

PACKAGES="$(cat $PACKAGE_LIST)"

for PKG in $PACKAGES; do
  cd "$TMP"

  echo "Cloning AUR repo for $PKG ... "
  git clone -n ssh://aur@aur.archlinux.org/$PKG.git

  echo "copying new files into git repo ..."
  rsync -avP --exclude="*.log" --exclude=".git/" "$PKGBUILDS/$PKG/" "$TMP/$PKG/"

  cd "$TMP/$PKG/"
  git add .

  TYPE=$(gum choose "fix" "feat" "docs" "style" "refactor" "test" "chore" "revert" "update")
  SCOPE=$(gum input --placeholder "scope")

  # Since the scope is optional, wrap it in parentheses if it has a value.
  test -n "$SCOPE" && SCOPE="($SCOPE)"

  # Pre-populate the input with the type(scope): so that the user may change it
  SUMMARY=$(gum input --value "$TYPE$SCOPE: " --placeholder "Summary of this change")
  DESCRIPTION=$(gum write --placeholder "Details of this change")

  # Commit these changes if user confirms
  gum confirm "Commit changes?" && git commit --author="$PACKAGER" -m "$SUMMARY" -m "$DESCRIPTION"

  gum confirm "Push to AUR?" && git push

done
