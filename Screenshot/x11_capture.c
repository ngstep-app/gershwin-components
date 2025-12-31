/*
 * Copyright (c) 2025 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */


 #include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <time.h>
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <X11/Xatom.h>
#include <X11/cursorfont.h>

// Global variables
static Display *disp = NULL;
static Window root;
static Screen *scr = NULL;
static int x11_error_occurred = 0;

// X11 Error Handler
static int x11_error_handler(Display *display, XErrorEvent *error) {
    char error_text[256];
    XGetErrorText(display, error->error_code, error_text, sizeof(error_text));
    fprintf(stderr, "X11 Error: %s (error_code=%d, request_code=%d)\n",
            error_text, error->error_code, error->request_code);
    x11_error_occurred = 1;
    return 0;
}

typedef enum {
    CaptureWindow,
    CaptureArea,
    CaptureFullScreen
} CaptureMode;

typedef struct {
    int x, y, width, height;
} CaptureRect;

int x11_init(void) {
    disp = XOpenDisplay(NULL);
    if (!disp) {
        return 0;
    }
    
    // Install error handler
    XSetErrorHandler(x11_error_handler);
    x11_error_occurred = 0;
    
    scr = ScreenOfDisplay(disp, DefaultScreen(disp));
    root = RootWindow(disp, DefaultScreen(disp));
    
    return 1;
}

void x11_cleanup(void) {
    if (disp) {
        XCloseDisplay(disp);
        disp = NULL;
    }
}

// Get window at pointer position
Window get_window_at_pointer(Display *display, Window root_window) {
    if (!display || !root_window) {
        return 0;
    }
    
    Window root_return, child_return;
    int root_x, root_y, win_x, win_y;
    unsigned int mask_return;
    
    // Reset error flag
    x11_error_occurred = 0;
    
    // Get pointer position
    if (!XQueryPointer(display, root_window, &root_return, &child_return,
                      &root_x, &root_y, &win_x, &win_y, &mask_return)) {
        fprintf(stderr, "XQueryPointer failed\n");
        return root_window;
    }
    
    // Check for errors
    XSync(display, False);
    if (x11_error_occurred) {
        fprintf(stderr, "X11 error in XQueryPointer\n");
        return root_window;
    }
    
    if (child_return == None) {
        return root_window;
    }
    
    // Traverse to find actual window
    Window target = child_return;
    while (1) {
        if (!XQueryPointer(display, target, &root_return, &child_return,
                          &root_x, &root_y, &win_x, &win_y, &mask_return)) {
            break;
        }
        
        // Check for errors
        XSync(display, False);
        if (x11_error_occurred) {
            break;
        }
        
        if (child_return == None) {
            break;
        }
        target = child_return;
    }
    
    return target;
}

// Select a window interactively
Window select_window_interactive(Display *display, Window root_window) {
    if (!display || !root_window) {
        fprintf(stderr, "Invalid display or window\n");
        return 0;
    }
    
    x11_error_occurred = 0;
    
    Cursor cursor = XCreateFontCursor(display, XC_crosshair);
    if (!cursor) {
        fprintf(stderr, "Failed to create cursor\n");
        return 0;
    }
    
    // Flush any pending events
    XSync(display, False);
    
    fprintf(stderr, "Attempting pointer grab with ButtonPressMask | KeyPressMask\n");
    int status = XGrabPointer(display, root_window, False,
                             ButtonPressMask | KeyPressMask,
                             GrabModeAsync, GrabModeAsync, root_window, cursor, CurrentTime);
    
    if (status != GrabSuccess) {
        fprintf(stderr, "Failed to grab pointer: status=%d\n", status);
        XFreeCursor(display, cursor);
        return 0;
    }
    
    fprintf(stderr, "Pointer grab succeeded, attempting keyboard grab\n");
    // Grab keyboard to capture ESC key (but this can fail without causing issues)
    int kbd_status = XGrabKeyboard(display, root_window, False, GrabModeAsync, GrabModeAsync, CurrentTime);
    if (kbd_status != GrabSuccess) {
        fprintf(stderr, "Warning: Failed to grab keyboard: status=%d (continuing anyway)\n", kbd_status);
    } else {
        fprintf(stderr, "Keyboard grab succeeded\n");
    }
    
    XSync(display, False);  // Ensure all requests are processed
    
    XEvent event;
    Window target = 0;
    
    while (1) {
        if (XPending(display) == 0) {
            usleep(10000); // 10ms sleep to prevent busy waiting
            continue;
        }
        
        XNextEvent(display, &event);
        
        if (x11_error_occurred) {
            fprintf(stderr, "X11 error occurred during window selection\n");
            target = 0;
            break;
        }
        
        if (event.type == KeyPress) {
            // Check if ESC key was pressed
            KeySym keysym = XLookupKeysym(&event.xkey, 0);
            if (keysym == XK_Escape) {
                // Cancel selection
                target = 0;
                break;
            }
        } else if (event.type == ButtonPress) {
            // Check if right mouse button (Button3) was pressed
            if (event.xbutton.button == Button3) {
                // Cancel selection
                target = 0;
                break;
            } else if (event.xbutton.button == Button1) {
                // Left click - proceed with selection
                target = event.xbutton.subwindow;
                if (target == None) {
                    target = root_window;
                } else {
                    target = get_window_at_pointer(display, root_window);
                }
                break;
            }
        }
    }
    
    if (kbd_status == GrabSuccess) {
        XUngrabKeyboard(display, CurrentTime);
    }
    XUngrabPointer(display, CurrentTime);
    XFreeCursor(display, cursor);
    XFlush(display);
    
    return target;
}

// Get window geometry
int get_window_rect(Display *display, Window window, CaptureRect *rect) {
    if (!display || !window || !rect) {
        fprintf(stderr, "Invalid parameters for get_window_rect\n");
        return 0;
    }
    
    // Reset error flag
    x11_error_occurred = 0;
    
    XWindowAttributes attrs;
    if (!XGetWindowAttributes(display, window, &attrs)) {
        fprintf(stderr, "Failed to get window attributes\n");
        return 0;
    }
    
    // Check for X11 errors after getting attributes
    XSync(display, False);
    if (x11_error_occurred) {
        fprintf(stderr, "X11 error while getting window attributes\n");
        return 0;
    }
    
    // Translate to root coordinates
    Window child;
    int root_x, root_y;
    XTranslateCoordinates(display, window, attrs.root, 0, 0, &root_x, &root_y, &child);
    
    // Check for X11 errors after translation
    XSync(display, False);
    if (x11_error_occurred) {
        fprintf(stderr, "X11 error while translating coordinates\n");
        return 0;
    }
    
    rect->x = root_x;
    rect->y = root_y;
    rect->width = attrs.width;
    rect->height = attrs.height;
    
    return 1;
}

// Select area interactively
int select_area_interactive(Display *display, Window root_window, CaptureRect *rect) {
    if (!display || !root_window || !rect) {
        fprintf(stderr, "Invalid parameters for area selection\n");
        return 0;
    }
    
    x11_error_occurred = 0;
    
    Cursor cursor = XCreateFontCursor(display, XC_crosshair);
    if (!cursor) {
        fprintf(stderr, "Failed to create cursor\n");
        return 0;
    }
    
    // Flush any pending events
    XSync(display, False);
    
    int status = XGrabPointer(display, root_window, False,
                             ButtonPressMask | ButtonReleaseMask | PointerMotionMask,
                             GrabModeAsync, GrabModeAsync, root_window, cursor, CurrentTime);
    
    if (status != GrabSuccess) {
        fprintf(stderr, "Failed to grab pointer: status=%d\n", status);
        XFreeCursor(display, cursor);
        return 0;
    }
    
    // Also grab keyboard to capture ESC key
    int kbd_status = XGrabKeyboard(display, root_window, False, GrabModeAsync, GrabModeAsync, CurrentTime);
    if (kbd_status != GrabSuccess) {
        fprintf(stderr, "Warning: Failed to grab keyboard\n");
    }
    
    // Create an override-redirect window for drawing the selection rectangle
    // This lets X11 handle the rectangle rendering properly
    XSetWindowAttributes attrs;
    attrs.override_redirect = True;
    
    // Create a semi-transparent blue color (RGB: 100, 149, 237 = cornflower blue)
    // Allocate the color
    XColor blue_color;
    Colormap colormap = DefaultColormap(display, DefaultScreen(display));
    blue_color.red = 0x6400;    // 100/255 * 65535
    blue_color.green = 0x9500;  // 149/255 * 65535
    blue_color.blue = 0xED00;   // 237/255 * 65535
    blue_color.flags = DoRed | DoGreen | DoBlue;
    XAllocColor(display, colormap, &blue_color);
    
    attrs.background_pixel = blue_color.pixel;
    attrs.border_pixel = WhitePixel(display, DefaultScreen(display));
    
    Window selection_window = XCreateWindow(display, root_window,
                                           0, 0, 1, 1, 2,
                                           CopyFromParent, InputOutput, CopyFromParent,
                                           CWOverrideRedirect | CWBackPixel | CWBorderPixel,
                                           &attrs);
    
    if (!selection_window) {
        fprintf(stderr, "Failed to create selection window\n");
        if (kbd_status == GrabSuccess) {
            XUngrabKeyboard(display, CurrentTime);
        }
        XUngrabPointer(display, CurrentTime);
        XFreeCursor(display, cursor);
        return 0;
    }
    
    // Set window opacity to 30% using _NET_WM_WINDOW_OPACITY property
    Atom opacity_atom = XInternAtom(display, "_NET_WM_WINDOW_OPACITY", False);
    if (opacity_atom != None) {
        unsigned long opacity = (unsigned long)(0.3 * 0xFFFFFFFF);  // 30% opacity
        XChangeProperty(display, selection_window, opacity_atom, XA_CARDINAL, 32,
                       PropModeReplace, (unsigned char *)&opacity, 1);
    }
    
    XEvent event;
    int start_x = 0, start_y = 0, end_x = 0, end_y = 0;
    int pressed = 0;
    int cancelled = 0;
    
    while (1) {
        if (XPending(display) == 0) {
            usleep(10000); // 10ms sleep
            continue;
        }
        
        XNextEvent(display, &event);
        
        if (x11_error_occurred) {
            fprintf(stderr, "X11 error occurred during area selection\n");
            cancelled = 1;
            break;
        }
        
        if (event.type == KeyPress) {
            // Check if ESC key was pressed
            KeySym keysym = XLookupKeysym(&event.xkey, 0);
            if (keysym == XK_Escape) {
                // Cancel selection
                cancelled = 1;
                break;
            }
        } else if (event.type == ButtonPress) {
            // Check if right mouse button (Button3) was pressed
            if (event.xbutton.button == Button3) {
                // Cancel selection
                cancelled = 1;
                break;
            } else if (event.xbutton.button == Button1) {
                // Left click - start selection
                start_x = event.xbutton.x_root;
                start_y = event.xbutton.y_root;
                pressed = 1;
            }
        } else if (event.type == MotionNotify && pressed) {
            // Update current position
            int current_x = event.xmotion.x_root;
            int current_y = event.xmotion.y_root;
            
            // Calculate rectangle bounds
            int rx = (start_x < current_x) ? start_x : current_x;
            int ry = (start_y < current_y) ? start_y : current_y;
            int rw = abs(current_x - start_x);
            int rh = abs(current_y - start_y);
            
            // Resize and reposition the selection window - X11 handles all drawing
            if (rw > 0 && rh > 0) {
                XMoveResizeWindow(display, selection_window, rx, ry, rw, rh);
                XMapRaised(display, selection_window);
            }
        } else if (event.type == ButtonRelease && pressed) {
            if (event.xbutton.button == Button1) {
                // Left button release - complete selection
                end_x = event.xbutton.x_root;
                end_y = event.xbutton.y_root;
                break;
            }
        }
    }
    
    // Hide and destroy the selection window
    XUnmapWindow(display, selection_window);
    XDestroyWindow(display, selection_window);
    XSync(display, False);
    // Brief delay to ensure window is fully destroyed before capture
    usleep(100000); // 100ms
    
    if (kbd_status == GrabSuccess) {
        XUngrabKeyboard(display, CurrentTime);
    }
    XUngrabPointer(display, CurrentTime);
    XFreeCursor(display, cursor);
    XSync(display, False);
    
    // If cancelled, return failure
    if (cancelled) {
        rect->x = 0;
        rect->y = 0;
        rect->width = 0;
        rect->height = 0;
        return 0;
    }
    
    // Calculate rectangle
    rect->x = (start_x < end_x) ? start_x : end_x;
    rect->y = (start_y < end_y) ? start_y : end_y;
    rect->width = abs(end_x - start_x);
    rect->height = abs(end_y - start_y);
    
    return 1;
}

// Capture screenshot data using X11
unsigned char* x11_capture_data(CaptureMode mode, int delay, CaptureRect* rect, 
                                  int* width, int* height, int* bytes_per_pixel) {
    if (!disp) {
        if (!x11_init()) {
            return NULL;
        }
    }
    
    // Apply delay if specified
    if (delay > 0) {
        sleep(delay);
    }
    
    CaptureRect capture_rect;
    
    switch (mode) {
        case CaptureFullScreen:
            capture_rect.x = 0;
            capture_rect.y = 0;
            capture_rect.width = scr->width;
            capture_rect.height = scr->height;
            break;
            
        case CaptureWindow:
            if (rect && rect->width > 0 && rect->height > 0) {
                capture_rect = *rect;
            } else {
                // Interactive window selection
                Window window = select_window_interactive(disp, root);
                if (!window || !get_window_rect(disp, window, &capture_rect)) {
                    return NULL;
                }
            }
            break;
            
        case CaptureArea:
            if (rect && rect->width > 0 && rect->height > 0) {
                capture_rect = *rect;
            } else {
                // Interactive area selection
                if (!select_area_interactive(disp, root, &capture_rect)) {
                    return NULL;
                }
            }
            break;
            
        default:
            return NULL;
    }
    
    // Ensure dimensions are valid
    if (capture_rect.width <= 0 || capture_rect.height <= 0) {
        return NULL;
    }
    
    // Capture the screen using XGetImage
    XImage *image = XGetImage(disp, root, capture_rect.x, capture_rect.y,
                              capture_rect.width, capture_rect.height,
                              AllPlanes, ZPixmap);
    
    if (!image) {
        return NULL;
    }
    
    // Convert XImage to RGBA format for GNUstep
    int w = image->width;
    int h = image->height;
    int bpp = 4; // RGBA
    
    unsigned char *data = malloc(w * h * bpp);
    if (!data) {
        XDestroyImage(image);
        return NULL;
    }
    
    // Get the visual information
    Visual *visual = DefaultVisual(disp, DefaultScreen(disp));
    int depth = DefaultDepth(disp, DefaultScreen(disp));
    
    fprintf(stderr, "Display depth: %d, byte_order: %d, bitmap_bit_order: %d\n", 
            depth, ImageByteOrder(disp), BitmapBitOrder(disp));
    fprintf(stderr, "Red mask: 0x%lx, Green mask: 0x%lx, Blue mask: 0x%lx\n",
            visual->red_mask, visual->green_mask, visual->blue_mask);
    
    // Calculate the number of bits to shift for proper 8-bit normalization
    int red_shift = 0, green_shift = 0, blue_shift = 0;
    int red_bits = 0, green_bits = 0, blue_bits = 0;
    unsigned long mask;
    
    // Find shift and bit count for red
    mask = visual->red_mask;
    while (mask && !(mask & 1)) { mask >>= 1; red_shift++; }
    while (mask & 1) { mask >>= 1; red_bits++; }
    
    // Find shift and bit count for green
    mask = visual->green_mask;
    while (mask && !(mask & 1)) { mask >>= 1; green_shift++; }
    while (mask & 1) { mask >>= 1; green_bits++; }
    
    // Find shift and bit count for blue
    mask = visual->blue_mask;
    while (mask && !(mask & 1)) { mask >>= 1; blue_shift++; }
    while (mask & 1) { mask >>= 1; blue_bits++; }
    
    fprintf(stderr, "Red: shift=%d bits=%d, Green: shift=%d bits=%d, Blue: shift=%d bits=%d\n",
            red_shift, red_bits, green_shift, green_bits, blue_shift, blue_bits);
    
    // Convert image data to RGBA
    for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
            unsigned long pixel = XGetPixel(image, x, y);
            int offset = (y * w + x) * bpp;
            
            // Extract and normalize RGB components
            unsigned long r_val = (pixel & visual->red_mask) >> red_shift;
            unsigned long g_val = (pixel & visual->green_mask) >> green_shift;
            unsigned long b_val = (pixel & visual->blue_mask) >> blue_shift;
            
            // Normalize to 8 bits (scale from red_bits/green_bits/blue_bits to 8 bits)
            if (red_bits < 8) {
                r_val = (r_val << (8 - red_bits)) | (r_val >> (2 * red_bits - 8));
            } else if (red_bits > 8) {
                r_val >>= (red_bits - 8);
            }
            
            if (green_bits < 8) {
                g_val = (g_val << (8 - green_bits)) | (g_val >> (2 * green_bits - 8));
            } else if (green_bits > 8) {
                g_val >>= (green_bits - 8);
            }
            
            if (blue_bits < 8) {
                b_val = (b_val << (8 - blue_bits)) | (b_val >> (2 * blue_bits - 8));
            } else if (blue_bits > 8) {
                b_val >>= (blue_bits - 8);
            }
            
            data[offset + 0] = (unsigned char)r_val;  // R
            data[offset + 1] = (unsigned char)g_val;  // G
            data[offset + 2] = (unsigned char)b_val;  // B
            data[offset + 3] = 0xFF;                  // A (fully opaque)
        }
    }
    
    *width = w;
    *height = h;
    *bytes_per_pixel = bpp;
    
    XDestroyImage(image);
    return data;
}

void x11_free_data(unsigned char* data) {
    if (data) {
        free(data);
    }
}

CaptureRect x11_select_window(void) {
    CaptureRect rect = {0, 0, 0, 0};
    
    if (!disp) {
        if (!x11_init()) {
            fprintf(stderr, "Failed to initialize X11\n");
            return rect;
        }
    }
    
    x11_error_occurred = 0;
    
    Window window = select_window_interactive(disp, root);
    
    // Check for errors or cancellation
    if (x11_error_occurred || window == 0) {
        fprintf(stderr, "Window selection failed or cancelled\n");
        return rect;  // Return zero rect
    }
    
    if (!get_window_rect(disp, window, &rect)) {
        fprintf(stderr, "Failed to get window geometry\n");
        rect.x = rect.y = rect.width = rect.height = 0;
    }
    
    return rect;
}

CaptureRect x11_select_area(void) {
    CaptureRect rect = {0, 0, 0, 0};
    
    if (!disp) {
        if (!x11_init()) {
            fprintf(stderr, "Failed to initialize X11\n");
            return rect;
        }
    }
    
    x11_error_occurred = 0;
    
    int result = select_area_interactive(disp, root, &rect);
    
    // Check for errors or cancellation
    if (x11_error_occurred || result == 0) {
        fprintf(stderr, "Area selection failed or cancelled\n");
        rect.x = rect.y = rect.width = rect.height = 0;
    }
    
    return rect;
}

char* x11_capture(CaptureMode mode, const char* filename, int delay, CaptureRect* rect) {
    // This function is kept for compatibility but not fully implemented
    // The actual image saving is done in Objective-C using GNUstep's NSImage
    return NULL;
}