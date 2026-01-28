include $(GNUSTEP_MAKEFILES)/common.make

LIBRARY_NAME = UIBridgeAgent

UIBridgeAgent_OBJC_FILES = UIBridgeAgent.m
UIBridgeAgent_HEADER_FILES = UIBridgeAgent.h
UIBridgeAgent_LIBRARIES = gnustep-base gnustep-gui

include $(GNUSTEP_MAKEFILES)/library.make

# Install configuration
PREFIX ?= /
# Prefer the GNUstep configured libraries directory when available; fall back to the conventional system location
LIBDIR ?= $(GNUSTEP_SYSTEM_LIBRARIES)
ifeq ($(LIBDIR),)
LIBDIR := /System/Library/Libraries
endif

after-install::
	mkdir -p $(DESTDIR)$(LIBDIR)
	install -m 0755 obj/libUIBridgeAgent.so $(DESTDIR)$(LIBDIR)/libUIBridgeAgent.so

after-uninstall::
	 rm -f $(DESTDIR)$(LIBDIR)/libUIBridgeAgent.so
