../arm-linux-user/qemu-arm  -cpu max ./00000000-0000-0000-0000-4b45594d5354.elf 
../arm-linux-user/qemu-arm -singlestep -g 1234 -cpu max ./00000000-0000-0000-0000-4b45594d5354.elf
../aarch64-linux-user/qemu-aarch64 -singlestep -cpu cortex-a57 ./bin/00000005-0005-0005-0505-050505050505

#TEE_CMD=4 ../aarch64-linux-user/qemu-aarch64 -singlestep -cpu cortex-a57 ./bin/root_task
#do_syscall_teegris: syslog 'ERR: root_task handle_open_session() pid=2: Trusted storage is not ready

#TEE_CMD=777 ../arm-linux-user/qemu-arm  -cpu max ./00000000-0000-0000-0000-4b45594d5354.elf 2>&1 | tee err.log
#afl-fuzz  -n -i fuzz_keymaster/in/ -o fuzz_keymaster/out/ -- ../arm-linux-user/qemu-arm -z @@ -cpu max ./00000000-0000-0000-0000-4b45594d5354.elf

#TEE_CMD=888 ../arm-linux-user/qemu-arm -singlestep   -cpu max ./00000000-0000-0000-0000-564c544b5052_VLTKPR.elf
#TEE_CMD=888 ../arm-linux-user/qemu-arm -singlestep  -z fuzz_vaultkeeper/in/test0.bin -cpu max ./00000000-0000-0000-0000-564c544b5052_VLTKPR.elf
