/*
   american fuzzy lop - high-performance binary-only instrumentation
   -----------------------------------------------------------------

   Written by Andrew Griffiths <agriffiths@google.com> and
              Michal Zalewski <lcamtuf@google.com>

   Idea & design very much by Andrew Griffiths.

   Copyright 2015, 2016, 2017 Google Inc. All rights reserved.

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at:

     http://www.apache.org/licenses/LICENSE-2.0

   This code is a shim patched into the separately-distributed source
   code of QEMU 2.10.0. It leverages the built-in QEMU tracing functionality
   to implement AFL-style instrumentation and to take care of the remaining
   parts of the AFL fork server logic.

   The resulting QEMU binary is essentially a standalone instrumentation
   tool; for an example of how to leverage it for other purposes, you can
   have a look at afl-showmap.c.

 */

#include <sys/shm.h>

#include "/home/alexander/builds/emu/afl-unicorn/config.h"
//#include "config.h"

/***************************
 * VARIOUS AUXILIARY STUFF *
 ***************************/

/* A snippet patched into tb_find_slow to inform the parent process that
   we have hit a new block that hasn't been translated yet, and to tell
   it to translate within its own context, too (this avoids translation
   overhead in the next forked-off copy). */

#if 0
#define AFL_QEMU_CPU_SNIPPET1 do { \
    afl_request_tsl(pc, cs_base, flags); \
  } while (0)
#else
#define AFL_QEMU_CPU_SNIPPET1 do { } while (0)
#endif

/* This snippet kicks in when the instruction pointer is positioned at
   _start and does the usual forkserver stuff, not very different from
   regular instrumentation injected via afl-as.h. */
      
extern void __afl_manual_init(void);

#define AFL_QEMU_CPU_SNIPPET2 do { \
    if(itb->pc == afl_entry_point) { \
	    afl_setup(); \
	    __afl_manual_init(); \
    } \
    afl_maybe_log(itb->pc); \
  } while (0)

/* This is equivalent to afl-as.h: */
extern u8* __afl_area_ptr;

/* Exported variables populated by the code patched into elfload.c: */

abi_ulong afl_entry_point, /* ELF entry point (_start) */
          afl_start_code,  /* .text start pointer      */
          afl_end_code;    /* .text end pointer        */

/* Set in the child process in forkserver mode: */
static unsigned int afl_inst_rms = MAP_SIZE;

/* Function declarations. */

static inline void afl_maybe_log(abi_ulong);

/*************************
 * ACTUAL IMPLEMENTATION *
 *************************/

/* Set up SHM region and initialize other stuff. */

static void afl_setup(void) {
  if (getenv("AFL_INST_LIBS")) {
    afl_start_code = 0;
    afl_end_code   = (abi_ulong)-1;
  }
}

/* The equivalent of the tuple logging routine from afl-as.h. */

static inline void afl_maybe_log(abi_ulong cur_loc) {

  //static __thread abi_ulong prev_loc;
  extern u32 __afl_prev_loc;

  /* Optimize for cur_loc > afl_end_code, which is the most likely case on
     Linux systems. */

  if (cur_loc > afl_end_code || cur_loc < afl_start_code || !__afl_area_ptr)
    return;

  /* Looks like QEMU always maps to fixed locations, so ASAN is not a
     concern. Phew. But instruction addresses may be aligned. Let's mangle
     the value to get something quasi-uniform. */

  //cur_loc  = (cur_loc >> 4) ^ (cur_loc << 8);
  cur_loc = (cur_loc>>2) ^ (cur_loc >> 16);
  cur_loc &= MAP_SIZE - 1;

  /* Implement probabilistic instrumentation by looking at scrambled block
     address. This keeps the instrumented locations stable across runs. */

  if (cur_loc >= afl_inst_rms) {
	fprintf(stderr, "%s: cur_loc=%x, afl_inst_rms=%x\n", __func__, cur_loc, afl_inst_rms);
	return;
  }
  
  if (!__afl_area_ptr) {
	__afl_manual_init();
        return;
  }

  __afl_area_ptr[cur_loc ^ __afl_prev_loc]++;
  __afl_prev_loc = cur_loc >> 1;

}
