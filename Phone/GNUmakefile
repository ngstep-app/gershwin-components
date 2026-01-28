include $(GNUSTEP_MAKEFILES)/common.make

APP_NAME = Phone

Phone_OBJC_FILES = \
	main.m \
	AppDelegate.m \
	MainWindowController.m \
	PreferencesController.m \
	SIPManager.m

ADDITIONAL_OBJCFLAGS = -fobjc-arc -I/usr/local/include
ADDITIONAL_GUI_LIBS += /usr/local/lib/libbaresip.a /usr/local/lib/libre.a -lresolv -lm -ldl -lz -lssl -lcrypto -lpthread -lpng -lasound -lX11 -lportaudio -ljack -ldispatch -lgtk-3 -lgdk-3 -lpangocairo-1.0 -lpango-1.0 -lharfbuzz -latk-1.0 -lcairo-gobject -lcairo -lgdk_pixbuf-2.0 -lgio-2.0 -lgobject-2.0 -lglib-2.0 -lXext

include $(GNUSTEP_MAKEFILES)/application.make
