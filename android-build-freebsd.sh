#!/usr/local/bin/bash

pushd .
cd ./distrib/sdl-1.2.15/
./android-configure.sh --cc=gcc47 --try-64 || exit -1
gmake -j10 || exit -1
gmake install || exit -1
popd

./android-rebuild.sh --no-gles  --verbose --debug --ignore-audio --cc=gcc47 --sdl-config="${PWD}/distrib/sdl-1.2.15/out/freebsd-x86_64/bin/sdl-config" || exit -1
gmake -j10 || exit -1
