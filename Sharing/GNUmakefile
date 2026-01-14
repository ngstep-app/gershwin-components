include $(GNUSTEP_MAKEFILES)/common.make

BUNDLE_NAME = Sharing

Sharing_OBJC_FILES = \
	SharingPane.m \
	SharingController.m

Sharing_RESOURCE_FILES = Sharing.png SharingInfo.plist
Sharing_BUNDLE_LIBS = -lPreferencePanes
Sharing_PRINCIPAL_CLASS = SharingPane

# For network operations
Sharing_LDFLAGS = -ldl

PREF_INSTALL_DIR = $(GNUSTEP_SYSTEM_LIBRARY)/Bundles
HELPER_INSTALL_DIR = $(GNUSTEP_SYSTEM_LIBRARY)/Tools
BUNDLE_EXTENSION = .prefPane

include $(GNUSTEP_MAKEFILES)/bundle.make

# Build the sharing-helper as a standalone C program (no GNUstep dependency)
# This allows it to run via sudo without needing GNUstep libraries in the path
HELPER_SRC = sharing-helper.c
HELPER_BIN = obj/sharing-helper

$(HELPER_BIN): $(HELPER_SRC)
	@mkdir -p obj
	$(CC) -O2 -Wall -o $@ $<

all:: $(HELPER_BIN)

clean::
	rm -f $(HELPER_BIN)

# Custom install target
.PHONY: custom-install custom-uninstall

install:: custom-install

custom-install: $(BUNDLE_NAME)$(BUNDLE_EXTENSION) $(HELPER_BIN)
	@if [ -n "$(DESTDIR)" ]; then \
		echo "Installing $(BUNDLE_NAME) to $(DESTDIR)$(PREF_INSTALL_DIR)"; \
		mkdir -p $(DESTDIR)$(PREF_INSTALL_DIR); \
		cp -R $(BUNDLE_NAME)$(BUNDLE_EXTENSION) $(DESTDIR)$(PREF_INSTALL_DIR)/; \
		echo "Installing sharing-helper to $(DESTDIR)$(HELPER_INSTALL_DIR)"; \
		mkdir -p $(DESTDIR)$(HELPER_INSTALL_DIR); \
		cp $(HELPER_BIN) $(DESTDIR)$(HELPER_INSTALL_DIR)/sharing-helper; \
		chmod 755 $(DESTDIR)$(HELPER_INSTALL_DIR)/sharing-helper; \
	else \
		echo "Installing $(BUNDLE_NAME) to $(PREF_INSTALL_DIR)"; \
		mkdir -p $(PREF_INSTALL_DIR); \
		cp -R $(BUNDLE_NAME)$(BUNDLE_EXTENSION) $(PREF_INSTALL_DIR)/; \
		echo "Installing sharing-helper to $(HELPER_INSTALL_DIR)"; \
		mkdir -p $(HELPER_INSTALL_DIR); \
		cp $(HELPER_BIN) $(HELPER_INSTALL_DIR)/sharing-helper; \
		chmod 755 $(HELPER_INSTALL_DIR)/sharing-helper; \
	fi

custom-uninstall:
	@if [ -n "$(DESTDIR)" ]; then \
		echo "Removing $(BUNDLE_NAME) from $(DESTDIR)$(PREF_INSTALL_DIR)"; \
		rm -rf $(DESTDIR)$(PREF_INSTALL_DIR)/$(BUNDLE_NAME)$(BUNDLE_EXTENSION); \
		echo "Removing sharing-helper from $(DESTDIR)$(HELPER_INSTALL_DIR)"; \
		rm -f $(DESTDIR)$(HELPER_INSTALL_DIR)/sharing-helper; \
	else \
		echo "Removing $(BUNDLE_NAME) from $(PREF_INSTALL_DIR)"; \
		rm -rf $(PREF_INSTALL_DIR)/$(BUNDLE_NAME)$(BUNDLE_EXTENSION); \
		echo "Removing sharing-helper from $(HELPER_INSTALL_DIR)"; \
		rm -f $(HELPER_INSTALL_DIR)/sharing-helper; \
	fi

uninstall:: custom-uninstall
