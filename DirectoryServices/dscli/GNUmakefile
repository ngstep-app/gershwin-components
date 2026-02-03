include $(GNUSTEP_MAKEFILES)/common.make

TOOL_NAME = dscli

dscli_OBJC_FILES = \
	main.m \
	DSPlatform.m \
	DSPlatformFreeBSD.m \
	DSPlatformLinux.m

dscli_OBJCFLAGS = -fobjc-arc
dscli_LDFLAGS = -lcrypt -Wl,-rpath,$(GNUSTEP_SYSTEM_LIBRARIES)

# Install to /System/Library/Tools
GNUSTEP_INSTALLATION_DOMAIN = SYSTEM

include $(GNUSTEP_MAKEFILES)/tool.make
