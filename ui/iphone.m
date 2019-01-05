/*
 * QEMU Cocoa CG display driver
 *
 * Copyright (c) 2008 Mike Kronenberg
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
 * THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

#include "qemu/osdep.h"

#include "qemu-common.h"
#include "ui/console.h"
#include "ui/input.h"
#include "sysemu/sysemu.h"
#include "qapi/error.h"
#include "qapi/qapi-commands.h"
#include "sysemu/blockdev.h"
#include "qemu-version.h"
#include "qom/cpu.h"

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

extern int qemu_main (int argc, const char * argv[], void *envp);

#define UIApp [UIApplication sharedApplication]

//#define DEBUG

#ifdef DEBUG
#define IPHONE_DEBUG(...)  { (void) fprintf (stdout, __VA_ARGS__); }
#else
#define IPHONE_DEBUG(...)  ((void) 0)
#endif

#define cgrect(nsrect) (*(CGRect *)&(nsrect))

typedef struct {
    int width;
    int height;
    int bitsPerComponent;
    int bitsPerPixel;
} QEMUScreen;

UIWindow *normalWindow;
static DisplayChangeListener *dcl;
static int stretch_video;

int gArgc;
const char **gArgv;

/*
 ------------------------------------------------------
    QemuCocoaView
 ------------------------------------------------------
*/
@interface QemuCocoaView : UIView
{
    QEMUScreen screen;
    UIWindow *fullScreenWindow;
    float cx,cy,cw,ch,cdx,cdy;
    CGDataProviderRef dataProviderRef;
    BOOL isMouseGrabbed;
    BOOL isFullscreen;
    BOOL isAbsoluteEnabled;
    BOOL isMouseDeassociated;
}
- (void) switchSurface:(DisplaySurface *)surface;
- (float) cdx;
- (float) cdy;
- (QEMUScreen) gscreen;
@end

QemuCocoaView *iphoneView;

@implementation QemuCocoaView
- (id)initWithFrame:(CGRect)frameRect
{
    IPHONE_DEBUG("QemuCocoaView: initWithFrame\n");

    self = [super initWithFrame:frameRect];
    if (self) {

        screen.bitsPerComponent = 8;
        screen.bitsPerPixel = 32;
        screen.width = frameRect.size.width;
        screen.height = frameRect.size.height;

    }
    return self;
}

- (void) dealloc
{
    IPHONE_DEBUG("QemuCocoaView: dealloc\n");

    if (dataProviderRef)
        CGDataProviderRelease(dataProviderRef);

    [super dealloc];
}

- (BOOL) isOpaque
{
    return YES;
}

- (BOOL) screenContainsPoint:(CGPoint) p
{
    return (p.x > -1 && p.x < screen.width && p.y > -1 && p.y < screen.height);
}

- (void) drawRect:(CGRect) rect
{
    IPHONE_DEBUG("QemuCocoaView: drawRect\n");

    // get CoreGraphic context
    //CGContextRef viewContextRef = [[UIGraphicsContext currentContext] graphicsPort];
	CGContextRef viewContextRef = UIGraphicsGetCurrentContext();
    CGContextSetInterpolationQuality (viewContextRef, kCGInterpolationNone);
    CGContextSetShouldAntialias (viewContextRef, NO);

    // draw screen bitmap directly to Core Graphics context
    if (!dataProviderRef) {
        // Draw request before any guest device has set up a framebuffer:
        // just draw an opaque black rectangle
        CGContextSetRGBFillColor(viewContextRef, 0, 0, 1.0, 1.0);
        CGContextFillRect(viewContextRef, rect);
    } else {
        CGImageRef imageRef = CGImageCreate(
            screen.width, //width
            screen.height, //height
            screen.bitsPerComponent, //bitsPerComponent
            screen.bitsPerPixel, //bitsPerPixel
            (screen.width * (screen.bitsPerComponent/2)), //bytesPerRow
            CGColorSpaceCreateWithName(kCGColorSpaceGenericRGB), //colorspace for OS X >= 10.4
            kCGBitmapByteOrder32Little | kCGImageAlphaNoneSkipFirst,
            dataProviderRef, //provider
            NULL, //decode
            0, //interpolate
            kCGRenderingIntentDefault //intent
        );
		UIGraphicsPushContext(viewContextRef);
		CGContextScaleCTM(viewContextRef, 1.0, -1.0);
		CGContextTranslateCTM(viewContextRef, 0, -rect.size.height);
		CGContextDrawImage (viewContextRef, rect, imageRef);
		UIGraphicsPopContext();
        CGImageRelease (imageRef);
    }
}

- (void) setContentDimensions
{
    IPHONE_DEBUG("QemuCocoaView: setContentDimensions\n");

    if (isFullscreen) {
        cdx = [[UIScreen mainScreen] bounds].size.width / (float)screen.width;
        cdy = [[UIScreen mainScreen] bounds].size.height / (float)screen.height;

        /* stretches video, but keeps same aspect ratio */
        if (stretch_video == true) {
            /* use smallest stretch value - prevents clipping on sides */
            if (MIN(cdx, cdy) == cdx) {
                cdy = cdx;
            } else {
                cdx = cdy;
            }
        } else {  /* No stretching */
            cdx = cdy = 1;
        }
        cw = screen.width * cdx;
        ch = screen.height * cdy;
        cx = ([[UIScreen mainScreen] bounds].size.width - cw) / 2.0;
        cy = ([[UIScreen mainScreen] bounds].size.height - ch) / 2.0;
    } else {
        cx = 0;
        cy = 0;
        cw = screen.width;
        ch = screen.height;
        cdx = 1.0;
        cdy = 1.0;
    }
}

- (void) switchSurface:(DisplaySurface *)surface
{
    IPHONE_DEBUG("QemuCocoaView: switchSurface\n");

    int w = surface_width(surface);
    int h = surface_height(surface);
    /* cdx == 0 means this is our very first surface, in which case we need
     * to recalculate the content dimensions even if it happens to be the size
     * of the initial empty window.
     */
    bool isResize = (w != screen.width || h != screen.height || cdx == 0.0);

    if (isResize) {
        // Resize before we trigger the redraw, or we'll redraw at the wrong size
        IPHONE_DEBUG("switchSurface: new size %d x %d\n", w, h);
        screen.width = w;
        screen.height = h;
        [self setContentDimensions];
        //[self setFrame:CGRectMake(cx, cy, cw, ch)];
    }

    // update screenBuffer
    if (dataProviderRef)
        CGDataProviderRelease(dataProviderRef);

    //sync host window color space with guests
    screen.bitsPerPixel = surface_bits_per_pixel(surface);
    screen.bitsPerComponent = surface_bytes_per_pixel(surface) * 2;

    dataProviderRef = CGDataProviderCreateWithData(NULL, surface_data(surface), w * 4 * h, NULL);
}

- (void) toggleFullScreen:(id)sender
{
    IPHONE_DEBUG("QemuCocoaView: toggleFullScreen\n");
}

- (void) setAbsoluteEnabled:(BOOL)tIsAbsoluteEnabled {isAbsoluteEnabled = tIsAbsoluteEnabled;}
- (BOOL) isMouseGrabbed {return isMouseGrabbed;}
- (BOOL) isAbsoluteEnabled {return isAbsoluteEnabled;}
- (BOOL) isMouseDeassociated {return isMouseDeassociated;}
- (float) cdx {return cdx;}
- (float) cdy {return cdy;}
- (QEMUScreen) gscreen {return screen;}

@end



/*
 ------------------------------------------------------
    QemuCocoaAppDelegate
 ------------------------------------------------------
*/
@interface QemuCocoaAppDelegate : UIResponder <UIApplicationDelegate>
{
}
@property (strong, nonatomic) UIWindow *window;
- (void)startEmulationWithArgc:(int)argc argv:(char**)argv;
@end

@implementation QemuCocoaAppDelegate
- (id) init
{
    IPHONE_DEBUG("QemuCocoaAppDelegate: init\n");

    self = [super init];

    return self;
}

- (void) dealloc
{
    IPHONE_DEBUG("QemuCocoaAppDelegate: dealloc\n");

    if (iphoneView)
        [iphoneView release];
    [super dealloc];
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // Override point for customization after application launch.
    IPHONE_DEBUG("QemuCocoaAppDelegate: applicationDidFinishLaunching\n");

	if (self) {

        // create a view and add it to the window
        iphoneView = [[QemuCocoaView alloc] initWithFrame:CGRectMake(0.0, 0.0, 640.0, 480.0)];
        if(!iphoneView) {
            fprintf(stderr, "(iphone) can't create a view\n");
            exit(1);
        }

        // create a window
        normalWindow = [UIWindow alloc];
		normalWindow = [normalWindow initWithFrame:[[UIScreen mainScreen] bounds]];
		self.window = normalWindow;

        if(!normalWindow) {
            fprintf(stderr, "(iphone) can't create window\n");
            exit(1);
        }
		UIViewController *controller = [[UIViewController alloc] init]; 
		normalWindow.rootViewController = controller;
		controller.view.backgroundColor = UIColor.blackColor;
		[controller.view addSubview:iphoneView];
		[normalWindow makeKeyAndVisible];
    }

    // launch QEMU, with the global args
    [self startEmulationWithArgc:gArgc argv:(char **)gArgv];
    return YES;
}


- (void)applicationWillResignActive:(UIApplication *)application {
}


- (void)applicationDidEnterBackground:(UIApplication *)application {
}


- (void)applicationWillEnterForeground:(UIApplication *)application {
}


- (void)applicationDidBecomeActive:(UIApplication *)application {
}

- (void)applicationWillTerminate:(UIApplication *)application {
    IPHONE_DEBUG("QemuCocoaAppDelegate: applicationWillTerminate\n");

    qemu_system_shutdown_request(SHUTDOWN_CAUSE_HOST_UI);
    exit(0);
}

- (void)qemuThread
{
	@autoreleasepool {
		int status;
		status = qemu_main(gArgc, gArgv, NULL);
		exit(status);
	}
}

- (void)startEmulationWithArgc:(int)argc argv:(char**)argv
{
    IPHONE_DEBUG("QemuCocoaAppDelegate: startEmulationWithArgc\n");
	[self performSelectorInBackground:@selector(qemuThread) withObject:self];
}
@end


static void register_iphone(void);
int xmain (int argc, const char * argv[]) {

    gArgc = argc;
    gArgv = argv;
    int i;

	register_iphone();
	@autoreleasepool {
    	return UIApplicationMain(argc, argv, nil, NSStringFromClass([QemuCocoaAppDelegate class]));
    }

    return 0;
}



#pragma mark qemu
static void iphone_update(DisplayChangeListener *dcl,
                         int x, int y, int w, int h)
{
	dispatch_queue_t main = dispatch_get_main_queue();
	dispatch_sync(main, ^{

		NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];

		IPHONE_DEBUG("qemu_iphone: iphone_update\n");

		CGRect rect;
		if ([iphoneView cdx] == 1.0) {
			rect = CGRectMake(x, [iphoneView gscreen].height - y - h, w, h);
		} else {
			rect = CGRectMake(
				x * [iphoneView cdx],
				([iphoneView gscreen].height - y - h) * [iphoneView cdy],
				w * [iphoneView cdx],
				h * [iphoneView cdy]);
		}
		[iphoneView setNeedsDisplayInRect:rect];

		[pool release];
	});
}

static void iphone_switch(DisplayChangeListener *dcl,
                         DisplaySurface *surface)
{
	NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
	IPHONE_DEBUG("qemu_iphone: iphone_switch\n");
	[iphoneView switchSurface:surface];
	[pool release];
}

static void iphone_refresh(DisplayChangeListener *dcl)
{
	graphic_hw_update(NULL);
}

static void iphone_cleanup(void)
{
    IPHONE_DEBUG("qemu_iphone: iphone_cleanup\n");
    g_free(dcl);
}

static const DisplayChangeListenerOps dcl_ops = {
    .dpy_name          = "iphone",
    .dpy_gfx_update = iphone_update,
    .dpy_gfx_switch = iphone_switch,
    .dpy_refresh = iphone_refresh,
};

static void iphone_display_init(DisplayState *ds, DisplayOptions *opts)
{
    IPHONE_DEBUG("qemu_iphone: iphone_display_init\n");

    dcl = g_malloc0(sizeof(DisplayChangeListener));

    // register vga output callbacks
    dcl->ops = &dcl_ops;
    register_displaychangelistener(dcl);

    // register cleanup function
    atexit(iphone_cleanup);
}

static QemuDisplay qemu_display_iphone = {
    .type       = DISPLAY_TYPE_IPHONE,
    .init       = iphone_display_init,
};

static void register_iphone(void)
{
    qemu_display_register(&qemu_display_iphone);
}

type_init(register_iphone);
