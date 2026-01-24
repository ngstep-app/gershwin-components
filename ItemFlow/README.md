# ItemFlow Framework

A view for GNUstep applications.

## Usage

To use this framework in your GNUstep application:

1. Add the framework to your `GNUmakefile`:

```makefile
# Include path to the framework headers
ADDITIONAL_OBJCFLAGS += -I/path/to/gershwin-components

# Link against the framework
ADDITIONAL_GUI_LIBS += -lItemFlow
ADDITIONAL_LIB_DIRS += -L/path/to/gershwin-components/ItemFlow/ItemFlow.framework

# Link against OpenGL
ADDITIONAL_LDFLAGS += -lGL -lGLU
```

2. Import the header in your code:

```objc
#import <ItemFlow/ItemFlow.h>
```

3. Ensure the framework is available at runtime (e.g., by bundling it or installing it to a system library path).

## Demo

See the `Demo` directory for a sample application.
