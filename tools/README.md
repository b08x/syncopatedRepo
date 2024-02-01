Software sources are maintained in the pkgbuilds directory in the form of PKGBUILD files. These define how to build each package.

The build.sh script is run, either manually or via automation like the watch.sh script monitoring for PKGBUILD changes.

It will select which packages to build based on arguments or user input.

It then builds each package in a chroot environment by:

Mounting the chroot
Running makepkg in the package source directory
This builds the binary package and stores it
The built packages are then signed and added to the local repository using tools like repoctl.

The local repository is synced to remote mirrors so the built packages can be distributed.

So in summary, build.sh takes the package sources, builds binaries in a chroot, signs and publishes them to a repository


----

The main logic is:

Set a trap to clean up on exit
Enter debug mode if specified
Loop through selected architectures
Set repo database file name
Prepare source and package directories
Loop through selected packages
Mount chroot
Build package in chroot
Sign and add package to local repository
Sign and add repository database to local repo
Sync local repos to remote mirro


Multiple architectures - The build.sh script supports building packages for different CPU architectures like x86_64 and x86_64_v3, with separate repo databases and directories for each.


Some packages seem to be automatically built and maintained for the Arch User Repository (AUR). The aur_deploy.sh script clones packages from the AUR git repos, syncs any new files from the local PKGBUILDs, commits changes and pushes them back to the AUR.
