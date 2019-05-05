#!/bin/bash

./configure \
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

