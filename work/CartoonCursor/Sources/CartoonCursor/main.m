#import <Cocoa/Cocoa.h>
#import <ApplicationServices/ApplicationServices.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreGraphics/CGRemoteOperation.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

static NSString * const DefaultsKeyEnabled = @"enabled";
static NSString * const DefaultsKeyStickerWalkFollow = @"stickerWalkFollow";
static NSString * const DefaultsKeyStickerFrameAnimation = @"stickerFrameAnimation";
static NSString * const DefaultsKeyStickerWalkSpeed = @"stickerWalkSpeed";
static NSString * const DefaultsKeyStickerWalkAmplitude = @"stickerWalkAmplitude";
static NSString * const DefaultsKeyHideSystemCursor = @"hideSystemCursor";
static NSString * const DefaultsKeyCursorSize = @"cursorSize";
static NSString * const DefaultsKeyImagePath = @"imagePath";
static NSString * const DefaultsKeyVirtualCursor = @"virtualCursor";
static NSString * const DefaultsKeyEffectStyle = @"effectStyle";
static NSString * const DefaultsKeyEffectColorMode = @"effectColorMode";
static NSString * const DefaultsKeyCustomEffectColors = @"customEffectColors";
static NSString * const DefaultsKeyCustomTrailColors = @"customTrailColors";
static NSString * const DefaultsKeyCustomClickColors = @"customClickColors";
static NSString * const DefaultsKeyCustomParticleColors = @"customParticleColors";
static NSString * const DefaultsKeyNativeCursorEffects = @"nativeCursorEffects";
static NSString * const DefaultsKeyNativeEffectColorMode = @"nativeEffectColorMode";
static NSString * const DefaultsKeyCustomNativeTrailColors = @"customNativeTrailColors";
static NSString * const DefaultsKeyCustomNativeClickColors = @"customNativeClickColors";
static NSString * const DefaultsKeyCustomNativeParticleColors = @"customNativeParticleColors";
static NSString * const DefaultsKeyBehaviorVersion = @"behaviorVersion";
static const NSInteger CurrentBehaviorVersion = 6;
static const NSTimeInterval CursorSuppressionInterval = 0.05;
static const CGFloat DefaultCoverCursorSize = 160.0;
static const CGFloat DefaultStickerWalkSpeed = 1.0;
static const CGFloat DefaultStickerWalkAmplitude = 1.0;

typedef NS_ENUM(NSInteger, CursorEffectStyle) {
    CursorEffectStyleOff = 0,
    CursorEffectStyleRings = 1,
    CursorEffectStyleSparkles = 2,
    CursorEffectStyleTrail = 3,
    CursorEffectStyleSparklesTrail = 4
};

typedef NS_ENUM(NSInteger, EffectColorMode) {
    EffectColorModeAuto = 0,
    EffectColorModeCustom = 1
};

typedef NS_ENUM(NSInteger, EffectColorRole) {
    EffectColorRoleTrail = 0,
    EffectColorRoleClick = 1,
    EffectColorRoleParticle = 2
};

typedef NS_ENUM(NSInteger, EffectColorTarget) {
    EffectColorTargetSticker = 0,
    EffectColorTargetNative = 1
};

static NSColor *CartoonColorUsingSRGB(NSColor *color) {
    NSColor *converted = [color colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    if (!converted) {
        converted = [color colorUsingColorSpace:NSColorSpace.deviceRGBColorSpace];
    }
    return converted ?: NSColor.whiteColor;
}

static NSString *CartoonHexStringFromColor(NSColor *color) {
    NSColor *converted = CartoonColorUsingSRGB(color);
    CGFloat red = 0;
    CGFloat green = 0;
    CGFloat blue = 0;
    CGFloat alpha = 0;
    [converted getRed:&red green:&green blue:&blue alpha:&alpha];

    NSInteger redByte = (NSInteger)llround(MAX(0.0, MIN(1.0, red)) * 255.0);
    NSInteger greenByte = (NSInteger)llround(MAX(0.0, MIN(1.0, green)) * 255.0);
    NSInteger blueByte = (NSInteger)llround(MAX(0.0, MIN(1.0, blue)) * 255.0);
    return [NSString stringWithFormat:@"#%02lX%02lX%02lX",
                                      (long)redByte,
                                      (long)greenByte,
                                      (long)blueByte];
}

static NSColor *CartoonColorFromHexString(NSString *hexString) {
    if (![hexString isKindOfClass:NSString.class]) {
        return nil;
    }

    NSString *trimmed = [hexString stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if ([trimmed hasPrefix:@"#"]) {
        trimmed = [trimmed substringFromIndex:1];
    }
    if (trimmed.length != 6) {
        return nil;
    }

    unsigned int value = 0;
    NSScanner *scanner = [NSScanner scannerWithString:trimmed];
    if (![scanner scanHexInt:&value]) {
        return nil;
    }

    CGFloat red = ((value >> 16) & 0xFF) / 255.0;
    CGFloat green = ((value >> 8) & 0xFF) / 255.0;
    CGFloat blue = (value & 0xFF) / 255.0;
    return [NSColor colorWithCalibratedRed:red green:green blue:blue alpha:1.0];
}

static CGFloat CartoonClampedStickerWalkSpeed(CGFloat speed) {
    if (!isfinite(speed) || speed <= 0) {
        return DefaultStickerWalkSpeed;
    }
    return MAX(0.30, MIN(2.2, speed));
}

static CGFloat CartoonClampedStickerWalkAmplitude(CGFloat amplitude) {
    if (!isfinite(amplitude) || amplitude <= 0) {
        return DefaultStickerWalkAmplitude;
    }
    return MAX(0.25, MIN(1.8, amplitude));
}

@interface OverlayWindow : NSWindow
- (instancetype)initWithFrame:(NSRect)frame;
@end

@implementation OverlayWindow

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithContentRect:frame
                            styleMask:NSWindowStyleMaskBorderless
                              backing:NSBackingStoreBuffered
                                defer:NO];
    if (!self) {
        return nil;
    }

    self.opaque = NO;
    self.backgroundColor = NSColor.clearColor;
    self.hasShadow = NO;
    self.ignoresMouseEvents = YES;
    self.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces |
        NSWindowCollectionBehaviorStationary |
        NSWindowCollectionBehaviorIgnoresCycle |
        NSWindowCollectionBehaviorFullScreenAuxiliary;
    self.level = CGWindowLevelForKey(kCGMaximumWindowLevelKey);

    return self;
}

- (BOOL)canBecomeKeyWindow {
    return NO;
}

- (BOOL)canBecomeMainWindow {
    return NO;
}

@end

@interface Pulse : NSObject
@property(nonatomic, assign) NSPoint point;
@property(nonatomic, assign) NSTimeInterval startTime;
@property(nonatomic, assign) NSInteger seed;
@end

@implementation Pulse
@end

@interface TrailPoint : NSObject
@property(nonatomic, assign) NSPoint point;
@property(nonatomic, assign) NSTimeInterval startTime;
@property(nonatomic, assign) NSInteger seed;
@end

@implementation TrailPoint
@end

@interface CursorView : NSView
@property(nonatomic, assign) NSPoint cursorPoint;
@property(nonatomic, assign) CGFloat cursorSize;
@property(nonatomic, strong) NSImage *image;
@property(nonatomic, assign) BOOL cursorVisible;
@property(nonatomic, assign) BOOL stickerVisible;
@property(nonatomic, assign) BOOL stickerWalkFollowEnabled;
@property(nonatomic, assign) BOOL stickerFrameAnimationEnabled;
@property(nonatomic, assign) CGFloat stickerWalkSpeedMultiplier;
@property(nonatomic, assign) CGFloat stickerWalkAmplitudeMultiplier;
@property(nonatomic, assign) CursorEffectStyle effectStyle;
@property(nonatomic, assign) EffectColorMode effectColorMode;
@property(nonatomic, assign) BOOL nativeCursorEffectsEnabled;
@property(nonatomic, assign) EffectColorMode nativeEffectColorMode;
@property(nonatomic, copy) NSArray<NSColor *> *customTrailColors;
@property(nonatomic, copy) NSArray<NSColor *> *customClickColors;
@property(nonatomic, copy) NSArray<NSColor *> *customParticleColors;
@property(nonatomic, copy) NSArray<NSColor *> *customNativeTrailColors;
@property(nonatomic, copy) NSArray<NSColor *> *customNativeClickColors;
@property(nonatomic, copy) NSArray<NSColor *> *customNativeParticleColors;
+ (NSArray<NSColor *> *)defaultEffectColors;
+ (NSArray<NSColor *> *)normalizedEffectColors:(NSArray<NSColor *> *)colors;
- (void)addPulseAtPoint:(NSPoint)point;
@end

@implementation CursorView {
    NSMutableArray<Pulse *> *_pulses;
    NSMutableArray<TrailPoint *> *_trailPoints;
    NSArray<NSColor *> *_autoEffectColors;
    NSArray<NSColor *> *_trailEffectColors;
    NSArray<NSColor *> *_clickEffectColors;
    NSArray<NSColor *> *_particleEffectColors;
    NSArray<NSColor *> *_nativeTrailEffectColors;
    NSArray<NSColor *> *_nativeClickEffectColors;
    NSArray<NSColor *> *_nativeParticleEffectColors;
    NSArray<NSColor *> *_customTrailColors;
    NSArray<NSColor *> *_customClickColors;
    NSArray<NSColor *> *_customParticleColors;
    NSArray<NSColor *> *_customNativeTrailColors;
    NSArray<NSColor *> *_customNativeClickColors;
    NSArray<NSColor *> *_customNativeParticleColors;
    EffectColorMode _effectColorMode;
    EffectColorMode _nativeEffectColorMode;
    BOOL _nativeCursorEffectsEnabled;
    BOOL _stickerWalkFollowEnabled;
    BOOL _stickerFrameAnimationEnabled;
    BOOL _hasStickerDrawPoint;
    NSPoint _stickerDrawPoint;
    NSPoint _lastTrailAnchorPoint;
    BOOL _hasTrailAnchorPoint;
    NSTimeInterval _lastStickerAnimationTime;
    CGFloat _stickerWalkPhase;
    CGFloat _stickerWalkSpeed;
    CGFloat _stickerWalkSpeedMultiplier;
    CGFloat _stickerWalkAmplitudeMultiplier;
    CGFloat _stickerWalkTilt;
    NSTimeInterval _lastTrailSampleTime;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (!self) {
        return nil;
    }

    _cursorSize = 64;
    _cursorVisible = NO;
    _stickerVisible = NO;
    _stickerWalkFollowEnabled = NO;
    _stickerFrameAnimationEnabled = NO;
    _stickerWalkSpeedMultiplier = DefaultStickerWalkSpeed;
    _stickerWalkAmplitudeMultiplier = DefaultStickerWalkAmplitude;
    _hasStickerDrawPoint = NO;
    _hasTrailAnchorPoint = NO;
    _effectStyle = CursorEffectStyleSparklesTrail;
    _effectColorMode = EffectColorModeAuto;
    _nativeEffectColorMode = EffectColorModeAuto;
    _nativeCursorEffectsEnabled = NO;
    _customTrailColors = [self.class defaultEffectColors];
    _customClickColors = [self.class defaultEffectColors];
    _customParticleColors = [self.class defaultEffectColors];
    _customNativeTrailColors = [self.class defaultEffectColors];
    _customNativeClickColors = [self.class defaultEffectColors];
    _customNativeParticleColors = [self.class defaultEffectColors];
    _pulses = [NSMutableArray array];
    _trailPoints = [NSMutableArray array];
    _autoEffectColors = [self.class defaultEffectColors];
    _trailEffectColors = [self.class defaultEffectColors];
    _clickEffectColors = [self.class defaultEffectColors];
    _particleEffectColors = [self.class defaultEffectColors];
    _nativeTrailEffectColors = [self.class defaultEffectColors];
    _nativeClickEffectColors = [self.class defaultEffectColors];
    _nativeParticleEffectColors = [self.class defaultEffectColors];
    _lastTrailSampleTime = 0;
    return self;
}

- (BOOL)isFlipped {
    return NO;
}

- (void)setCursorPoint:(NSPoint)cursorPoint {
    _cursorPoint = cursorPoint;
    [self updateStickerMotionTowardPoint:cursorPoint];

    NSPoint trailPoint = [self trailAnchorPoint];
    if (_hasTrailAnchorPoint) {
        [self maybeAddTrailPointFromPreviousPoint:_lastTrailAnchorPoint toPoint:trailPoint];
    }
    _lastTrailAnchorPoint = trailPoint;
    _hasTrailAnchorPoint = YES;
    self.needsDisplay = YES;
}

- (void)setCursorSize:(CGFloat)cursorSize {
    _cursorSize = cursorSize;
    self.needsDisplay = YES;
}

- (void)setImage:(NSImage *)image {
    _image = image;
    [self refreshEffectColors];
    self.needsDisplay = YES;
}

- (void)setCursorVisible:(BOOL)cursorVisible {
    _cursorVisible = cursorVisible;
    if (!cursorVisible) {
        _hasTrailAnchorPoint = NO;
        [self resetStickerMotion];
    }
    self.needsDisplay = YES;
}

- (void)setStickerVisible:(BOOL)stickerVisible {
    _stickerVisible = stickerVisible;
    if (!stickerVisible) {
        [self resetStickerMotion];
    }
    self.needsDisplay = YES;
}

- (void)setStickerWalkFollowEnabled:(BOOL)stickerWalkFollowEnabled {
    _stickerWalkFollowEnabled = stickerWalkFollowEnabled;
    [self resetStickerMotion];
    self.needsDisplay = YES;
}

- (void)setStickerFrameAnimationEnabled:(BOOL)stickerFrameAnimationEnabled {
    _stickerFrameAnimationEnabled = stickerFrameAnimationEnabled;
    [self resetStickerMotion];
    self.needsDisplay = YES;
}

- (void)setStickerWalkSpeedMultiplier:(CGFloat)stickerWalkSpeedMultiplier {
    _stickerWalkSpeedMultiplier = CartoonClampedStickerWalkSpeed(stickerWalkSpeedMultiplier);
}

- (void)setStickerWalkAmplitudeMultiplier:(CGFloat)stickerWalkAmplitudeMultiplier {
    _stickerWalkAmplitudeMultiplier = CartoonClampedStickerWalkAmplitude(stickerWalkAmplitudeMultiplier);
    self.needsDisplay = YES;
}

- (void)setEffectStyle:(CursorEffectStyle)effectStyle {
    _effectStyle = effectStyle;
    if (![self shouldDrawTrail]) {
        [_trailPoints removeAllObjects];
    }
    self.needsDisplay = YES;
}

- (void)setEffectColorMode:(EffectColorMode)effectColorMode {
    _effectColorMode = effectColorMode == EffectColorModeCustom ? EffectColorModeCustom : EffectColorModeAuto;
    [self refreshEffectColors];
    self.needsDisplay = YES;
}

- (void)setCustomTrailColors:(NSArray<NSColor *> *)customTrailColors {
    _customTrailColors = [self.class normalizedEffectColors:customTrailColors];
    [self refreshEffectColors];
    self.needsDisplay = YES;
}

- (void)setCustomClickColors:(NSArray<NSColor *> *)customClickColors {
    _customClickColors = [self.class normalizedEffectColors:customClickColors];
    [self refreshEffectColors];
    self.needsDisplay = YES;
}

- (void)setCustomParticleColors:(NSArray<NSColor *> *)customParticleColors {
    _customParticleColors = [self.class normalizedEffectColors:customParticleColors];
    [self refreshEffectColors];
    self.needsDisplay = YES;
}

- (void)setNativeCursorEffectsEnabled:(BOOL)nativeCursorEffectsEnabled {
    _nativeCursorEffectsEnabled = nativeCursorEffectsEnabled;
    self.needsDisplay = YES;
}

- (void)setNativeEffectColorMode:(EffectColorMode)nativeEffectColorMode {
    _nativeEffectColorMode = nativeEffectColorMode == EffectColorModeCustom ? EffectColorModeCustom : EffectColorModeAuto;
    [self refreshNativeEffectColors];
    self.needsDisplay = YES;
}

- (void)setCustomNativeTrailColors:(NSArray<NSColor *> *)customNativeTrailColors {
    _customNativeTrailColors = [self.class normalizedEffectColors:customNativeTrailColors];
    [self refreshNativeEffectColors];
    self.needsDisplay = YES;
}

- (void)setCustomNativeClickColors:(NSArray<NSColor *> *)customNativeClickColors {
    _customNativeClickColors = [self.class normalizedEffectColors:customNativeClickColors];
    [self refreshNativeEffectColors];
    self.needsDisplay = YES;
}

- (void)setCustomNativeParticleColors:(NSArray<NSColor *> *)customNativeParticleColors {
    _customNativeParticleColors = [self.class normalizedEffectColors:customNativeParticleColors];
    [self refreshNativeEffectColors];
    self.needsDisplay = YES;
}

- (void)refreshEffectColors {
    if (_effectColorMode == EffectColorModeCustom) {
        _trailEffectColors = [self.class normalizedEffectColors:_customTrailColors];
        _clickEffectColors = [self.class normalizedEffectColors:_customClickColors];
        _particleEffectColors = [self.class normalizedEffectColors:_customParticleColors];
        return;
    }

    _autoEffectColors = self.image ? [self.class effectColorsForImage:self.image] : [self.class defaultEffectColors];
    _trailEffectColors = _autoEffectColors;
    _clickEffectColors = _autoEffectColors;
    _particleEffectColors = _autoEffectColors;
}

- (void)refreshNativeEffectColors {
    if (_nativeEffectColorMode == EffectColorModeCustom) {
        _nativeTrailEffectColors = [self.class normalizedEffectColors:_customNativeTrailColors];
        _nativeClickEffectColors = [self.class normalizedEffectColors:_customNativeClickColors];
        _nativeParticleEffectColors = [self.class normalizedEffectColors:_customNativeParticleColors];
        return;
    }

    NSArray<NSColor *> *defaults = [self.class defaultEffectColors];
    _nativeTrailEffectColors = defaults;
    _nativeClickEffectColors = defaults;
    _nativeParticleEffectColors = defaults;
}

- (void)resetStickerMotion {
    _hasStickerDrawPoint = NO;
    _hasTrailAnchorPoint = NO;
    _lastStickerAnimationTime = 0;
    _stickerWalkPhase = 0;
    _stickerWalkSpeed = 0;
    _stickerWalkTilt = 0;
}

- (void)updateStickerMotionTowardPoint:(NSPoint)targetPoint {
    NSTimeInterval now = NSDate.timeIntervalSinceReferenceDate;
    if (!_stickerWalkFollowEnabled || !self.stickerVisible) {
        _stickerDrawPoint = targetPoint;
        _hasStickerDrawPoint = YES;
        _lastStickerAnimationTime = now;
        _stickerWalkSpeed = 0;
        _stickerWalkTilt *= 0.72;
        return;
    }

    if (!_hasStickerDrawPoint || _lastStickerAnimationTime <= 0) {
        _stickerDrawPoint = targetPoint;
        _hasStickerDrawPoint = YES;
        _lastStickerAnimationTime = now;
        return;
    }

    NSTimeInterval deltaTime = MAX(1.0 / 240.0, MIN(1.0 / 20.0, now - _lastStickerAnimationTime));
    _lastStickerAnimationTime = now;

    CGFloat deltaX = targetPoint.x - _stickerDrawPoint.x;
    CGFloat deltaY = targetPoint.y - _stickerDrawPoint.y;
    CGFloat targetDistance = hypot(deltaX, deltaY);
    if (targetDistance > MAX(420.0, self.cursorSize * 5.0)) {
        _stickerDrawPoint = targetPoint;
        _stickerWalkSpeed = 0;
        _stickerWalkTilt = 0;
        return;
    }

    CGFloat followAmount = 1.0 - exp(-deltaTime * 9.5 * _stickerWalkSpeedMultiplier);
    NSPoint previousPoint = _stickerDrawPoint;
    _stickerDrawPoint = NSMakePoint(_stickerDrawPoint.x + deltaX * followAmount,
                                    _stickerDrawPoint.y + deltaY * followAmount);

    CGFloat moveX = _stickerDrawPoint.x - previousPoint.x;
    CGFloat moveY = _stickerDrawPoint.y - previousPoint.y;
    CGFloat moveDistance = hypot(moveX, moveY);
    _stickerWalkSpeed = moveDistance / deltaTime;

    CGFloat strideLength = MAX(18.0, self.cursorSize * 0.42);
    _stickerWalkPhase += (moveDistance / strideLength) * (CGFloat)M_PI;
    if (_stickerWalkPhase > (CGFloat)M_PI * 200.0) {
        _stickerWalkPhase = fmod(_stickerWalkPhase, (CGFloat)M_PI * 2.0);
    }

    CGFloat horizontalVelocity = moveX / deltaTime;
    CGFloat targetTilt = MAX(-0.16, MIN(0.16, horizontalVelocity / 3200.0));
    _stickerWalkTilt = _stickerWalkTilt * 0.72 + targetTilt * 0.28;
}

- (NSPoint)stickerAnchorPoint {
    if (_stickerWalkFollowEnabled && self.stickerVisible && _hasStickerDrawPoint) {
        return _stickerDrawPoint;
    }
    return self.cursorPoint;
}

- (NSPoint)trailAnchorPoint {
    if (_stickerWalkFollowEnabled && self.stickerVisible && _hasStickerDrawPoint) {
        return _stickerDrawPoint;
    }
    return self.cursorPoint;
}

- (void)applyStickerWalkPoseForRect:(NSRect)rect {
    if (!self.stickerVisible || (!_stickerWalkFollowEnabled && !_stickerFrameAnimationEnabled)) {
        return;
    }

    CGFloat motionIntensity = MIN(1.0, _stickerWalkSpeed / MAX(260.0, self.cursorSize * 5.0));
    if (!_stickerFrameAnimationEnabled && motionIntensity < 0.015) {
        return;
    }

    CGFloat intensity = motionIntensity;
    CGFloat step = sin(_stickerWalkPhase);
    CGFloat landing = fabs(step);
    CGFloat tilt = _stickerWalkTilt;
    CGFloat sideStep = 0;
    CGFloat bobFactor = 0.030;
    CGFloat squashFactor = 0.045;
    CGFloat stretchFactor = 0.42;
    CGFloat sideFactor = 0.020;
    CGFloat rotationFactor = 1.0;

    if (_stickerFrameAnimationEnabled) {
        static const CGFloat stepFrames[] = {0.05, 1.00, 0.58, -0.14, -0.78, 0.36};
        static const CGFloat landingFrames[] = {0.92, 0.18, 0.36, 1.00, 0.28, 0.58};
        static const CGFloat tiltFrames[] = {-0.24, -0.12, 0.10, 0.24, 0.12, -0.10};
        static const CGFloat sideFrames[] = {-0.55, -0.25, 0.42, 0.55, 0.22, -0.38};
        static const NSInteger frameCount = 6;

        CGFloat frameRate = MAX(2.0, 4.8 * _stickerWalkSpeedMultiplier);
        NSInteger frameIndex = ((NSInteger)floor(NSDate.timeIntervalSinceReferenceDate * frameRate)) % frameCount;
        if (_stickerWalkFollowEnabled && motionIntensity >= 0.015) {
            frameIndex = (frameIndex + (NSInteger)floor(_stickerWalkPhase / (CGFloat)M_PI)) % frameCount;
        }

        step = stepFrames[frameIndex];
        landing = landingFrames[frameIndex];
        tilt = tiltFrames[frameIndex];
        sideStep = sideFrames[frameIndex];
        intensity = MAX(motionIntensity, _stickerWalkFollowEnabled ? 0.56 : 0.78);
        bobFactor = 0.095;
        squashFactor = 0.105;
        stretchFactor = 0.62;
        sideFactor = 0.055;
        rotationFactor = 1.18;
    }

    CGFloat amplitude = _stickerWalkAmplitudeMultiplier;
    CGFloat bob = step * self.cursorSize * bobFactor * intensity * amplitude;
    CGFloat squash = landing * squashFactor * intensity * amplitude;
    CGFloat stretch = squash * stretchFactor;
    CGFloat side = sideStep * self.cursorSize * sideFactor * intensity * amplitude;

    NSAffineTransform *transform = [NSAffineTransform transform];
    [transform translateXBy:NSMidX(rect) + side yBy:NSMidY(rect) + bob];
    [transform rotateByRadians:tilt * intensity * amplitude * rotationFactor];
    [transform scaleXBy:1.0 + stretch yBy:1.0 - squash];
    [transform translateXBy:-NSMidX(rect) yBy:-NSMidY(rect)];
    [transform concat];
}

- (void)addPulseAtPoint:(NSPoint)point {
    if (![self shouldDrawPulse]) {
        return;
    }

    Pulse *pulse = [[Pulse alloc] init];
    pulse.point = point;
    pulse.startTime = NSDate.timeIntervalSinceReferenceDate;
    pulse.seed = (NSInteger)round(pulse.startTime * 1000.0) % 997;
    [_pulses addObject:pulse];
    self.needsDisplay = YES;
}

- (BOOL)shouldDrawPulse {
    return self.effectStyle == CursorEffectStyleRings ||
        self.effectStyle == CursorEffectStyleSparkles ||
        self.effectStyle == CursorEffectStyleSparklesTrail;
}

- (BOOL)shouldDrawParticles {
    return self.effectStyle == CursorEffectStyleSparkles ||
        self.effectStyle == CursorEffectStyleSparklesTrail;
}

- (BOOL)shouldDrawTrail {
    return self.effectStyle == CursorEffectStyleTrail ||
        self.effectStyle == CursorEffectStyleSparklesTrail;
}

- (void)maybeAddTrailPointFromPreviousPoint:(NSPoint)previousPoint toPoint:(NSPoint)point {
    if (!self.cursorVisible || ![self shouldDrawTrail]) {
        return;
    }

    NSTimeInterval now = NSDate.timeIntervalSinceReferenceDate;
    CGFloat deltaX = point.x - previousPoint.x;
    CGFloat deltaY = point.y - previousPoint.y;
    CGFloat distance = hypot(deltaX, deltaY);
    if (distance < 5.0 && now - _lastTrailSampleTime < 0.045) {
        return;
    }

    TrailPoint *trailPoint = [[TrailPoint alloc] init];
    trailPoint.point = point;
    trailPoint.startTime = now;
    trailPoint.seed = (NSInteger)round(now * 1000.0) % 997;
    [_trailPoints addObject:trailPoint];
    _lastTrailSampleTime = now;

    if (_trailPoints.count > 42) {
        [_trailPoints removeObjectsInRange:NSMakeRange(0, _trailPoints.count - 42)];
    }
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];

    [self drawTrail];
    [self drawPulses];

    if (!self.cursorVisible || !self.stickerVisible) {
        return;
    }

    if (self.image) {
        NSRect drawRect = [self coverRectForImage:self.image];
        [NSGraphicsContext saveGraphicsState];
        [self applyStickerWalkPoseForRect:drawRect];
        [self drawCustomImage:self.image inRect:drawRect];
        [NSGraphicsContext restoreGraphicsState];
    } else {
        CGFloat size = self.cursorSize;
        NSRect drawRect = [self coverRectForSize:NSMakeSize(size, size)];
        [NSGraphicsContext saveGraphicsState];
        [self applyStickerWalkPoseForRect:drawRect];
        [self drawDefaultCartoonInRect:drawRect];
        [NSGraphicsContext restoreGraphicsState];
    }
}

- (NSRect)coverRectForImage:(NSImage *)image {
    CGFloat imageWidth = image.size.width;
    CGFloat imageHeight = image.size.height;

    if (image.representations.count > 0) {
        NSImageRep *representation = image.representations.firstObject;
        if (representation.pixelsWide > 0 && representation.pixelsHigh > 0) {
            imageWidth = representation.pixelsWide;
            imageHeight = representation.pixelsHigh;
        }
    }

    if (imageWidth <= 0 || imageHeight <= 0) {
        return [self coverRectForSize:NSMakeSize(self.cursorSize, self.cursorSize)];
    }

    CGFloat maxEdge = MAX(imageWidth, imageHeight);
    CGFloat scale = self.cursorSize / maxEdge;
    NSSize fittedSize = NSMakeSize(round(imageWidth * scale), round(imageHeight * scale));
    return [self coverRectForSize:fittedSize];
}

- (NSRect)coverRectForSize:(NSSize)size {
    // The system cursor hot spot sits at the arrow tip. Put that point near
    // the sticker's upper-left area so the sticker visually covers the arrow.
    CGFloat anchorX = 0.18;
    CGFloat anchorY = 0.82;

    NSPoint anchorPoint = [self stickerAnchorPoint];
    return NSMakeRect(round(anchorPoint.x - size.width * anchorX),
                      round(anchorPoint.y - size.height * anchorY),
                      size.width,
                      size.height);
}

- (void)drawCustomImage:(NSImage *)image inRect:(NSRect)rect {
    [NSGraphicsContext saveGraphicsState];

    NSShadow *shadow = [[NSShadow alloc] init];
    shadow.shadowBlurRadius = 9;
    shadow.shadowOffset = NSMakeSize(0, -2);
    shadow.shadowColor = [NSColor.blackColor colorWithAlphaComponent:0.22];
    [shadow set];

    [image drawInRect:rect
             fromRect:NSZeroRect
            operation:NSCompositingOperationSourceOver
             fraction:1.0
       respectFlipped:NO
                hints:nil];

    [NSGraphicsContext restoreGraphicsState];
}

+ (NSArray<NSColor *> *)defaultEffectColors {
    return @[
        [NSColor colorWithCalibratedRed:1.0 green:0.46 blue:0.63 alpha:1.0],
        [NSColor colorWithCalibratedRed:1.0 green:0.78 blue:0.25 alpha:1.0],
        [NSColor colorWithCalibratedRed:0.46 green:0.76 blue:1.0 alpha:1.0],
        [NSColor colorWithCalibratedRed:0.80 green:0.62 blue:1.0 alpha:1.0]
    ];
}

+ (NSArray<NSColor *> *)normalizedEffectColors:(NSArray<NSColor *> *)colors {
    NSMutableArray<NSColor *> *normalizedColors = [NSMutableArray array];

    for (id candidate in colors) {
        if (![candidate isKindOfClass:NSColor.class]) {
            continue;
        }

        NSColor *color = CartoonColorUsingSRGB(candidate);
        CGFloat red = 0;
        CGFloat green = 0;
        CGFloat blue = 0;
        CGFloat alpha = 0;
        [color getRed:&red green:&green blue:&blue alpha:&alpha];
        [normalizedColors addObject:[NSColor colorWithCalibratedRed:red green:green blue:blue alpha:1.0]];
        if (normalizedColors.count >= 4) {
            break;
        }
    }

    for (NSColor *fallbackColor in [self defaultEffectColors]) {
        if (normalizedColors.count >= 4) {
            break;
        }
        [normalizedColors addObject:fallbackColor];
    }

    return normalizedColors;
}

+ (NSArray<NSColor *> *)effectColorsForImage:(NSImage *)image {
    NSArray<NSColor *> *fallback = [self defaultEffectColors];
    NSBitmapImageRep *rep = nil;

    for (NSImageRep *candidate in image.representations) {
        if ([candidate isKindOfClass:NSBitmapImageRep.class]) {
            rep = (NSBitmapImageRep *)candidate;
            break;
        }
    }

    if (!rep && image.TIFFRepresentation) {
        rep = [NSBitmapImageRep imageRepWithData:image.TIFFRepresentation];
    }

    if (!rep || rep.pixelsWide <= 0 || rep.pixelsHigh <= 0) {
        return fallback;
    }

    NSMutableDictionary<NSString *, NSDictionary *> *buckets = [NSMutableDictionary dictionary];
    NSInteger step = MAX(1, MIN(rep.pixelsWide, rep.pixelsHigh) / 90);
    NSInteger sampledPixels = 0;
    NSInteger darkPixels = 0;

    for (NSInteger y = 0; y < rep.pixelsHigh; y += step) {
        for (NSInteger x = 0; x < rep.pixelsWide; x += step) {
            NSColor *pixel = [[rep colorAtX:x y:y] colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
            if (!pixel || pixel.alphaComponent < 0.35) {
                continue;
            }
            sampledPixels += 1;

            CGFloat hue = 0;
            CGFloat saturation = 0;
            CGFloat brightness = 0;
            CGFloat alpha = 0;
            [pixel getHue:&hue saturation:&saturation brightness:&brightness alpha:&alpha];

            if (brightness < 0.24) {
                darkPixels += 1;
                continue;
            }

            if (brightness > 0.96 || saturation < 0.18) {
                continue;
            }

            NSInteger hueBucket = (NSInteger)floor(hue * 24.0);
            NSInteger saturationBucket = (NSInteger)floor(saturation * 4.0);
            NSInteger brightnessBucket = (NSInteger)floor(brightness * 4.0);
            NSString *key = [NSString stringWithFormat:@"%ld-%ld-%ld",
                             (long)hueBucket,
                             (long)saturationBucket,
                             (long)brightnessBucket];

            NSDictionary *existing = buckets[key];
            NSInteger count = [existing[@"count"] integerValue] + 1;
            CGFloat score = count * (0.45 + saturation) * (0.40 + brightness);
            buckets[key] = @{
                @"count": @(count),
                @"score": @(score),
                @"hue": @(hue),
                @"saturation": @(MAX(0.45, saturation)),
                @"brightness": @(MIN(0.95, MAX(0.50, brightness)))
            };
        }
    }

    NSArray<NSDictionary *> *ranked = [buckets.allValues sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        CGFloat scoreA = [a[@"score"] doubleValue];
        CGFloat scoreB = [b[@"score"] doubleValue];
        if (scoreA < scoreB) {
            return NSOrderedDescending;
        }
        if (scoreA > scoreB) {
            return NSOrderedAscending;
        }
        return NSOrderedSame;
    }];

    NSMutableArray<NSColor *> *colors = [NSMutableArray array];
    for (NSDictionary *entry in ranked) {
        CGFloat hue = [entry[@"hue"] doubleValue];
        CGFloat saturation = [entry[@"saturation"] doubleValue];
        BOOL tooClose = NO;
        for (NSColor *existing in colors) {
            CGFloat existingHue = 0;
            CGFloat existingSaturation = 0;
            CGFloat existingBrightness = 0;
            CGFloat existingAlpha = 0;
            [[existing colorUsingColorSpace:NSColorSpace.sRGBColorSpace] getHue:&existingHue
                                                                      saturation:&existingSaturation
                                                                      brightness:&existingBrightness
                                                                           alpha:&existingAlpha];
            if (saturation < 0.10 || existingSaturation < 0.10) {
                continue;
            }

            CGFloat distance = fabs(hue - existingHue);
            distance = MIN(distance, 1.0 - distance);
            if (distance < 0.055) {
                tooClose = YES;
                break;
            }
        }

        if (tooClose) {
            continue;
        }

        NSColor *color = [NSColor colorWithCalibratedHue:hue
                                              saturation:saturation
                                              brightness:[entry[@"brightness"] doubleValue]
                                                   alpha:1.0];
        [colors addObject:color];
        if (colors.count >= 4) {
            break;
        }
    }

    BOOL shouldUseDarkAccent = sampledPixels > 0 && darkPixels > sampledPixels * 0.18;
    if (shouldUseDarkAccent) {
        for (NSColor *fallbackColor in fallback) {
            if (colors.count >= 3) {
                break;
            }
            [colors addObject:fallbackColor];
        }

        if (colors.count < 4) {
            [colors addObject:[NSColor colorWithCalibratedWhite:0.13 alpha:1.0]];
        }
    }

    for (NSColor *fallbackColor in fallback) {
        if (colors.count >= 4) {
            break;
        }
        [colors addObject:fallbackColor];
    }

    return colors;
}

- (NSArray<NSColor *> *)effectColorsForRole:(EffectColorRole)role {
    NSArray<NSColor *> *colors = nil;
    BOOL shouldUseNativeColors = self.nativeCursorEffectsEnabled;

    switch (role) {
        case EffectColorRoleTrail:
            colors = shouldUseNativeColors ? _nativeTrailEffectColors : _trailEffectColors;
            break;
        case EffectColorRoleClick:
            colors = shouldUseNativeColors ? _nativeClickEffectColors : _clickEffectColors;
            break;
        case EffectColorRoleParticle:
            colors = shouldUseNativeColors ? _nativeParticleEffectColors : _particleEffectColors;
            break;
    }

    return colors.count > 0 ? colors : self.class.defaultEffectColors;
}

- (NSColor *)effectColorForRole:(EffectColorRole)role index:(NSInteger)index alpha:(CGFloat)alpha {
    NSArray<NSColor *> *colors = [self effectColorsForRole:role];
    NSColor *baseColor = colors[index % colors.count];
    return [baseColor colorWithAlphaComponent:alpha];
}

- (void)drawDefaultCartoonInRect:(NSRect)rect {
    [NSGraphicsContext saveGraphicsState];

    NSShadow *shadow = [[NSShadow alloc] init];
    shadow.shadowBlurRadius = 10;
    shadow.shadowOffset = NSMakeSize(0, -3);
    shadow.shadowColor = [NSColor.blackColor colorWithAlphaComponent:0.22];
    [shadow set];

    [[NSColor colorWithCalibratedRed:1.0 green:0.82 blue:0.38 alpha:0.98] setFill];
    [[NSBezierPath bezierPathWithOvalInRect:NSInsetRect(rect, rect.size.width * 0.06, rect.size.height * 0.06)] fill];

    [NSGraphicsContext restoreGraphicsState];

    NSRect face = NSInsetRect(rect, rect.size.width * 0.06, rect.size.height * 0.06);
    NSRect leftEye = NSMakeRect(NSMinX(face) + NSWidth(face) * 0.30,
                                NSMinY(face) + NSHeight(face) * 0.56,
                                NSWidth(face) * 0.10,
                                NSHeight(face) * 0.14);
    NSRect rightEye = NSMakeRect(NSMinX(face) + NSWidth(face) * 0.60,
                                 NSMinY(face) + NSHeight(face) * 0.56,
                                 NSWidth(face) * 0.10,
                                 NSHeight(face) * 0.14);

    [[NSColor colorWithCalibratedWhite:0.08 alpha:0.92] setFill];
    [[NSBezierPath bezierPathWithOvalInRect:leftEye] fill];
    [[NSBezierPath bezierPathWithOvalInRect:rightEye] fill];

    [[NSColor.whiteColor colorWithAlphaComponent:0.85] setFill];
    [[NSBezierPath bezierPathWithOvalInRect:NSInsetRect(leftEye, NSWidth(leftEye) * 0.55, NSHeight(leftEye) * 0.58)] fill];
    [[NSBezierPath bezierPathWithOvalInRect:NSInsetRect(rightEye, NSWidth(rightEye) * 0.55, NSHeight(rightEye) * 0.58)] fill];

    [[NSColor colorWithCalibratedRed:1.0 green:0.42 blue:0.50 alpha:0.35] setFill];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(NSMinX(face) + NSWidth(face) * 0.17,
                                                       NSMinY(face) + NSHeight(face) * 0.40,
                                                       NSWidth(face) * 0.17,
                                                       NSHeight(face) * 0.10)] fill];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(NSMinX(face) + NSWidth(face) * 0.66,
                                                       NSMinY(face) + NSHeight(face) * 0.40,
                                                       NSWidth(face) * 0.17,
                                                       NSHeight(face) * 0.10)] fill];

    NSBezierPath *smile = [NSBezierPath bezierPath];
    [smile moveToPoint:NSMakePoint(NSMinX(face) + NSWidth(face) * 0.40,
                                   NSMinY(face) + NSHeight(face) * 0.38)];
    [smile curveToPoint:NSMakePoint(NSMinX(face) + NSWidth(face) * 0.60,
                                    NSMinY(face) + NSHeight(face) * 0.38)
          controlPoint1:NSMakePoint(NSMinX(face) + NSWidth(face) * 0.45,
                                    NSMinY(face) + NSHeight(face) * 0.29)
          controlPoint2:NSMakePoint(NSMinX(face) + NSWidth(face) * 0.55,
                                    NSMinY(face) + NSHeight(face) * 0.29)];
    [[NSColor colorWithCalibratedWhite:0.08 alpha:0.70] setStroke];
    smile.lineWidth = MAX(1.5, NSWidth(face) * 0.035);
    smile.lineCapStyle = NSLineCapStyleRound;
    [smile stroke];

    [self drawSparkleInsideRect:face];
}

- (void)drawSparkleInsideRect:(NSRect)rect {
    NSPoint center = NSMakePoint(NSMinX(rect) + NSWidth(rect) * 0.72,
                                 NSMinY(rect) + NSHeight(rect) * 0.73);
    CGFloat radius = NSWidth(rect) * 0.11;
    NSBezierPath *path = [NSBezierPath bezierPath];

    for (NSInteger index = 0; index < 8; index++) {
        CGFloat angle = (CGFloat)index * (CGFloat)M_PI / 4.0;
        CGFloat distance = index % 2 == 0 ? radius : radius * 0.42;
        NSPoint point = NSMakePoint(center.x + cos(angle) * distance,
                                    center.y + sin(angle) * distance);

        if (index == 0) {
            [path moveToPoint:point];
        } else {
            [path lineToPoint:point];
        }
    }

    [path closePath];
    [[NSColor colorWithCalibratedRed:0.42 green:0.72 blue:1.0 alpha:0.95] setFill];
    [path fill];
}

- (void)drawTrail {
    if (![self shouldDrawTrail]) {
        [_trailPoints removeAllObjects];
        return;
    }

    NSTimeInterval now = NSDate.timeIntervalSinceReferenceDate;
    CGFloat duration = 0.62;
    NSMutableArray<TrailPoint *> *activeTrailPoints = [NSMutableArray array];

    for (TrailPoint *trailPoint in _trailPoints) {
        CGFloat age = (CGFloat)(now - trailPoint.startTime);
        if (age >= duration) {
            continue;
        }

        [activeTrailPoints addObject:trailPoint];

        CGFloat progress = age / duration;
        CGFloat fade = pow(1.0 - progress, 1.55);
        CGFloat size = MAX(5.0, self.cursorSize * (0.105 - progress * 0.045));
        NSArray<NSColor *> *trailColors = [self effectColorsForRole:EffectColorRoleTrail];
        NSInteger colorIndex = trailPoint.seed % MAX(1, trailColors.count);
        NSColor *color = [self effectColorForRole:EffectColorRoleTrail index:colorIndex alpha:0.42 * fade];

        [self drawTrailBubbleAtPoint:trailPoint.point
                                size:size
                               color:color
                               alpha:0.42 * fade
                                seed:trailPoint.seed];
    }

    _trailPoints = activeTrailPoints;
}

- (void)drawTrailBubbleAtPoint:(NSPoint)point
                          size:(CGFloat)size
                         color:(NSColor *)color
                         alpha:(CGFloat)alpha
                          seed:(NSInteger)seed {
    CGFloat offset = sin((CGFloat)seed * 0.73) * size * 0.55;
    NSPoint bubblePoint = NSMakePoint(point.x + offset, point.y - size * 0.20);
    NSRect rect = NSMakeRect(bubblePoint.x - size / 2,
                             bubblePoint.y - size / 2,
                             size,
                             size);

    [[color colorWithAlphaComponent:alpha] setFill];
    [[NSBezierPath bezierPathWithOvalInRect:rect] fill];

    if (seed % 4 == 0) {
        NSColor *accent = [self effectColorForRole:EffectColorRoleTrail index:seed % 5 alpha:alpha * 0.75];
        [self drawStarAtPoint:NSMakePoint(bubblePoint.x + size * 0.66, bubblePoint.y + size * 0.18)
                         size:size * 0.86
                        color:accent
                        alpha:alpha * 0.75];
    }
}

- (void)drawPulses {
    if (![self shouldDrawPulse]) {
        [_pulses removeAllObjects];
        return;
    }

    NSTimeInterval now = NSDate.timeIntervalSinceReferenceDate;
    NSMutableArray<Pulse *> *activePulses = [NSMutableArray array];

    for (Pulse *pulse in _pulses) {
        NSTimeInterval age = now - pulse.startTime;
        CGFloat duration = 0.86;
        if (age >= duration) {
            continue;
        }

        [activePulses addObject:pulse];

        CGFloat progress = (CGFloat)(age / duration);
        CGFloat eased = 1.0 - pow(1.0 - progress, 3.0);
        CGFloat fade = pow(MAX(0.0, 1.0 - progress), 1.4);
        CGFloat baseRadius = MAX(34.0, self.cursorSize * 0.33);

        [self drawPulseGlowAtPoint:pulse.point
                         baseRadius:baseRadius
                           progress:progress
                               fade:fade];
        if ([self shouldDrawParticles]) {
            [self drawPulseParticlesAtPoint:pulse.point
                                  baseRadius:baseRadius
                                    progress:progress
                                       eased:eased
                                        fade:fade
                                        seed:pulse.seed];
        }
    }

    _pulses = activePulses;
}

- (void)drawPulseGlowAtPoint:(NSPoint)point
                  baseRadius:(CGFloat)baseRadius
                    progress:(CGFloat)progress
                        fade:(CGFloat)fade {
    CGFloat eased = 1.0 - pow(1.0 - progress, 3.0);
    CGFloat haloRadius = baseRadius * (0.40 + eased * 1.45);
    NSRect haloRect = NSMakeRect(point.x - haloRadius,
                                 point.y - haloRadius,
                                 haloRadius * 2,
                                 haloRadius * 2);

    [[self effectColorForRole:EffectColorRoleClick index:0 alpha:0.13 * fade] setFill];
    [[NSBezierPath bezierPathWithOvalInRect:haloRect] fill];

    CGFloat ringRadius = baseRadius * (0.58 + eased * 1.20);
    NSRect ringRect = NSMakeRect(point.x - ringRadius,
                                 point.y - ringRadius,
                                 ringRadius * 2,
                                 ringRadius * 2);
    NSBezierPath *ring = [NSBezierPath bezierPathWithOvalInRect:ringRect];
    ring.lineWidth = MAX(2.0, self.cursorSize * 0.020);
    [[self effectColorForRole:EffectColorRoleClick index:0 alpha:0.46 * fade] setStroke];
    [ring stroke];

    if (progress > 0.14) {
        CGFloat delayed = MIN(1.0, (progress - 0.14) / 0.86);
        CGFloat delayedFade = pow(1.0 - delayed, 1.7);
        CGFloat secondRadius = baseRadius * (0.42 + delayed * 1.55);
        NSRect secondRect = NSMakeRect(point.x - secondRadius,
                                       point.y - secondRadius,
                                       secondRadius * 2,
                                       secondRadius * 2);
        NSBezierPath *secondRing = [NSBezierPath bezierPathWithOvalInRect:secondRect];
        secondRing.lineWidth = MAX(1.5, self.cursorSize * 0.014);
        [[self effectColorForRole:EffectColorRoleClick index:1 alpha:0.28 * delayedFade] setStroke];
        [secondRing stroke];
    }
}

- (void)drawPulseParticlesAtPoint:(NSPoint)point
                        baseRadius:(CGFloat)baseRadius
                          progress:(CGFloat)progress
                             eased:(CGFloat)eased
                              fade:(CGFloat)fade
                              seed:(NSInteger)seed {
    NSInteger count = 10;
    CGFloat phase = (CGFloat)(seed % 31) * 0.09;
    CGFloat pop = sin(MIN(1.0, progress * 1.7) * (CGFloat)M_PI);

    for (NSInteger index = 0; index < count; index++) {
        CGFloat angle = phase + ((CGFloat)index / (CGFloat)count) * (CGFloat)M_PI * 2.0;
        CGFloat wobble = sin((CGFloat)(seed + index * 17)) * 0.12;
        CGFloat travel = baseRadius * (0.32 + eased * (1.15 + 0.12 * (CGFloat)(index % 3)));
        NSPoint particlePoint = NSMakePoint(point.x + cos(angle + wobble) * travel,
                                            point.y + sin(angle + wobble) * travel + pop * baseRadius * 0.10);
        CGFloat size = MAX(6.0, baseRadius * (0.13 + 0.018 * (CGFloat)(index % 4))) * (0.72 + pop * 0.28);
        CGFloat alpha = 0.88 * fade;
        NSColor *color = [self effectColorForRole:EffectColorRoleParticle index:index alpha:1.0];

        if (index % 3 == 0) {
            [self drawHeartAtPoint:particlePoint size:size color:color alpha:alpha];
        } else if (index % 3 == 1) {
            [self drawStarAtPoint:particlePoint size:size * 1.05 color:color alpha:alpha];
        } else {
            [self drawDotAtPoint:particlePoint size:size * 0.58 color:color alpha:alpha * 0.85];
        }
    }
}

- (void)drawHeartAtPoint:(NSPoint)point
                    size:(CGFloat)size
                   color:(NSColor *)color
                   alpha:(CGFloat)alpha {
    CGFloat s = size;
    NSBezierPath *heart = [NSBezierPath bezierPath];
    [heart moveToPoint:NSMakePoint(point.x, point.y - s * 0.42)];
    [heart curveToPoint:NSMakePoint(point.x - s * 0.48, point.y + s * 0.10)
          controlPoint1:NSMakePoint(point.x - s * 0.45, point.y - s * 0.15)
          controlPoint2:NSMakePoint(point.x - s * 0.58, point.y - s * 0.02)];
    [heart curveToPoint:NSMakePoint(point.x, point.y + s * 0.42)
          controlPoint1:NSMakePoint(point.x - s * 0.48, point.y + s * 0.36)
          controlPoint2:NSMakePoint(point.x - s * 0.16, point.y + s * 0.48)];
    [heart curveToPoint:NSMakePoint(point.x + s * 0.48, point.y + s * 0.10)
          controlPoint1:NSMakePoint(point.x + s * 0.16, point.y + s * 0.48)
          controlPoint2:NSMakePoint(point.x + s * 0.48, point.y + s * 0.36)];
    [heart curveToPoint:NSMakePoint(point.x, point.y - s * 0.42)
          controlPoint1:NSMakePoint(point.x + s * 0.58, point.y - s * 0.02)
          controlPoint2:NSMakePoint(point.x + s * 0.45, point.y - s * 0.15)];
    [heart closePath];

    [[color colorWithAlphaComponent:alpha] setFill];
    [heart fill];
}

- (void)drawStarAtPoint:(NSPoint)point
                   size:(CGFloat)size
                  color:(NSColor *)color
                  alpha:(CGFloat)alpha {
    CGFloat radius = size * 0.55;
    NSBezierPath *star = [NSBezierPath bezierPath];
    for (NSInteger index = 0; index < 8; index++) {
        CGFloat angle = (CGFloat)index * (CGFloat)M_PI / 4.0 + (CGFloat)M_PI / 8.0;
        CGFloat distance = index % 2 == 0 ? radius : radius * 0.42;
        NSPoint pointOnStar = NSMakePoint(point.x + cos(angle) * distance,
                                          point.y + sin(angle) * distance);
        if (index == 0) {
            [star moveToPoint:pointOnStar];
        } else {
            [star lineToPoint:pointOnStar];
        }
    }
    [star closePath];

    [[color colorWithAlphaComponent:alpha] setFill];
    [star fill];
}

- (void)drawDotAtPoint:(NSPoint)point
                  size:(CGFloat)size
                 color:(NSColor *)color
                 alpha:(CGFloat)alpha {
    NSRect rect = NSMakeRect(point.x - size / 2,
                             point.y - size / 2,
                             size,
                             size);
    [[color colorWithAlphaComponent:alpha] setFill];
    [[NSBezierPath bezierPathWithOvalInRect:rect] fill];
}

@end

@interface CursorController : NSObject
@property(nonatomic, assign, getter=isEnabled) BOOL enabled;
@property(nonatomic, assign) BOOL stickerWalkFollowEnabled;
@property(nonatomic, assign) BOOL stickerFrameAnimationEnabled;
@property(nonatomic, assign) CGFloat stickerWalkSpeedMultiplier;
@property(nonatomic, assign) CGFloat stickerWalkAmplitudeMultiplier;
@property(nonatomic, assign) BOOL nativeCursorEffectsEnabled;
@property(nonatomic, assign) BOOL hideSystemCursor;
@property(nonatomic, assign) BOOL virtualCursorEnabled;
@property(nonatomic, assign, readonly) BOOL virtualCursorActive;
@property(nonatomic, assign, readonly) BOOL needsAccessibilityPermission;
@property(nonatomic, assign) CGFloat cursorSize;
@property(nonatomic, assign) CursorEffectStyle effectStyle;
@property(nonatomic, assign) EffectColorMode effectColorMode;
@property(nonatomic, assign) EffectColorMode nativeEffectColorMode;
@property(nonatomic, copy) NSArray<NSColor *> *customTrailColors;
@property(nonatomic, copy) NSArray<NSColor *> *customClickColors;
@property(nonatomic, copy) NSArray<NSColor *> *customParticleColors;
@property(nonatomic, copy) NSArray<NSColor *> *customNativeTrailColors;
@property(nonatomic, copy) NSArray<NSColor *> *customNativeClickColors;
@property(nonatomic, copy) NSArray<NSColor *> *customNativeParticleColors;
+ (NSArray<NSNumber *> *)sizes;
- (void)start;
- (void)stop;
- (void)loadImageFromURL:(NSURL *)url;
- (void)useDefaultCartoon;
- (CGEventRef)handleEventTapWithType:(CGEventType)type event:(CGEventRef)event;
@end

static CGEventRef CartoonCursorEventTapCallback(CGEventTapProxy proxy,
                                                CGEventType type,
                                                CGEventRef event,
                                                void *userInfo);

@implementation CursorController {
    NSMutableArray<OverlayWindow *> *_windows;
    NSMutableArray<CursorView *> *_views;
    NSTimer *_timer;
    id _screenObserver;
    id _globalClickMonitor;
    id _localClickMonitor;
    NSMutableDictionary<NSNumber *, NSNumber *> *_hideDepthByDisplay;
    NSInteger _nsCursorHideDepth;
    NSTimeInterval _lastCursorSuppressionTime;
    CFMachPortRef _eventTap;
    CFRunLoopSourceRef _eventTapSource;
    BOOL _virtualCursorEnabled;
    BOOL _virtualCursorActive;
    BOOL _needsAccessibilityPermission;
    BOOL _mouseCursorAssociated;
    BOOL _stickerWalkFollowEnabled;
    BOOL _stickerFrameAnimationEnabled;
    CGFloat _stickerWalkSpeedMultiplier;
    CGFloat _stickerWalkAmplitudeMultiplier;
    BOOL _nativeCursorEffectsEnabled;
    CGPoint _virtualQuartzPoint;
    CursorEffectStyle _effectStyle;
    EffectColorMode _effectColorMode;
    EffectColorMode _nativeEffectColorMode;
    NSArray<NSColor *> *_customTrailColors;
    NSArray<NSColor *> *_customClickColors;
    NSArray<NSColor *> *_customParticleColors;
    NSArray<NSColor *> *_customNativeTrailColors;
    NSArray<NSColor *> *_customNativeClickColors;
    NSArray<NSColor *> *_customNativeParticleColors;
    NSImage *_customImage;
}

+ (NSArray<NSNumber *> *)sizes {
    return @[@32, @48, @64, @80, @96, @128, @160, @192, @256];
}

+ (NSArray<NSColor *> *)effectColorsFromStoredHexStrings:(NSArray *)hexStrings {
    NSMutableArray<NSColor *> *colors = [NSMutableArray array];
    for (id value in hexStrings) {
        if (![value isKindOfClass:NSString.class]) {
            continue;
        }

        NSColor *color = CartoonColorFromHexString(value);
        if (color) {
            [colors addObject:color];
        }
    }

    return [CursorView normalizedEffectColors:colors];
}

+ (NSArray<NSString *> *)storedHexStringsFromEffectColors:(NSArray<NSColor *> *)colors {
    NSMutableArray<NSString *> *hexStrings = [NSMutableArray array];
    for (NSColor *color in [CursorView normalizedEffectColors:colors]) {
        [hexStrings addObject:CartoonHexStringFromColor(color)];
    }
    return hexStrings;
}

- (instancetype)init {
    self = [super init];
    if (!self) {
        return nil;
    }

    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if ([defaults objectForKey:DefaultsKeyEnabled] == nil) {
        _enabled = YES;
    } else {
        _enabled = [defaults boolForKey:DefaultsKeyEnabled];
    }

    if ([defaults objectForKey:DefaultsKeyStickerWalkFollow] == nil) {
        _stickerWalkFollowEnabled = NO;
        [defaults setBool:NO forKey:DefaultsKeyStickerWalkFollow];
    } else {
        _stickerWalkFollowEnabled = [defaults boolForKey:DefaultsKeyStickerWalkFollow];
    }

    if ([defaults objectForKey:DefaultsKeyStickerFrameAnimation] == nil) {
        _stickerFrameAnimationEnabled = NO;
        [defaults setBool:NO forKey:DefaultsKeyStickerFrameAnimation];
    } else {
        _stickerFrameAnimationEnabled = [defaults boolForKey:DefaultsKeyStickerFrameAnimation];
    }

    if ([defaults objectForKey:DefaultsKeyStickerWalkSpeed] == nil) {
        _stickerWalkSpeedMultiplier = DefaultStickerWalkSpeed;
        [defaults setDouble:_stickerWalkSpeedMultiplier forKey:DefaultsKeyStickerWalkSpeed];
    } else {
        _stickerWalkSpeedMultiplier = CartoonClampedStickerWalkSpeed([defaults doubleForKey:DefaultsKeyStickerWalkSpeed]);
    }

    if ([defaults objectForKey:DefaultsKeyStickerWalkAmplitude] == nil) {
        _stickerWalkAmplitudeMultiplier = DefaultStickerWalkAmplitude;
        [defaults setDouble:_stickerWalkAmplitudeMultiplier forKey:DefaultsKeyStickerWalkAmplitude];
    } else {
        _stickerWalkAmplitudeMultiplier = CartoonClampedStickerWalkAmplitude([defaults doubleForKey:DefaultsKeyStickerWalkAmplitude]);
    }

    NSInteger behaviorVersion = [defaults integerForKey:DefaultsKeyBehaviorVersion];
    if (behaviorVersion < CurrentBehaviorVersion) {
        _hideSystemCursor = NO;
        [defaults setBool:NO forKey:DefaultsKeyHideSystemCursor];
        [defaults setInteger:CurrentBehaviorVersion forKey:DefaultsKeyBehaviorVersion];
    } else if ([defaults objectForKey:DefaultsKeyHideSystemCursor] == nil) {
        _hideSystemCursor = NO;
    } else {
        _hideSystemCursor = [defaults boolForKey:DefaultsKeyHideSystemCursor];
    }

    if ([defaults objectForKey:DefaultsKeyVirtualCursor] == nil || behaviorVersion < CurrentBehaviorVersion) {
        _virtualCursorEnabled = NO;
        [defaults setBool:NO forKey:DefaultsKeyVirtualCursor];
    } else {
        _virtualCursorEnabled = [defaults boolForKey:DefaultsKeyVirtualCursor];
    }

    double savedSize = [defaults doubleForKey:DefaultsKeyCursorSize];
    if (behaviorVersion < CurrentBehaviorVersion || savedSize <= 0) {
        _cursorSize = DefaultCoverCursorSize;
        [defaults setDouble:_cursorSize forKey:DefaultsKeyCursorSize];
    } else {
        _cursorSize = (CGFloat)savedSize;
    }

    if ([defaults objectForKey:DefaultsKeyEffectStyle] == nil) {
        _effectStyle = CursorEffectStyleSparklesTrail;
        [defaults setInteger:_effectStyle forKey:DefaultsKeyEffectStyle];
    } else {
        _effectStyle = [defaults integerForKey:DefaultsKeyEffectStyle];
        if (_effectStyle < CursorEffectStyleOff || _effectStyle > CursorEffectStyleSparklesTrail) {
            _effectStyle = CursorEffectStyleSparklesTrail;
        }
    }

    if ([defaults objectForKey:DefaultsKeyEffectColorMode] == nil) {
        _effectColorMode = EffectColorModeAuto;
        [defaults setInteger:_effectColorMode forKey:DefaultsKeyEffectColorMode];
    } else {
        _effectColorMode = [defaults integerForKey:DefaultsKeyEffectColorMode] == EffectColorModeCustom ?
            EffectColorModeCustom :
            EffectColorModeAuto;
    }

    NSArray *legacyStoredColors = [defaults arrayForKey:DefaultsKeyCustomEffectColors];
    NSArray<NSColor *> *legacyColors = legacyStoredColors.count > 0 ?
        [self.class effectColorsFromStoredHexStrings:legacyStoredColors] :
        [CursorView defaultEffectColors];

    NSArray *storedTrailColors = [defaults arrayForKey:DefaultsKeyCustomTrailColors];
    _customTrailColors = storedTrailColors.count > 0 ?
        [self.class effectColorsFromStoredHexStrings:storedTrailColors] :
        legacyColors;
    if ([defaults objectForKey:DefaultsKeyCustomTrailColors] == nil) {
        [defaults setObject:[self.class storedHexStringsFromEffectColors:_customTrailColors]
                     forKey:DefaultsKeyCustomTrailColors];
    }

    NSArray *storedClickColors = [defaults arrayForKey:DefaultsKeyCustomClickColors];
    _customClickColors = storedClickColors.count > 0 ?
        [self.class effectColorsFromStoredHexStrings:storedClickColors] :
        legacyColors;
    if ([defaults objectForKey:DefaultsKeyCustomClickColors] == nil) {
        [defaults setObject:[self.class storedHexStringsFromEffectColors:_customClickColors]
                     forKey:DefaultsKeyCustomClickColors];
    }

    NSArray *storedParticleColors = [defaults arrayForKey:DefaultsKeyCustomParticleColors];
    _customParticleColors = storedParticleColors.count > 0 ?
        [self.class effectColorsFromStoredHexStrings:storedParticleColors] :
        legacyColors;
    if ([defaults objectForKey:DefaultsKeyCustomParticleColors] == nil) {
        [defaults setObject:[self.class storedHexStringsFromEffectColors:_customParticleColors]
                     forKey:DefaultsKeyCustomParticleColors];
    }

    if ([defaults objectForKey:DefaultsKeyNativeEffectColorMode] == nil) {
        _nativeEffectColorMode = _effectColorMode;
        [defaults setInteger:_nativeEffectColorMode forKey:DefaultsKeyNativeEffectColorMode];
    } else {
        _nativeEffectColorMode = [defaults integerForKey:DefaultsKeyNativeEffectColorMode] == EffectColorModeCustom ?
            EffectColorModeCustom :
            EffectColorModeAuto;
    }

    NSArray *storedNativeTrailColors = [defaults arrayForKey:DefaultsKeyCustomNativeTrailColors];
    _customNativeTrailColors = storedNativeTrailColors.count > 0 ?
        [self.class effectColorsFromStoredHexStrings:storedNativeTrailColors] :
        _customTrailColors;
    if ([defaults objectForKey:DefaultsKeyCustomNativeTrailColors] == nil) {
        [defaults setObject:[self.class storedHexStringsFromEffectColors:_customNativeTrailColors]
                     forKey:DefaultsKeyCustomNativeTrailColors];
    }

    NSArray *storedNativeClickColors = [defaults arrayForKey:DefaultsKeyCustomNativeClickColors];
    _customNativeClickColors = storedNativeClickColors.count > 0 ?
        [self.class effectColorsFromStoredHexStrings:storedNativeClickColors] :
        _customClickColors;
    if ([defaults objectForKey:DefaultsKeyCustomNativeClickColors] == nil) {
        [defaults setObject:[self.class storedHexStringsFromEffectColors:_customNativeClickColors]
                     forKey:DefaultsKeyCustomNativeClickColors];
    }

    NSArray *storedNativeParticleColors = [defaults arrayForKey:DefaultsKeyCustomNativeParticleColors];
    _customNativeParticleColors = storedNativeParticleColors.count > 0 ?
        [self.class effectColorsFromStoredHexStrings:storedNativeParticleColors] :
        _customParticleColors;
    if ([defaults objectForKey:DefaultsKeyCustomNativeParticleColors] == nil) {
        [defaults setObject:[self.class storedHexStringsFromEffectColors:_customNativeParticleColors]
                     forKey:DefaultsKeyCustomNativeParticleColors];
    }

    if ([defaults objectForKey:DefaultsKeyNativeCursorEffects] == nil) {
        _nativeCursorEffectsEnabled = NO;
        [defaults setBool:NO forKey:DefaultsKeyNativeCursorEffects];
    } else {
        _nativeCursorEffectsEnabled = [defaults boolForKey:DefaultsKeyNativeCursorEffects];
    }

    NSString *imagePath = [defaults stringForKey:DefaultsKeyImagePath];
    if (imagePath.length > 0) {
        _customImage = [[NSImage alloc] initWithContentsOfFile:imagePath];
    }

    _hideDepthByDisplay = [NSMutableDictionary dictionary];
    _windows = [NSMutableArray array];
    _views = [NSMutableArray array];
    _nsCursorHideDepth = 0;
    _lastCursorSuppressionTime = 0;
    _eventTap = NULL;
    _eventTapSource = NULL;
    _virtualCursorActive = NO;
    _needsAccessibilityPermission = NO;
    _mouseCursorAssociated = YES;
    _virtualQuartzPoint = CGPointZero;
    return self;
}

- (void)dealloc {
    [self stop];
}

- (void)setEnabled:(BOOL)enabled {
    _enabled = enabled;
    [NSUserDefaults.standardUserDefaults setBool:enabled forKey:DefaultsKeyEnabled];
    [self applyVirtualCursorState];
    [self applyEnabledState];
}

- (BOOL)stickerWalkFollowEnabled {
    return _stickerWalkFollowEnabled;
}

- (void)setStickerWalkFollowEnabled:(BOOL)stickerWalkFollowEnabled {
    _stickerWalkFollowEnabled = stickerWalkFollowEnabled;
    [NSUserDefaults.standardUserDefaults setBool:stickerWalkFollowEnabled forKey:DefaultsKeyStickerWalkFollow];
    for (CursorView *view in _views) {
        view.stickerWalkFollowEnabled = stickerWalkFollowEnabled;
    }
}

- (BOOL)stickerFrameAnimationEnabled {
    return _stickerFrameAnimationEnabled;
}

- (void)setStickerFrameAnimationEnabled:(BOOL)stickerFrameAnimationEnabled {
    _stickerFrameAnimationEnabled = stickerFrameAnimationEnabled;
    [NSUserDefaults.standardUserDefaults setBool:stickerFrameAnimationEnabled forKey:DefaultsKeyStickerFrameAnimation];
    for (CursorView *view in _views) {
        view.stickerFrameAnimationEnabled = stickerFrameAnimationEnabled;
    }
}

- (CGFloat)stickerWalkSpeedMultiplier {
    return _stickerWalkSpeedMultiplier;
}

- (void)setStickerWalkSpeedMultiplier:(CGFloat)stickerWalkSpeedMultiplier {
    _stickerWalkSpeedMultiplier = CartoonClampedStickerWalkSpeed(stickerWalkSpeedMultiplier);
    [NSUserDefaults.standardUserDefaults setDouble:_stickerWalkSpeedMultiplier forKey:DefaultsKeyStickerWalkSpeed];
    for (CursorView *view in _views) {
        view.stickerWalkSpeedMultiplier = _stickerWalkSpeedMultiplier;
    }
}

- (CGFloat)stickerWalkAmplitudeMultiplier {
    return _stickerWalkAmplitudeMultiplier;
}

- (void)setStickerWalkAmplitudeMultiplier:(CGFloat)stickerWalkAmplitudeMultiplier {
    _stickerWalkAmplitudeMultiplier = CartoonClampedStickerWalkAmplitude(stickerWalkAmplitudeMultiplier);
    [NSUserDefaults.standardUserDefaults setDouble:_stickerWalkAmplitudeMultiplier forKey:DefaultsKeyStickerWalkAmplitude];
    for (CursorView *view in _views) {
        view.stickerWalkAmplitudeMultiplier = _stickerWalkAmplitudeMultiplier;
    }
}

- (BOOL)nativeCursorEffectsEnabled {
    return _nativeCursorEffectsEnabled;
}

- (void)setNativeCursorEffectsEnabled:(BOOL)nativeCursorEffectsEnabled {
    _nativeCursorEffectsEnabled = nativeCursorEffectsEnabled;
    [NSUserDefaults.standardUserDefaults setBool:nativeCursorEffectsEnabled forKey:DefaultsKeyNativeCursorEffects];
    for (CursorView *view in _views) {
        view.nativeCursorEffectsEnabled = nativeCursorEffectsEnabled;
    }
    [self applyEnabledState];
}

- (void)setHideSystemCursor:(BOOL)hideSystemCursor {
    _hideSystemCursor = hideSystemCursor;
    [NSUserDefaults.standardUserDefaults setBool:hideSystemCursor forKey:DefaultsKeyHideSystemCursor];
    [self applyVirtualCursorState];
    [self applyCursorVisibility];
}

- (BOOL)virtualCursorActive {
    return _virtualCursorActive;
}

- (BOOL)needsAccessibilityPermission {
    return _needsAccessibilityPermission;
}

- (BOOL)virtualCursorEnabled {
    return _virtualCursorEnabled;
}

- (void)setVirtualCursorEnabled:(BOOL)virtualCursorEnabled {
    _virtualCursorEnabled = virtualCursorEnabled;
    [NSUserDefaults.standardUserDefaults setBool:virtualCursorEnabled forKey:DefaultsKeyVirtualCursor];
    [self applyVirtualCursorState];
}

- (void)setCursorSize:(CGFloat)cursorSize {
    _cursorSize = cursorSize;
    [NSUserDefaults.standardUserDefaults setDouble:cursorSize forKey:DefaultsKeyCursorSize];
    for (CursorView *view in _views) {
        view.cursorSize = cursorSize;
    }
}

- (CursorEffectStyle)effectStyle {
    return _effectStyle;
}

- (void)setEffectStyle:(CursorEffectStyle)effectStyle {
    _effectStyle = effectStyle;
    [NSUserDefaults.standardUserDefaults setInteger:effectStyle forKey:DefaultsKeyEffectStyle];
    for (CursorView *view in _views) {
        view.effectStyle = effectStyle;
    }
}

- (EffectColorMode)effectColorMode {
    return _effectColorMode;
}

- (void)setEffectColorMode:(EffectColorMode)effectColorMode {
    _effectColorMode = effectColorMode == EffectColorModeCustom ? EffectColorModeCustom : EffectColorModeAuto;
    [NSUserDefaults.standardUserDefaults setInteger:_effectColorMode forKey:DefaultsKeyEffectColorMode];
    for (CursorView *view in _views) {
        view.effectColorMode = _effectColorMode;
    }
}

- (EffectColorMode)nativeEffectColorMode {
    return _nativeEffectColorMode;
}

- (void)setNativeEffectColorMode:(EffectColorMode)nativeEffectColorMode {
    _nativeEffectColorMode = nativeEffectColorMode == EffectColorModeCustom ? EffectColorModeCustom : EffectColorModeAuto;
    [NSUserDefaults.standardUserDefaults setInteger:_nativeEffectColorMode forKey:DefaultsKeyNativeEffectColorMode];
    for (CursorView *view in _views) {
        view.nativeEffectColorMode = _nativeEffectColorMode;
    }
}

- (NSArray<NSColor *> *)customTrailColors {
    return _customTrailColors;
}

- (void)setCustomTrailColors:(NSArray<NSColor *> *)customTrailColors {
    _customTrailColors = [CursorView normalizedEffectColors:customTrailColors];
    [NSUserDefaults.standardUserDefaults setObject:[self.class storedHexStringsFromEffectColors:_customTrailColors]
                                           forKey:DefaultsKeyCustomTrailColors];
    for (CursorView *view in _views) {
        view.customTrailColors = _customTrailColors;
    }
}

- (NSArray<NSColor *> *)customClickColors {
    return _customClickColors;
}

- (void)setCustomClickColors:(NSArray<NSColor *> *)customClickColors {
    _customClickColors = [CursorView normalizedEffectColors:customClickColors];
    [NSUserDefaults.standardUserDefaults setObject:[self.class storedHexStringsFromEffectColors:_customClickColors]
                                           forKey:DefaultsKeyCustomClickColors];
    for (CursorView *view in _views) {
        view.customClickColors = _customClickColors;
    }
}

- (NSArray<NSColor *> *)customParticleColors {
    return _customParticleColors;
}

- (void)setCustomParticleColors:(NSArray<NSColor *> *)customParticleColors {
    _customParticleColors = [CursorView normalizedEffectColors:customParticleColors];
    [NSUserDefaults.standardUserDefaults setObject:[self.class storedHexStringsFromEffectColors:_customParticleColors]
                                           forKey:DefaultsKeyCustomParticleColors];
    for (CursorView *view in _views) {
        view.customParticleColors = _customParticleColors;
    }
}

- (NSArray<NSColor *> *)customNativeTrailColors {
    return _customNativeTrailColors;
}

- (void)setCustomNativeTrailColors:(NSArray<NSColor *> *)customNativeTrailColors {
    _customNativeTrailColors = [CursorView normalizedEffectColors:customNativeTrailColors];
    [NSUserDefaults.standardUserDefaults setObject:[self.class storedHexStringsFromEffectColors:_customNativeTrailColors]
                                           forKey:DefaultsKeyCustomNativeTrailColors];
    for (CursorView *view in _views) {
        view.customNativeTrailColors = _customNativeTrailColors;
    }
}

- (NSArray<NSColor *> *)customNativeClickColors {
    return _customNativeClickColors;
}

- (void)setCustomNativeClickColors:(NSArray<NSColor *> *)customNativeClickColors {
    _customNativeClickColors = [CursorView normalizedEffectColors:customNativeClickColors];
    [NSUserDefaults.standardUserDefaults setObject:[self.class storedHexStringsFromEffectColors:_customNativeClickColors]
                                           forKey:DefaultsKeyCustomNativeClickColors];
    for (CursorView *view in _views) {
        view.customNativeClickColors = _customNativeClickColors;
    }
}

- (NSArray<NSColor *> *)customNativeParticleColors {
    return _customNativeParticleColors;
}

- (void)setCustomNativeParticleColors:(NSArray<NSColor *> *)customNativeParticleColors {
    _customNativeParticleColors = [CursorView normalizedEffectColors:customNativeParticleColors];
    [NSUserDefaults.standardUserDefaults setObject:[self.class storedHexStringsFromEffectColors:_customNativeParticleColors]
                                           forKey:DefaultsKeyCustomNativeParticleColors];
    for (CursorView *view in _views) {
        view.customNativeParticleColors = _customNativeParticleColors;
    }
}

- (void)start {
    [self rebuildOverlay];
    [self startClickMonitors];

    __weak typeof(self) weakSelf = self;
    _screenObserver = [NSNotificationCenter.defaultCenter addObserverForName:NSApplicationDidChangeScreenParametersNotification
                                                                      object:nil
                                                                       queue:NSOperationQueue.mainQueue
                                                                  usingBlock:^(__unused NSNotification *notification) {
        [weakSelf rebalanceHiddenCursorForActiveDisplays];
        [weakSelf rebuildOverlay];
    }];

    [self applyVirtualCursorState];
    [self applyEnabledState];
}

- (void)stop {
    [self stopVirtualCursorIfNeeded];
    [self stopTimer];
    [self removeClickMonitors];
    [self showSystemCursorIfNeeded];
    for (OverlayWindow *window in _windows) {
        [window orderOut:nil];
    }
    [_windows removeAllObjects];
    [_views removeAllObjects];

    if (_screenObserver) {
        [NSNotificationCenter.defaultCenter removeObserver:_screenObserver];
        _screenObserver = nil;
    }
}

- (void)loadImageFromURL:(NSURL *)url {
    NSImage *image = [[NSImage alloc] initWithContentsOfURL:url];
    if (!image) {
        return;
    }

    _customImage = image;
    [NSUserDefaults.standardUserDefaults setObject:url.path forKey:DefaultsKeyImagePath];
    for (CursorView *view in _views) {
        view.image = image;
    }
}

- (void)useDefaultCartoon {
    _customImage = nil;
    [NSUserDefaults.standardUserDefaults removeObjectForKey:DefaultsKeyImagePath];
    for (CursorView *view in _views) {
        view.image = nil;
    }
}

- (void)rebuildOverlay {
    BOOL wasVisible = [self shouldRunOverlay];

    for (OverlayWindow *window in _windows) {
        [window orderOut:nil];
    }
    [_windows removeAllObjects];
    [_views removeAllObjects];

    for (NSScreen *screen in NSScreen.screens) {
        NSRect frame = screen.frame;
        CursorView *newView = [[CursorView alloc] initWithFrame:NSMakeRect(0, 0, NSWidth(frame), NSHeight(frame))];
        newView.cursorSize = self.cursorSize;
        newView.image = _customImage;
        newView.effectStyle = self.effectStyle;
        newView.stickerWalkFollowEnabled = self.stickerWalkFollowEnabled;
        newView.stickerFrameAnimationEnabled = self.stickerFrameAnimationEnabled;
        newView.stickerWalkSpeedMultiplier = self.stickerWalkSpeedMultiplier;
        newView.stickerWalkAmplitudeMultiplier = self.stickerWalkAmplitudeMultiplier;
        newView.customTrailColors = self.customTrailColors;
        newView.customClickColors = self.customClickColors;
        newView.customParticleColors = self.customParticleColors;
        newView.nativeCursorEffectsEnabled = self.nativeCursorEffectsEnabled;
        newView.customNativeTrailColors = self.customNativeTrailColors;
        newView.customNativeClickColors = self.customNativeClickColors;
        newView.customNativeParticleColors = self.customNativeParticleColors;
        newView.nativeEffectColorMode = self.nativeEffectColorMode;
        newView.effectColorMode = self.effectColorMode;
        newView.stickerVisible = self.isEnabled;

        OverlayWindow *newWindow = [[OverlayWindow alloc] initWithFrame:frame];
        newWindow.contentView = newView;

        [_views addObject:newView];
        [_windows addObject:newWindow];

        if (wasVisible) {
            [newWindow orderFrontRegardless];
        }
    }

    [self tick];
}

- (void)applyEnabledState {
    if ([self shouldRunOverlay]) {
        if (_windows.count == 0) {
            [self rebuildOverlay];
        }

        for (OverlayWindow *window in _windows) {
            [window orderFrontRegardless];
        }
        [self startTimer];
    } else {
        [self stopVirtualCursorIfNeeded];
        [self stopTimer];
        for (OverlayWindow *window in _windows) {
            [window orderOut:nil];
        }
    }

    [self applyCursorVisibility];
}

- (BOOL)shouldRunOverlay {
    return self.isEnabled || self.nativeCursorEffectsEnabled;
}

- (void)startTimer {
    if (_timer) {
        return;
    }

    __weak typeof(self) weakSelf = self;
    _timer = [NSTimer timerWithTimeInterval:1.0 / 60.0
                                    repeats:YES
                                      block:^(__unused NSTimer *timer) {
        [weakSelf tick];
    }];
    [NSRunLoop.mainRunLoop addTimer:_timer forMode:NSRunLoopCommonModes];
}

- (void)stopTimer {
    [_timer invalidate];
    _timer = nil;
}

- (void)tick {
    if (![self shouldRunOverlay] || _windows.count == 0) {
        return;
    }

    NSPoint globalPoint = [self currentCursorAppKitPoint];
    NSPoint localPoint = NSZeroPoint;
    CursorView *activeView = [self viewForGlobalPoint:globalPoint localPoint:&localPoint];

    for (CursorView *view in _views) {
        BOOL isActiveView = view == activeView;
        view.cursorVisible = isActiveView;
        view.stickerVisible = self.isEnabled && isActiveView;
    }

    if (activeView) {
        activeView.cursorPoint = localPoint;
    }

    [self reinforceCursorVisibilityState];
}

- (void)startClickMonitors {
    NSEventMask mask = NSEventMaskLeftMouseDown | NSEventMaskRightMouseDown | NSEventMaskOtherMouseDown;
    __weak typeof(self) weakSelf = self;

    _globalClickMonitor = [NSEvent addGlobalMonitorForEventsMatchingMask:mask handler:^(__unused NSEvent *event) {
        [weakSelf addPulse];
    }];

    _localClickMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:mask handler:^NSEvent *(NSEvent *event) {
        [weakSelf addPulse];
        return event;
    }];
}

- (void)removeClickMonitors {
    if (_globalClickMonitor) {
        [NSEvent removeMonitor:_globalClickMonitor];
        _globalClickMonitor = nil;
    }

    if (_localClickMonitor) {
        [NSEvent removeMonitor:_localClickMonitor];
        _localClickMonitor = nil;
    }
}

- (void)addPulse {
    if (![self shouldRunOverlay] || _windows.count == 0) {
        return;
    }

    NSPoint globalPoint = [self currentCursorAppKitPoint];
    NSPoint localPoint = NSZeroPoint;
    CursorView *activeView = [self viewForGlobalPoint:globalPoint localPoint:&localPoint];
    [activeView addPulseAtPoint:localPoint];
}

- (CursorView *)viewForGlobalPoint:(NSPoint)globalPoint localPoint:(NSPoint *)localPoint {
    for (NSUInteger index = 0; index < _windows.count; index++) {
        OverlayWindow *window = _windows[index];
        if (!NSPointInRect(globalPoint, window.frame)) {
            continue;
        }

        if (localPoint) {
            *localPoint = NSMakePoint(globalPoint.x - NSMinX(window.frame),
                                      globalPoint.y - NSMinY(window.frame));
        }

        return _views[index];
    }

    return nil;
}

- (NSPoint)currentCursorAppKitPoint {
    if (_virtualCursorActive) {
        return [self.class appKitPointFromQuartzPoint:_virtualQuartzPoint];
    }

    return NSEvent.mouseLocation;
}

- (void)applyVirtualCursorState {
    if (self.isEnabled && self.hideSystemCursor && self.virtualCursorEnabled) {
        [self startVirtualCursorIfPossible];
    } else {
        [self stopVirtualCursorIfNeeded];
    }
}

- (void)startVirtualCursorIfPossible {
    if (_virtualCursorActive) {
        return;
    }

    if (![self requestAccessibilityTrustIfNeeded]) {
        _needsAccessibilityPermission = YES;
        return;
    }
    _needsAccessibilityPermission = NO;

    _virtualQuartzPoint = [self.class quartzPointFromAppKitPoint:NSEvent.mouseLocation];

    CGEventMask eventMask =
        CGEventMaskBit(kCGEventMouseMoved) |
        CGEventMaskBit(kCGEventLeftMouseDown) |
        CGEventMaskBit(kCGEventLeftMouseUp) |
        CGEventMaskBit(kCGEventRightMouseDown) |
        CGEventMaskBit(kCGEventRightMouseUp) |
        CGEventMaskBit(kCGEventOtherMouseDown) |
        CGEventMaskBit(kCGEventOtherMouseUp) |
        CGEventMaskBit(kCGEventLeftMouseDragged) |
        CGEventMaskBit(kCGEventRightMouseDragged) |
        CGEventMaskBit(kCGEventOtherMouseDragged) |
        CGEventMaskBit(kCGEventScrollWheel);

    _eventTap = CGEventTapCreate(kCGHIDEventTap,
                                 kCGHeadInsertEventTap,
                                 kCGEventTapOptionDefault,
                                 eventMask,
                                 CartoonCursorEventTapCallback,
                                 (__bridge void *)self);

    if (!_eventTap) {
        _needsAccessibilityPermission = YES;
        return;
    }

    _eventTapSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, _eventTap, 0);
    CFRunLoopAddSource(CFRunLoopGetMain(), _eventTapSource, kCFRunLoopCommonModes);
    CGEventTapEnable(_eventTap, true);

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    CGAssociateMouseAndMouseCursorPosition(false);
#pragma clang diagnostic pop
    _mouseCursorAssociated = NO;
    _virtualCursorActive = YES;

    [self parkSystemCursorAwayFromVirtualCursor];
    [self reinforceCursorVisibilityState];
}

- (BOOL)requestAccessibilityTrustIfNeeded {
    NSDictionary *options = @{(__bridge NSString *)kAXTrustedCheckOptionPrompt: @(YES)};
    return AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);
}

- (void)stopVirtualCursorIfNeeded {
    if (_eventTap) {
        CGEventTapEnable(_eventTap, false);
    }

    if (_eventTapSource) {
        CFRunLoopRemoveSource(CFRunLoopGetMain(), _eventTapSource, kCFRunLoopCommonModes);
        CFRelease(_eventTapSource);
        _eventTapSource = NULL;
    }

    if (_eventTap) {
        CFRelease(_eventTap);
        _eventTap = NULL;
    }

    if (!_mouseCursorAssociated) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        CGAssociateMouseAndMouseCursorPosition(true);
#pragma clang diagnostic pop
        _mouseCursorAssociated = YES;
        CGWarpMouseCursorPosition(_virtualQuartzPoint);
    }

    _virtualCursorActive = NO;
}

- (CGEventRef)handleEventTapWithType:(CGEventType)type event:(CGEventRef)event {
    if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
        if (_eventTap) {
            CGEventTapEnable(_eventTap, true);
        }
        return event;
    }

    if (!_virtualCursorActive) {
        return event;
    }

    if ([self.class eventTypeCarriesMouseDelta:type]) {
        int64_t deltaX = CGEventGetIntegerValueField(event, kCGMouseEventDeltaX);
        int64_t deltaY = CGEventGetIntegerValueField(event, kCGMouseEventDeltaY);
        _virtualQuartzPoint.x += (CGFloat)deltaX;
        _virtualQuartzPoint.y += (CGFloat)deltaY;
        _virtualQuartzPoint = [self.class clampedQuartzPoint:_virtualQuartzPoint];
    }

    CGEventSetLocation(event, _virtualQuartzPoint);
    return event;
}

+ (BOOL)eventTypeCarriesMouseDelta:(CGEventType)type {
    return type == kCGEventMouseMoved ||
        type == kCGEventLeftMouseDragged ||
        type == kCGEventRightMouseDragged ||
        type == kCGEventOtherMouseDragged;
}

- (void)parkSystemCursorAwayFromVirtualCursor {
    CGRect bounds = [self.class quartzUnionBounds];
    CGPoint parkedPoint = CGPointMake(CGRectGetMinX(bounds) + 1, CGRectGetMinY(bounds) + 1);
    CGWarpMouseCursorPosition(parkedPoint);
}

+ (CGPoint)clampedQuartzPoint:(CGPoint)point {
    CGRect bounds = [self quartzUnionBounds];
    CGFloat minX = CGRectGetMinX(bounds);
    CGFloat maxX = CGRectGetMaxX(bounds) - 1;
    CGFloat minY = CGRectGetMinY(bounds);
    CGFloat maxY = CGRectGetMaxY(bounds) - 1;
    return CGPointMake(MIN(MAX(point.x, minX), maxX),
                       MIN(MAX(point.y, minY), maxY));
}

+ (CGRect)quartzUnionBounds {
    NSArray<NSNumber *> *displayIDs = [self activeDisplayIDs];
    CGRect result = CGRectNull;
    for (NSNumber *displayID in displayIDs) {
        CGRect bounds = CGDisplayBounds(displayID.unsignedIntValue);
        result = CGRectIsNull(result) ? bounds : CGRectUnion(result, bounds);
    }

    if (CGRectIsNull(result)) {
        NSScreen *screen = NSScreen.mainScreen;
        return CGRectMake(0, 0, NSWidth(screen.frame), NSHeight(screen.frame));
    }

    return result;
}

+ (CGPoint)quartzPointFromAppKitPoint:(NSPoint)point {
    for (NSScreen *screen in NSScreen.screens) {
        if (!NSPointInRect(point, screen.frame)) {
            continue;
        }

        NSNumber *screenNumber = screen.deviceDescription[@"NSScreenNumber"];
        CGRect bounds = CGDisplayBounds(screenNumber.unsignedIntValue);
        return CGPointMake(CGRectGetMinX(bounds) + point.x - NSMinX(screen.frame),
                           CGRectGetMinY(bounds) + NSMaxY(screen.frame) - point.y);
    }

    NSScreen *screen = NSScreen.mainScreen;
    NSNumber *screenNumber = screen.deviceDescription[@"NSScreenNumber"];
    CGRect bounds = CGDisplayBounds(screenNumber.unsignedIntValue);
    return CGPointMake(CGRectGetMinX(bounds) + point.x - NSMinX(screen.frame),
                       CGRectGetMinY(bounds) + NSMaxY(screen.frame) - point.y);
}

+ (NSPoint)appKitPointFromQuartzPoint:(CGPoint)point {
    for (NSScreen *screen in NSScreen.screens) {
        NSNumber *screenNumber = screen.deviceDescription[@"NSScreenNumber"];
        CGRect bounds = CGDisplayBounds(screenNumber.unsignedIntValue);
        if (!CGRectContainsPoint(bounds, point)) {
            continue;
        }

        return NSMakePoint(NSMinX(screen.frame) + point.x - CGRectGetMinX(bounds),
                           NSMaxY(screen.frame) - (point.y - CGRectGetMinY(bounds)));
    }

    NSScreen *screen = NSScreen.mainScreen;
    return NSMakePoint(NSMidX(screen.frame), NSMidY(screen.frame));
}

- (void)applyCursorVisibility {
    if (self.isEnabled && self.hideSystemCursor) {
        [self reinforceCursorVisibilityState];
    } else {
        [self showSystemCursorIfNeeded];
    }
}

- (void)reinforceCursorVisibilityState {
    if (!self.isEnabled || !self.hideSystemCursor) {
        return;
    }

    NSTimeInterval now = NSDate.timeIntervalSinceReferenceDate;
    if (now - _lastCursorSuppressionTime < CursorSuppressionInterval) {
        return;
    }
    _lastCursorSuppressionTime = now;

    NSArray<NSNumber *> *displayIDs = [self.class activeDisplayIDs];
    for (NSNumber *displayID in displayIDs) {
        if (CGDisplayHideCursor(displayID.unsignedIntValue) == kCGErrorSuccess) {
            NSInteger depth = [_hideDepthByDisplay[displayID] integerValue];
            _hideDepthByDisplay[displayID] = @(depth + 1);
        }
    }

    [NSCursor hide];
    _nsCursorHideDepth += 1;
}

- (void)hideSystemCursorIfNeeded {
    [self reinforceCursorVisibilityState];
}

- (void)rebalanceHiddenCursorForActiveDisplays {
    NSArray<NSNumber *> *displayIDs = [self.class activeDisplayIDs];
    NSMutableSet<NSNumber *> *activeDisplayIDs = [NSMutableSet setWithArray:displayIDs];
    NSArray<NSNumber *> *knownDisplayIDs = _hideDepthByDisplay.allKeys;

    for (NSNumber *displayID in knownDisplayIDs) {
        if ([activeDisplayIDs containsObject:displayID]) {
            continue;
        }

        NSInteger depth = [_hideDepthByDisplay[displayID] integerValue];
        for (NSInteger index = 0; index < depth; index++) {
            CGDisplayShowCursor(displayID.unsignedIntValue);
        }
        [_hideDepthByDisplay removeObjectForKey:displayID];
    }
}

- (void)showSystemCursorIfNeeded {
    NSArray<NSNumber *> *displayIDs = _hideDepthByDisplay.allKeys;
    for (NSNumber *displayID in displayIDs) {
        NSInteger depth = [_hideDepthByDisplay[displayID] integerValue];
        for (NSInteger index = 0; index < depth; index++) {
            CGDisplayShowCursor(displayID.unsignedIntValue);
        }
    }
    [_hideDepthByDisplay removeAllObjects];

    for (NSInteger index = 0; index < _nsCursorHideDepth; index++) {
        [NSCursor unhide];
    }
    _nsCursorHideDepth = 0;
    _lastCursorSuppressionTime = 0;
}

+ (NSArray<NSNumber *> *)activeDisplayIDs {
    uint32_t displayCount = 0;
    CGGetActiveDisplayList(0, NULL, &displayCount);

    if (displayCount == 0) {
        return @[@(CGMainDisplayID())];
    }

    CGDirectDisplayID *displayIDs = calloc(displayCount, sizeof(CGDirectDisplayID));
    if (!displayIDs) {
        return @[@(CGMainDisplayID())];
    }

    CGGetActiveDisplayList(displayCount, displayIDs, &displayCount);

    NSMutableArray<NSNumber *> *result = [NSMutableArray arrayWithCapacity:displayCount];
    for (uint32_t index = 0; index < displayCount; index++) {
        [result addObject:@(displayIDs[index])];
    }

    free(displayIDs);
    return result;
}

@end

static CGEventRef CartoonCursorEventTapCallback(CGEventTapProxy proxy,
                                                CGEventType type,
                                                CGEventRef event,
                                                void *userInfo) {
    CursorController *controller = (__bridge CursorController *)userInfo;
    return [controller handleEventTapWithType:type event:event];
}

@interface AppDelegate : NSObject <NSApplicationDelegate, NSTextFieldDelegate>
@end

@implementation AppDelegate {
    CursorController *_cursorController;
    NSStatusItem *_statusItem;
    NSPanel *_palettePanel;
    EffectColorTarget _palettePanelTarget;
    EffectColorRole _palettePanelRole;
    NSArray<NSImageView *> *_paletteColorSwatches;
    NSArray<NSTextField *> *_paletteHexFields;
    NSArray<NSTextField *> *_paletteRedFields;
    NSArray<NSTextField *> *_paletteGreenFields;
    NSArray<NSTextField *> *_paletteBlueFields;
    NSArray<NSArray<NSButton *> *> *_palettePresetButtons;
    NSArray<NSColor *> *_paletteDraftColors;
    BOOL _updatingPaletteControls;
}

- (instancetype)init {
    self = [super init];
    if (!self) {
        return nil;
    }

    _cursorController = [[CursorController alloc] init];
    _palettePanelTarget = EffectColorTargetSticker;
    _palettePanelRole = EffectColorRoleTrail;
    return self;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    [self setupStatusItem];
    [_cursorController start];
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    [_cursorController stop];
}

- (void)setupStatusItem {
    _statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
    _statusItem.button.image = [self statusImage];
    _statusItem.button.toolTip = @"Cartoon Cursor";
    [self rebuildMenu];
}

- (NSImage *)statusImage {
    NSImage *image = [NSImage imageWithSystemSymbolName:@"cursorarrow.rays"
                               accessibilityDescription:@"Cartoon Cursor"];
    image.template = YES;
    return image;
}

- (NSString *)titleForEffectStyle:(CursorEffectStyle)style {
    switch (style) {
        case CursorEffectStyleOff:
            return @"Off";
        case CursorEffectStyleRings:
            return @"Rings";
        case CursorEffectStyleSparkles:
            return @"Sparkles";
        case CursorEffectStyleTrail:
            return @"Trail";
        case CursorEffectStyleSparklesTrail:
            return @"Sparkles + Trail";
    }

    return @"Sparkles + Trail";
}

- (NSString *)titleForEffectColorMode:(EffectColorMode)mode {
    return [self titleForEffectColorMode:mode target:EffectColorTargetSticker];
}

- (NSString *)titleForEffectColorMode:(EffectColorMode)mode target:(EffectColorTarget)target {
    switch (mode) {
        case EffectColorModeAuto:
            return target == EffectColorTargetNative ? @"Auto Default Colors" : @"Auto From Sticker";
        case EffectColorModeCustom:
            return @"Custom Palettes";
    }

    return target == EffectColorTargetNative ? @"Auto Default Colors" : @"Auto From Sticker";
}

- (NSString *)titleForEffectColorTarget:(EffectColorTarget)target {
    switch (target) {
        case EffectColorTargetSticker:
            return @"Sticker Colors";
        case EffectColorTargetNative:
            return @"Native Cursor Colors";
    }

    return @"Sticker Colors";
}

- (NSString *)titleForEffectColorRole:(EffectColorRole)role {
    switch (role) {
        case EffectColorRoleTrail:
            return @"Trail Colors";
        case EffectColorRoleClick:
            return @"Click Colors";
        case EffectColorRoleParticle:
            return @"Sparkle Colors";
    }

    return @"Trail Colors";
}

- (EffectColorMode)effectColorModeForTarget:(EffectColorTarget)target {
    return target == EffectColorTargetNative ? _cursorController.nativeEffectColorMode : _cursorController.effectColorMode;
}

- (void)setEffectColorMode:(EffectColorMode)mode forTarget:(EffectColorTarget)target {
    if (target == EffectColorTargetNative) {
        _cursorController.nativeEffectColorMode = mode;
    } else {
        _cursorController.effectColorMode = mode;
    }
}

- (NSArray<NSColor *> *)customColorsForRole:(EffectColorRole)role target:(EffectColorTarget)target {
    switch (role) {
        case EffectColorRoleTrail:
            return target == EffectColorTargetNative ?
                _cursorController.customNativeTrailColors :
                _cursorController.customTrailColors;
        case EffectColorRoleClick:
            return target == EffectColorTargetNative ?
                _cursorController.customNativeClickColors :
                _cursorController.customClickColors;
        case EffectColorRoleParticle:
            return target == EffectColorTargetNative ?
                _cursorController.customNativeParticleColors :
                _cursorController.customParticleColors;
    }

    return target == EffectColorTargetNative ?
        _cursorController.customNativeTrailColors :
        _cursorController.customTrailColors;
}

- (void)setCustomColors:(NSArray<NSColor *> *)colors forRole:(EffectColorRole)role target:(EffectColorTarget)target {
    switch (role) {
        case EffectColorRoleTrail:
            if (target == EffectColorTargetNative) {
                _cursorController.customNativeTrailColors = colors;
            } else {
                _cursorController.customTrailColors = colors;
            }
            break;
        case EffectColorRoleClick:
            if (target == EffectColorTargetNative) {
                _cursorController.customNativeClickColors = colors;
            } else {
                _cursorController.customClickColors = colors;
            }
            break;
        case EffectColorRoleParticle:
            if (target == EffectColorTargetNative) {
                _cursorController.customNativeParticleColors = colors;
            } else {
                _cursorController.customParticleColors = colors;
            }
            break;
    }
}

- (NSMenuItem *)effectColorMenuItemForRole:(EffectColorRole)role target:(EffectColorTarget)target {
    NSString *title = [NSString stringWithFormat:@"%@...", [self titleForEffectColorRole:role]];
    NSMenuItem *roleItem = [[NSMenuItem alloc] initWithTitle:title
                                                      action:@selector(showEffectColorEditor:)
                                               keyEquivalent:@""];
    roleItem.target = self;
    roleItem.representedObject = @(target * 10 + role);
    return roleItem;
}

- (NSImage *)swatchImageForColor:(NSColor *)color {
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(16, 16)];
    [image lockFocus];

    NSRect rect = NSMakeRect(2, 2, 12, 12);
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:rect xRadius:3 yRadius:3];
    [CartoonColorUsingSRGB(color) setFill];
    [path fill];

    [[NSColor colorWithCalibratedWhite:0 alpha:0.22] setStroke];
    path.lineWidth = 1.0;
    [path stroke];

    [image unlockFocus];
    image.template = NO;
    return image;
}

- (NSImage *)paletteChipImageForColor:(NSColor *)color selected:(BOOL)selected {
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(22, 22)];
    [image lockFocus];

    NSRect rect = NSMakeRect(3, 3, 16, 16);
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:rect xRadius:4 yRadius:4];
    [CartoonColorUsingSRGB(color) setFill];
    [path fill];

    NSColor *borderColor = selected ? NSColor.controlAccentColor : [NSColor colorWithCalibratedWhite:0 alpha:0.28];
    [borderColor setStroke];
    path.lineWidth = selected ? 2.0 : 1.0;
    [path stroke];

    [image unlockFocus];
    image.template = NO;
    return image;
}

- (NSArray<NSColor *> *)palettePresetColors {
    return @[
        CartoonColorFromHexString(@"#000000"),
        CartoonColorFromHexString(@"#FFFFFF"),
        CartoonColorFromHexString(@"#7A7A7A"),
        CartoonColorFromHexString(@"#FF5A8A"),
        CartoonColorFromHexString(@"#FF3B30"),
        CartoonColorFromHexString(@"#FF9500"),
        CartoonColorFromHexString(@"#FFD60A"),
        CartoonColorFromHexString(@"#34C759"),
        CartoonColorFromHexString(@"#00C7BE"),
        CartoonColorFromHexString(@"#32ADE6"),
        CartoonColorFromHexString(@"#007AFF"),
        CartoonColorFromHexString(@"#5856D6"),
        CartoonColorFromHexString(@"#AF52DE"),
        CartoonColorFromHexString(@"#FF9FCE"),
        CartoonColorFromHexString(@"#B5E7FF"),
        CartoonColorFromHexString(@"#C8F7C5")
    ];
}

- (void)showEffectColorEditor:(NSMenuItem *)sender {
    NSNumber *roleNumber = sender.representedObject;
    if (![roleNumber isKindOfClass:NSNumber.class]) {
        return;
    }

    NSInteger encodedValue = roleNumber.integerValue;
    EffectColorTarget target = encodedValue >= 10 ? encodedValue / 10 : EffectColorTargetSticker;
    EffectColorRole role = encodedValue >= 10 ? encodedValue % 10 : encodedValue;
    [self showPalettePanelForTarget:target role:role];
}

- (void)showPalettePanelForTarget:(EffectColorTarget)target role:(EffectColorRole)role {
    _palettePanelTarget = target;
    _palettePanelRole = role;
    NSArray<NSColor *> *colors = [CursorView normalizedEffectColors:[self customColorsForRole:role target:target]];
    _paletteDraftColors = colors;

    NSRect frame = NSMakeRect(0, 0, 520, 410);
    _palettePanel = [[NSPanel alloc] initWithContentRect:frame
                                               styleMask:NSWindowStyleMaskTitled |
                                                         NSWindowStyleMaskClosable |
                                                         NSWindowStyleMaskUtilityWindow
                                                 backing:NSBackingStoreBuffered
                                                   defer:NO];
    _palettePanel.title = [NSString stringWithFormat:@"%@ · %@",
                                                      [self titleForEffectColorTarget:target],
                                                      [self titleForEffectColorRole:role]];
    _palettePanel.releasedWhenClosed = NO;
    _palettePanel.level = NSFloatingWindowLevel;

    NSView *contentView = [[NSView alloc] initWithFrame:frame];
    NSMutableArray<NSImageView *> *colorSwatches = [NSMutableArray array];
    NSMutableArray<NSTextField *> *hexFields = [NSMutableArray array];
    NSMutableArray<NSTextField *> *redFields = [NSMutableArray array];
    NSMutableArray<NSTextField *> *greenFields = [NSMutableArray array];
    NSMutableArray<NSTextField *> *blueFields = [NSMutableArray array];
    NSMutableArray<NSArray<NSButton *> *> *presetButtons = [NSMutableArray array];
    NSArray<NSColor *> *presetColors = [self palettePresetColors];

    NSTextField *titleLabel = [NSTextField labelWithString:@"Pick a swatch or type values, then apply together."];
    titleLabel.frame = NSMakeRect(24, 374, 472, 20);
    titleLabel.textColor = NSColor.secondaryLabelColor;
    [contentView addSubview:titleLabel];

    NSArray<NSDictionary *> *headers = @[
        @{@"title": @"Hex", @"x": @154},
        @{@"title": @"R", @"x": @314},
        @{@"title": @"G", @"x": @366},
        @{@"title": @"B", @"x": @418}
    ];
    for (NSDictionary *header in headers) {
        NSTextField *label = [NSTextField labelWithString:header[@"title"]];
        label.frame = NSMakeRect([header[@"x"] doubleValue], 344, 42, 18);
        label.textColor = NSColor.secondaryLabelColor;
        [contentView addSubview:label];
    }

    for (NSInteger index = 0; index < 4; index++) {
        CGFloat y = 286 - index * 72;
        NSTextField *label = [NSTextField labelWithString:[NSString stringWithFormat:@"Color %ld", (long)index + 1]];
        label.frame = NSMakeRect(24, y + 35, 70, 20);
        [contentView addSubview:label];

        NSImageView *swatch = [[NSImageView alloc] initWithFrame:NSMakeRect(98, y + 32, 30, 26)];
        swatch.image = [self swatchImageForColor:colors[index]];
        swatch.imageScaling = NSImageScaleNone;
        [contentView addSubview:swatch];
        [colorSwatches addObject:swatch];

        NSTextField *hexField = [[NSTextField alloc] initWithFrame:NSMakeRect(144, y + 31, 128, 28)];
        hexField.stringValue = CartoonHexStringFromColor(colors[index]);
        hexField.tag = index;
        hexField.target = self;
        hexField.action = @selector(paletteHexFieldChanged:);
        hexField.delegate = self;
        hexField.font = [NSFont monospacedSystemFontOfSize:13 weight:NSFontWeightRegular];
        [contentView addSubview:hexField];
        [hexFields addObject:hexField];

        NSArray<NSNumber *> *channelXs = @[@308, @360, @412];
        NSArray<NSMutableArray<NSTextField *> *> *channelFieldGroups = @[redFields, greenFields, blueFields];
        for (NSInteger channel = 0; channel < 3; channel++) {
            NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(channelXs[channel].doubleValue, y + 31, 42, 28)];
            field.tag = index * 3 + channel;
            field.target = self;
            field.action = @selector(paletteChannelFieldChanged:);
            field.delegate = self;
            field.font = [NSFont monospacedSystemFontOfSize:13 weight:NSFontWeightRegular];
            [contentView addSubview:field];
            [channelFieldGroups[channel] addObject:field];
        }

        NSMutableArray<NSButton *> *rowPresetButtons = [NSMutableArray arrayWithCapacity:presetColors.count];
        for (NSInteger presetIndex = 0; presetIndex < (NSInteger)presetColors.count; presetIndex++) {
            NSButton *button = [[NSButton alloc] initWithFrame:NSMakeRect(98 + presetIndex * 24, y + 2, 22, 22)];
            button.bordered = NO;
            button.image = [self paletteChipImageForColor:presetColors[presetIndex] selected:NO];
            button.imageScaling = NSImageScaleNone;
            button.target = self;
            button.action = @selector(selectPalettePresetColor:);
            button.tag = index * 100 + presetIndex;
            button.toolTip = CartoonHexStringFromColor(presetColors[presetIndex]);
            [contentView addSubview:button];
            [rowPresetButtons addObject:button];
        }
        [presetButtons addObject:rowPresetButtons];
    }

    NSButton *resetButton = [NSButton buttonWithTitle:@"Reset"
                                               target:self
                                               action:@selector(resetOpenPalettePanel:)];
    resetButton.frame = NSMakeRect(24, 14, 90, 30);
    [contentView addSubview:resetButton];

    NSButton *cancelButton = [NSButton buttonWithTitle:@"Cancel"
                                              target:self
                                              action:@selector(closePalettePanel:)];
    cancelButton.frame = NSMakeRect(344, 14, 90, 30);
    [contentView addSubview:cancelButton];

    NSButton *applyButton = [NSButton buttonWithTitle:@"Apply"
                                               target:self
                                               action:@selector(applyPalettePanel:)];
    applyButton.frame = NSMakeRect(438, 14, 72, 30);
    applyButton.keyEquivalent = @"\r";
    [contentView addSubview:applyButton];

    _paletteColorSwatches = colorSwatches;
    _paletteHexFields = hexFields;
    _paletteRedFields = redFields;
    _paletteGreenFields = greenFields;
    _paletteBlueFields = blueFields;
    _palettePresetButtons = presetButtons;
    _palettePanel.contentView = contentView;

    [NSApp activateIgnoringOtherApps:YES];
    [_palettePanel center];
    [_palettePanel makeKeyAndOrderFront:nil];
    [self updatePalettePanelControlsWithColors:colors];
    [self rebuildMenu];
}

- (void)paletteHexFieldChanged:(NSTextField *)sender {
    [self applyPaletteHexField:sender allowPartial:NO];
}

- (BOOL)applyPaletteHexField:(NSTextField *)sender allowPartial:(BOOL)allowPartial {
    if (_updatingPaletteControls) {
        return NO;
    }

    NSInteger index = sender.tag;
    if (index < 0 || index >= 4) {
        return NO;
    }

    NSString *trimmed = [sender.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSInteger hexLength = [trimmed hasPrefix:@"#"] ? trimmed.length - 1 : trimmed.length;
    if (allowPartial && hexLength != 6) {
        return NO;
    }

    NSColor *color = CartoonColorFromHexString(trimmed);
    if (!color) {
        if (!allowPartial) {
            NSBeep();
            NSArray<NSColor *> *colors = [CursorView normalizedEffectColors:_paletteDraftColors];
            sender.stringValue = CartoonHexStringFromColor(colors[index]);
        }
        return NO;
    }

    [self setPaletteDraftColor:color atIndex:index preservingField:sender];
    return YES;
}

- (void)paletteChannelFieldChanged:(NSTextField *)sender {
    [self applyPaletteChannelField:sender allowPartial:NO];
}

- (void)selectPalettePresetColor:(NSButton *)sender {
    NSInteger index = sender.tag / 100;
    NSInteger presetIndex = sender.tag % 100;
    NSArray<NSColor *> *presetColors = [self palettePresetColors];
    if (index < 0 || index >= 4 || presetIndex < 0 || presetIndex >= (NSInteger)presetColors.count) {
        return;
    }

    [_palettePanel makeFirstResponder:nil];
    [self setPaletteDraftColor:presetColors[presetIndex] atIndex:index preservingField:nil];
}

- (BOOL)applyPaletteChannelField:(NSTextField *)sender allowPartial:(BOOL)allowPartial {
    if (_updatingPaletteControls) {
        return NO;
    }

    NSInteger index = sender.tag / 3;
    NSInteger channel = sender.tag % 3;
    if (index < 0 || index >= 4 || channel < 0 || channel >= 3) {
        return NO;
    }

    NSString *trimmed = [sender.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (allowPartial && trimmed.length == 0) {
        return NO;
    }

    NSScanner *scanner = [NSScanner scannerWithString:trimmed];
    NSInteger value = 0;
    BOOL didScan = [scanner scanInteger:&value] && scanner.isAtEnd;
    if (!didScan || value < 0 || value > 255) {
        if (!allowPartial) {
            NSBeep();
            NSArray<NSColor *> *colors = [CursorView normalizedEffectColors:_paletteDraftColors];
            [self updatePaletteRowAtIndex:index color:colors[index] preservingField:nil];
        }
        return NO;
    }

    NSArray<NSColor *> *colors = [CursorView normalizedEffectColors:_paletteDraftColors];
    NSColor *existingColor = CartoonColorUsingSRGB(colors[index]);
    CGFloat red = 0;
    CGFloat green = 0;
    CGFloat blue = 0;
    CGFloat alpha = 0;
    [existingColor getRed:&red green:&green blue:&blue alpha:&alpha];

    if (channel == 0) {
        red = value / 255.0;
    } else if (channel == 1) {
        green = value / 255.0;
    } else {
        blue = value / 255.0;
    }

    NSColor *color = [NSColor colorWithCalibratedRed:red green:green blue:blue alpha:1.0];
    [self setPaletteDraftColor:color atIndex:index preservingField:sender];
    return YES;
}

- (void)controlTextDidChange:(NSNotification *)notification {
    id object = notification.object;
    if (![object isKindOfClass:NSTextField.class]) {
        return;
    }

    NSTextField *field = object;
    if ([_paletteHexFields containsObject:field]) {
        [self applyPaletteHexField:field allowPartial:YES];
        return;
    }

    if ([_paletteRedFields containsObject:field] ||
        [_paletteGreenFields containsObject:field] ||
        [_paletteBlueFields containsObject:field]) {
        [self applyPaletteChannelField:field allowPartial:YES];
        return;
    }
}

- (void)resetOpenPalettePanel:(NSButton *)sender {
    NSArray<NSColor *> *defaults = [CursorView defaultEffectColors];
    _paletteDraftColors = defaults;
    [self updatePalettePanelControlsWithColors:defaults];
}

- (void)closePalettePanel:(NSButton *)sender {
    [_palettePanel orderOut:nil];
}

- (void)applyPalettePanel:(NSButton *)sender {
    [self setEffectColorMode:EffectColorModeCustom forTarget:_palettePanelTarget];
    NSArray<NSColor *> *colors = [CursorView normalizedEffectColors:_paletteDraftColors];
    [self setCustomColors:colors forRole:_palettePanelRole target:_palettePanelTarget];
    [self rebuildMenu];
    [_palettePanel orderOut:nil];
}

- (void)updatePalettePanelControlsWithColors:(NSArray<NSColor *> *)colors {
    [self updatePalettePanelControlsWithColors:colors preservingField:nil];
}

- (void)updatePalettePanelControlsWithColors:(NSArray<NSColor *> *)colors preservingField:(NSTextField *)preservedField {
    NSArray<NSColor *> *normalizedColors = [CursorView normalizedEffectColors:colors];
    _updatingPaletteControls = YES;

    for (NSInteger index = 0; index < 4; index++) {
        [self updatePaletteRowAtIndex:index color:normalizedColors[index] preservingField:preservedField];
    }
    _updatingPaletteControls = NO;
}

- (void)setPaletteDraftColor:(NSColor *)color atIndex:(NSInteger)index preservingField:(NSTextField *)preservedField {
    if (index < 0 || index >= 4) {
        return;
    }

    NSMutableArray<NSColor *> *colors = [[CursorView normalizedEffectColors:_paletteDraftColors] mutableCopy];
    NSColor *normalizedColor = CartoonColorUsingSRGB(color);
    colors[index] = normalizedColor;
    _paletteDraftColors = colors;

    _updatingPaletteControls = YES;
    [self updatePaletteRowAtIndex:index color:normalizedColor preservingField:preservedField];
    _updatingPaletteControls = NO;
}

- (void)updatePaletteRowAtIndex:(NSInteger)index color:(NSColor *)color preservingField:(NSTextField *)preservedField {
    if (index < 0 || index >= 4) {
        return;
    }

    if (index < (NSInteger)_paletteColorSwatches.count) {
        _paletteColorSwatches[index].image = [self swatchImageForColor:color];
    }
    if (index < (NSInteger)_paletteHexFields.count) {
        NSTextField *field = _paletteHexFields[index];
        if (field != preservedField) {
            field.stringValue = CartoonHexStringFromColor(color);
        }
    }

    NSColor *rgbColor = CartoonColorUsingSRGB(color);
    CGFloat red = 0;
    CGFloat green = 0;
    CGFloat blue = 0;
    CGFloat alpha = 0;
    [rgbColor getRed:&red green:&green blue:&blue alpha:&alpha];
    if (index < (NSInteger)_paletteRedFields.count) {
        NSTextField *field = _paletteRedFields[index];
        if (field != preservedField) {
            field.integerValue = (NSInteger)llround(red * 255.0);
        }
    }
    if (index < (NSInteger)_paletteGreenFields.count) {
        NSTextField *field = _paletteGreenFields[index];
        if (field != preservedField) {
            field.integerValue = (NSInteger)llround(green * 255.0);
        }
    }
    if (index < (NSInteger)_paletteBlueFields.count) {
        NSTextField *field = _paletteBlueFields[index];
        if (field != preservedField) {
            field.integerValue = (NSInteger)llround(blue * 255.0);
        }
    }

    if (index < (NSInteger)_palettePresetButtons.count) {
        NSString *selectedHex = CartoonHexStringFromColor(color);
        NSArray<NSColor *> *presetColors = [self palettePresetColors];
        NSArray<NSButton *> *buttons = _palettePresetButtons[index];
        for (NSInteger presetIndex = 0; presetIndex < (NSInteger)buttons.count && presetIndex < (NSInteger)presetColors.count; presetIndex++) {
            BOOL selected = [selectedHex isEqualToString:CartoonHexStringFromColor(presetColors[presetIndex])];
            buttons[presetIndex].image = [self paletteChipImageForColor:presetColors[presetIndex] selected:selected];
        }
    }
}

- (NSMenu *)effectColorsSubmenuForTarget:(EffectColorTarget)target {
    NSMenu *submenu = [[NSMenu alloc] init];
    NSArray<NSNumber *> *colorModes = @[@(EffectColorModeAuto), @(EffectColorModeCustom)];
    EffectColorMode currentMode = [self effectColorModeForTarget:target];

    for (NSNumber *modeNumber in colorModes) {
        EffectColorMode mode = modeNumber.integerValue;
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:[self titleForEffectColorMode:mode target:target]
                                                      action:@selector(selectEffectColorMode:)
                                               keyEquivalent:@""];
        item.target = self;
        item.representedObject = @(target * 10 + mode);
        item.state = currentMode == mode ? NSControlStateValueOn : NSControlStateValueOff;
        [submenu addItem:item];
    }

    [submenu addItem:NSMenuItem.separatorItem];
    [submenu addItem:[self effectColorMenuItemForRole:EffectColorRoleTrail target:target]];
    [submenu addItem:[self effectColorMenuItemForRole:EffectColorRoleClick target:target]];
    [submenu addItem:[self effectColorMenuItemForRole:EffectColorRoleParticle target:target]];

    return submenu;
}

- (NSArray<NSDictionary *> *)stickerWalkSpeedOptions {
    return @[
        @{@"title": @"Very Slow", @"value": @0.35},
        @{@"title": @"Slow", @"value": @0.65},
        @{@"title": @"Normal", @"value": @1.0},
        @{@"title": @"Fast", @"value": @1.45},
        @{@"title": @"Very Fast", @"value": @2.0}
    ];
}

- (NSArray<NSDictionary *> *)stickerWalkAmplitudeOptions {
    return @[
        @{@"title": @"Tiny", @"value": @0.35},
        @{@"title": @"Small", @"value": @0.65},
        @{@"title": @"Normal", @"value": @1.0},
        @{@"title": @"Bouncy", @"value": @1.35}
    ];
}

- (void)rebuildMenu {
    NSMenu *menu = [[NSMenu alloc] init];

    NSMenuItem *enabledItem = [[NSMenuItem alloc] initWithTitle:@"Enabled"
                                                         action:@selector(toggleEnabled:)
                                                  keyEquivalent:@""];
    enabledItem.target = self;
    enabledItem.state = _cursorController.isEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    [menu addItem:enabledItem];

    NSMenuItem *walkFollowItem = [[NSMenuItem alloc] initWithTitle:@"Sticker Walk Follow"
                                                            action:@selector(toggleStickerWalkFollow:)
                                                     keyEquivalent:@""];
    walkFollowItem.target = self;
    walkFollowItem.state = _cursorController.stickerWalkFollowEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    [menu addItem:walkFollowItem];

    NSMenuItem *frameAnimationItem = [[NSMenuItem alloc] initWithTitle:@"Sticker Frame Animation"
                                                                action:@selector(toggleStickerFrameAnimation:)
                                                         keyEquivalent:@""];
    frameAnimationItem.target = self;
    frameAnimationItem.state = _cursorController.stickerFrameAnimationEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    [menu addItem:frameAnimationItem];

    NSMenuItem *walkSpeedItem = [[NSMenuItem alloc] initWithTitle:@"Sticker Walk Speed"
                                                           action:nil
                                                    keyEquivalent:@""];
    NSMenu *walkSpeedMenu = [[NSMenu alloc] init];
    for (NSDictionary *option in [self stickerWalkSpeedOptions]) {
        NSNumber *speed = option[@"value"];
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:option[@"title"]
                                                      action:@selector(selectStickerWalkSpeed:)
                                               keyEquivalent:@""];
        item.target = self;
        item.representedObject = speed;
        item.state = fabs(_cursorController.stickerWalkSpeedMultiplier - speed.doubleValue) < 0.01 ?
            NSControlStateValueOn :
            NSControlStateValueOff;
        [walkSpeedMenu addItem:item];
    }
    walkSpeedItem.submenu = walkSpeedMenu;
    [menu addItem:walkSpeedItem];

    NSMenuItem *walkAmplitudeItem = [[NSMenuItem alloc] initWithTitle:@"Sticker Walk Amplitude"
                                                               action:nil
                                                        keyEquivalent:@""];
    NSMenu *walkAmplitudeMenu = [[NSMenu alloc] init];
    for (NSDictionary *option in [self stickerWalkAmplitudeOptions]) {
        NSNumber *amplitude = option[@"value"];
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:option[@"title"]
                                                      action:@selector(selectStickerWalkAmplitude:)
                                               keyEquivalent:@""];
        item.target = self;
        item.representedObject = amplitude;
        item.state = fabs(_cursorController.stickerWalkAmplitudeMultiplier - amplitude.doubleValue) < 0.01 ?
            NSControlStateValueOn :
            NSControlStateValueOff;
        [walkAmplitudeMenu addItem:item];
    }
    walkAmplitudeItem.submenu = walkAmplitudeMenu;
    [menu addItem:walkAmplitudeItem];

    NSMenuItem *nativeEffectsItem = [[NSMenuItem alloc] initWithTitle:@"Native Cursor Effects"
                                                               action:@selector(toggleNativeCursorEffects:)
                                                        keyEquivalent:@""];
    nativeEffectsItem.target = self;
    nativeEffectsItem.state = _cursorController.nativeCursorEffectsEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    [menu addItem:nativeEffectsItem];

    NSMenuItem *hideItem = [[NSMenuItem alloc] initWithTitle:@"Try Native Hide Cursor"
                                                      action:@selector(toggleHideSystemCursor:)
                                               keyEquivalent:@""];
    hideItem.target = self;
    hideItem.state = _cursorController.hideSystemCursor ? NSControlStateValueOn : NSControlStateValueOff;
    [menu addItem:hideItem];

    [menu addItem:NSMenuItem.separatorItem];

    NSMenuItem *chooseItem = [[NSMenuItem alloc] initWithTitle:@"Choose Cartoon Image..."
                                                        action:@selector(chooseImage:)
                                                 keyEquivalent:@""];
    chooseItem.target = self;
    [menu addItem:chooseItem];

    NSMenuItem *defaultItem = [[NSMenuItem alloc] initWithTitle:@"Use Default Cartoon"
                                                         action:@selector(useDefaultCartoon:)
                                                  keyEquivalent:@""];
    defaultItem.target = self;
    [menu addItem:defaultItem];

    NSMenuItem *sizeItem = [[NSMenuItem alloc] initWithTitle:@"Size" action:nil keyEquivalent:@""];
    NSMenu *sizeMenu = [[NSMenu alloc] init];
    for (NSNumber *size in CursorController.sizes) {
        NSString *title = [NSString stringWithFormat:@"%ld px", (long)size.integerValue];
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title
                                                      action:@selector(selectSize:)
                                               keyEquivalent:@""];
        item.target = self;
        item.representedObject = size;
        item.state = fabs(_cursorController.cursorSize - size.doubleValue) < 0.5 ? NSControlStateValueOn : NSControlStateValueOff;
        [sizeMenu addItem:item];
    }
    sizeItem.submenu = sizeMenu;
    [menu addItem:sizeItem];

    NSMenuItem *effectItem = [[NSMenuItem alloc] initWithTitle:@"Effect" action:nil keyEquivalent:@""];
    NSMenu *effectMenu = [[NSMenu alloc] init];
    NSArray<NSNumber *> *effectStyles = @[
        @(CursorEffectStyleSparklesTrail),
        @(CursorEffectStyleSparkles),
        @(CursorEffectStyleTrail),
        @(CursorEffectStyleRings),
        @(CursorEffectStyleOff)
    ];
    for (NSNumber *styleNumber in effectStyles) {
        CursorEffectStyle style = styleNumber.integerValue;
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:[self titleForEffectStyle:style]
                                                      action:@selector(selectEffectStyle:)
                                               keyEquivalent:@""];
        item.target = self;
        item.representedObject = styleNumber;
        item.state = _cursorController.effectStyle == style ? NSControlStateValueOn : NSControlStateValueOff;
        [effectMenu addItem:item];
    }
    effectItem.submenu = effectMenu;
    [menu addItem:effectItem];

    NSMenuItem *effectColorsItem = [[NSMenuItem alloc] initWithTitle:@"Effect Colors" action:nil keyEquivalent:@""];
    NSMenu *effectColorsMenu = [[NSMenu alloc] init];

    NSMenuItem *stickerColorsItem = [[NSMenuItem alloc] initWithTitle:[self titleForEffectColorTarget:EffectColorTargetSticker]
                                                               action:nil
                                                        keyEquivalent:@""];
    stickerColorsItem.submenu = [self effectColorsSubmenuForTarget:EffectColorTargetSticker];
    [effectColorsMenu addItem:stickerColorsItem];

    NSMenuItem *nativeColorsItem = [[NSMenuItem alloc] initWithTitle:[self titleForEffectColorTarget:EffectColorTargetNative]
                                                              action:nil
                                                       keyEquivalent:@""];
    nativeColorsItem.submenu = [self effectColorsSubmenuForTarget:EffectColorTargetNative];
    [effectColorsMenu addItem:nativeColorsItem];

    [effectColorsMenu addItem:NSMenuItem.separatorItem];

    NSMenuItem *resetColorsItem = [[NSMenuItem alloc] initWithTitle:@"Reset All Custom Palettes"
                                                             action:@selector(resetAllCustomEffectColors:)
                                                      keyEquivalent:@""];
    resetColorsItem.target = self;
    [effectColorsMenu addItem:resetColorsItem];

    effectColorsItem.submenu = effectColorsMenu;
    [menu addItem:effectColorsItem];

    [menu addItem:NSMenuItem.separatorItem];

    NSMenuItem *quitItem = [[NSMenuItem alloc] initWithTitle:@"Quit Cartoon Cursor"
                                                      action:@selector(quit:)
                                               keyEquivalent:@"q"];
    quitItem.target = self;
    [menu addItem:quitItem];

    _statusItem.menu = menu;
}

- (void)toggleEnabled:(NSMenuItem *)sender {
    _cursorController.enabled = !_cursorController.isEnabled;
    [self rebuildMenu];
}

- (void)toggleStickerWalkFollow:(NSMenuItem *)sender {
    _cursorController.stickerWalkFollowEnabled = !_cursorController.stickerWalkFollowEnabled;
    [self rebuildMenu];
}

- (void)toggleStickerFrameAnimation:(NSMenuItem *)sender {
    _cursorController.stickerFrameAnimationEnabled = !_cursorController.stickerFrameAnimationEnabled;
    [self rebuildMenu];
}

- (void)selectStickerWalkSpeed:(NSMenuItem *)sender {
    NSNumber *speed = sender.representedObject;
    if (![speed isKindOfClass:NSNumber.class]) {
        return;
    }

    _cursorController.stickerWalkSpeedMultiplier = speed.doubleValue;
    [self rebuildMenu];
}

- (void)selectStickerWalkAmplitude:(NSMenuItem *)sender {
    NSNumber *amplitude = sender.representedObject;
    if (![amplitude isKindOfClass:NSNumber.class]) {
        return;
    }

    _cursorController.stickerWalkAmplitudeMultiplier = amplitude.doubleValue;
    [self rebuildMenu];
}

- (void)toggleNativeCursorEffects:(NSMenuItem *)sender {
    _cursorController.nativeCursorEffectsEnabled = !_cursorController.nativeCursorEffectsEnabled;
    [self rebuildMenu];
}

- (void)toggleHideSystemCursor:(NSMenuItem *)sender {
    _cursorController.hideSystemCursor = !_cursorController.hideSystemCursor;
    [self rebuildMenu];
}

- (void)toggleVirtualCursor:(NSMenuItem *)sender {
    _cursorController.virtualCursorEnabled = !_cursorController.virtualCursorEnabled;
    [self rebuildMenu];
}

- (void)chooseImage:(NSMenuItem *)sender {
    [NSApp activateIgnoringOtherApps:YES];

    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.title = @"Choose Cartoon Image";
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = NO;
    panel.allowsMultipleSelection = NO;
    if (@available(macOS 12.0, *)) {
        panel.allowedContentTypes = @[UTTypeImage];
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        panel.allowedFileTypes = @[@"png", @"jpg", @"jpeg", @"gif", @"tiff", @"heic", @"webp"];
#pragma clang diagnostic pop
    }

    __weak typeof(self) weakSelf = self;
    [panel beginWithCompletionHandler:^(NSModalResponse result) {
        if (result != NSModalResponseOK || panel.URL == nil) {
            return;
        }

        AppDelegate *strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }

        [strongSelf->_cursorController loadImageFromURL:panel.URL];
        [strongSelf rebuildMenu];
    }];
}

- (void)useDefaultCartoon:(NSMenuItem *)sender {
    [_cursorController useDefaultCartoon];
    [self rebuildMenu];
}

- (void)selectSize:(NSMenuItem *)sender {
    NSNumber *size = sender.representedObject;
    if (![size isKindOfClass:NSNumber.class]) {
        return;
    }

    _cursorController.cursorSize = size.doubleValue;
    [self rebuildMenu];
}

- (void)selectEffectStyle:(NSMenuItem *)sender {
    NSNumber *style = sender.representedObject;
    if (![style isKindOfClass:NSNumber.class]) {
        return;
    }

    _cursorController.effectStyle = style.integerValue;
    [self rebuildMenu];
}

- (void)selectEffectColorMode:(NSMenuItem *)sender {
    NSNumber *mode = sender.representedObject;
    if (![mode isKindOfClass:NSNumber.class]) {
        return;
    }

    NSInteger encodedValue = mode.integerValue;
    EffectColorTarget target = encodedValue >= 10 ? encodedValue / 10 : EffectColorTargetSticker;
    EffectColorMode colorMode = encodedValue >= 10 ? encodedValue % 10 : encodedValue;
    [self setEffectColorMode:colorMode forTarget:target];
    [self rebuildMenu];
}

- (void)resetAllCustomEffectColors:(NSMenuItem *)sender {
    _cursorController.effectColorMode = EffectColorModeCustom;
    _cursorController.nativeEffectColorMode = EffectColorModeCustom;
    NSArray<NSColor *> *defaults = [CursorView defaultEffectColors];
    _cursorController.customTrailColors = defaults;
    _cursorController.customClickColors = defaults;
    _cursorController.customParticleColors = defaults;
    _cursorController.customNativeTrailColors = defaults;
    _cursorController.customNativeClickColors = defaults;
    _cursorController.customNativeParticleColors = defaults;
    [self rebuildMenu];
}

- (void)quit:(NSMenuItem *)sender {
    [NSApp terminate:nil];
}

@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *app = NSApplication.sharedApplication;
        AppDelegate *delegate = [[AppDelegate alloc] init];
        app.delegate = delegate;
        [app run];
    }

    return 0;
}
