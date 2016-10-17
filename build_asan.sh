#!/bin/bash

export LOCAL_LLVM_BUILD=$HOME/Documents/workspace/builds/llvm/build

export CONF_OPTS=(
--audio-drv-list=''
--disable-aio
--disable-bluez
--disable-brlapi
--disable-bsd-user
--disable-curses
--disable-darwin-user
--disable-kqemu
--disable-kvm
--disable-linux-user
--disable-pthread
--disable-sparse
--disable-strip
--disable-vde
--disable-vnc-sasl
--disable-vnc-tls
--disable-werror
--disable-xen
--target-list=arm-softmmu

--extra-cflags="-Wall -g3 -Os -fno-omit-frame-pointer -fno-inline -fsanitize=address -I/Applications/Xcode.app/Contents//Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/c++/v1 -fsanitize=address"
--extra-ldflags="-L$LOCAL_LLVM_BUILD/lib/ -L$LOCAL_LLVM_BUILD/lib/clang/3.6.0/lib/darwin/ -lclang_rt.asan_osx_dynamic -lc++ -lc++abi -Xlinker -rpath -Xlinker $LOCAL_LLVM_BUILD/lib"
--cc="$LOCAL_LLVM_BUILD/bin/clang"
)

./configure "${CONF_OPTS[@]}"

