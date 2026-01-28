include $(GNUSTEP_MAKEFILES)/common.make

TOOL_NAME = UIBridgeServer
ADDITIONAL_LDFLAGS += -L../Agent/obj -Wl,-rpath,/usr/lib/aarch64-linux-gnu:/lib/aarch64-linux-gnu:'$$ORIGIN/../../Agent/obj' -lX11 -lXext
UIBridgeServer_OBJC_FILES = main.m X11Support.m LLDBController.m
UIBridgeServer_LIBRARIES = gnustep-base gnustep-gui objc

include $(GNUSTEP_MAKEFILES)/tool.make

# Install configuration
PREFIX ?= /
# Install configuration
# Prefer the GNUstep configured Tools directory when available; fall back to the conventional system location
BINDIR ?= $(GNUSTEP_SYSTEM_TOOLS)
ifeq ($(BINDIR),)
BINDIR := /System/Library/Tools
endif
LIBDIR ?= /usr/lib

after-install::
	mkdir -p $(DESTDIR)$(BINDIR)
	install -m 0755 obj/UIBridgeServer $(DESTDIR)$(BINDIR)/UIBridgeServer

after-uninstall::
	 rm -f $(DESTDIR)$(BINDIR)/UIBridgeServer
