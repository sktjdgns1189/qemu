# Generic (opcode, data size, buffer type inline)
export TEE_CMD=999

# If you don't export one of these,
# they are taken from the first 4 32-bit words in the file
export TEEGRIS_BUF_IN_SIZE=0x1680c
export TEEGRIS_BUF_OUT_SIZE=0x1680c
export TEEGRIS_PARAM_TYPES=0x65
export TEEGRIS_OPCODE_BASE=0x10

# just running in QEMU
../arm-linux-user/qemu-arm -singlestep  -z fuzz_inline/in/test0.bin -cpu max ./u3/00000000-0000-0000-0000-00575644524d.WVDRM.elf

# Dumb fuzzing without coverage
afl-fuzz -m 2000 -t 10000 -n -x fuzz_inline/dict/teegris_ta.dict -i fuzz_inline/in/ -o fuzz_inline/out/ ../arm-linux-user/qemu-arm -z @@ -cpu max ./u3/00000000-0000-0000-0000-00575644524d.WVDRM.elf

# With coverage support in QEMU/Unicorn mode
~/builds/emu/afl-unicorn/afl-fuzz -m 5000 -t 10000 -Q -x fuzz_inline/dict/teegris_ta.dict -i fuzz_inline/in/ -o fuzz_inline/out/ ../arm-linux-user/qemu-arm -z @@ -cpu max ./u3/00000000-0000-0000-0000-00575644524d.WVDRM.elf
