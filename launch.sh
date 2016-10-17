#!/bin/bash

./arm-softmmu/qemu-system-arm -m 256 -M mini2440 -serial stdio  -pflash ../wm5/50/SPHIDPI_BIN
