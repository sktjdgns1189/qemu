/*
 * This file provides emulation for the Designware I2C controller
 * on the Intel BayTrail SoCs.
 *
 * When running on a real board, it tries to mmap() the real PCI device
 * and pass through all MMIO access to allow debugging all register
 * reads and writes on a board without VT-D
 *
 * When finding/mmapping the device fails, the emulation returns
 * zero for all register access. It is not intended to be used
 * in any other way except tracing MMIO on real hardware.
 */

#include "hw/pci/pci.h"
#include "net/net.h"
#include "hw/loader.h"
#include "qemu/timer.h"
#include "sysemu/dma.h"
#include "sysemu/sysemu.h"
#include "trace.h"

#include "hw/pci/qfake_passthru.h"

#define TYPE_PCI_INTELI2C "intel-i2c"

#define PCI_INTELI2C(obj) \
     OBJECT_CHECK(PCIIntelI2CState, (obj), TYPE_PCI_INTELI2C)

#define BAR_COUNT 1

#define INTELI2C_PNPMMIO_SIZE 0x1000
#define INTELI2C_IOPORT_SIZE 0x1000

#define INTEL_I2C_VID 0x8086
#define INTEL_I2C_PID(busn) ((0xf41) + (busn))

#define INTEL_I2C_BUS_COUNT 6

#define INTEL_I2C_GET_BUS(state) ((state->pid) - INTEL_I2C_PID(0))

typedef struct {
    MemoryRegion mmios[BAR_COUNT];
    void *dma_opaque;
    qemu_irq irq;
    void (*phys_mem_read)(void *dma_opaque, hwaddr addr,
                         uint8_t *buf, int len, int do_bswap);
    void (*phys_mem_write)(void *dma_opaque, hwaddr addr,
                          uint8_t *buf, int len, int do_bswap);
    unsigned pid;
} IntelI2CState;

typedef struct {
    /*< private >*/
    PCIDevice parent_obj;
    /*< public >*/

    IntelI2CState state;
    MemoryRegion io_bar;
} PCIIntelI2CState;

static volatile uint8_t *IntelRealBars[INTEL_I2C_BUS_COUNT] = {};

static uint32_t intel_i2c_passthru_read(uint32_t addr, uint32_t bus_id)
{
    if (bus_id >= INTEL_I2C_BUS_COUNT) {
        fprintf(stderr, "%s: invalid bus number %d\n", __func__, bus_id);
        return 0;
    }

    if ((!IntelRealBars[bus_id]) || ((void*)0xffffffff == IntelRealBars[bus_id])) {
        fprintf(stderr, "%s: memory not mapped for bus %d\n", __func__, bus_id);
        return 0;
    }

    return *((uint32_t*)(IntelRealBars[bus_id] + addr));
}

static void intel_i2c_passthru_write(uint32_t addr, uint32_t val, uint32_t bus_id)
{
    if (bus_id >= INTEL_I2C_BUS_COUNT) {
        fprintf(stderr, "%s: invalid bus number %d\n", __func__, bus_id);
        return;
    }

    if ((!IntelRealBars[bus_id]) || ((void*)0xffffffff == IntelRealBars[bus_id])) {
        fprintf(stderr, "%s: memory not mapped for bus %d\n", __func__, bus_id);
        return;
    }

    *((uint32_t*)(IntelRealBars[bus_id] + addr)) = val;
}

static uint64_t intel_i2c_ioport_read(void *opaque, hwaddr addr,
                                  unsigned size)
{
    IntelI2CState *d = opaque;
    uint32_t val = intel_i2c_passthru_read(addr, INTEL_I2C_GET_BUS(d));
    fprintf(stderr, "%s: addr=%x size=%x\n", __func__, (uint32_t)addr, size);
    return val;
}

static void intel_i2c_ioport_write(void *opaque, hwaddr addr,
                               uint64_t data, unsigned size)
{
    IntelI2CState *d = opaque;
    fprintf(stderr, "%s: (uint32_t)addr=%x size=%x\n", __func__, (uint32_t)addr, size);
    intel_i2c_passthru_write(addr, data, INTEL_I2C_GET_BUS(d));
}

static const MemoryRegionOps intel_i2c_io_ops = {
    .read = intel_i2c_ioport_read,
    .write = intel_i2c_ioport_write,
    .endianness = DEVICE_LITTLE_ENDIAN,
};

static void intel_i2c_mmio_writeb(void *opaque, hwaddr addr, uint32_t val)
{
    IntelI2CState *d = opaque;
    (void)d;
    fprintf(stderr, "%s: (uint32_t)addr=%x val=%x pid=%x\n", __func__, (uint32_t)addr, val, d->pid);
    intel_i2c_passthru_write(addr, val, INTEL_I2C_GET_BUS(d));
}

static uint32_t intel_i2c_mmio_readb(void *opaque, hwaddr addr)
{
    IntelI2CState *d = opaque;
    (void)d;
    uint32_t val = intel_i2c_passthru_read(addr, INTEL_I2C_GET_BUS(d));
    fprintf(stderr, "%s: (uint32_t)addr=%x val=%x pid=%x\n", __func__, (uint32_t)addr, val, d->pid);
    return val;
}

static void intel_i2c_mmio_writew(void *opaque, hwaddr addr, uint32_t val)
{
    IntelI2CState *d = opaque;
    (void)d;
    fprintf(stderr, "%s: (uint32_t)addr=%x val=%x pid=%x\n", __func__, (uint32_t)addr, val, d->pid);
    intel_i2c_passthru_write(addr, val, INTEL_I2C_GET_BUS(d));
}

static uint32_t intel_i2c_mmio_readw(void *opaque, hwaddr addr)
{
    IntelI2CState *d = opaque;
    (void)d;
    uint32_t val = intel_i2c_passthru_read(addr, INTEL_I2C_GET_BUS(d));
    fprintf(stderr, "%s: (uint32_t)addr=%x val=%x pid=%x\n", __func__, (uint32_t)addr, val, d->pid);
    return val;
}

static void intel_i2c_mmio_writel(void *opaque, hwaddr addr, uint32_t val)
{
    IntelI2CState *d = opaque;
    (void)d;
    fprintf(stderr, "%s: (uint32_t)addr=%x val=%x pid=%x\n", __func__, (uint32_t)addr, val, d->pid);
    intel_i2c_passthru_write(addr, val, INTEL_I2C_GET_BUS(d));
}

static uint32_t intel_i2c_mmio_readl(void *opaque, hwaddr addr)
{
    IntelI2CState *d = opaque;
    (void)d;
    uint32_t val = intel_i2c_passthru_read(addr, INTEL_I2C_GET_BUS(d));
    fprintf(stderr, "%s: (uint32_t)addr=%x val=%x pid=%x\n", __func__, (uint32_t)addr, val, d->pid);
    return val;
}

static const VMStateDescription vmstate_intel_i2c = {
    .name = "intel_i2c",
    .version_id = 3,
    .minimum_version_id = 2,
    .fields = (VMStateField[]) {
        VMSTATE_PCI_DEVICE(parent_obj, PCIIntelI2CState),
        VMSTATE_STRUCT(state, PCIIntelI2CState, 0, vmstate_intel_i2c, IntelI2CState),
        VMSTATE_END_OF_LIST()
    }
};

/* PCI interface */

static const MemoryRegionOps intel_i2c_mmio_ops = {
    .old_mmio = {
        .read = { intel_i2c_mmio_readb, intel_i2c_mmio_readw, intel_i2c_mmio_readl },
        .write = { intel_i2c_mmio_writeb, intel_i2c_mmio_writew, intel_i2c_mmio_writel },
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

static void intel_i2c_uninit(PCIDevice *dev)
{
    PCIIntelI2CState *d = PCI_INTELI2C(dev);
    qemu_free_irq(d->state.irq);
}

static void intel_i2c_realize(PCIDevice *pci_dev, Error **errp)
{
    PCIIntelI2CState *d = PCI_INTELI2C(pci_dev);
    IntelI2CState *s = &d->state;
    uint8_t *pci_conf;

    pci_conf = pci_dev->config;

    pci_set_word(pci_conf + PCI_STATUS,
                 PCI_STATUS_FAST_BACK | PCI_STATUS_DEVSEL_MEDIUM);

    pci_set_word(pci_conf + PCI_SUBSYSTEM_VENDOR_ID, INTEL_I2C_VID);
    pci_set_word(pci_conf + PCI_SUBSYSTEM_ID, INTEL_I2C_PID(0));

    pci_conf[PCI_INTERRUPT_PIN] = 1; /* interrupt pin A */
    pci_conf[PCI_MIN_GNT] = 0x06;
    pci_conf[PCI_MAX_LAT] = 0xff;

    s->pid = pci_get_word(pci_conf + PCI_DEVICE_ID);

    int i;
    /* Handler for memory-mapped I/O */
    for (i = 0; i < BAR_COUNT; i++) {
        memory_region_init_io(&(s->mmios[i]), OBJECT(d), &intel_i2c_mmio_ops, s,
                          "intel_i2c-mmio", INTELI2C_PNPMMIO_SIZE);
        pci_register_bar(pci_dev, i, PCI_BASE_ADDRESS_SPACE_MEMORY, &s->mmios[i]);
    }

    #if 0
    memory_region_init_io(&d->io_bar, OBJECT(d), &intel_i2c_io_ops, s, "intel_i2c-io",
                          INTELI2C_IOPORT_SIZE);
    pci_register_bar(pci_dev, 0, PCI_BASE_ADDRESS_SPACE_IO, &d->io_bar);
    #endif

    s->irq = pci_allocate_irq(pci_dev);
    s->phys_mem_read = pci_physical_memory_read;
    s->phys_mem_write = pci_physical_memory_write;
    s->dma_opaque = pci_dev;

}

static void pci_reset(DeviceState *dev)
{
    //PCIIntelI2CState *d = PCI_INTELI2C(dev);
    (void)dev;
}

static void intel_i2c_instance_init(Object *obj)
{
    //PCIIntelI2CState *d = PCI_INTELI2C(obj);
    (void)obj;
}

static Property intel_i2c_properties[] = {
    DEFINE_PROP_END_OF_LIST(),
};

typedef struct IIC_Info {
    unsigned pid;
    const char *name;
} IIC_Info;

#define DEF_I2C(num) [num] = { .pid = INTEL_I2C_PID(num), .name = "intel-i2c-" #num }

static const IIC_Info i2c_dev_info[INTEL_I2C_BUS_COUNT] = {
    DEF_I2C(0),
    DEF_I2C(1),
    DEF_I2C(2),
    DEF_I2C(3),
    DEF_I2C(4),
    DEF_I2C(5),
};

static void intel_i2c_class_init(ObjectClass *klass, void *data)
{
    DeviceClass *dc = DEVICE_CLASS(klass);
    PCIDeviceClass *k = PCI_DEVICE_CLASS(klass);
    IIC_Info *i = (IIC_Info*)data;

    k->realize = intel_i2c_realize;
    k->exit = intel_i2c_uninit;
    k->vendor_id = INTEL_I2C_VID;
    k->device_id = i->pid;
    k->revision = 0x10;
    k->class_id = PCI_CLASS_COMMUNICATION_SERIAL;
    dc->reset = pci_reset;
    dc->vmsd = &vmstate_intel_i2c;
    dc->props = intel_i2c_properties;
    set_bit(DEVICE_CATEGORY_MISC, dc->categories);
}

static const TypeInfo i2c_base_info = {
    .name = TYPE_PCI_INTELI2C,
    .parent = TYPE_PCI_DEVICE,
    .abstract = true,
};

static int QFakePciInitIntelI2C(void)
{
    int i;
    for (i = 0; i < INTEL_I2C_BUS_COUNT; i++) {
        QFakePciResource resource = {
            .bars = {
                [0] = {
                    .length = 0x1000,
                },
            },
        };
        if (QFAKE_RC_OK != QFakeFindPciDevice(&resource, 0x8086, 0xf41 + i)) {
            continue;
        }
        IntelRealBars[i] = resource.bars[0].start;
    }
    return QFAKE_RC_OK;
}

static void intel_i2c_register_types(void)
{
    int i;
    TypeInfo i2c_type_info = {
        //.name          = TYPE_PCI_INTELI2C,
        .parent        = TYPE_PCI_INTELI2C,
        .instance_size = sizeof(PCIIntelI2CState),
        .class_init    = intel_i2c_class_init,
        .instance_init = intel_i2c_instance_init,
    };

    type_register_static(&i2c_base_info);
    QFakePciInitIntelI2C();

    for (i = 0; i < INTEL_I2C_BUS_COUNT; i++) {
        i2c_type_info.name = i2c_dev_info[i].name;
        i2c_type_info.class_data = (void*)(i2c_dev_info + i);
        type_register(&i2c_type_info);
    }
}

type_init(intel_i2c_register_types)
