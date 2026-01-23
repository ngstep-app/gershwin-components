/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "ItemFlowView.h"
#import <AppKit/NSOpenGL.h>
#import <GL/gl.h>
#import <math.h>

// Configuration Constants
#define COVER_SPACING 0.45f
#define CENTER_SPACING 1.3f
#define SIDE_ANGLE 70.0f
#define CAMERA_Z -3.8f
#define CAMERA_Y 0.3f
#define REFLECTION_OPACITY 0.4f

@interface ItemFlowView () {
    NSMutableArray *_textures; 
    CGFloat _currentPosition;
    CGFloat _targetPosition;
    NSTimer *_animationTimer;
    NSTimeInterval _lastTime;
}
@end

@implementation ItemFlowView

@synthesize dataSource;
@synthesize delegate;

- (instancetype)initWithFrame:(NSRect)frame {
    NSOpenGLPixelFormatAttribute attrs[] = {
        NSOpenGLPFADoubleBuffer,
        NSOpenGLPFADepthSize, 24,
        0
    };
    NSOpenGLPixelFormat *pf = [[NSOpenGLPixelFormat alloc] initWithAttributes:attrs];
    if (!pf) {
        NSLog(@"Failed to create pixel format");
    }
    
    self = [super initWithFrame:frame pixelFormat:pf];
    if (self) {
        _textures = [NSMutableArray array];
        _currentPosition = 0.0f;
        _targetPosition = 0.0f;
    }
    return self;
}

- (void)dealloc {
    [_animationTimer invalidate];
    _animationTimer = nil;
}

- (NSUInteger)selectedIndex {
    return (NSUInteger)round(_targetPosition);
}

- (void)setSelectedIndex:(NSUInteger)index {
    // Clamp
    if (_textures.count > 0 && index >= _textures.count) index = _textures.count - 1;
    if (_textures.count == 0) index = 0;
    
    if (_targetPosition != (CGFloat)index) {
        _targetPosition = (CGFloat)index;
        
        // Notify delegate about the INTENT to select
        if (delegate && [delegate respondsToSelector:@selector(itemFlowView:didSelectItemAtIndex:)]) {
            [delegate itemFlowView:self didSelectItemAtIndex:index];
        }
        
        [self startAnimation];
    }
}

#pragma mark - Animation

- (void)startAnimation {
    if (!_animationTimer) {
        _lastTime = [NSDate timeIntervalSinceReferenceDate];
        _animationTimer = [NSTimer scheduledTimerWithTimeInterval:1.0/60.0 target:self selector:@selector(updateAnimation:) userInfo:nil repeats:YES];
        [[NSRunLoop currentRunLoop] addTimer:_animationTimer forMode:NSRunLoopCommonModes];
    }
}

- (void)updateAnimation:(NSTimer *)timer {
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    NSTimeInterval dt = now - _lastTime;
    _lastTime = now;
    
    if (dt > 0.1) dt = 0.1; // Cap dt to prevent jumps
    
    CGFloat diff = _targetPosition - _currentPosition;
    
    // Spring/Lerp physics
    // Simple exponential ease-out
    CGFloat speed = 8.0f;
    CGFloat change = diff * speed * dt;
    
    if (fabs(diff) < 0.005f) {
        _currentPosition = _targetPosition;
        [_animationTimer invalidate];
        _animationTimer = nil;
    } else {
        _currentPosition += change;
    }
    
    [self setNeedsDisplay:YES];
}

#pragma mark - OpenGL Setup

- (void)prepareOpenGL {
    [super prepareOpenGL];
    
    glEnable(GL_DEPTH_TEST);
    glEnable(GL_TEXTURE_2D);
    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    
    glClearColor(0.0f, 0.0f, 0.0f, 1.0f); // Black background
    glHint(GL_PERSPECTIVE_CORRECTION_HINT, GL_NICEST);
}

- (void)reshape {
    [super reshape];
    NSRect bounds = [self bounds];
    GLsizei w = (GLsizei)bounds.size.width;
    GLsizei h = (GLsizei)bounds.size.height;
    glViewport(0, 0, w, h);
    
    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
    
    GLdouble aspect = (GLdouble)w / (GLdouble)(h ?: 1);
    
    // gluPerspective equivalent
    GLdouble fovY = 50.0;
    GLdouble zNear = 0.5;
    GLdouble zFar = 100.0;
    GLdouble fH = tan(fovY / 360.0 * M_PI) * zNear;
    GLdouble fW = fH * aspect;
    glFrustum(-fW, fW, -fH, fH, zNear, zFar);
    
    glMatrixMode(GL_MODELVIEW);
}

#pragma mark - Rendering

- (void)drawRect:(NSRect)dirtyRect {
    [[self openGLContext] makeCurrentContext];
    
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    glLoadIdentity();
    
    glTranslatef(0.0f, CAMERA_Y, CAMERA_Z);
    
    [self drawItems];
    
    [[self openGLContext] flushBuffer];
}

- (void)drawItems {
    NSUInteger count = _textures.count;
    if (count == 0) return;
    
    // Sort items so we draw back-to-front for transparency handling (Painter's Algorithm)
    // The "Peak" is at _currentPosition.
    // Things left of peak (index < current) draw 0 -> floor(current)
    // Things right of peak (index > current) draw max -> ceil(current)
    
    NSInteger centerIdx = (NSInteger)(_currentPosition);
    if (centerIdx < 0) centerIdx = 0;
    
    // Draw Left Stack: 0 up to centerIdx-1
    for (NSInteger i = 0; i < centerIdx; i++) {
        [self drawItemAtIndex:i];
    }
    
    // Draw Right Stack: last down to centerIdx+1
    for (NSInteger i = count - 1; i > centerIdx; i--) {
        [self drawItemAtIndex:i];
    }
    
    // Draw the "middle" items (centerIdx and maybe centerIdx+1 if doing fractional transition)
    // Actually, just draw centerIdx last.
    // It's possible multiple items are 'near' center during transition.
    // Ideally we sort by Z distance.
    // But simplistic sorting:
    // 0..centerIdx (exclusive)
    // count..centerIdx (exclusive)
    // Then centerIdx itself.
    
    [self drawItemAtIndex:centerIdx];
}

- (void)drawItemAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)_textures.count) return;
    
    glPushMatrix();
    
    float d = (float)index - _currentPosition;
    float absD = fabsf(d);
    
    float translateX = 0.0f;
    float translateZ = 0.0f;
    float rotateY = 0.0f;
    
    const float zCenter = 0.0f;
    const float zSide = -2.5f;
    
    if (absD < 1.0f) {
        // Transition Zone (0 to 1)
        float t = absD; // 0 is center, 1 is side
        
        // Linear or Ease-in/out
        // X moves from 0 to CENTER_SPACING
        float xDist = CENTER_SPACING * t;
        translateX = (d >= 0) ? xDist : -xDist;
        
        // Z moves from zCenter to zSide
        translateZ = zCenter * (1.0f - t) + zSide * t;
        
        // Rotation 0 to SIDE_ANGLE
        float angle = SIDE_ANGLE * t;
        rotateY = (d >= 0) ? -angle : angle;
        
    } else {
        // Side Zone (> 1)
        float normD = absD - 1.0f;
        float xBase = CENTER_SPACING;
        float xRest = normD * COVER_SPACING;
        
        float xTotal = xBase + xRest;
        translateX = (d >= 0) ? xTotal : -xTotal;
        
        translateZ = zSide;
        rotateY = (d >= 0) ? -SIDE_ANGLE : SIDE_ANGLE;
    }
    
    glTranslatef(translateX, 0.0f, translateZ);
    glRotatef(rotateY, 0.0f, 1.0f, 0.0f);
    
    GLuint texID = [_textures[index] unsignedIntValue];
    glBindTexture(GL_TEXTURE_2D, texID ? texID : 0);
    
    // 1. Draw Reflection w/ Gradient Alpha
    // Save state
    glPushMatrix();
    glTranslatef(0.0f, -2.0f, 0.0f); // Move down
    glScalef(1.0f, -1.0f, 1.0f);     // Flip Y
    
    // Draw Quad with Gradient
    glBegin(GL_QUADS);
    // Reflection Top (geometry bottom -1) -> Alpha REFLECTION_OPACITY
    glColor4f(1.0f, 1.0f, 1.0f, REFLECTION_OPACITY);
    glTexCoord2f(0.0f, 1.0f); glVertex3f(-1.0f, -1.0f, 0.0f);
    glTexCoord2f(1.0f, 1.0f); glVertex3f( 1.0f, -1.0f, 0.0f);
    
    // Reflection Bottom (geometry top +1) -> Alpha 0.0
    glColor4f(1.0f, 1.0f, 1.0f, 0.0f);
    glTexCoord2f(1.0f, 0.0f); glVertex3f( 1.0f,  1.0f, 0.0f);
    glTexCoord2f(0.0f, 0.0f); glVertex3f(-1.0f,  1.0f, 0.0f);
    glEnd();
    
    glPopMatrix();
    
    // 2. Draw Main Image
    // Optional: Darken based on distance
    float brightness = 1.0f;
    if (absD > 0.5f) {
        // Fade to grey slightly when on side
        float factor = (absD - 0.5f) * 0.3f;
        if (factor > 0.6f) factor = 0.6f;
        brightness = 1.0f - factor;
    }
    glColor3f(brightness, brightness, brightness);
    
    glBegin(GL_QUADS);
    glTexCoord2f(0.0f, 1.0f); glVertex3f(-1.0f, -1.0f, 0.0f);
    glTexCoord2f(1.0f, 1.0f); glVertex3f( 1.0f, -1.0f, 0.0f);
    glTexCoord2f(1.0f, 0.0f); glVertex3f( 1.0f,  1.0f, 0.0f);
    glTexCoord2f(0.0f, 0.0f); glVertex3f(-1.0f,  1.0f, 0.0f);
    glEnd();
    
    glPopMatrix();
}

#pragma mark - Data Loading

- (GLuint)createTextureFromImage:(NSImage *)image {
    if (!image) return 0;
    
    NSBitmapImageRep *bitmap = nil;
    for (NSImageRep *rep in [image representations]) {
        if ([rep isKindOfClass:[NSBitmapImageRep class]]) {
            bitmap = (NSBitmapImageRep *)rep;
            break;
        }
    }
    if (!bitmap) {
        bitmap = [NSBitmapImageRep imageRepWithData:[image TIFFRepresentation]];
    }
    if (!bitmap) return 0;
    
    GLuint texID;
    glGenTextures(1, &texID);
    glBindTexture(GL_TEXTURE_2D, texID);
    
    // Linear filtering ensures it looks okay when shrunk/rotated
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    
    // Clamp to edge to avoid border artifacts
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    
    unsigned char *data = [bitmap bitmapData];
    if (data) {
        GLenum format = [bitmap hasAlpha] ? GL_RGBA : GL_RGB;
        // pixelWide/High are NSInteger
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, (GLsizei)[bitmap pixelsWide], (GLsizei)[bitmap pixelsHigh],
                    0, format, GL_UNSIGNED_BYTE, data);
    }
    
    return texID;
}

- (void)reloadData {
    [[self openGLContext] makeCurrentContext];
    for (NSNumber *texNum in _textures) {
        GLuint t = [texNum unsignedIntValue];
        glDeleteTextures(1, &t);
    }
    [_textures removeAllObjects];
    
    if (dataSource) {
        NSUInteger count = [dataSource numberOfItemsInItemFlowView:self];
        for (NSUInteger i = 0; i < count; i++) {
            NSImage *img = [dataSource itemFlowView:self imageAtIndex:i];
            GLuint t = img ? [self createTextureFromImage:img] : 0;
            [_textures addObject:@(t)];
        }
    }
    
    // Reset positions? Only if out of bounds
    if (_textures.count > 0 && _targetPosition >= _textures.count) {
        _targetPosition = (CGFloat)(_textures.count - 1);
        _currentPosition = _targetPosition;
    } else if (_textures.count == 0) {
        _targetPosition = 0;
        _currentPosition = 0;
    }
    
    [self setNeedsDisplay:YES];
}

#pragma mark - Inputs

- (void)keyDown:(NSEvent *)event {
    NSString *chars = [event charactersIgnoringModifiers];
    if ([chars length] > 0) {
        unichar c = [chars characterAtIndex:0];
        if (c == NSLeftArrowFunctionKey) {
             [self moveSelectionBy:-1];
             return;
        } else if (c == NSRightArrowFunctionKey) {
             [self moveSelectionBy:1];
             return;
        }
    }
    [super keyDown:event];
}

- (void)mouseDown:(NSEvent *)event {
    NSPoint p = [self convertPoint:[event locationInWindow] fromView:nil];
    CGFloat width = NSWidth(self.bounds);
    
    if (p.x < width * 0.35) {
        [self moveSelectionBy:-1];
    } else if (p.x > width * 0.65) {
        [self moveSelectionBy:1];
    }
}

- (void)scrollWheel:(NSEvent *)event {
    CGFloat delta = [event deltaY];
    if (delta == 0) delta = [event deltaX];
    
    // Threshold to prevent over-sensitive scrolling
    if (fabs(delta) > 0.5) {
        if (delta > 0) [self moveSelectionBy:-1];
        else [self moveSelectionBy:1];
    }
}

- (void)moveSelectionBy:(NSInteger)delta {
    NSInteger newIndex = (NSInteger)round(_targetPosition) + delta;
    if (newIndex < 0) newIndex = 0;
    if (_textures.count > 0 && newIndex >= (NSInteger)_textures.count) newIndex = _textures.count - 1;
    
    [self setSelectedIndex:newIndex];
}

// Make sure we accept key events
- (BOOL)acceptsFirstResponder {
    return YES;
}

@end
