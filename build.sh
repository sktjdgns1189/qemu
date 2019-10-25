#!/bin/bash

#export PATH=/home/alexander/builds/emu/afl-unicorn/:$PATH
export PATH=~/Documents/workspace/bin/llvm/clang+llvm-9.0.0-x86_64-linux-gnu-ubuntu-18.04/bin/:$PATH
export AFL_PATH=/home/alexander/builds/emu/afl-unicorn/

./configure \
	--cc=/home/alexander/builds/emu/afl-unicorn/afl-clang-fast \
	--host-cc=/home/alexander/builds/emu/afl-unicorn/afl-clang-fast \
	--target-list=arm-linux-user,aarch64-linux-user \
	--enable-user \
	--disable-system \
	--disable-werror \
	--disable-sdl \
	--disable-vnc \
	--disable-virtfs \
	--disable-cocoa \
	--disable-xen \
	--enable-capstone=git \
	--disable-tcg-interpreter \
	--enable-debug-tcg \
	--enable-debug-info

