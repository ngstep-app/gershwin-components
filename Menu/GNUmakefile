include $(GNUSTEP_MAKEFILES)/common.make

PACKAGE_NAME = Menu
VERSION = 1.0
APP_NAME = Menu

# App info
Menu_APPLICATION_ICON = Menu.png
Menu_PRINCIPAL_CLASS = MenuApplication

# Source files
Menu_OBJC_FILES = \
	main.m \
	MenuApplication.m \
	MenuController.m \
	MenuBarView.m \
	AppMenuWidget.m \
	MenuProtocolManager.m \
	DBusMenuImporter.m \
	GTKMenuImporter.m \
	DBusMenuParser.m \
	GTKMenuParser.m \
	DBusMenuShortcutParser.m \
	DBusMenuActionHandler.m \
	GTKActionHandler.m \
	DBusSubmenuManager.m \
	GTKSubmenuManager.m \
	DBusConnection.m \
	MenuUtils.m \
	X11ShortcutManager.m \
	RoundedCornersView.m \
	MenuCacheManager.m

# Header files
Menu_HEADER_FILES = \
	MenuApplication.h \
	MenuController.h \
	MenuBarView.h \
	AppMenuWidget.h \
	MenuProtocolManager.h \
	DBusMenuImporter.h \
	GTKMenuImporter.h \
	DBusMenuParser.h \
	GTKMenuParser.h \
	DBusMenuShortcutParser.h \
	DBusMenuActionHandler.h \
	GTKActionHandler.h \
	DBusSubmenuManager.h \
	GTKSubmenuManager.h \
	DBusConnection.h \
	MenuUtils.h \
	X11ShortcutManager.h \
	RoundedCornersView.h \
	MenuCacheManager.h

# Resources
Menu_RESOURCE_FILES = \
	Menu.png \
	Info.plist


# Libraries and frameworks
Menu_TOOL_LIBS += -ldbus-1 -lX11
Menu_GUI_LIBS += -L/System/Library/Libraries -lgnustep-gui -lgnustep-base -lobjc
Menu_LDFLAGS += -Wl,--export-dynamic -L/System/Library/Libraries -Wl,-rpath,/System/Library/Libraries -Wl,--no-as-needed

# Compiler flags - Force use of /System GNUstep and objc2 with ARC
ADDITIONAL_OBJCFLAGS = -Wall -Wextra -O2 -I/System/Library/Headers -fobjc-runtime=gnustep-2.0 -fobjc-arc -Wno-unused-parameter
ADDITIONAL_CPPFLAGS = -I/usr/include/dbus-1.0 -I/usr/lib/x86_64-linux-gnu/dbus-1.0/include -I/System/Library/Headers

INSTALL_APPS_DIR = $(GNUSTEP_SYSTEM_APPS)

include $(GNUSTEP_MAKEFILES)/application.make

# Custom install target that completely overrides built-in behavior
.PHONY: custom-install custom-uninstall

install:: custom-install

custom-install: $(APP_NAME).app
	@if [ -n "$(DESTDIR)" ]; then \
		echo "Installing $(APP_NAME) to $(DESTDIR)$(INSTALL_APPS_DIR)"; \
		mkdir -p $(DESTDIR)$(INSTALL_APPS_DIR); \
		cp -R $(APP_NAME).app $(DESTDIR)$(INSTALL_APPS_DIR)/; \
		mkdir -p $(DESTDIR)$(INSTALL_APPS_DIR)/$(APP_NAME).app/Resources; \
		cp Menu.png $(DESTDIR)$(INSTALL_APPS_DIR)/$(APP_NAME).app/Resources/; \
	else \
		echo "Installing $(APP_NAME) to $(INSTALL_APPS_DIR)"; \
		sudo -A mkdir -p $(INSTALL_APPS_DIR); \
		sudo -A cp -R $(APP_NAME).app $(INSTALL_APPS_DIR)/; \
		sudo -A mkdir -p $(INSTALL_APPS_DIR)/$(APP_NAME).app/Resources; \
		sudo -A cp Menu.png $(INSTALL_APPS_DIR)/$(APP_NAME).app/Resources/; \
	fi

# Override uninstall target to properly support DESTDIR and PREFIX
uninstall:: custom-uninstall

custom-uninstall:
	@if [ -n "$(DESTDIR)" ]; then \
		echo "Uninstalling $(APP_NAME) from $(DESTDIR)$(INSTALL_APPS_DIR)"; \
		rm -rf $(DESTDIR)$(INSTALL_APPS_DIR)/$(APP_NAME).app; \
	else \
		echo "Uninstalling $(APP_NAME) from $(INSTALL_APPS_DIR)"; \
		sudo -A rm -rf $(INSTALL_APPS_DIR)/$(APP_NAME).app; \
	fi
