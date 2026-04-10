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

# Build the LD_PRELOAD redirect library (plain C shared library)
REDIRECT_SO = obj/pkgwrap-redirect.so
REDIRECT_INSTALL_DIR = /System/Library/pkgwrap

$(REDIRECT_SO): pkgwrap-redirect.c
	@mkdir -p obj
	$(CC) -shared -fPIC -O2 -Wall -o $@ $< -ldl

after-all:: $(REDIRECT_SO)

after-install:: $(REDIRECT_SO)
	@mkdir -p $(REDIRECT_INSTALL_DIR)
	cp $(REDIRECT_SO) $(REDIRECT_INSTALL_DIR)/pkgwrap-redirect.so

after-clean::
	rm -f $(REDIRECT_SO)

-include GNUmakefile.postamble
