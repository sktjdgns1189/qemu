#ifndef __QFAKE_PASSTHRU_H__
#define __QFAKE_PASSTHRU_H__

#include <stdio.h>
#include <sys/mman.h>

enum {
    QFAKE_RC_OK = 1,
    QFAKE_RC_FAIL = 2,
};

#define QFAKE_RETURN_IF(cond) do { if ((cond)) { return; } } while (0)
#define QFAKE_RETFAIL_IF(cond) do { \
    if ((cond)) { \
        fprintf(stderr, "QFAKE %s: Failed to check: " #cond "\n", __func__); \
        return -1; \
    } \
} while (0)

#define QFAKE_PCI_BAR_COUNT 6

typedef struct QFakePciBar {
    void *start;
    uint64_t length;
} QFakePciBar;

typedef struct QFakePciResource {
    QFakePciBar bars[QFAKE_PCI_BAR_COUNT];
} QFakePciResource;

static inline int QFakeFindPciDevice(
    QFakePciResource *resource, unsigned vid, unsigned pid)
{
    int rc = QFAKE_RC_OK;
    FILE *fd = NULL;
    int memfd = NULL;

    char shell_cmd[256] = {};
    sprintf(shell_cmd, "lspci -d %x:%x -v | grep 'Memory at.*' -o | cut -d' ' -f3", vid, pid);

    fd = popen(shell_cmd, "r");
    QFAKE_RETFAIL_IF(!fd);

    memfd = open("/dev/mem", O_RDWR);
    QFAKE_RETFAIL_IF(memfd < 0);

    int i;
    for (i = 0; i < QFAKE_PCI_BAR_COUNT; i++)
    {
        uint32_t barAddr = 0;
        uint64_t size = resource->bars[i].length;
        if (fscanf(fd, "%x\n", &barAddr) < 1) {

            //If the user specified the size for the BAR and we were unable
            //to use this BAR, it's an error
            if (size) {
                rc = QFAKE_RC_FAIL;
            }
            continue;
        }

        //Fixup BAR size when not specified
        if (!size) {
            size = 0x100000;
        }

        //FIXME: parse memory size from lspci. for now, 1M
        printf("%s: BAR[%d] @ %x for %x:%x\n", __func__, i, barAddr, vid, pid);

        void *mem = NULL;
        mem = (void*)mmap(0, size, PROT_READ | PROT_WRITE, MAP_SHARED, memfd, barAddr);

        if (!mem) {
            rc = QFAKE_RC_FAIL;
            continue;
        }
        if ((void*)0xffffffff == mem) {
            rc = QFAKE_RC_FAIL;
            continue;
        }

        resource->bars[i].start = mem;
    }

    pclose(fd);
    fd = NULL;
    return rc;
}

#endif //__QFAKE_PASSTHRU_H__
