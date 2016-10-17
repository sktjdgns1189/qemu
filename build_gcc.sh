#!/bin/bash

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

--extra-cflags='-Wall -g2 -fno-omit-frame-pointer -I/usr/local/include'
--target-list=arm-softmmu
--cc=gcc-4.9
--host-cc=gcc-4.9
)

./configure "${CONF_OPTS[@]}"
