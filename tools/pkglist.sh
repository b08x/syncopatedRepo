#!/usr/bin/env bash

declare -rx WORKSPACE="${HOME}/Workspace"
declare -rx PKGBUILDS="${WORKSPACE}/syncopatedRepo/pkgbuilds"

declare -a package_list=$(fd . -t d --max-depth 1 $PKGBUILDS)

for pkg in ${package_list[@]}; do
	cd $pkg

	name=$(cat .SRCINFO | grep -E '^\s*pkgbase\s*=' | choose 2 | xargs -0)
	url=$(cat .SRCINFO | grep -E '^\s*url\s*=' | choose 2 | xargs -0)
	desc=$(cat .SRCINFO | grep -E '^\s*pkgdesc\s*=' | head -n 1 | choose -f '=' 1 | xargs -0)
	ver=$(cat .SRCINFO | grep -E '^\s*pkgver\s*=' | choose 2 | xargs -0)

	echo -e "| [$name]($url) | $desc | $ver |"

done
