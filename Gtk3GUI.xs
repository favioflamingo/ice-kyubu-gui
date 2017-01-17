#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include <zbar.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <errno.h>
#include <stdint.h>
#include <stdarg.h>
#include <stdbool.h>
#include <signal.h>
#include <X11/Xlib.h>
#include <X11/keysym.h>
#include <X11/extensions/XTest.h>

char qrcode[8192];
int qrcode_size;
zbar_processor_t *proc;

/*
 * this function converts BGR3/4 to an integer so we can force the image format
 */
uint32_t fourcc_parse (const char *format)
{
	uint32_t fourcc = 0;
	if(format) {
	int i;
	for(i = 0; i < 4 && format[i]; i++)
	fourcc |= ((uint32_t)format[i]) << (i * 8);
	}
	return(fourcc);
}
/*
 * Basically, once a qr code is scanned, fake key press alt+f4 to close the window.
 * Print the qrcode text out stdout.
 * 
 */
static void success_handler (zbar_image_t *image,
                        const void *userdata)
{
    /* extract results */
    const zbar_symbol_t *symbol = zbar_image_first_symbol(image);
    for(; symbol; symbol = zbar_symbol_next(symbol)) {
        /* do something useful with results */
        zbar_symbol_type_t typ = zbar_symbol_get_type(symbol);

        const char *data = zbar_symbol_get_data(symbol);

        qrcode_size = sprintf(qrcode,"%s\n", data);
        write(1,qrcode,qrcode_size);
        
        //fflush(stdout);
        Display *display;
        unsigned int keycode[2];
        display = XOpenDisplay(NULL);
        // XK_Alt_L XK_F4 XK_Pause
        keycode[0] = XKeysymToKeycode(display,  XK_Alt_L);
        keycode[1] = XKeysymToKeycode(display,  XK_F4);
        XTestFakeKeyEvent(display, keycode[0], True, 0);
        XTestFakeKeyEvent(display, keycode[1], True, 0);
        XTestFakeKeyEvent(display, keycode[0], False, 0);
        XTestFakeKeyEvent(display, keycode[1], False, 0);
        XFlush(display);
    }
}

int getqrcode (int seconds)
{
    const uint8_t *device = "/dev/video0";

    zbar_increase_verbosity();
    zbar_set_verbosity(7);

    /* create a Processor */
    proc = zbar_processor_create(1);

    /* prescale the window */
    zbar_processor_request_size(proc, 320, 240);

    /* configure the Processor */
    zbar_processor_set_config(proc, 0, ZBAR_CFG_ENABLE, 1);

    fprintf(stderr,"gtk3zbar-part 1\n");
    /*
     * Force the format, for some reason, negotiation does not work.
     */
    const char *infmt = "BGR4";
    const char *outfmt = "BGR3";
    zbar_processor_force_format(proc,fourcc_parse(infmt),fourcc_parse(outfmt));
    fprintf(stderr,"gtk3zbar-part 2\n");
    /* initialize the Processor */
    zbar_processor_init(proc, device, 1);
    fprintf(stderr,"gtk3zbar-part 3\n");
    /* setup a callback */
    zbar_processor_set_data_handler(proc, success_handler, NULL);

    /* enable the preview window */
    zbar_processor_set_visible(proc, 1);
    zbar_processor_set_active(proc, 1);
    fprintf(stderr,"gtk3zbar-part 4\n");
    /* keep scanning until user provides key/mouse input */
    //zbar_process_one(proc,seconds*1000);
    zbar_processor_user_wait(proc,seconds*1000);

    /* clean up */
    zbar_processor_destroy(proc);
    fprintf(stderr,"gtk3zbar-part 5\n");
    
    return 0;
}


MODULE = Kgc::Client::Gtk3GUI PACKAGE = Kgc::Client::Gtk3GUI
		
		
PROTOTYPES: DISABLED


int
getqrcode (seconds)
	int	seconds