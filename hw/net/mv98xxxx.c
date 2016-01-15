/*
 * This file provides emulation for the Marvell Bobcat (Prestera)
 * Network SoC.
 *
 * When a real board is connected via PCIe, the emulation layer
 * will mmap() the real device and just proxy all register accesses.
 * It is intended to allow debugging PCIe access on a board without VT-D.
 *
 * When no real device is detected, the emulation provides the minimal
 * subset of registers needed to get our firmware past the initialization
 * process
 */

#include "hw/pci/pci.h"
#include "net/net.h"
#include "hw/loader.h"
#include "qemu/timer.h"
#include "sysemu/dma.h"
#include "sysemu/sysemu.h"
#include "trace.h"

#include "pcnet.h"

#include "hw/pci/qfake_passthru.h"

#define TYPE_PCI_PCNET "pcnet"

#define PCI_PCNET(obj) \
     OBJECT_CHECK(PCIPCNetState, (obj), TYPE_PCI_PCNET)

typedef struct {
    /*< private >*/
    PCIDevice parent_obj;
    /*< public >*/

    PCNetState state;
    MemoryRegion io_bar;
} PCIPCNetState;

static volatile uint8_t *MarvelBars[2] = {};

#define MARVEL_HWID 0x11ab
#define BOBCAT_DEVID 0xdd74
#define MARVEL_BAR0_SIZE 0x100000
#define MARVEL_BAR1_SIZE 0x4000000

#define IS_VALID_BAR(addr) (addr && ((void*)0xffffffff != addr))

static uint32_t mv98xxxx_fake_read(uint32_t addr, uint32_t bar)
{
    if (IS_VALID_BAR(MarvelBars[!!bar])) {
        uint32_t val = *((uint32_t*)(MarvelBars[!!bar] + addr));
        fprintf(stderr, "%s: REAL bar=%x addr=%x val=%x\n", __func__, bar, addr, val);
        return val;
    }
    else {
        fprintf(stderr, "%s: FAKE addr=%x\n", __func__, addr);
    }

    uint32_t val = 0;
    switch (addr) {
        case 0:
            return (BOBCAT_DEVID << 16) | MARVEL_HWID;
            break;
        case 0x50:
            return MARVEL_HWID;
            break;
        case 0x4c:
            return BOBCAT_DEVID;
            break;
        case 0x58:
        case 0x4004034:
        case 0x4004054:
            val = -1;
            break;
    }

    if ((addr & 0x4050) == 0x4050) {
        val |= (1 << 28);
    }
    if ((addr & 0x09030000) == 0x09030000) {
        val |= -1;
    }

    if (addr == 0x0b00002c) {
        val = 0;
    }
    return val;
}

static void mv98xxxx_fake_write(uint32_t addr, uint32_t val, uint32_t bar)
{
    if (IS_VALID_BAR(MarvelBars[!!bar])) {
        fprintf(stderr, "%s: REAL bar=%x addr=%x val=%x\n", __func__, bar, addr, val);
        *((uint32_t*)(MarvelBars[!!bar] + addr)) = val;
    }
    else {
        fprintf(stderr, "%s: FAKE addr=%x val=%x\n", __func__, addr, val);
    }
}

static uint64_t pcnet_ioport_read(void *opaque, hwaddr addr,
                                  unsigned size)
{
    uint32_t val = mv98xxxx_fake_read(addr, (uint64_t)opaque);
    fprintf(stderr, "%s: addr=%x size=%x\n", __func__, (uint32_t)addr, size);
    return val;
}

static void pcnet_ioport_write(void *opaque, hwaddr addr,
                               uint64_t data, unsigned size)
{
    fprintf(stderr, "%s: (uint32_t)addr=%x size=%x\n", __func__, (uint32_t)addr, size);
    mv98xxxx_fake_write(addr, data, (uint64_t)opaque);
}

static const MemoryRegionOps pcnet_io_ops = {
    .read = pcnet_ioport_read,
    .write = pcnet_ioport_write,
    .endianness = DEVICE_LITTLE_ENDIAN,
};

static void pcnet_mmio_writeb(void *opaque, hwaddr addr, uint32_t val)
{
    fprintf(stderr, "%s: (uint32_t)addr=%x val=%x\n", __func__, (uint32_t)addr, val);
    mv98xxxx_fake_write(addr, val, (uint64_t)opaque);
}

static uint32_t pcnet_mmio_readb(void *opaque, hwaddr addr)
{
    uint32_t val = mv98xxxx_fake_read(addr, (uint64_t)opaque);
    fprintf(stderr, "%s: (uint32_t)addr=%x val=%x\n", __func__, (uint32_t)addr, val);
    return val;
}

static void pcnet_mmio_writew(void *opaque, hwaddr addr, uint32_t val)
{
    fprintf(stderr, "%s: (uint32_t)addr=%x val=%x\n", __func__, (uint32_t)addr, val);
    mv98xxxx_fake_write(addr, val, (uint64_t)opaque);
}

static uint32_t pcnet_mmio_readw(void *opaque, hwaddr addr)
{
    uint32_t val = mv98xxxx_fake_read(addr, (uint64_t)opaque);
    fprintf(stderr, "%s: (uint32_t)addr=%x val=%x\n", __func__, (uint32_t)addr, val);
    return val;
}

static void pcnet_mmio_writel(void *opaque, hwaddr addr, uint32_t val)
{
    fprintf(stderr, "%s: (uint32_t)addr=%x val=%x\n", __func__, (uint32_t)addr, val);
    mv98xxxx_fake_write(addr, val, (uint64_t)opaque);
}

static uint32_t pcnet_mmio_readl(void *opaque, hwaddr addr)
{
    uint32_t val = mv98xxxx_fake_read(addr, (uint64_t)opaque);
    fprintf(stderr, "%s: (uint32_t)addr=%x val=%x\n", __func__, (uint32_t)addr, val);
    return val;
}

static const VMStateDescription vmstate_pci_pcnet = {
    .name = "pcnet",
    .version_id = 3,
    .minimum_version_id = 2,
    .fields = (VMStateField[]) {
        VMSTATE_PCI_DEVICE(parent_obj, PCIPCNetState),
        VMSTATE_STRUCT(state, PCIPCNetState, 0, vmstate_pcnet, PCNetState),
        VMSTATE_END_OF_LIST()
    }
};

/* PCI interface */

static const MemoryRegionOps pcnet_mmio_ops = {
    .old_mmio = {
        .read = { pcnet_mmio_readb, pcnet_mmio_readw, pcnet_mmio_readl },
        .write = { pcnet_mmio_writeb, pcnet_mmio_writew, pcnet_mmio_writel },
    },
    .endianness = DEVICE_LITTLE_ENDIAN,
};

static void pci_physical_memory_write(void *dma_opaque, hwaddr addr,
                                      uint8_t *buf, int len, int do_bswap)
{
    fprintf(stderr, "PCI WRITE\n");
    uint32_t idx;
    for (idx = 0; idx < len; idx++) {
        fprintf(stderr, "%02x ", buf[idx]);

        if ((idx && (idx % 32 == 0)) || (idx == (len - 1))) {
            fprintf(stderr, "\n");
        }
    }
}

static void pci_physical_memory_read(void *dma_opaque, hwaddr addr,
                                     uint8_t *buf, int len, int do_bswap)
{
    fprintf(stderr, "PCI READ\n");
    uint32_t idx;
    for (idx = 0; idx < len; idx++) {
        fprintf(stderr, "%02x ", buf[idx]);

        if ((idx && (idx % 32 == 0)) || (idx == (len - 1))) {
            fprintf(stderr, "\n");
        }
    }
}

static void pci_pcnet_uninit(PCIDevice *dev)
{
    PCIPCNetState *d = PCI_PCNET(dev);

    qemu_free_irq(d->state.irq);
    timer_del(d->state.poll_timer);
    timer_free(d->state.poll_timer);
    qemu_del_nic(d->state.nic);
}

static NetClientInfo net_pci_pcnet_info = {
    .type = NET_CLIENT_OPTIONS_KIND_NIC,
    .size = sizeof(NICState),
    .can_receive = pcnet_can_receive,
    .receive = pcnet_receive,
    .link_status_changed = pcnet_set_link_status,
};

static void pci_pcnet_realize(PCIDevice *pci_dev, Error **errp)
{
    PCIPCNetState *d = PCI_PCNET(pci_dev);
    PCNetState *s = &d->state;
    uint8_t *pci_conf;

    pci_conf = pci_dev->config;

    pci_set_word(pci_conf + PCI_STATUS,
                 PCI_STATUS_FAST_BACK | PCI_STATUS_DEVSEL_MEDIUM);

    pci_set_word(pci_conf + PCI_SUBSYSTEM_VENDOR_ID, MARVEL_HWID);
    pci_set_word(pci_conf + PCI_SUBSYSTEM_ID, BOBCAT_DEVID);

    pci_conf[PCI_INTERRUPT_PIN] = 1; /* interrupt pin A */
    pci_conf[PCI_MIN_GNT] = 0x06;
    pci_conf[PCI_MAX_LAT] = 0xff;

    int i;
    /* Handler for memory-mapped I/O */
    for (i = 1; i < 6; i++) {
    memory_region_init_io(&(s->mmios[i]), OBJECT(d), &pcnet_mmio_ops, (void*)(uint64_t)i,
                          "pcnet-mmio", PCNET_PNPMMIO_SIZE);
    }

    memory_region_init_io(&d->io_bar, OBJECT(d), &pcnet_io_ops, (void*)0, "pcnet-io",
                          PCNET_IOPORT_SIZE);
    pci_register_bar(pci_dev, 0, PCI_BASE_ADDRESS_SPACE_IO, &d->io_bar);

    for (i = 1; i < 6; i++) {
        pci_register_bar(pci_dev, i, PCI_BASE_ADDRESS_SPACE_MEMORY, &s->mmios[i]);
    }

    s->irq = pci_allocate_irq(pci_dev);
    s->phys_mem_read = pci_physical_memory_read;
    s->phys_mem_write = pci_physical_memory_write;
    s->dma_opaque = pci_dev;

    pcnet_common_init(DEVICE(pci_dev), s, &net_pci_pcnet_info);
}

static void pci_reset(DeviceState *dev)
{
    PCIPCNetState *d = PCI_PCNET(dev);

    pcnet_h_reset(&d->state);
}

static void pcnet_instance_init(Object *obj)
{
    PCIPCNetState *d = PCI_PCNET(obj);
    PCNetState *s = &d->state;

    device_add_bootindex_property(obj, &s->conf.bootindex,
                                  "bootindex", "/ethernet-phy@0",
                                  DEVICE(obj), NULL);
}

static Property pcnet_properties[] = {
    DEFINE_NIC_PROPERTIES(PCIPCNetState, state.conf),
    DEFINE_PROP_END_OF_LIST(),
};

static void pcnet_class_init(ObjectClass *klass, void *data)
{
    DeviceClass *dc = DEVICE_CLASS(klass);
    PCIDeviceClass *k = PCI_DEVICE_CLASS(klass);

    k->realize = pci_pcnet_realize;
    k->exit = pci_pcnet_uninit;
    k->vendor_id = MARVEL_HWID;
    k->device_id = BOBCAT_DEVID;
    k->revision = 0x10;
    k->class_id = PCI_CLASS_NETWORK_ETHERNET;
    dc->reset = pci_reset;
    dc->vmsd = &vmstate_pci_pcnet;
    dc->props = pcnet_properties;
    set_bit(DEVICE_CATEGORY_NETWORK, dc->categories);
}

static const TypeInfo pcnet_info = {
    .name          = TYPE_PCI_PCNET,
    .parent        = TYPE_PCI_DEVICE,
    .instance_size = sizeof(PCIPCNetState),
    .class_init    = pcnet_class_init,
    .instance_init = pcnet_instance_init,
};

static int QFakeInitMarvel(void)
{
    QFakePciResource res = {
        .bars = {
            [0] = {
                .length = MARVEL_BAR0_SIZE,
            },
            [1] = {
                .length = MARVEL_BAR1_SIZE,
            },
        },
    };
    QFAKE_RETFAIL_IF(QFAKE_RC_OK != QFakeFindPciDevice(&res, MARVEL_HWID, BOBCAT_DEVID));

    QFAKE_RETFAIL_IF(!res.bars[0].start);
    QFAKE_RETFAIL_IF(res.bars[0].length < MARVEL_BAR0_SIZE);
    QFAKE_RETFAIL_IF(!res.bars[1].start);
    QFAKE_RETFAIL_IF(res.bars[1].length < MARVEL_BAR1_SIZE);

    MarvelBars[0] = (volatile uint8_t*)res.bars[0].start;
    MarvelBars[1] = (volatile uint8_t*)res.bars[1].start;

    return QFAKE_RC_OK;
}

static void pci_pcnet_register_types(void)
{
    QFakeInitMarvel();
    type_register_static(&pcnet_info);
}

type_init(pci_pcnet_register_types)
