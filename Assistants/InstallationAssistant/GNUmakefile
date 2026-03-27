include $(GNUSTEP_MAKEFILES)/common.make

# Application configuration
APP_NAME = InstallationAssistant

# Source files
InstallationAssistant_OBJC_FILES = InstallationAssistant.m InstallationSteps.m

# Resource files
InstallationAssistant_RESOURCE_FILES = \
	Resources/en.lproj/Localizable.strings \
	Resources/de.lproj/Localizable.strings \
	Resources/installer-FreeBSD.sh \
	Resources/installer-Linux.sh

# Required frameworks and libraries - use GNUstep naming
InstallationAssistant_GUI_LIBS += -lgnustep-gui -lgnustep-base

# Compiler and linker flags - embed framework in bundle
InstallationAssistant_CPPFLAGS += -Wall -Wextra -Werror -O2 -I$(shell pwd)/../AssistantFramework/GSAssistantFramework.framework/Versions/1/Headers
InstallationAssistant_LDFLAGS += -L$(shell pwd)/../AssistantFramework/GSAssistantFramework.framework/Versions/1 -lGSAssistantFramework -Wl,-rpath,'$$ORIGIN/Frameworks/GSAssistantFramework.framework/Versions/1' -ldispatch

include $(GNUSTEP_MAKEFILES)/application.make

# Copy framework into app bundle after building
after-all::
	@echo "Copying GSAssistantFramework into app bundle..."
	@mkdir -p $(APP_NAME).app/Frameworks
	@cp -R ../AssistantFramework/GSAssistantFramework.framework $(APP_NAME).app/Frameworks/
	@echo "Framework embedded in $(APP_NAME).app/Frameworks/"
	@echo "Fixing localized resource structure..."
	@mkdir -p $(APP_NAME).app/Resources/en.lproj
	@mkdir -p $(APP_NAME).app/Resources/de.lproj
	@# Move any flattened Localizable.strings to proper .lproj directories
	@if [ -f $(APP_NAME).app/Resources/Localizable.strings ]; then \
		mv $(APP_NAME).app/Resources/Localizable.strings $(APP_NAME).app/Resources/en.lproj/; \
	fi
	@cp Resources/de.lproj/Localizable.strings $(APP_NAME).app/Resources/de.lproj/ 2>/dev/null || true
	@echo "Localized resource structure fixed"
	@echo "Making installer scripts executable..."
	@chmod +x $(APP_NAME).app/Resources/installer-FreeBSD.sh 2>/dev/null || true
	@chmod +x $(APP_NAME).app/Resources/installer-Linux.sh 2>/dev/null || true
	@echo "Installer scripts ready"

# Custom install target
.PHONY: custom-install custom-uninstall

install:: custom-install

custom-install: $(APP_NAME)$(EXEEXT)
	@if [ -n "$(DESTDIR)" ]; then \
		echo "Installing $(APP_NAME) to $(DESTDIR)$(GNUSTEP_SYSTEM_APPS)/Utilities"; \
		mkdir -p $(DESTDIR)$(GNUSTEP_SYSTEM_APPS)/Utilities; \
		rm -rf $(DESTDIR)$(GNUSTEP_SYSTEM_APPS)/Utilities/$(APP_NAME).app; \
		cp -R $(APP_NAME).app $(DESTDIR)$(GNUSTEP_SYSTEM_APPS)/Utilities/; \
	else \
		echo "Installing $(APP_NAME) to $(GNUSTEP_SYSTEM_APPS)/Utilities"; \
		mkdir -p $(GNUSTEP_SYSTEM_APPS)/Utilities; \
		rm -rf $(GNUSTEP_SYSTEM_APPS)/Utilities/$(APP_NAME).app; \
		cp -R $(APP_NAME).app $(GNUSTEP_SYSTEM_APPS)/Utilities/; \
	fi

# Override uninstall target to properly support DESTDIR
uninstall:: custom-uninstall

custom-uninstall:
	@if [ -n "$(DESTDIR)" ]; then \
		echo "Uninstalling $(APP_NAME) from $(DESTDIR)$(GNUSTEP_SYSTEM_APPS)/Utilities"; \
		rm -rf $(DESTDIR)$(GNUSTEP_SYSTEM_APPS)/Utilities/$(APP_NAME).app; \
	else \
		echo "Uninstalling $(APP_NAME) from $(GNUSTEP_SYSTEM_APPS)/Utilities"; \
		rm -rf $(GNUSTEP_SYSTEM_APPS)/Utilities/$(APP_NAME).app; \
	fi

# Override built-in install targets to do nothing
internal-application-install::

internal-application-uninstall::
