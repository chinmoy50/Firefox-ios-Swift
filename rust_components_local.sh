#!/usr/bin/env bash

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

# Uses a local version of rust-components-swift
#
#
# This script switches the Xcode project to use a local version of rust-components swift

set -e

# CMDNAME is used in the usage text below
CMDNAME=$(basename "$0")
USAGE=$(cat <<EOT
${CMDNAME}
Tarik Eshaq <teshaq@mozilla.com>

Uses a local version of rust-components-swift

This script allows switching the Xcode project to use a local version of rust-components-swift
and back to use the remote version.


USAGE:
    ${CMDNAME} [OPTIONS] <LOCAL_RUST_COMPONENTS_SWIFT_PATH>

OPTIONS:
    -d, --disable                                         Disables local development on rust-components-swift
    -b, --branch  <RUST_COMPONENTS_SWIFT_BRANCH>          Specifies a specific branch of rust-components-swift. Defaults to the currently checked-out branch.
                                                          Useful only if you do not need application-services changes. Otherwise just manually checkout to the branch
                                                          then omit this option and use -a to set the application services directory

    -h, --help                                            Display this help message.
    -a, --application-services <LOCAL_APP_SERVICES_PATH>  Prepare the local rust-components-swift to use a local application services
EOT
)

msg () {
  printf "\033[0;34m> %s\033[0m\n" "${1}"
}

helptext() {
    echo "$USAGE"
}



THIS_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_FILE="$THIS_DIR/Client.xcodeproj/project.pbxproj"
RUST_COMPONENTS_REMOTE="https://github.com/mozilla/rust-components-swift"
REPO_PATH=
DISABLE="false"
APP_SERVICES_DIR=
while (( "$#" )); do
    case "$1" in
        -d|--disable)
            DISABLE="true"
            shift
            ;;
        -a|--application-services)
            APP_SERVICES_DIR=$2
            shift 2
            ;;
        -b|--branch)
            BRANCH_NAME=$2
            shift 2
            ;;
        -h|--help)
            helptext
            exit 0
            ;;
        --) # end argument parsing
            shift
            break
            ;;
        --*=|-*) # unsupported flags
            echo "Error: Unsupported flag $1" >&2
            exit 1
            ;;
        *) # preserve positional arguments
            REPO_PATH=$1
            shift
            ;;
    esac
done

if [ "true" = $DISABLE ]; then
  # We disable the local development and revert back
  git checkout -- $PROJECT_FILE
  exit 0
fi

if [ -z $REPO_PATH ]; then
    msg "Please set the rust-components-swift path."
    msg "This is a path to a local checkout of the rust-components-swift repository"
    msg "You can find the repository on $RUST_COMPONENTS_REMOTE"
    exit 1
fi

if [ ! -z $APP_SERVICES_DIR ]; then
    msg "Setting $REPO_PATH to use $APP_SERVICES_DIR"
    msg "This might take a few minutes as it needs to build the Rust code from source"
    pushd $REPO_PATH
    ./appservices_local_xcframework.sh $APP_SERVICES_DIR
    git commit -m "[Automation] enables local development, please revert this before pushing"
    popd
fi

## First we find the name of the branch the local rust-components-swift is on.
pushd $REPO_PATH
if [ -z BRANCH_NAME]; then
    BRANCH_NAME=$(git status --branch --porcelain | grep '##' | cut -c 4-)
fi
FULL_PATH=$( pwd )
FULL_PATH_ESCAPED=$( echo $FULL_PATH |  sed 's/\//\\\//g' )
popd


if [ -z $BRANCH_NAME ]; then
    msg "Unable to find a local branch in $REPO_PATH"
    msg "Please double check that the path is a valid rust-components-swift path"
    exit 1
fi

RUST_COMPONENTS_REMOTE_ESCAPED=$(echo ${RUST_COMPONENTS_REMOTE} | sed 's/\//\\\//g')

## We now want to replace the occurance of the remote repo with the full path
## The indentation here is important, and it's the indentation that Xcode by default sets
## Perl is installed by default on MacOS so it is safe to use here
perl -0777 -pi -e "s/			repositoryURL = \"${RUST_COMPONENTS_REMOTE_ESCAPED}.git\";
			requirement = {
				kind = exactVersion;
				version = .*?;/			repositoryURL = \"file:\/\/${FULL_PATH_ESCAPED}\";
			requirement = {
				kind = branch;
				version = null;
				branch = ${BRANCH_NAME};/igs" $PROJECT_FILE

msg "Done setting up firefox-ios to use $REPO_PATH"
msg "You will most likely need to reset package caches in Xcode, and possibly clear the build folder"
msg "To undo the changes, you can run `${CMDNAME} -d` or reset the changes to the Xcode project file."
msg "IMPORTANT: `${CMDNAME} -d` will remove **all** changes to the project file, so you might lose an uncommited work
    if you made changes to the Xcode settings"
