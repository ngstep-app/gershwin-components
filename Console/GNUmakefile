# Copyright (c) 2026 Simon Peter
#
# SPDX-License-Identifier: BSD-2-Clause

include $(GNUSTEP_MAKEFILES)/common.make

APP_NAME = Console
VERSION = 1.0

Console_OBJC_FILES = \
	main.m \
	LogEntry.m \
	LogQuery.m \
	LogSource.m \
	ConsoleController.m

Console_HEADERS = \
	LogEntry.h \
	LogQuery.h \
	LogSource.h \
	ConsoleController.h

Console_RESOURCE_FILES = \
	Resources/Console.gorm

Console_MAIN_MODEL_FILE = Console.gorm

Console_APPLICATION_ICON = Console.icns

Console_OBJCFLAGS = -Wall -O2
Console_LDFLAGS = -lgnustep-base -lgnustep-gui -Wl,-rpath,/System/Library/Libraries

ADDITIONAL_OBJCFLAGS += -Wno-import

include $(GNUSTEP_MAKEFILES)/application.make
