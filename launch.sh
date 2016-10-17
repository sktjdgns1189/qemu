#!/bin/bash

export KERNEL=../wm5/50/SPHIDPI_BIN
export BLDR=../wm5/50/eboot.nb0
export MTD=$KERNEL
export PFLASH=$KERNEL
export MINI2440_BOOT=nand

export ARGS=(
-m 128
-M mini2440
-serial stdio
-kernel $BLDR
-mtdblock $MTD
-pflash $PFLASH
-nographic
)

echo ./arm-softmmu/qemu-system-arm "${ARGS[@]}" $@
./arm-softmmu/qemu-system-arm "${ARGS[@]}" $@
