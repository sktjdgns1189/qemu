#!/bin/bash

./configure \
	--target-list=aarch64-softmmu \
	--disable-werror \
	--disable-user \
	--disable-sdl \
	--disable-vnc \
	--disable-virtfs \
	--disable-cocoa \
	--disable-xen \
	--enable-capstone=git \
	--disable-tcg-interpreter \
	--enable-debug-tcg \
	--enable-debug-info
