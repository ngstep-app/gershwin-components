include $(GNUSTEP_MAKEFILES)/common.make

TOOL_NAME = dshelper

dshelper_OBJC_FILES = \
	main.m \
	dshelper.m

dshelper_HEADER_FILES = \
	dshelper.h

dshelper_OBJCFLAGS = -fobjc-arc
dshelper_LDFLAGS = -lcrypt -ldispatch -lBlocksRuntime

# Install to /System/Library/Tools
GNUSTEP_INSTALLATION_DOMAIN = SYSTEM

include $(GNUSTEP_MAKEFILES)/tool.make

# Install sysvinit service script
after-install::
	@if [ -d /etc/init.d ]; then \
		$(INSTALL) -m 755 dshelper.init /etc/init.d/dshelper; \
		echo "Installed sysvinit script"; \
	else \
		echo "No /etc/init.d directory found, skipping service install"; \
	fi
