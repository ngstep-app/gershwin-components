include $(GNUSTEP_MAKEFILES)/common.make

TOOL_NAME = pkgwrap

pkgwrap_OBJC_FILES = \
	pkgwrap.m \
	PWPackageManager.m \
	PWBundleAssembler.m \
	PWLauncherGenerator.m \
	../appwrap/DesktopFileParser.m \
	../appwrap/GWBundleCreator.m \
	../appwrap/GWDocumentIcon.m \
	../appwrap/GWUtils.m

GNUSTEP_INSTALLATION_DOMAIN = SYSTEM
pkgwrap_INSTALL_DIR = $(GNUSTEP_SYSTEM_TOOLS)

CC ?= $(shell command -v clang19 2>/dev/null || command -v clang 2>/dev/null || echo cc)
ADDITIONAL_OBJCFLAGS += -I../appwrap -Wall -Wextra -Werror -O2
ADDITIONAL_LDFLAGS += -lgnustep-base -lgnustep-gui

-include GNUmakefile.preamble

include $(GNUSTEP_MAKEFILES)/tool.make

-include GNUmakefile.postamble
