//
//  main.m
//  QemuLauncher
//
//  Created by Alexander Tarasikov on 06/01/2019.
//  Copyright © 2019 test. All rights reserved.
//

#import <UIKit/UIKit.h>
#include <unistd.h>

void runQemu(void)
{
    NSString * path = [[[NSBundle mainBundle] pathForResource:  @"efi-virtio" ofType: @"rom"] stringByDeletingLastPathComponent];
    NSLog(@"path to rsrc: %@\n", path);
    chdir([path UTF8String]);
    
    extern int xmain(int argc, char ** argv, char **envp);
    char *qargs1[] = {
        "yolo",
        "-M", "virt-2.6",
        "-cpu", "cortex-a57",
        "-m", "512M",
        "-kernel", "linux",
        "-append", "earlycon=pl011,0x9000000 console=ttyAMA0 lpj=9999",
        "-serial", "mon:stdio",
        "-display", "iphone",
        "-smp", "1",
    };
    
    char *qargs[] = {
        "yolo",
        "-M", "versatilepb",
        "-cpu", "arm1176",
        "-m", "256M",
        "-append", "console=ttyAMA0 console=fb0 root=/dev/sda2 rootwait",
        "-kernel", "kernel-qemu",
        "-dtb", "versatile-pb.dtb",
        "-serial", "mon:stdio",
        "-display", "iphone",
        //"-nographic"
    };
    
    char *qargs_x86[] = {
        "yolo",
        "-m", "256M",
        "-cdrom", "kolibri.iso",
        "-serial", "mon:stdio",
        "-display", "iphone",
        "-vga", "std",
        //"-nographic"
    };
    int qargc = sizeof(qargs) / sizeof(qargs[0]);
    int x = xmain(qargc, qargs, 0);
    printf("%s: xmain returns %d\n", __func__, x);
}

int main(int argc, char * argv[]) {
    runQemu();
}
