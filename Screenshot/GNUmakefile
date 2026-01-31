include $(GNUSTEP_MAKEFILES)/common.make

GNUSTEP_INSTALLATION_DOMAIN = SYSTEM

APP_NAME = Screenshot
PACKAGE_NAME = Screenshot
Screenshot_PRINCIPAL_CLASS = NSApplication
Screenshot_APPLICATION_ICON = Screenshot.png

#
# Resource files
#
Screenshot_RESOURCE_FILES = \
	Screenshot.png \
	Resources/Info.plist \
	Resources/Info-gnustep.plist

Screenshot_LOCALIZED_RESOURCE_FILES = \
	Localizable.strings

Screenshot_LANGUAGES = English

# Build-time generation of Info files
Resources/Info.plist: Info.plist | Resources
	$(ECHO_NOTHING)if [ -n "$(INSTALL_FILE)" ]; then $(INSTALL_FILE) $< $@; else cp $< $@; fi$(END_ECHO)

Resources/Info-gnustep.plist: Resources/Info.plist
	$(ECHO_NOTHING)if command -v plmerge >/dev/null 2>&1; then \
	  plmerge $< "$(GNUSTEP_PLIST_DEPEND)" > $@; \
	else \
	  cp $< $@; \
	fi$(END_ECHO)

#
# Source
#
Screenshot_HEADER_FILES = \
	ScreenshotController.h \
	ScreenshotCapture.h

Screenshot_OBJC_FILES = \
	ScreenshotController.m \
	ScreenshotCapture.m

Screenshot_C_FILES = \
	x11_capture.c

Screenshot_OBJC_FILES += Screenshot_main.m

# Link with required libraries
Screenshot_GUI_LIBS += -lX11

-include GNUmakefile.preamble

include $(GNUSTEP_MAKEFILES)/application.make

# Ensure Info.plist is copied into the built app and Info-gnustep is generated from it
# Make 'all' depend on copying/generation so it happens during normal builds
all:: copy-info

copy-info: $(APP_NAME).app
	$(ECHO_NOTHING)if [ -n "$(INSTALL_FILE)" ]; then $(INSTALL_FILE) Info.plist $(APP_NAME).app/Resources/Info.plist; else cp Info.plist $(APP_NAME).app/Resources/Info.plist; fi$(END_ECHO)
	$(ECHO_NOTHING)if command -v plmerge >/dev/null 2>&1; then \
	  plmerge $(APP_NAME).app/Resources/Info-gnustep.plist Info.plist "$(GNUSTEP_PLIST_DEPEND)"; \
	fi$(END_ECHO)

-include GNUmakefile.postamble