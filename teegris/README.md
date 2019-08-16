# Introduction. What's this?
A fork of QEMU-usermode to run TrustZone applications (TAs) for the
Samsung TEEGRIS operating system with the goal of debugging and testing.

# Current status.
Implemente enough syscalls for the dynamic linker to load TA up to the
event loop.
Once event loop is reached and a call to `recvmsg` is made, it is intercepted
and redirected to `TA_InvokeCommandEntryPoint` with user-supplied parameters.
This allows to test TA argument handler routines without implementing the
complete support for sockets and threads.

The shell variable `TEE_CMD` controls how this argument injection works.
Please study the `run.sh` script for more info. In short, you can specify
parameters (opcode, parameter types, in/out buffer sizes) inside the input
binary before the payload OR you can export a shell variable which overrides
the value from the binary.

# Building
Inside the root of the cloned QEMU tree

```
./build.sh
make -j8
```

# Running
Have a look at `run.sh`

# TODO
* Persistent mode for fast fuzzing
* Parameter type/size definitions for all TAs
* A script to run fuzzing on a multicore system
* Generate dictionary from CMP instructions args like libFuzzer
* Proper support for sockets and threads? (Not really necessary for
testing most top-level code).

# Directory Structure for TEEGRIS
Use binaries from "startup.tzar" from GPL kernel sources.
Use TEE binaries from System/Vendor (UUID-like names, just grep for
"0000-0000-0000").

```
├── bin
│   ├── 00000005-0005-0005-0505-050505050505
│   ├── 00000007-0007-0007-0707-070707070707
│   ├── aarch64
│   │   ├── libc++.so
│   │   ├── libdlmsl.so
│   │   ├── libmath.so
│   │   ├── libpthread.so
│   │   ├── libringbuf.so
│   │   ├── librootcert.so
│   │   ├── libscrypto.so
│   │   ├── libtee_debugsl.so
│   │   ├── libteesl.so
│   │   ├── libtui.so
│   │   └── libtzsl.so
│   ├── arm
│   │   ├── libc++.so
│   │   ├── libdlmsl.so
│   │   ├── libmath.so
│   │   ├── libpthread.so
│   │   ├── libringbuf.so
│   │   ├── librootcert.so
│   │   ├── libscrypto.so
│   │   ├── libtee_debugsl.so
│   │   ├── libteesl.so
│   │   ├── libtui.so
│   │   └── libtzsl.so
│   ├── libtzld64.so
│   ├── libtzld.so
│   └── root_task
└── u3
    └── 00000000-0000-0000-0000-XXYYZZWWAABB.elf
```
