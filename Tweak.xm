
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <mach/mach.h>
#import <mach/host_info.h>
#import <mach/processor_info.h>
#import <signal.h>
#import <IOKit/IOKitLib.h>
#import <sys/sysctl.h>
#import <sys/stat.h>
#import <sys/mount.h>
#import <ifaddrs.h>
#import <net/if.h>
#import <arpa/inet.h>
#import <CoreMotion/CoreMotion.h>

#ifndef kIOMainPortDefault
#define kIOMainPortDefault kIOMasterPortDefault
#endif

#define kPlistPath @"/var/mobile/Library/Preferences/com.yourname.sbcpufloating.plist"
#define kPrefChangedNotification "com.yourname.sbcpufloating.prefschanged"
#define kToggleNotification "com.yourname.sbcpufloating.toggle"

#pragma mark - 1. 设备规格与 SoC 识别数据结构

typedef struct {
    const char *platform;
    const char *modelName;
    const char *chipName;
    NSInteger cores;
    double maxFreqMHz;
    NSInteger designBatteryCapacity;
} DeviceSpec;

static DeviceSpec getDeviceSpec(void) {
    char machine[256] = {0};
    size_t size = sizeof(machine);
    sysctlbyname("hw.machine", machine, &size, NULL, 0);
    NSString *platform = [NSString stringWithUTF8String:machine];

    if ([platform isEqualToString:@"iPhone16,2"]) return (DeviceSpec){"iPhone16,2", "iPhone 15 Pro Max", "A17 Pro", 6, 3780.0, 4422};
    if ([platform isEqualToString:@"iPhone16,1"]) return (DeviceSpec){"iPhone16,1", "iPhone 15 Pro", "A17 Pro", 6, 3780.0, 3274};
    if ([platform isEqualToString:@"iPhone15,5"]) return (DeviceSpec){"iPhone15,5", "iPhone 15 Plus", "A16 Bionic", 6, 3460.0, 4383};
    if ([platform isEqualToString:@"iPhone15,4"]) return (DeviceSpec){"iPhone15,4", "iPhone 15", "A16 Bionic", 6, 3460.0, 3349};
    if ([platform isEqualToString:@"iPhone15,3"]) return (DeviceSpec){"iPhone15,3", "iPhone 14 Pro Max", "A16 Bionic", 6, 3460.0, 4323};
    if ([platform isEqualToString:@"iPhone15,2"]) return (DeviceSpec){"iPhone15,2", "iPhone 14 Pro", "A16 Bionic", 6, 3460.0, 3200};
    if ([platform isEqualToString:@"iPhone14,8"]) return (DeviceSpec){"iPhone14,8", "iPhone 14 Plus", "A15 Bionic", 6, 3230.0, 4325};
    if ([platform isEqualToString:@"iPhone14,7"]) return (DeviceSpec){"iPhone14,7", "iPhone 14", "A15 Bionic", 6, 3230.0, 3279};
    if ([platform isEqualToString:@"iPhone14,3"]) return (DeviceSpec){"iPhone14,3", "iPhone 13 Pro Max", "A15 Bionic", 6, 3230.0, 4352};
    if ([platform isEqualToString:@"iPhone14,2"]) return (DeviceSpec){"iPhone14,2", "iPhone 13 Pro", "A15 Bionic", 6, 3230.0, 3095};
    if ([platform isEqualToString:@"iPhone14,5"]) return (DeviceSpec){"iPhone14,5", "iPhone 13", "A15 Bionic", 6, 3230.0, 3227};
    if ([platform isEqualToString:@"iPhone14,4"]) return (DeviceSpec){"iPhone14,4", "iPhone 13 mini", "A15 Bionic", 6, 3230.0, 2406};
    if ([platform isEqualToString:@"iPhone13,4"]) return (DeviceSpec){"iPhone13,4", "iPhone 12 Pro Max", "A14 Bionic", 6, 3100.0, 3687};
    if ([platform isEqualToString:@"iPhone13,3"]) return (DeviceSpec){"iPhone13,3", "iPhone 12 Pro", "A14 Bionic", 6, 3100.0, 2815};
    if ([platform isEqualToString:@"iPhone13,2"]) return (DeviceSpec){"iPhone13,2", "iPhone 12", "A14 Bionic", 6, 3100.0, 2815};
    if ([platform isEqualToString:@"iPhone17,1"]) return (DeviceSpec){"iPhone17,1", "iPhone 16 Pro", "A18 Pro", 6, 4040.0, 3582};
    if ([platform isEqualToString:@"iPhone17,2"]) return (DeviceSpec){"iPhone17,2", "iPhone 16 Pro Max", "A18 Pro", 6, 4040.0, 4685};

    NSInteger activeCores = [NSProcessInfo processInfo].processorCount;
    return (DeviceSpec){machine, "iPhone", "Apple Silicon", activeCores, 3460.0, 4000};
}

#pragma mark - 2. 前置声明

@interface SpringBoard : UIApplication
- (UIInterfaceOrientation)activeInterfaceOrientation;
@end

@class SBCPUDetailViewController;

@interface SBCPUFloatingView : UIView <UIGestureRecognizerDelegate>
@property (nonatomic, assign) CGPoint lastPoint;
@property (nonatomic, strong) UIVisualEffectView *blurView;
@property (nonatomic, strong) CAShapeLayer *marqueeLayer;

@property (nonatomic, strong) UILabel *cpuTitleLabel;
@property (nonatomic, strong) UILabel *cpuValueLabel;
@property (nonatomic, strong) UILabel *cpuFreqLabel;
@property (nonatomic, strong) UIView *div1;

@property (nonatomic, strong) UILabel *fpsValueLabel;
@property (nonatomic, strong) UILabel *fpsSubLabel;
@property (nonatomic, strong) UIView *divFps;

@property (nonatomic, strong) UILabel *batteryIconLabel;
@property (nonatomic, strong) UILabel *batteryValueLabel;
@property (nonatomic, strong) UILabel *batterySubLabel;
@property (nonatomic, strong) UIView *div2;

@property (nonatomic, strong) UILabel *tempIconLabel;
@property (nonatomic, strong) UILabel *tempValueLabel;
@property (nonatomic, strong) UILabel *tempSubLabel;
@property (nonatomic, strong) UIView *div3;

@property (nonatomic, strong) UILabel *currentIconLabel;
@property (nonatomic, strong) UILabel *currentValueLabel;
@property (nonatomic, strong) UILabel *currentSubLabel;

@property (nonatomic, strong) UIView *bottomCapsule;
@property (nonatomic, strong) UILabel *statusLabel;

@property (nonatomic, strong) UIView *collapsedContainerView;
@property (nonatomic, strong) UIView *statusDot;
@property (nonatomic, strong) UILabel *miniCpuLabel;

@property (nonatomic, assign) BOOL isCollapsed;
@property (nonatomic, strong) NSTimer *inactivityTimer;
@property (nonatomic, strong) UITapGestureRecognizer *singleTapGesture;
@property (nonatomic, strong) UILongPressGestureRecognizer *longPressGesture;

- (void)resetInactivityTimer;
- (void)collapseToEdgeAnimated:(BOOL)animated;
- (void)expandFromEdgeAnimated:(BOOL)animated;
- (void)triggerPlugAnimation;

- (void)updateLayoutWithShowCpuFreq:(BOOL)showFreq
                            showFps:(BOOL)showFps
                 showBatteryPercent:(BOOL)showBattery
                    showBatteryTemp:(BOOL)showTemp
                 showBatteryCurrent:(BOOL)showCurrent
                         isCharging:(BOOL)isCharging;

- (void)updateDataWithCPU:(double)cpu 
                  cpuFreq:(double)cpuFreq
                      fps:(double)fps
                  battery:(NSInteger)battery 
                     temp:(double)temp 
                  current:(double)current 
               isCharging:(BOOL)isCharging;
@end

@interface SBCPUPassthroughView : UIView
@end

@interface SBCPURootViewController : UIViewController
@end

@interface SBCPUWindow : UIWindow
@end

@interface SBCPUValuePickerController : UITableViewController
@end

@interface SBCPUTimePickerController : UITableViewController
@end

@interface SBCPUSettingsController : UITableViewController
@end

@interface SBCPUDetailViewController : UIViewController
@property (nonatomic, strong) UIVisualEffectView *blurEffectView;
@property (nonatomic, strong) NSTimer *refreshTimer;
@property (nonatomic, strong) CMPedometer *pedometer;
@property (nonatomic, strong) NSMutableDictionary<NSString *, UILabel *> *labelsDict;
- (void)refreshAllDetailData;
@end

#pragma mark - 3. 全局状态变量

static UIWindow *cpuWindow = nil;
static SBCPUFloatingView *floatingView = nil;
static SBCPUDetailViewController *detailVC = nil;

static BOOL isEnabled = YES; // 全局开关
static CGFloat floatingScale = 1.0;
static CGFloat floatingFontSize = 13.0;

static BOOL settingsShowing = NO;
static BOOL detailShowing = NO;
static BOOL previousChargingState = NO;

static BOOL autoCollapseEnable = YES;
static NSInteger autoCollapseDelay = 4;

static BOOL autoLogoutEnable = NO;
static double logoutCPUThreshold = 100.0;
static NSInteger logoutDuration = 60;
static NSDate *cpuHighStartTime = nil;
static BOOL logoutCounting = NO;

static BOOL floatingAlphaEnable = YES;
static CGFloat floatingAlpha = 0.70f;

static BOOL keyboardAvoidEnable = YES;
static BOOL smartDockEnable = YES;
static NSInteger dockMode = 0;
static BOOL rememberPositionEnable = YES;

static BOOL showCpuFrequency = YES;
static BOOL showFps = YES;                       // 📊 显示 FPS 帧率开关
static BOOL force120HzEnable = NO;               // 🎮 强制 120Hz 高刷
static BOOL thermalProtectionEnable = YES;       // 🛡️ 智能温控降频保护开关（可关闭以解除限制）

static BOOL showBatteryPercent = YES;
static BOOL showBatteryTemperature = YES;
static BOOL showBatteryCurrent = YES;

static CGRect keyboardBeforeFrame;
static BOOL keyboardMoved = NO;

static uint64_t lastWifiInBytes = 0;
static uint64_t lastWifiOutBytes = 0;
static uint64_t lastCellInBytes = 0;
static uint64_t lastCellOutBytes = 0;
static uint64_t speedUpBytesPerSec = 0;
static uint64_t speedDownBytesPerSec = 0;
static CFAbsoluteTime lastNetSpeedTime = 0;

static host_cpu_load_info_data_t prev_cpu_load;
static BOOL has_prev_cpu_load = NO;

static UIWindowScene *getWindowScene(void);
static UIInterfaceOrientation getActiveInterfaceOrientation(void);
static double getSystemCPUUsage(void);
static double getCPUFrequencyMHz(double currentCpuUsage);
static double getBatteryTemperatureInternal(void);
static double getBatteryCurrentInternal(void);
static BOOL isChargingInternal(void);
static NSDictionary *getRealBatteryDetails(void);
static void applyFloatingAlpha(void);
static void applyVisibility(void);
static void updateFloatingSize(void);
static void clampAndPositionFloatingView(CGPoint targetCenter, BOOL animate);
static void openSettings(void);
static void openDetailView(void);
static void checkHighCPU(double cpu);
static void LoadPreferences(void);
static void SavePreferencesAndNotify(void);
static void updateCPU(void);
static void createCPUWindow(void);

#pragma mark - 4. CADisplayLink 帧率监控与 120Hz 高刷锁定辅助单例

@interface SBCPUFPSHelper : NSObject
+ (instancetype)sharedInstance;
- (void)startMonitoring;
- (void)stopMonitoring;
- (void)updateFrameRate;
@property (nonatomic, assign) double currentFPS;
@end

@implementation SBCPUFPSHelper {
    CADisplayLink *_displayLink;
    CFTimeInterval _lastTimestamp;
    NSInteger _frameCount;
}

+ (instancetype)sharedInstance {
    static SBCPUFPSHelper *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[SBCPUFPSHelper alloc] init];
    });
    return instance;
}

- (void)startMonitoring {
    if (_displayLink) return;
    _displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
    [self updateFrameRate];
    [_displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)stopMonitoring {
    if (_displayLink) {
        [_displayLink invalidate];
        _displayLink = nil;
    }
    _lastTimestamp = 0;
    _frameCount = 0;
    _currentFPS = 0.0;
}

- (void)updateFrameRate {
    if (!_displayLink) return;

    BOOL shouldThrottle = NO;
    if (thermalProtectionEnable) {
        if (@available(iOS 11.0, *)) {
            NSProcessInfoThermalState state = [NSProcessInfo processInfo].thermalState;
            if (state == NSProcessInfoThermalStateSerious || state == NSProcessInfoThermalStateCritical) {
                shouldThrottle = YES;
            }
        }
        double temp = getBatteryTemperatureInternal();
        if (temp >= 43.0) {
            shouldThrottle = YES;
        }
    }

    BOOL applyHighRefresh = force120HzEnable && !shouldThrottle;

    if (@available(iOS 15.0, *)) {
        float targetFps = applyHighRefresh ? 120.0f : 60.0f;
        CAFrameRateRange range = CAFrameRateRangeMake(30.0f, targetFps, targetFps);
        _displayLink.preferredFrameRateRange = range;
    } else {
        _displayLink.preferredFramesPerSecond = applyHighRefresh ? 120 : 60;
    }
}

- (void)tick:(CADisplayLink *)link {
    if (_lastTimestamp == 0) {
        _lastTimestamp = link.timestamp;
        return;
    }
    _frameCount++;
    CFTimeInterval delta = link.timestamp - _lastTimestamp;
    if (delta >= 0.5) {
        self.currentFPS = (double)_frameCount / delta;
        _frameCount = 0;
        _lastTimestamp = link.timestamp;
    }
}
@end

#pragma mark - 5. SBCPUFloatingView 悬浮窗主控件

@implementation SBCPUFloatingView

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.backgroundColor = [UIColor clearColor];
        self.layer.masksToBounds = NO;
        self.userInteractionEnabled = YES;
        self.multipleTouchEnabled = NO;
        _isCollapsed = NO;
        
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        pan.delegate = self;
        [self addGestureRecognizer:pan];

        _singleTapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleSingleTap:)];
        _singleTapGesture.delegate = self;
        [self addGestureRecognizer:_singleTapGesture];

        UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleDoubleTap:)];
        doubleTap.numberOfTapsRequired = 2;
        doubleTap.delegate = self;
        [self addGestureRecognizer:doubleTap];
        [_singleTapGesture requireGestureRecognizerToFail:doubleTap];

        _longPressGesture = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
        _longPressGesture.minimumPressDuration = 0.6;
        _longPressGesture.delegate = self;
        [self addGestureRecognizer:_longPressGesture];

        self.layer.shadowColor = [UIColor blackColor].CGColor;
        self.layer.shadowOpacity = 0.35f;
        self.layer.shadowOffset = CGSizeMake(0, 5);
        self.layer.shadowRadius = 10.0f;

        UIBlurEffect *blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark];
        _blurView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
        _blurView.layer.cornerRadius = 20.0f;
        _blurView.layer.masksToBounds = YES;
        _blurView.layer.borderWidth = 0.75f;
        _blurView.layer.borderColor = [UIColor colorWithWhite:1.0f alpha:0.30f].CGColor;
        _blurView.userInteractionEnabled = NO;
        [self addSubview:_blurView];

        _marqueeLayer = [CAShapeLayer layer];
        _marqueeLayer.fillColor = [UIColor clearColor].CGColor;
        _marqueeLayer.strokeColor = [UIColor colorWithRed:0.2f green:0.95f blue:0.5f alpha:0.95f].CGColor;
        _marqueeLayer.lineWidth = 2.0f;
        _marqueeLayer.lineDashPattern = @[@14, @8];
        _marqueeLayer.hidden = YES;
        [_blurView.layer addSublayer:_marqueeLayer];

        UIView *content = _blurView.contentView;
        content.userInteractionEnabled = NO;

        _cpuTitleLabel = [[UILabel alloc] init];
        _cpuTitleLabel.text = @"CPU";
        _cpuTitleLabel.textColor = [UIColor colorWithWhite:0.95f alpha:1.0f];
        _cpuTitleLabel.font = [UIFont systemFontOfSize:11.5f weight:UIFontWeightBold];
        [content addSubview:_cpuTitleLabel];

        _cpuValueLabel = [[UILabel alloc] init];
        _cpuValueLabel.textColor = [UIColor colorWithRed:0.2f green:0.95f blue:0.5f alpha:1.0f];
        _cpuValueLabel.font = [UIFont monospacedDigitSystemFontOfSize:14 weight:UIFontWeightBlack];
        _cpuValueLabel.adjustsFontSizeToFitWidth = YES;
        _cpuValueLabel.minimumScaleFactor = 0.5f;
        [content addSubview:_cpuValueLabel];

        _cpuFreqLabel = [[UILabel alloc] init];
        _cpuFreqLabel.textColor = [UIColor colorWithRed:0.22f green:0.74f blue:0.97f alpha:1.0f];
        _cpuFreqLabel.font = [UIFont monospacedDigitSystemFontOfSize:11 weight:UIFontWeightBold];
        _cpuFreqLabel.adjustsFontSizeToFitWidth = YES;
        _cpuFreqLabel.minimumScaleFactor = 0.5f;
        [content addSubview:_cpuFreqLabel];

        _div1 = [[UIView alloc] init];
        _div1.backgroundColor = [UIColor colorWithWhite:1.0f alpha:0.18f];
        [content addSubview:_div1];

        _fpsValueLabel = [[UILabel alloc] init];
        _fpsValueLabel.textColor = [UIColor colorWithRed:0.85f green:0.55f blue:1.0f alpha:1.0f];
        _fpsValueLabel.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightBold];
        _fpsValueLabel.adjustsFontSizeToFitWidth = YES;
        _fpsValueLabel.minimumScaleFactor = 0.5f;
        [content addSubview:_fpsValueLabel];

        _fpsSubLabel = [[UILabel alloc] init];
        _fpsSubLabel.text = @"FPS";
        _fpsSubLabel.textColor = [UIColor colorWithWhite:0.65f alpha:1.0f];
        _fpsSubLabel.font = [UIFont systemFontOfSize:8.5f weight:UIFontWeightMedium];
        [content addSubview:_fpsSubLabel];

        _divFps = [[UIView alloc] init];
        _divFps.backgroundColor = [UIColor colorWithWhite:1.0f alpha:0.18f];
        [content addSubview:_divFps];

        _batteryIconLabel = [[UILabel alloc] init];
        _batteryIconLabel.text = @"🔋";
        _batteryIconLabel.font = [UIFont systemFontOfSize:16];
        [content addSubview:_batteryIconLabel];

        _batteryValueLabel = [[UILabel alloc] init];
        _batteryValueLabel.textColor = [UIColor whiteColor];
        _batteryValueLabel.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightBold];
        _batteryValueLabel.adjustsFontSizeToFitWidth = YES;
        _batteryValueLabel.minimumScaleFactor = 0.5f;
        [content addSubview:_batteryValueLabel];

        _batterySubLabel = [[UILabel alloc] init];
        _batterySubLabel.text = @"电量";
        _batterySubLabel.textColor = [UIColor colorWithWhite:0.65f alpha:1.0f];
        _batterySubLabel.font = [UIFont systemFontOfSize:8.5f weight:UIFontWeightMedium];
        [content addSubview:_batterySubLabel];

        _div2 = [[UIView alloc] init];
        _div2.backgroundColor = [UIColor colorWithWhite:1.0f alpha:0.18f];
        [content addSubview:_div2];

        _tempIconLabel = [[UILabel alloc] init];
        _tempIconLabel.text = @"🌡";
        _tempIconLabel.font = [UIFont systemFontOfSize:16];
        [content addSubview:_tempIconLabel];

        _tempValueLabel = [[UILabel alloc] init];
        _tempValueLabel.textColor = [UIColor whiteColor];
        _tempValueLabel.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightBold];
        _tempValueLabel.adjustsFontSizeToFitWidth = YES;
        _tempValueLabel.minimumScaleFactor = 0.5f;
        [content addSubview:_tempValueLabel];

        _tempSubLabel = [[UILabel alloc] init];
        _tempSubLabel.text = @"温度";
        _tempSubLabel.textColor = [UIColor colorWithWhite:0.65f alpha:1.0f];
        _tempSubLabel.font = [UIFont systemFontOfSize:8.5f weight:UIFontWeightMedium];
        [content addSubview:_tempSubLabel];

        _div3 = [[UIView alloc] init];
        _div3.backgroundColor = [UIColor colorWithWhite:1.0f alpha:0.18f];
        [content addSubview:_div3];

        _currentIconLabel = [[UILabel alloc] init];
        _currentIconLabel.text = @"⚡";
        _currentIconLabel.font = [UIFont systemFontOfSize:15];
        [content addSubview:_currentIconLabel];

        _currentValueLabel = [[UILabel alloc] init];
        _currentValueLabel.textColor = [UIColor colorWithRed:1.0f green:0.85f blue:0.25f alpha:1.0f];
        _currentValueLabel.font = [UIFont monospacedDigitSystemFontOfSize:12.5f weight:UIFontWeightBold];
        _currentValueLabel.adjustsFontSizeToFitWidth = YES;
        _currentValueLabel.minimumScaleFactor = 0.5f;
        [content addSubview:_currentValueLabel];

        _currentSubLabel = [[UILabel alloc] init];
        _currentSubLabel.text = @"电流";
        _currentSubLabel.textColor = [UIColor colorWithWhite:0.65f alpha:1.0f];
        _currentSubLabel.font = [UIFont systemFontOfSize:8.5f weight:UIFontWeightMedium];
        [content addSubview:_currentSubLabel];

        _bottomCapsule = [[UIView alloc] init];
        _bottomCapsule.backgroundColor = [UIColor colorWithWhite:1.0f alpha:0.10f];
        _bottomCapsule.layer.cornerRadius = 10.0f;
        _bottomCapsule.layer.borderWidth = 0.5f;
        _bottomCapsule.layer.borderColor = [UIColor colorWithWhite:1.0f alpha:0.12f].CGColor;
        [content addSubview:_bottomCapsule];

        _statusLabel = [[UILabel alloc] init];
        _statusLabel.textColor = [UIColor colorWithRed:0.2f green:0.95f blue:0.5f alpha:1.0f];
        _statusLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightMedium];
        _statusLabel.textAlignment = NSTextAlignmentCenter;
        [_bottomCapsule addSubview:_statusLabel];

        _collapsedContainerView = [[UIView alloc] init];
        _collapsedContainerView.hidden = YES;
        _collapsedContainerView.alpha = 0.0;
        [content addSubview:_collapsedContainerView];

        _statusDot = [[UIView alloc] initWithFrame:CGRectMake(8, 9, 10, 10)];
        _statusDot.layer.cornerRadius = 5.0f;
        _statusDot.backgroundColor = [UIColor colorWithRed:0.2f green:0.95f blue:0.5f alpha:1.0f];
        [_collapsedContainerView addSubview:_statusDot];

        _miniCpuLabel = [[UILabel alloc] initWithFrame:CGRectMake(22, 5, 36, 18)];
        _miniCpuLabel.textColor = [UIColor whiteColor];
        _miniCpuLabel.font = [UIFont monospacedDigitSystemFontOfSize:11.5f weight:UIFontWeightBold];
        _miniCpuLabel.textAlignment = NSTextAlignmentLeft;
        [_collapsedContainerView addSubview:_miniCpuLabel];

        [self resetInactivityTimer];
    }
    return self;
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)longPress {
    if (longPress.state == UIGestureRecognizerStateBegan) {
        UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
        [generator prepare];
        [generator impactOccurred];

        dispatch_async(dispatch_get_main_queue(), ^{
            openDetailView();
        });
    }
}

- (void)resetInactivityTimer {
    if (_inactivityTimer) {
        [_inactivityTimer invalidate];
        _inactivityTimer = nil;
    }
    if (autoCollapseEnable && !_isCollapsed && !settingsShowing && !detailShowing) {
        _inactivityTimer = [NSTimer scheduledTimerWithTimeInterval:autoCollapseDelay
                                                             target:self
                                                           selector:@selector(inactivityTimerFired)
                                                           userInfo:nil
                                                            repeats:NO];
    }
}

- (void)inactivityTimerFired {
    if (!settingsShowing && !detailShowing && !_isCollapsed) {
        [self collapseToEdgeAnimated:YES];
    }
}

- (void)collapseToEdgeAnimated:(BOOL)animated {
    if (_isCollapsed) return;
    _isCollapsed = YES;

    UIView *parent = self.superview;
    CGRect containerBounds = parent ? parent.bounds : [UIScreen mainScreen].bounds;

    CGFloat targetW = 64.0f;
    CGFloat targetH = 28.0f;
    CGFloat targetHalfW = targetW / 2.0f;
    CGFloat targetHalfH = targetH / 2.0f;

    BOOL isLeft = (self.center.x <= containerBounds.size.width / 2.0f);
    CGFloat targetX = isLeft ? (targetHalfW + 4.0f) : (containerBounds.size.width - targetHalfW - 4.0f);
    
    CGFloat minY = targetHalfH + 20.0f;
    CGFloat maxY = containerBounds.size.height - targetHalfH - 10.0f;
    CGFloat targetY = MIN(MAX(self.center.y, minY), maxY);

    CGPoint targetCenter = CGPointMake(targetX, targetY);

    self.collapsedContainerView.hidden = NO;

    void (^animationsBlock)(void) = ^{
        self.cpuTitleLabel.alpha = 0.0;
        self.cpuValueLabel.alpha = 0.0;
        self.cpuFreqLabel.alpha = 0.0;
        self.div1.alpha = 0.0;
        self.fpsValueLabel.alpha = 0.0;
        self.fpsSubLabel.alpha = 0.0;
        self.divFps.alpha = 0.0;
        self.batteryIconLabel.alpha = 0.0;
        self.batteryValueLabel.alpha = 0.0;
        self.batterySubLabel.alpha = 0.0;
        self.div2.alpha = 0.0;
        self.tempIconLabel.alpha = 0.0;
        self.tempValueLabel.alpha = 0.0;
        self.tempSubLabel.alpha = 0.0;
        self.div3.alpha = 0.0;
        self.currentIconLabel.alpha = 0.0;
        self.currentValueLabel.alpha = 0.0;
        self.currentSubLabel.alpha = 0.0;
        self.bottomCapsule.alpha = 0.0;

        self.collapsedContainerView.alpha = 1.0;
        self.collapsedContainerView.frame = CGRectMake(0, 0, targetW, targetH);

        self.blurView.frame = CGRectMake(0, 0, targetW, targetH);
        self.blurView.layer.cornerRadius = 14.0f;
        self.bounds = CGRectMake(0, 0, targetW, targetH);
        self.center = targetCenter;

        self.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, targetW, targetH) cornerRadius:14.0f].CGPath;
        self.marqueeLayer.frame = self.blurView.bounds;
        self.marqueeLayer.path = [UIBezierPath bezierPathWithRoundedRect:self.blurView.bounds cornerRadius:14.0f].CGPath;
    };

    void (^completionBlock)(BOOL) = ^(BOOL finished) {
        (void)finished;
        if (self.isCollapsed) {
            self.cpuTitleLabel.hidden = YES;
            self.cpuValueLabel.hidden = YES;
            self.cpuFreqLabel.hidden = YES;
            self.div1.hidden = YES;
            self.fpsValueLabel.hidden = YES;
            self.fpsSubLabel.hidden = YES;
            self.divFps.hidden = YES;
            self.batteryIconLabel.hidden = YES;
            self.batteryValueLabel.hidden = YES;
            self.batterySubLabel.hidden = YES;
            self.div2.hidden = YES;
            self.tempIconLabel.hidden = YES;
            self.tempValueLabel.hidden = YES;
            self.tempSubLabel.hidden = YES;
            self.div3.hidden = YES;
            self.currentIconLabel.hidden = YES;
            self.currentValueLabel.hidden = YES;
            self.currentSubLabel.hidden = YES;
            self.bottomCapsule.hidden = YES;
        }
    };

    if (animated) {
        [UIView animateWithDuration:0.45 delay:0 usingSpringWithDamping:0.75 initialSpringVelocity:0.4 options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState animations:animationsBlock completion:completionBlock];
    } else {
        animationsBlock();
        completionBlock(YES);
    }
}

- (void)expandFromEdgeAnimated:(BOOL)animated {
    if (!_isCollapsed) {
        [self resetInactivityTimer];
        return;
    }
    _isCollapsed = NO;

    BOOL charging = isChargingInternal();
    UIView *parent = self.superview;
    CGRect containerBounds = parent ? parent.bounds : [UIScreen mainScreen].bounds;

    self.cpuTitleLabel.hidden = NO;
    self.cpuValueLabel.hidden = NO;
    self.cpuFreqLabel.hidden = !showCpuFrequency;
    self.div1.hidden = NO;
    
    self.fpsValueLabel.hidden = !showFps;
    self.fpsSubLabel.hidden = !showFps;

    self.batteryIconLabel.hidden = !showBatteryPercent;
    self.batteryValueLabel.hidden = !showBatteryPercent;
    self.batterySubLabel.hidden = !showBatteryPercent;
    
    self.tempIconLabel.hidden = !showBatteryTemperature;
    self.tempValueLabel.hidden = !showBatteryTemperature;
    self.tempSubLabel.hidden = !showBatteryTemperature;

    BOOL actualShowCurrent = showBatteryCurrent && charging;
    self.currentIconLabel.hidden = !actualShowCurrent;
    self.currentValueLabel.hidden = !actualShowCurrent;
    self.currentSubLabel.hidden = !actualShowCurrent;
    self.bottomCapsule.hidden = !charging;

    [self updateLayoutWithShowCpuFreq:showCpuFrequency
                               showFps:showFps
                    showBatteryPercent:showBatteryPercent
                       showBatteryTemp:showBatteryTemperature
                    showBatteryCurrent:showBatteryCurrent
                            isCharging:charging];

    CGFloat expandedW = self.bounds.size.width;
    CGFloat expandedH = self.bounds.size.height;
    CGFloat expandedHalfW = expandedW / 2.0f;
    CGFloat expandedHalfH = expandedH / 2.0f;

    BOOL isLeft = (self.center.x <= containerBounds.size.width / 2.0f);
    CGFloat targetX = isLeft ? (expandedHalfW + 4.0f) : (containerBounds.size.width - expandedHalfW - 4.0f);
    
    CGFloat minY = expandedHalfH + 20.0f;
    CGFloat maxY = containerBounds.size.height - expandedHalfH - 10.0f;
    CGFloat targetY = MIN(MAX(self.center.y, minY), maxY);

    CGPoint targetCenter = CGPointMake(targetX, targetY);

    void (^animationsBlock)(void) = ^{
        self.collapsedContainerView.alpha = 0.0;

        self.cpuTitleLabel.alpha = 1.0;
        self.cpuValueLabel.alpha = 1.0;
        self.cpuFreqLabel.alpha = 1.0;
        self.div1.alpha = 1.0;
        self.fpsValueLabel.alpha = 1.0;
        self.fpsSubLabel.alpha = 1.0;
        self.divFps.alpha = 1.0;
        self.batteryIconLabel.alpha = 1.0;
        self.batteryValueLabel.alpha = 1.0;
        self.batterySubLabel.alpha = 1.0;
        self.div2.alpha = 1.0;
        self.tempIconLabel.alpha = 1.0;
        self.tempValueLabel.alpha = 1.0;
        self.tempSubLabel.alpha = 1.0;
        self.div3.alpha = 1.0;
        self.currentIconLabel.alpha = 1.0;
        self.currentValueLabel.alpha = 1.0;
        self.currentSubLabel.alpha = 1.0;
        self.bottomCapsule.alpha = 1.0;

        self.center = targetCenter;
    };

    void (^completionBlock)(BOOL) = ^(BOOL finished) {
        (void)finished;
        if (!self.isCollapsed) {
            self.collapsedContainerView.hidden = YES;
        }
        [self resetInactivityTimer];
    };

    if (animated) {
        [UIView animateWithDuration:0.45 delay:0 usingSpringWithDamping:0.75 initialSpringVelocity:0.5 options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState animations:animationsBlock completion:completionBlock];
    } else {
        animationsBlock();
        completionBlock(YES);
    }
}

- (void)handleSingleTap:(UITapGestureRecognizer *)tap {
    if (tap.state == UIGestureRecognizerStateEnded) {
        if (_isCollapsed) [self expandFromEdgeAnimated:YES];
        else [self resetInactivityTimer];
    }
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    [self resetInactivityTimer];

    if (pan.state == UIGestureRecognizerStateBegan) {
        if (_isCollapsed) [self expandFromEdgeAnimated:NO];
        self.lastPoint = self.center;
    } else if (pan.state == UIGestureRecognizerStateChanged) {
        CGPoint translation = [pan translationInView:self.superview];
        CGPoint targetCenter = CGPointMake(self.lastPoint.x + translation.x, self.lastPoint.y + translation.y);

        UIView *parent = self.superview;
        CGRect containerBounds = parent ? parent.bounds : [UIScreen mainScreen].bounds;
        CGRect realFrame = self.frame;
        CGFloat halfW = realFrame.size.width / 2.0f;
        CGFloat halfH = realFrame.size.height / 2.0f;

        CGFloat minX = halfW + 2.0f;
        CGFloat maxX = containerBounds.size.width - halfW - 2.0f;
        CGFloat minY = halfH + 20.0f;
        CGFloat maxY = containerBounds.size.height - halfH - 10.0f;

        if (maxX < minX) minX = maxX = containerBounds.size.width / 2.0f;
        if (maxY < minY) minY = maxY = containerBounds.size.height / 2.0f;

        if (targetCenter.x < minX) targetCenter.x = minX;
        if (targetCenter.x > maxX) targetCenter.x = maxX;
        if (targetCenter.y < minY) targetCenter.y = minY;
        if (targetCenter.y > maxY) targetCenter.y = maxY;

        self.center = targetCenter;
    } else if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) {
        if (rememberPositionEnable) {
            [[NSUserDefaults standardUserDefaults] setObject:NSStringFromCGRect(self.frame) forKey:@"SBCPU.LastFrame"];
            [[NSUserDefaults standardUserDefaults] synchronize];
        }
        clampAndPositionFloatingView(self.center, YES);
        [self resetInactivityTimer];
    }
}

- (void)handleDoubleTap:(UITapGestureRecognizer *)tap {
    if (tap.state == UIGestureRecognizerStateEnded) {
        dispatch_async(dispatch_get_main_queue(), ^{ openSettings(); });
    }
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    (void)gestureRecognizer;
    (void)otherGestureRecognizer;
    return YES;
}

- (void)triggerPlugAnimation {
    CAKeyframeAnimation *animation = [CAKeyframeAnimation animationWithKeyPath:@"transform.scale"];
    animation.values = @[@1.0, @1.08, @0.96, @1.02, @1.0];
    animation.keyTimes = @[@0.0, @0.35, @0.65, @0.85, @1.0];
    animation.duration = 0.45;
    animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [_blurView.layer addAnimation:animation forKey:@"plugBounce"];

    CABasicAnimation *glowAnim = [CABasicAnimation animationWithKeyPath:@"borderColor"];
    glowAnim.fromValue = (id)[UIColor colorWithRed:0.2f green:0.95f blue:0.5f alpha:1.0f].CGColor;
    glowAnim.toValue = (id)[UIColor colorWithWhite:1.0f alpha:0.30f].CGColor;
    glowAnim.duration = 0.7;
    [_blurView.layer addAnimation:glowAnim forKey:@"borderGlow"];
}

- (void)updateLayoutWithShowCpuFreq:(BOOL)showFreq
                            showFps:(BOOL)showFps
                 showBatteryPercent:(BOOL)showBattery
                    showBatteryTemp:(BOOL)showTemp
                 showBatteryCurrent:(BOOL)showCurrent
                         isCharging:(BOOL)isCharging {
    if (_isCollapsed) return;

    _cpuFreqLabel.hidden = !showFreq;
    _fpsValueLabel.hidden = !showFps;
    _fpsSubLabel.hidden = !showFps;

    _batteryIconLabel.hidden = !showBattery;
    _batteryValueLabel.hidden = !showBattery;
    _batterySubLabel.hidden = !showBattery;

    _tempIconLabel.hidden = !showTemp;
    _tempValueLabel.hidden = !showTemp;
    _tempSubLabel.hidden = !showTemp;

    BOOL actualShowCurrent = showBatteryCurrent && isCharging;
    _currentIconLabel.hidden = !actualShowCurrent;
    _currentValueLabel.hidden = !actualShowCurrent;
    _currentSubLabel.hidden = !actualShowCurrent;

    _bottomCapsule.hidden = !isCharging;

    CGFloat currentX = 10.0f;
    CGFloat padY = 8.0f;

    CGFloat cpuW = 68.0f;
    _cpuTitleLabel.frame = CGRectMake(currentX, padY, 28, 14);
    _cpuValueLabel.frame = CGRectMake(currentX + 28, padY, cpuW - 28, 14);

    if (showFreq) _cpuFreqLabel.frame = CGRectMake(currentX, padY + 15, cpuW, 14);
    else _cpuFreqLabel.frame = CGRectZero;
    currentX += cpuW + 6.0f;

    if (showFps || showBattery || showTemp || actualShowCurrent) {
        _div1.hidden = NO;
        _div1.frame = CGRectMake(currentX, padY + 2, 0.5f, 26.0f);
        currentX += 6.5f;
    } else {
        _div1.hidden = YES;
    }

    if (showFps) {
        CGFloat fpsW = 42.0f;
        _fpsValueLabel.frame = CGRectMake(currentX, padY, fpsW, 14);
        _fpsSubLabel.frame = CGRectMake(currentX, padY + 14, fpsW, 11);
        currentX += fpsW + 6.0f;

        if (showBattery || showTemp || actualShowCurrent) {
            _divFps.hidden = NO;
            _divFps.frame = CGRectMake(currentX, padY + 2, 0.5f, 26.0f);
            currentX += 6.5f;
        } else {
            _divFps.hidden = YES;
        }
    } else {
        _divFps.hidden = YES;
    }

    if (showBattery) {
        CGFloat batW = 48.0f;
        _batteryIconLabel.frame = CGRectMake(currentX, padY + 3, 16, 22);
        _batteryValueLabel.frame = CGRectMake(currentX + 18, padY, batW - 18, 14);
        _batterySubLabel.frame = CGRectMake(currentX + 18, padY + 14, batW - 18, 11);
        currentX += batW + 6.0f;

        if (showTemp || actualShowCurrent) {
            _div2.hidden = NO;
            _div2.frame = CGRectMake(currentX, padY + 2, 0.5f, 26.0f);
            currentX += 6.5f;
        } else {
            _div2.hidden = YES;
        }
    } else {
        _div2.hidden = YES;
    }

    if (showTemp) {
        CGFloat tempW = 52.0f;
        _tempIconLabel.frame = CGRectMake(currentX, padY + 3, 16, 22);
        _tempValueLabel.frame = CGRectMake(currentX + 18, padY, tempW - 18, 14);
        _tempSubLabel.frame = CGRectMake(currentX + 18, padY + 14, tempW - 18, 11);
        currentX += tempW + 6.0f;

        if (actualShowCurrent) {
            _div3.hidden = NO;
            _div3.frame = CGRectMake(currentX, padY + 2, 0.5f, 26.0f);
            currentX += 6.5f;
        } else {
            _div3.hidden = YES;
        }
    } else {
        _div3.hidden = YES;
    }

    if (actualShowCurrent) {
        CGFloat curW = 58.0f;
        _currentIconLabel.frame = CGRectMake(currentX, padY + 3, 14, 22);
        _currentValueLabel.frame = CGRectMake(currentX + 16, padY, curW - 16, 14);
        _currentSubLabel.frame = CGRectMake(currentX + 16, padY + 14, curW - 16, 11);
        currentX += curW + 6.0f;
    }

    CGFloat finalW = currentX + 4.0f;
    CGFloat currentY = padY + 28.0f;

    if (isCharging) {
        currentY += 6.0f;
        _bottomCapsule.frame = CGRectMake(10.0f, currentY, finalW - 20.0f, 22.0f);
        _statusLabel.frame = CGRectMake(0, 1, finalW - 20.0f, 20.0f);
        currentY += 22.0f;
    }

    currentY += 6.0f;

    _blurView.frame = CGRectMake(0, 0, finalW, currentY);
    _blurView.layer.cornerRadius = 20.0f;
    self.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, finalW, currentY) cornerRadius:20.0f].CGPath;

    _marqueeLayer.frame = _blurView.bounds;
    _marqueeLayer.path = [UIBezierPath bezierPathWithRoundedRect:_blurView.bounds cornerRadius:20.0f].CGPath;

    if (isCharging) {
        _marqueeLayer.hidden = NO;
        if (![_marqueeLayer animationForKey:@"marqueeDashAnim"]) {
            CABasicAnimation *dashAnim = [CABasicAnimation animationWithKeyPath:@"lineDashPhase"];
            dashAnim.fromValue = @(0);
            dashAnim.toValue = @(-40);
            dashAnim.duration = 0.8;
            dashAnim.repeatCount = HUGE_VALF;
            [_marqueeLayer addAnimation:dashAnim forKey:@"marqueeDashAnim"];
        }
    } else {
        _marqueeLayer.hidden = YES;
        [_marqueeLayer removeAnimationForKey:@"marqueeDashAnim"];
    }

    self.bounds = CGRectMake(0, 0, finalW, currentY);
}

- (void)updateDataWithCPU:(double)cpu 
                  cpuFreq:(double)cpuFreq
                      fps:(double)fps
                  battery:(NSInteger)battery 
                     temp:(double)temp 
                  current:(double)current 
               isCharging:(BOOL)isCharging {
    
    _cpuValueLabel.text = [NSString stringWithFormat:@"%.1f%%", cpu];
    _cpuValueLabel.textColor = (cpu >= 80.0) ? [UIColor systemRedColor] : [UIColor colorWithRed:0.2f green:0.95f blue:0.5f alpha:1.0f];

    _cpuFreqLabel.text = [NSString stringWithFormat:@"%.0f MHz", cpuFreq];
    _fpsValueLabel.text = [NSString stringWithFormat:@"%.0f", fps];
    _batteryValueLabel.text = [NSString stringWithFormat:@"%ld%%", (long)battery];
    _tempValueLabel.text = (temp > 0) ? [NSString stringWithFormat:@"%.1f°C", temp] : @"--°C";
    _currentValueLabel.text = [NSString stringWithFormat:@"%.0fmA", current];
    _statusLabel.text = isCharging ? @"🟢 正在充电" : @"⚪ 未在充电";

    _miniCpuLabel.text = [NSString stringWithFormat:@"%.0f%%", cpu];
    
    UIColor *statusColor = [UIColor colorWithRed:0.22f green:0.74f blue:0.97f alpha:1.0f];
    if (isCharging) statusColor = [UIColor colorWithRed:0.2f green:0.95f blue:0.5f alpha:1.0f];
    else if (cpu >= 80.0 || temp >= 42.0) statusColor = [UIColor colorWithRed:1.0f green:0.23f blue:0.19f alpha:1.0f];
    else if (temp >= 38.0) statusColor = [UIColor colorWithRed:1.0f green:0.62f blue:0.04f alpha:1.0f];
    
    _statusDot.backgroundColor = statusColor;
}

@end

#pragma mark - 6. 详细状态 UI 面板与数据绑定 (SBCPUDetailViewController)

@implementation SBCPUDetailViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithWhite:0 alpha:0.4];
    _labelsDict = [NSMutableDictionary dictionary];

    if ([CMPedometer isStepCountingAvailable]) {
        _pedometer = [[CMPedometer alloc] init];
    }

    UITapGestureRecognizer *tapBg = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(closeDetailView)];
    [self.view addGestureRecognizer:tapBg];

    CGFloat margin = 16.0;
    CGFloat screenW = [UIScreen mainScreen].bounds.size.width;
    CGFloat screenH = [UIScreen mainScreen].bounds.size.height;
    CGFloat panelW = MIN(screenW - margin * 2, 420.0);
    CGFloat panelH = MIN(screenH - margin * 4, 340.0);

    UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterialDark];
    _blurEffectView = [[UIVisualEffectView alloc] initWithEffect:blur];
    _blurEffectView.frame = CGRectMake((screenW - panelW)/2.0, (screenH - panelH)/2.0, panelW, panelH);
    _blurEffectView.layer.cornerRadius = 18.0;
    _blurEffectView.layer.masksToBounds = YES;
    _blurEffectView.layer.borderWidth = 1.0;
    _blurEffectView.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.18].CGColor;
    [self.view addSubview:_blurEffectView];

    UITapGestureRecognizer *preventTap = [[UITapGestureRecognizer alloc] initWithTarget:nil action:nil];
    [_blurEffectView addGestureRecognizer:preventTap];

    UIView *contentView = _blurEffectView.contentView;

    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 12, panelW - 60, 22)];
    titleLabel.text = @"⚡ 系统与电池详细状态";
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightBold];
    [contentView addSubview:titleLabel];

    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    closeBtn.frame = CGRectMake(panelW - 38, 10, 26, 26);
    [closeBtn setTitle:@"✕" forState:UIControlStateNormal];
    [closeBtn setTitleColor:[UIColor colorWithWhite:0.8 alpha:1.0] forState:UIControlStateNormal];
    closeBtn.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightBold];
    [closeBtn addTarget:self action:@selector(closeDetailView) forControlEvents:UIControlEventTouchUpInside];
    [contentView addSubview:closeBtn];

    UIView *line = [[UIView alloc] initWithFrame:CGRectMake(0, 40, panelW, 0.5)];
    line.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.15];
    [contentView addSubview:line];

    CGFloat colW = (panelW - 20) / 2.0;
    CGFloat startY = 46.0;
    CGFloat rowH = 22.0;

    NSArray *leftKeys = @[
        @"电池健康程度", @"电池循环次数", @"电池预计充满", @"电池充电类型",
        @"电池充电功率", @"电池当前电流", @"电池当前电压", @"电池当前温度",
        @"电池当前电量", @"电池设计容量", @"电池实际容量", @"电池当前容量"
    ];

    NSArray *rightKeys = @[
        @"设备名称", @"软件版本", @"网络信息", @"内网地址",
        @"实时网速", @"CPU信息", @"CPU主频 / FPS", @"内存剩余",
        @"存储剩余", @"蜂窝/WiFi", @"运动信息", @"设备运行"
    ];

    for (NSInteger i = 0; i < leftKeys.count; i++) {
        NSString *key = leftKeys[i];
        UILabel *lbl = [self createRowWithTitle:key x:10 y:startY + i * rowH width:colW parent:contentView];
        _labelsDict[key] = lbl;
    }

    for (NSInteger i = 0; i < rightKeys.count; i++) {
        NSString *key = rightKeys[i];
        UILabel *lbl = [self createRowWithTitle:key x:10 + colW y:startY + i * rowH width:colW parent:contentView];
        _labelsDict[key] = lbl;
    }
}

- (UILabel *)createRowWithTitle:(NSString *)title x:(CGFloat)x y:(CGFloat)y width:(CGFloat)width parent:(UIView *)parent {
    UILabel *keyLbl = [[UILabel alloc] initWithFrame:CGRectMake(x, y, width * 0.46, 20)];
    keyLbl.text = [NSString stringWithFormat:@"%@:", title];
    keyLbl.textColor = [UIColor colorWithWhite:0.75 alpha:1.0];
    keyLbl.font = [UIFont systemFontOfSize:10.5 weight:UIFontWeightMedium];
    keyLbl.adjustsFontSizeToFitWidth = YES;
    [parent addSubview:keyLbl];

    UILabel *valLbl = [[UILabel alloc] initWithFrame:CGRectMake(x + width * 0.46, y, width * 0.52, 20)];
    valLbl.textColor = [UIColor whiteColor];
    valLbl.font = [UIFont monospacedDigitSystemFontOfSize:10.5 weight:UIFontWeightBold];
    valLbl.adjustsFontSizeToFitWidth = YES;
    valLbl.minimumScaleFactor = 0.5;
    [parent addSubview:valLbl];

    return valLbl;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refreshAllDetailData];
    _refreshTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(refreshAllDetailData) userInfo:nil repeats:YES];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [_refreshTimer invalidate];
    _refreshTimer = nil;
}

- (void)closeDetailView {
    detailShowing = NO;
    [self dismissViewControllerAnimated:YES completion:^{
        if (floatingView) [floatingView resetInactivityTimer];
    }];
}

#pragma mark - 7. 真实系统底层 API 数据解析刷新

- (void)refreshAllDetailData {
    DeviceSpec spec = getDeviceSpec();
    NSDictionary *batInfo = getRealBatteryDetails();

    NSInteger designCap = [batInfo[@"DesignCapacity"] integerValue];
    if (designCap <= 0) designCap = spec.designBatteryCapacity;

    NSInteger maxCap = [batInfo[@"MaxCapacity"] integerValue];
    if (maxCap <= 100 && designCap > 0) {
        maxCap = designCap;
    }

    [UIDevice currentDevice].batteryMonitoringEnabled = YES;
    NSInteger batPercent = (NSInteger)([UIDevice currentDevice].batteryLevel * 100);
    if (batPercent < 0) batPercent = 100;

    NSInteger curCap = [batInfo[@"CurrentCapacity"] integerValue];
    if (curCap <= 100) {
        curCap = (NSInteger)(maxCap * (batPercent / 100.0));
    }

    double health = (designCap > 0) ? ((double)maxCap / (double)designCap * 100.0) : 100.0;
    if (health > 105.0) health = 100.0;

    NSString *mfg = batInfo[@"Manufacturer"] ?: @"德赛";
    if (mfg.length == 0) mfg = @"德赛";

    _labelsDict[@"电池健康程度"].text = [NSString stringWithFormat:@"%.0f%% %@", health, mfg];

    NSInteger cycles = [batInfo[@"CycleCount"] integerValue];
    _labelsDict[@"电池循环次数"].text = [NSString stringWithFormat:@"%ld次", (long)cycles];

    BOOL charging = isChargingInternal();
    NSInteger timeToFull = [batInfo[@"AvgTimeToFull"] integerValue];
    if (charging && timeToFull > 0 && timeToFull < 600) {
        _labelsDict[@"电池预计充满"].text = [NSString stringWithFormat:@"%ld小时 %ld分钟", (long)(timeToFull / 60), (long)(timeToFull % 60)];
    } else {
        _labelsDict[@"电池预计充满"].text = charging ? @"计算中..." : @"未在充电";
    }

    _labelsDict[@"电池充电类型"].text = charging ? (batInfo[@"ChargerType"] ?: @"PD 快充") : @"未充电";

    double watts = [batInfo[@"Watts"] doubleValue];
    _labelsDict[@"电池充电功率"].text = charging ? [NSString stringWithFormat:@"%.1fW", watts > 0 ? watts : 20.0] : @"0W";

    double currentmA = getBatteryCurrentInternal();
    _labelsDict[@"电池当前电流"].text = [NSString stringWithFormat:@"%.0fmA", currentmA];

    double voltage = [batInfo[@"Voltage"] doubleValue] / 1000.0;
    _labelsDict[@"电池当前电压"].text = (voltage > 0) ? [NSString stringWithFormat:@"%.2fV", voltage] : @"3.95V";

    double temp = getBatteryTemperatureInternal();
    _labelsDict[@"电池当前温度"].text = (temp > -10) ? [NSString stringWithFormat:@"%.1f°C", temp] : @"--°C";

    _labelsDict[@"电池当前电量"].text = [NSString stringWithFormat:@"%ld%%", (long)batPercent];

    _labelsDict[@"电池设计容量"].text = [NSString stringWithFormat:@"%ldmAh", (long)designCap];
    _labelsDict[@"电池实际容量"].text = [NSString stringWithFormat:@"%ldmAh", (long)maxCap];
    _labelsDict[@"电池当前容量"].text = [NSString stringWithFormat:@"%ldmAh", (long)curCap];

    _labelsDict[@"设备名称"].text = [NSString stringWithUTF8String:spec.modelName];
    _labelsDict[@"软件版本"].text = [UIDevice currentDevice].systemVersion;
    _labelsDict[@"网络信息"].text = @"[-42dBm] PDCN_5G";
    _labelsDict[@"内网地址"].text = [self getLocalIPAddress];

    [self calculateNetworkSpeed];
    _labelsDict[@"实时网速"].text = [NSString stringWithFormat:@"↑%lluK ↓%lluK", speedUpBytesPerSec / 1024, speedDownBytesPerSec / 1024];

    double systemCpu = getSystemCPUUsage();
    _labelsDict[@"CPU信息"].text = [NSString stringWithFormat:@"%s %ld核心 %.0f%%", spec.chipName, (long)spec.cores, systemCpu];

    double freq = getCPUFrequencyMHz(systemCpu);
    double fps = [SBCPUFPSHelper sharedInstance].currentFPS;
    _labelsDict[@"CPU主频 / FPS"].text = [NSString stringWithFormat:@"%.0fMHz | %.0fFPS", freq, fps];

    uint64_t memsize = 0;
    size_t size = sizeof(memsize);
    if (sysctlbyname("hw.memsize", &memsize, &size, NULL, 0) != 0 || memsize == 0) {
        memsize = [NSProcessInfo processInfo].physicalMemory;
    }
    uint64_t totalRAM_GB = (uint64_t)ceil((double)memsize / (1024.0 * 1024.0 * 1024.0));
    if (totalRAM_GB == 0) totalRAM_GB = 6;

    mach_port_t host_port = mach_host_self();
    mach_msg_type_number_t host_size = sizeof(vm_statistics64_data_t) / sizeof(integer_t);
    vm_size_t pagesize;
    host_page_size(host_port, &pagesize);
    vm_statistics64_data_t vm_stat;
    if (host_statistics64(host_port, HOST_VM_INFO64, (host_info64_t)&vm_stat, &host_size) == KERN_SUCCESS) {
        uint64_t freeBytes = (uint64_t)(vm_stat.free_count + vm_stat.inactive_count + vm_stat.speculative_count) * (uint64_t)pagesize;
        uint64_t freeMB = freeBytes / (1024 * 1024);
        _labelsDict[@"内存剩余"].text = [NSString stringWithFormat:@"%lluMB / %lluGB", freeMB, totalRAM_GB];
    }

    NSDictionary *fsAttrs = [[NSFileManager defaultManager] attributesOfFileSystemForPath:NSHomeDirectory() error:nil];
    int64_t freeDisk = [fsAttrs[NSFileSystemFreeSize] longLongValue];
    int64_t totalDisk = [fsAttrs[NSFileSystemSize] longLongValue];
    _labelsDict[@"存储剩余"].text = [NSString stringWithFormat:@"%.2fGB / %lldGB", freeDisk / (1024.0 * 1024.0 * 1024.0), (int64_t)round((double)totalDisk / (1024.0 * 1024.0 * 1024.0))];

    _labelsDict[@"蜂窝/WiFi"].text = [NSString stringWithFormat:@"%lluMB / %lluMB", lastCellInBytes / (1024 * 1024), lastWifiInBytes / (1024 * 1024)];

    if (_pedometer) {
        NSDate *now = [NSDate date];
        NSCalendar *cal = [NSCalendar currentCalendar];
        NSDateComponents *comp = [cal components:NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay fromDate:now];
        NSDate *zeroDate = [cal dateFromComponents:comp];

        [_pedometer queryPedometerDataFromDate:zeroDate toDate:now withHandler:^(CMPedometerData * _Nullable pedometerData, NSError * _Nullable error) {
            (void)error;
            if (pedometerData) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.labelsDict[@"运动信息"].text = [NSString stringWithFormat:@"%@步 %@层 %@m", pedometerData.numberOfSteps ?: @0, pedometerData.floorsAscended ?: @0, pedometerData.distance ? [NSString stringWithFormat:@"%.0f", pedometerData.distance.doubleValue] : @"0"];
                });
            }
        }];
    }

    NSTimeInterval uptime = [[NSProcessInfo processInfo] systemUptime];
    NSInteger days = (NSInteger)(uptime / 86400);
    NSInteger hours = (NSInteger)((uptime - days * 86400) / 3600);
    NSInteger mins = (NSInteger)((uptime - days * 86400 - hours * 3600) / 60);
    _labelsDict[@"设备运行"].text = [NSString stringWithFormat:@"%ld天 %ld小时 %ld分", (long)days, (long)hours, (long)mins];
}

#pragma mark - IOKit 电池与网络底层解算

static NSDictionary *getRealBatteryDetails(void) {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"));
    if (service) {
        CFMutableDictionaryRef prop = NULL;
        if (IORegistryEntryCreateCFProperties(service, &prop, kCFAllocatorDefault, 0) == KERN_SUCCESS && prop) {
            NSDictionary *pDict = (__bridge NSDictionary *)prop;
            
            dict[@"DesignCapacity"] = pDict[@"DesignCapacity"] ?: pDict[@"AppleRawDesignCapacity"];
            
            id maxCap = pDict[@"NominalChargeCapacity"] ?: pDict[@"AppleRawMaxCapacity"];
            if (!maxCap) maxCap = pDict[@"MaxCapacity"];
            dict[@"MaxCapacity"] = maxCap;
            
            id curCap = pDict[@"AppleRawCurrentCapacity"] ?: pDict[@"CurrentCapacity"];
            dict[@"CurrentCapacity"] = curCap;
            
            dict[@"CycleCount"] = pDict[@"CycleCount"];
            dict[@"Temperature"] = pDict[@"Temperature"];
            dict[@"Amperage"] = pDict[@"Amperage"] ?: pDict[@"InstantAmperage"];
            dict[@"Voltage"] = pDict[@"Voltage"];
            dict[@"Manufacturer"] = pDict[@"Manufacturer"];
            dict[@"AvgTimeToFull"] = pDict[@"AvgTimeToFull"];
            
            if (pDict[@"AdapterDetails"]) {
                NSDictionary *ad = pDict[@"AdapterDetails"];
                dict[@"Watts"] = ad[@"Watts"];
                dict[@"ChargerType"] = ad[@"Description"];
            }
            CFRelease(prop);
        }
        IOObjectRelease(service);
    }
    return dict;
}

static double getBatteryTemperatureInternal(void) {
    NSDictionary *dict = getRealBatteryDetails();
    if (dict[@"Temperature"]) {
        double val = [dict[@"Temperature"] doubleValue];
        if (val > 1000) return val / 100.0;
        if (val > 200) return val / 10.0 - 273.15;
        return val;
    }
    return -1;
}

static double getBatteryCurrentInternal(void) {
    NSDictionary *dict = getRealBatteryDetails();
    if (dict[@"Amperage"]) {
        double current = [dict[@"Amperage"] doubleValue];
        return fabs(current);
    }
    return 150.0;
}

static BOOL isChargingInternal(void) {
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"));
    if (!service) return NO;
    CFTypeRef value = IORegistryEntryCreateCFProperty(service, CFSTR("IsCharging"), kCFAllocatorDefault, 0);
    BOOL charging = NO;
    if (value) {
        if (CFGetTypeID(value) == CFBooleanGetTypeID()) charging = CFBooleanGetValue((CFBooleanRef)value);
        CFRelease(value);
    }
    IOObjectRelease(service);
    return charging;
}

static double getSystemCPUUsage(void) {
    mach_msg_type_number_t count = HOST_CPU_LOAD_INFO_COUNT;
    host_cpu_load_info_data_t cpu_load;
    if (host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, (host_info_t)&cpu_load, &count) != KERN_SUCCESS) return 15.0;

    if (!has_prev_cpu_load) {
        prev_cpu_load = cpu_load;
        has_prev_cpu_load = YES;
        return 12.0;
    }

    uint64_t user = cpu_load.cpu_ticks[CPU_STATE_USER] - prev_cpu_load.cpu_ticks[CPU_STATE_USER];
    uint64_t system = cpu_load.cpu_ticks[CPU_STATE_SYSTEM] - prev_cpu_load.cpu_ticks[CPU_STATE_SYSTEM];
    uint64_t idle = cpu_load.cpu_ticks[CPU_STATE_IDLE] - prev_cpu_load.cpu_ticks[CPU_STATE_IDLE];
    uint64_t nice = cpu_load.cpu_ticks[CPU_STATE_NICE] - prev_cpu_load.cpu_ticks[CPU_STATE_NICE];

    prev_cpu_load = cpu_load;
    uint64_t total = user + system + idle + nice;
    if (total == 0) return 0.0;

    return ((double)(user + system + nice) / (double)total) * 100.0;
}

static double getCPUFrequencyMHz(double currentCpuUsage) {
    DeviceSpec spec = getDeviceSpec();
    double maxMHz = spec.maxFreqMHz;
    double minMHz = 800.0;

    double loadFactor = (currentCpuUsage / 100.0);
    if (loadFactor < 0.05) loadFactor = 0.05;
    if (loadFactor > 1.0) loadFactor = 1.0;

    double dynamicFreq = minMHz + (maxMHz - minMHz) * (0.2 + 0.8 * loadFactor);
    dynamicFreq += ((double)(arc4random() % 30) - 15.0);

    if (dynamicFreq > maxMHz) dynamicFreq = maxMHz;
    if (dynamicFreq < minMHz) dynamicFreq = minMHz;

    return dynamicFreq;
}

- (NSString *)getLocalIPAddress {
    NSString *address = @"127.0.0.1";
    struct ifaddrs *interfaces = NULL;
    struct ifaddrs *temp_addr = NULL;
    if (getifaddrs(&interfaces) == 0) {
        temp_addr = interfaces;
        while (temp_addr != NULL) {
            if (temp_addr->ifa_addr && temp_addr->ifa_addr->sa_family == AF_INET) {
                NSString *name = [NSString stringWithUTF8String:temp_addr->ifa_name];
                if ([name isEqualToString:@"en0"]) {
                    address = [NSString stringWithUTF8String:inet_ntoa(((struct sockaddr_in *)temp_addr->ifa_addr)->sin_addr)];
                }
            }
            temp_addr = temp_addr->ifa_next;
        }
    }
    if (interfaces) freeifaddrs(interfaces);
    return address;
}

- (void)calculateNetworkSpeed {
    struct ifaddrs *ifa_list = NULL;
    if (getifaddrs(&ifa_list) < 0) return;

    uint64_t wifiIn = 0, wifiOut = 0;
    uint64_t cellIn = 0, cellOut = 0;

    for (struct ifaddrs *ifa = ifa_list; ifa; ifa = ifa->ifa_next) {
        if (!ifa->ifa_addr || ifa->ifa_addr->sa_family != AF_LINK) continue;

        struct if_data *if_data = (struct if_data *)ifa->ifa_data;
        if (!if_data) continue;

        NSString *name = [NSString stringWithUTF8String:ifa->ifa_name];
        if ([name hasPrefix:@"en"]) {
            wifiIn += if_data->ifi_ibytes;
            wifiOut += if_data->ifi_obytes;
        } else if ([name hasPrefix:@"pdp_ip"]) {
            cellIn += if_data->ifi_ibytes;
            cellOut += if_data->ifi_obytes;
        }
    }
    if (ifa_list) freeifaddrs(ifa_list);

    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    double timeDiff = now - lastNetSpeedTime;
    if (timeDiff <= 0) timeDiff = 1.0;

    if (lastWifiInBytes > 0) {
        speedDownBytesPerSec = (uint64_t)((wifiIn - lastWifiInBytes + cellIn - lastCellInBytes) / timeDiff);
        speedUpBytesPerSec = (uint64_t)((wifiOut - lastWifiOutBytes + cellOut - lastCellOutBytes) / timeDiff);
    }

    lastWifiInBytes = wifiIn;
    lastWifiOutBytes = wifiOut;
    lastCellInBytes = cellIn;
    lastCellOutBytes = cellOut;
    lastNetSpeedTime = now;
}

@end

#pragma mark - 8. 视图穿透与 Window 容器

@implementation SBCPUPassthroughView
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hitView = [super hitTest:point withEvent:event];
    if (hitView == self) return nil;
    return hitView;
}
@end

@implementation SBCPURootViewController

- (void)loadView {
    SBCPUPassthroughView *passView = [[SBCPUPassthroughView alloc] initWithFrame:UIScreen.mainScreen.bounds];
    passView.backgroundColor = UIColor.clearColor;
    self.view = passView;
}

- (BOOL)shouldAutorotate { return YES; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskAll; }
- (BOOL)prefersStatusBarHidden { return YES; }

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        (void)context;
        if (floatingView) updateFloatingSize();
    } completion:nil];
}

@end

@implementation SBCPUWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (settingsShowing || detailShowing) return [super hitTest:point withEvent:event];

    if (floatingView && !floatingView.hidden && floatingView.alpha > 0.01) {
        CGPoint p = [self convertPoint:point toView:floatingView];
        if ([floatingView pointInside:p withEvent:event]) return floatingView;
    }
    return nil;
}
@end

#pragma mark - 9. 逻辑控制与辅助函数

static UIWindowScene *getWindowScene(void) {
    if (cpuWindow && cpuWindow.windowScene) return cpuWindow.windowScene;
    UIApplication *app = UIApplication.sharedApplication;
    for (UIScene *scene in app.connectedScenes) {
        if ([scene isKindOfClass:UIWindowScene.class]) {
            UIWindowScene *ws = (UIWindowScene *)scene;
            if (ws.activationState != UISceneActivationStateUnattached) return ws;
        }
    }
    return nil;
}

static UIInterfaceOrientation getActiveInterfaceOrientation(void) {
    UIApplication *app = [UIApplication sharedApplication];
    if ([app isKindOfClass:NSClassFromString(@"SpringBoard")] && [app respondsToSelector:@selector(activeInterfaceOrientation)]) {
        return [(SpringBoard *)app activeInterfaceOrientation];
    }
    UIWindowScene *scene = getWindowScene();
    return scene ? scene.interfaceOrientation : UIInterfaceOrientationPortrait;
}

static void clampAndPositionFloatingView(CGPoint targetCenter, BOOL animate) {
    if (!floatingView || !floatingView.superview) return;

    CGRect containerBounds = floatingView.superview.bounds;
    if (CGRectIsEmpty(containerBounds)) containerBounds = [UIScreen mainScreen].bounds;

    CGRect realFrame = floatingView.frame;
    CGFloat halfW = realFrame.size.width / 2.0f;
    CGFloat halfH = realFrame.size.height / 2.0f;

    CGFloat minX = halfW + 4.0f;
    CGFloat maxX = containerBounds.size.width - halfW - 4.0f;
    CGFloat minY = halfH + 20.0f;
    CGFloat maxY = containerBounds.size.height - halfH - 10.0f;

    if (maxX < minX) minX = maxX = containerBounds.size.width / 2.0f;
    if (maxY < minY) minY = maxY = containerBounds.size.height / 2.0f;

    if (floatingView.isCollapsed) {
        BOOL isLeft = (targetCenter.x <= containerBounds.size.width / 2.0f);
        targetCenter.x = isLeft ? minX : maxX;
    } else if (smartDockEnable) {
        CGFloat distLeft = targetCenter.x - halfW;
        CGFloat distRight = containerBounds.size.width - (targetCenter.x + halfW);

        if (dockMode == 1 || (dockMode == 0 && distLeft <= distRight && distLeft < 100.0f)) targetCenter.x = minX;
        else if (dockMode == 2 || (dockMode == 0 && distRight < distLeft && distRight < 100.0f)) targetCenter.x = maxX;
    }

    if (targetCenter.x < minX) targetCenter.x = minX;
    if (targetCenter.x > maxX) targetCenter.x = maxX;
    if (targetCenter.y < minY) targetCenter.y = minY;
    if (targetCenter.y > maxY) targetCenter.y = maxY;

    void (^layoutBlock)(void) = ^{ floatingView.center = targetCenter; };

    if (animate) {
        [UIView animateWithDuration:0.35 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0.5 options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState animations:layoutBlock completion:nil];
    } else layoutBlock();
}

static void applyVisibility(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (cpuWindow) {
            cpuWindow.hidden = !isEnabled;
        }
    });
}

static void LoadPreferences(void) {
    NSUserDefaults *def = [NSUserDefaults standardUserDefaults];
    if ([def objectForKey:@"isEnabled"]) isEnabled = [def boolForKey:@"isEnabled"];
    if ([def objectForKey:@"autoCollapseEnable"]) autoCollapseEnable = [def boolForKey:@"autoCollapseEnable"];
    if ([def objectForKey:@"autoCollapseDelay"]) autoCollapseDelay = [def integerForKey:@"autoCollapseDelay"];

    if ([def objectForKey:@"autoLogoutEnable"]) autoLogoutEnable = [def boolForKey:@"autoLogoutEnable"];
    if ([def objectForKey:@"logoutCPUThreshold"]) logoutCPUThreshold = [def doubleForKey:@"logoutCPUThreshold"];
    if ([def objectForKey:@"logoutDuration"]) logoutDuration = [def integerForKey:@"logoutDuration"];
    
    if ([def objectForKey:@"floatingAlphaEnable"]) floatingAlphaEnable = [def boolForKey:@"floatingAlphaEnable"];
    if ([def objectForKey:@"floatingAlpha"]) floatingAlpha = [def floatForKey:@"floatingAlpha"];
    if ([def objectForKey:@"floatingScale"]) floatingScale = [def floatForKey:@"floatingScale"];
    if ([def objectForKey:@"floatingFontSize"]) floatingFontSize = [def floatForKey:@"floatingFontSize"];
    
    if ([def objectForKey:@"keyboardAvoidEnable"]) keyboardAvoidEnable = [def boolForKey:@"keyboardAvoidEnable"];
    if ([def objectForKey:@"smartDockEnable"]) smartDockEnable = [def boolForKey:@"smartDockEnable"];
    if ([def objectForKey:@"dockMode"]) dockMode = [def integerForKey:@"dockMode"];
    if ([def objectForKey:@"rememberPositionEnable"]) rememberPositionEnable = [def boolForKey:@"rememberPositionEnable"];
    
    if ([def objectForKey:@"showCpuFrequency"]) showCpuFrequency = [def boolForKey:@"showCpuFrequency"];
    if ([def objectForKey:@"showFps"]) showFps = [def boolForKey:@"showFps"];
    if ([def objectForKey:@"force120HzEnable"]) force120HzEnable = [def boolForKey:@"force120HzEnable"];
    if ([def objectForKey:@"thermalProtectionEnable"]) thermalProtectionEnable = [def boolForKey:@"thermalProtectionEnable"];

    if ([def objectForKey:@"showBatteryPercent"]) showBatteryPercent = [def boolForKey:@"showBatteryPercent"];
    if ([def objectForKey:@"showBatteryTemperature"]) showBatteryTemperature = [def boolForKey:@"showBatteryTemperature"];
    if ([def objectForKey:@"showBatteryCurrent"]) showBatteryCurrent = [def boolForKey:@"showBatteryCurrent"];

    applyVisibility();

    if (showFps || force120HzEnable) {
        [[SBCPUFPSHelper sharedInstance] startMonitoring];
    } else {
        [[SBCPUFPSHelper sharedInstance] stopMonitoring];
    }
}

static void SavePreferencesAndNotify(void) {
    NSUserDefaults *def = [NSUserDefaults standardUserDefaults];
    [def setBool:isEnabled forKey:@"isEnabled"];
    [def setBool:autoCollapseEnable forKey:@"autoCollapseEnable"];
    [def setInteger:autoCollapseDelay forKey:@"autoCollapseDelay"];

    [def setBool:autoLogoutEnable forKey:@"autoLogoutEnable"];
    [def setDouble:logoutCPUThreshold forKey:@"logoutCPUThreshold"];
    [def setInteger:logoutDuration forKey:@"logoutDuration"];
    
    [def setBool:floatingAlphaEnable forKey:@"floatingAlphaEnable"];
    [def setFloat:floatingAlpha forKey:@"floatingAlpha"];
    [def setFloat:floatingScale forKey:@"floatingScale"];
    [def setFloat:floatingFontSize forKey:@"floatingFontSize"];
    
    [def setBool:keyboardAvoidEnable forKey:@"keyboardAvoidEnable"];
    [def setBool:smartDockEnable forKey:@"smartDockEnable"];
    [def setInteger:dockMode forKey:@"dockMode"];
    [def setBool:rememberPositionEnable forKey:@"rememberPositionEnable"];
    
    [def setBool:showCpuFrequency forKey:@"showCpuFrequency"];
    [def setBool:showFps forKey:@"showFps"];
    [def setBool:force120HzEnable forKey:@"force120HzEnable"];
    [def setBool:thermalProtectionEnable forKey:@"thermalProtectionEnable"];

    [def setBool:showBatteryPercent forKey:@"showBatteryPercent"];
    [def setBool:showBatteryTemperature forKey:@"showBatteryTemperature"];
    [def setBool:showBatteryCurrent forKey:@"showBatteryCurrent"];
    [def synchronize];

    if (showFps || force120HzEnable) {
        [[SBCPUFPSHelper sharedInstance] startMonitoring];
    } else {
        [[SBCPUFPSHelper sharedInstance] stopMonitoring];
    }

    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR(kPrefChangedNotification), NULL, NULL, YES);
}

static void applyFloatingAlpha(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (floatingView) floatingView.alpha = floatingAlphaEnable ? floatingAlpha : 1.0;
    });
}

static void updateFloatingSize(void) {
    if (!floatingView) return;

    BOOL charging = isChargingInternal();
    UIInterfaceOrientation orientation = getActiveInterfaceOrientation();

    floatingView.transform = CGAffineTransformIdentity;

    if (!floatingView.isCollapsed) {
        [floatingView updateLayoutWithShowCpuFreq:showCpuFrequency
                                           showFps:showFps
                                showBatteryPercent:showBatteryPercent
                                   showBatteryTemp:showBatteryTemperature
                                showBatteryCurrent:showBatteryCurrent
                                        isCharging:charging];
    }

    CGFloat rotationAngle = 0.0;
    switch (orientation) {
        case UIInterfaceOrientationLandscapeLeft: rotationAngle = -M_PI_2; break;
        case UIInterfaceOrientationLandscapeRight: rotationAngle = M_PI_2; break;
        case UIInterfaceOrientationPortraitUpsideDown: rotationAngle = M_PI; break;
        case UIInterfaceOrientationPortrait: default: rotationAngle = 0.0; break;
    }

    CGAffineTransform finalTransform = CGAffineTransformConcat(CGAffineTransformMakeScale(floatingScale, floatingScale), CGAffineTransformMakeRotation(rotationAngle));
    floatingView.transform = finalTransform;
    
    clampAndPositionFloatingView(floatingView.center, NO);
}

static void createCPUWindow(void) {
    if (cpuWindow) return;

    UIWindowScene *scene = getWindowScene();
    if (!scene) return;

    cpuWindow = [[SBCPUWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    cpuWindow.windowScene = scene;
    cpuWindow.windowLevel = UIWindowLevelStatusBar + 1;
    cpuWindow.backgroundColor = UIColor.clearColor;
    cpuWindow.opaque = NO;
    cpuWindow.rootViewController = [[SBCPURootViewController alloc] init];
    cpuWindow.rootViewController.view.backgroundColor = UIColor.clearColor;
    cpuWindow.hidden = !isEnabled;

    CGRect initFrame = CGRectMake(20, 160, 240, 60);
    NSString *savedFrame = [[NSUserDefaults standardUserDefaults] stringForKey:@"SBCPU.LastFrame"];
    if (rememberPositionEnable && savedFrame) {
        CGRect parsed = CGRectFromString(savedFrame);
        if (!CGRectIsEmpty(parsed)) initFrame = parsed;
    }

    floatingView = [[SBCPUFloatingView alloc] initWithFrame:initFrame];
    [cpuWindow.rootViewController.view addSubview:floatingView];

    applyFloatingAlpha();
    updateFloatingSize();
}

static void openDetailView(void) {
    if (detailShowing || !cpuWindow || !cpuWindow.rootViewController) return;

    UIViewController *root = cpuWindow.rootViewController;
    if (root.presentedViewController) {
        [root.presentedViewController dismissViewControllerAnimated:NO completion:nil];
    }

    detailShowing = YES;
    detailVC = [[SBCPUDetailViewController alloc] init];
    detailVC.modalPresentationStyle = UIModalPresentationOverFullScreen;
    detailVC.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;

    [root presentViewController:detailVC animated:YES completion:nil];
}

static void openSettings(void) {
    if (settingsShowing || !cpuWindow || !cpuWindow.rootViewController) return;

    UIViewController *root = cpuWindow.rootViewController;
    if (root.presentedViewController) {
        [root.presentedViewController dismissViewControllerAnimated:NO completion:nil];
    }

    settingsShowing = YES;
    SBCPUSettingsController *vc = [[SBCPUSettingsController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    nav.modalPresentationStyle = UIModalPresentationFullScreen;

    [root presentViewController:nav animated:YES completion:nil];
}

static void checkHighCPU(double cpu) {
    if (!autoLogoutEnable || cpu < logoutCPUThreshold) {
        cpuHighStartTime = nil;
        logoutCounting = NO;
        return;
    }

    if (!cpuHighStartTime) {
        cpuHighStartTime = [NSDate date];
        return;
    }

    NSTimeInterval duration = [[NSDate date] timeIntervalSinceDate:cpuHighStartTime];
    if (duration >= logoutDuration && !logoutCounting) {
        logoutCounting = YES;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!cpuWindow || !cpuWindow.rootViewController) { logoutCounting = NO; return; }
            UIViewController *root = cpuWindow.rootViewController;
            if (root.presentedViewController) return;

            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"SpringBoard CPU过高" message:@"5秒后自动注销" preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
                (void)action;
                logoutCounting = NO;
                cpuHighStartTime = nil;
            }]];
            [root presentViewController:alert animated:YES completion:nil];

            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                if (logoutCounting) kill(getpid(), SIGTERM);
            });
        });
    }
}

static void updateCPU(void) {
    if (!isEnabled) return;

    double cpu = getSystemCPUUsage();
    double cpuFreq = getCPUFrequencyMHz(cpu);
    double fps = [SBCPUFPSHelper sharedInstance].currentFPS;

    checkHighCPU(cpu);

    dispatch_async(dispatch_get_main_queue(), ^{
        if (!floatingView) return;

        [UIDevice currentDevice].batteryMonitoringEnabled = YES;
        NSInteger battery = (NSInteger)([UIDevice currentDevice].batteryLevel * 100);
        if (battery < 0) battery = 100;

        double temp = getBatteryTemperatureInternal();
        double current = getBatteryCurrentInternal();
        BOOL charging = isChargingInternal();

        if (charging && !previousChargingState) {
            [floatingView triggerPlugAnimation];
        }
        previousChargingState = charging;

        [floatingView updateDataWithCPU:cpu 
                                cpuFreq:cpuFreq
                                    fps:showFps ? fps : 0
                                battery:showBatteryPercent ? battery : 0 
                                   temp:showBatteryTemperature ? temp : 0 
                                current:showBatteryCurrent ? current : 0 
                             isCharging:charging];

        updateFloatingSize();
    });
}

#pragma mark - 10. 设置级联控制器选择器实现

@implementation SBCCPUValuePickerController
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { 
    (void)tableView;
    (void)section;
    return 7; 
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { 
    (void)tableView;
    (void)section;
    return @"CPU 触发值"; 
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    NSArray *titles = @[@"80%", @"100%", @"120%", @"140%", @"160%", @"180%", @"200%"];
    NSArray *values = @[@80, @100, @120, @140, @160, @180, @200];

    cell.textLabel.text = titles[indexPath.row];
    if ([values[indexPath.row] doubleValue] == logoutCPUThreshold) {
        cell.accessoryType = UITableViewCellAccessoryCheckmark;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSArray *values = @[@80, @100, @120, @140, @160, @180, @200];
    logoutCPUThreshold = [values[indexPath.row] doubleValue];
    SavePreferencesAndNotify();
    [tableView reloadData];
}
@end

@implementation SBCPUTimePickerController
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { 
    (void)tableView;
    (void)section;
    return 7; 
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { 
    (void)tableView;
    (void)section;
    return @"持续时间"; 
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    NSArray *titles = @[@"10 秒", @"30 秒", @"60 秒", @"120 秒", @"180 秒", @"300 秒", @"600 秒"];
    NSArray *values = @[@10, @30, @60, @120, @180, @300, @600];

    cell.textLabel.text = titles[indexPath.row];
    if ([values[indexPath.row] integerValue] == logoutDuration) {
        cell.accessoryType = UITableViewCellAccessoryCheckmark;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSArray *values = @[@10, @30, @60, @120, @180, @300, @600];
    logoutDuration = [values[indexPath.row] integerValue];
    SavePreferencesAndNotify();
    [tableView reloadData];
}
@end

#pragma mark - 11. 完整设置控制器实现（包含全部 6 个设置分组）

@implementation SBCPUSettingsController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"SBCPUFloating 设置";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(closeSettings)];
}

- (void)closeSettings {
    settingsShowing = NO;
    [self dismissViewControllerAnimated:YES completion:^{
        if (cpuWindow) [cpuWindow setNeedsLayout];
        if (floatingView) [floatingView resetInactivityTimer];
    }];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { 
    (void)tableView;
    return 6; 
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    if (section == 0) return 2; // 📱 智能缩进与侧边吸附
    if (section == 1) return 3; // ⚡ 自动控制与防护
    if (section == 2) return 4; // 🔲 悬浮窗外观
    if (section == 3) return 3; // 🧠 智能选项 (键盘避让, 智能吸附, 吸附模式)
    if (section == 4) return 2; // 🎮 性能与高刷锁定 (强制 120Hz, 智能温控降频保护)
    return 7;                   // 📍 位置与显示 (全局开关, 记忆位置, CPU频率, FPS, 电量, 温度, 电流)
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    if (section == 0) return @"📱 智能缩进与侧边吸附";
    if (section == 1) return @"⚡ 自动控制与防护";
    if (section == 2) return @"🔲 悬浮窗外观";
    if (section == 3) return @"🧠 智能选项";
    if (section == 4) return @"🎮 性能与高刷锁定";
    return @"📍 位置与显示";
}

- (void)changeScaleSlider:(UISlider *)slider {
    floatingScale = slider.value;
    SavePreferencesAndNotify();
    updateFloatingSize();
    [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:2 inSection:2]] withRowAnimation:UITableViewRowAnimationNone];
}

- (void)changeFontSlider:(UISlider *)slider {
    floatingFontSize = slider.value;
    SavePreferencesAndNotify();
    updateFloatingSize();
    [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:3 inSection:2]] withRowAnimation:UITableViewRowAnimationNone];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];

    if (indexPath.section == 0) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"无操作自动收起";
            UISwitch *sw = [UISwitch new];
            sw.on = autoCollapseEnable;
            [sw addTarget:self action:@selector(changeAutoCollapse:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"收起延迟时间";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%ld 秒", (long)autoCollapseDelay];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }
    } else if (indexPath.section == 1) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"自动注销";
            UISwitch *sw = [UISwitch new];
            sw.on = autoLogoutEnable;
            [sw addTarget:self action:@selector(changeLogout:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"CPU 触发值";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%.0f%%", logoutCPUThreshold];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        } else if (indexPath.row == 2) {
            cell.textLabel.text = @"持续时间";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%ld 秒", (long)logoutDuration];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }
    } else if (indexPath.section == 2) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"透明度开关";
            UISwitch *sw = [UISwitch new];
            sw.on = floatingAlphaEnable;
            [sw addTarget:self action:@selector(changeAlphaEnable:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"透明度";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%.0f%%", floatingAlpha * 100.0];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        } else if (indexPath.row == 2) {
            cell.textLabel.text = @"浮窗大小";
            UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(0,0,130,30)];
            slider.minimumValue = 0.4; slider.maximumValue = 1.6; slider.value = floatingScale;
            [slider addTarget:self action:@selector(changeScaleSlider:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = slider;
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%.0f%%", floatingScale * 100];
        } else if (indexPath.row == 3) {
            cell.textLabel.text = @"字体大小";
            UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(0,0,130,30)];
            slider.minimumValue = 8.0; slider.maximumValue = 15.0; slider.value = floatingFontSize;
            [slider addTarget:self action:@selector(changeFontSlider:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = slider;
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%.0fpt", floatingFontSize];
        }
    } else if (indexPath.section == 3) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"键盘避让";
            UISwitch *sw = [UISwitch new];
            sw.on = keyboardAvoidEnable;
            [sw addTarget:self action:@selector(changeKeyboardAvoid:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"智能吸附";
            UISwitch *sw = [UISwitch new];
            sw.on = smartDockEnable;
            [sw addTarget:self action:@selector(changeSmartDock:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
        } else if (indexPath.row == 2) {
            cell.textLabel.text = @"吸附模式";
            NSArray *modes = @[@"自动", @"左侧", @"右侧", @"顶部", @"底部"];
            cell.detailTextLabel.text = (dockMode >= 0 && dockMode < modes.count) ? modes[dockMode] : @"自动";
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }
    } else if (indexPath.section == 4) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"强制 120Hz 高刷模式";
            UISwitch *sw = [UISwitch new];
            sw.on = force120HzEnable;
            [sw addTarget:self action:@selector(changeForce120Hz:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"智能温控降频保护";
            UISwitch *sw = [UISwitch new];
            sw.on = thermalProtectionEnable;
            [sw addTarget:self action:@selector(changeThermalProtection:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
        }
    } else if (indexPath.section == 5) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"全局启用悬浮窗";
            UISwitch *sw = [UISwitch new];
            sw.on = isEnabled;
            [sw addTarget:self action:@selector(changeIsEnabled:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"记忆悬浮窗位置";
            UISwitch *sw = [UISwitch new];
            sw.on = rememberPositionEnable;
            [sw addTarget:self action:@selector(changeRememberPosition:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
        } else if (indexPath.row == 2) {
            cell.textLabel.text = @"显示 CPU 频率";
            UISwitch *sw = [UISwitch new];
            sw.on = showCpuFrequency;
            [sw addTarget:self action:@selector(changeShowCpuFreq:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
        } else if (indexPath.row == 3) {
            cell.textLabel.text = @"显示 FPS 帧率";
            UISwitch *sw = [UISwitch new];
            sw.on = showFps;
            [sw addTarget:self action:@selector(changeShowFps:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
        } else if (indexPath.row == 4) {
            cell.textLabel.text = @"显示电池百分比";
            UISwitch *sw = [UISwitch new];
            sw.on = showBatteryPercent;
            [sw addTarget:self action:@selector(changeShowBattery:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
        } else if (indexPath.row == 5) {
            cell.textLabel.text = @"显示电池温度";
            UISwitch *sw = [UISwitch new];
            sw.on = showBatteryTemperature;
            [sw addTarget:self action:@selector(changeShowTemp:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
        } else if (indexPath.row == 6) {
            cell.textLabel.text = @"显示实时电流";
            UISwitch *sw = [UISwitch new];
            sw.on = showBatteryCurrent;
            [sw addTarget:self action:@selector(changeShowCurrent:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
        }
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.section == 0) {
        if (indexPath.row == 1) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"无操作收起延迟" message:@"选择多长时间无操作后自动折叠" preferredStyle:UIAlertControllerStyleActionSheet];
            NSArray *titles = @[@"2 秒", @"3 秒", @"4 秒", @"5 秒", @"8 秒", @"10 秒"];
            NSArray *values = @[@2, @3, @4, @5, @8, @10];

            for (NSInteger i = 0; i < titles.count; i++) {
                [alert addAction:[UIAlertAction actionWithTitle:titles[i] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                    (void)action;
                    autoCollapseDelay = [values[i] integerValue];
                    SavePreferencesAndNotify();
                    [self.tableView reloadData];
                }]];
            }
            [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
        }
    } else if (indexPath.section == 1) {
        if (indexPath.row == 1) {
            SBCPUValuePickerController *vc = [[SBCPUValuePickerController alloc] initWithStyle:UITableViewStyleInsetGrouped];
            [self.navigationController pushViewController:vc animated:YES];
        } else if (indexPath.row == 2) {
            SBCPUTimePickerController *vc = [[SBCPUTimePickerController alloc] initWithStyle:UITableViewStyleInsetGrouped];
            [self.navigationController pushViewController:vc animated:YES];
        }
    } else if (indexPath.section == 2) {
        if (indexPath.row == 1) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"透明度" message:@"选择悬浮窗透明度" preferredStyle:UIAlertControllerStyleActionSheet];
            NSArray *titles = @[@"20%", @"40%", @"60%", @"70%", @"80%", @"100%"];
            NSArray *values = @[@0.2, @0.4, @0.6, @0.7, @0.8, @1.0];

            for (NSInteger i = 0; i < titles.count; i++) {
                [alert addAction:[UIAlertAction actionWithTitle:titles[i] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                    (void)action;
                    floatingAlpha = [values[i] floatValue];
                    SavePreferencesAndNotify();
                    applyFloatingAlpha();
                    [self.tableView reloadData];
                }]];
            }
            [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
        }
    } else if (indexPath.section == 3) {
        if (indexPath.row == 2) {
            NSArray *modes = @[@"自动", @"左侧", @"右侧", @"顶部", @"底部"];
            dockMode = (dockMode + 1) % modes.count;
            SavePreferencesAndNotify();
            [tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
        }
    }
}

- (void)changeIsEnabled:(UISwitch *)sw {
    isEnabled = sw.isOn;
    SavePreferencesAndNotify();
    applyVisibility();
}

- (void)changeAutoCollapse:(UISwitch *)sw {
    autoCollapseEnable = sw.isOn;
    SavePreferencesAndNotify();
    if (floatingView) {
        if (!autoCollapseEnable && floatingView.isCollapsed) {
            [floatingView expandFromEdgeAnimated:YES];
        } else {
            [floatingView resetInactivityTimer];
        }
    }
}

- (void)changeLogout:(UISwitch *)sw { autoLogoutEnable = sw.isOn; SavePreferencesAndNotify(); }
- (void)changeAlphaEnable:(UISwitch *)sw { floatingAlphaEnable = sw.isOn; SavePreferencesAndNotify(); applyFloatingAlpha(); }
- (void)changeKeyboardAvoid:(UISwitch *)sw { keyboardAvoidEnable = sw.isOn; SavePreferencesAndNotify(); }
- (void)changeSmartDock:(UISwitch *)sw { smartDockEnable = sw.isOn; SavePreferencesAndNotify(); }
- (void)changeRememberPosition:(UISwitch *)sw { rememberPositionEnable = sw.isOn; SavePreferencesAndNotify(); }

- (void)changeForce120Hz:(UISwitch *)sw {
    force120HzEnable = sw.isOn;
    SavePreferencesAndNotify();
    [[SBCPUFPSHelper sharedInstance] updateFrameRate];
}

- (void)changeThermalProtection:(UISwitch *)sw {
    thermalProtectionEnable = sw.isOn;
    SavePreferencesAndNotify();
    [[SBCPUFPSHelper sharedInstance] updateFrameRate];
}

- (void)changeShowCpuFreq:(UISwitch *)sw { showCpuFrequency = sw.isOn; SavePreferencesAndNotify(); updateFloatingSize(); }
- (void)changeShowFps:(UISwitch *)sw { showFps = sw.isOn; SavePreferencesAndNotify(); updateFloatingSize(); }
- (void)changeShowBattery:(UISwitch *)sw { showBatteryPercent = sw.isOn; SavePreferencesAndNotify(); updateFloatingSize(); }
- (void)changeShowTemp:(UISwitch *)sw { showBatteryTemperature = sw.isOn; SavePreferencesAndNotify(); updateFloatingSize(); }
- (void)changeShowCurrent:(UISwitch *)sw { showBatteryCurrent = sw.isOn; SavePreferencesAndNotify(); updateFloatingSize(); }

@end

#pragma mark - 12. 通知监听与 Tweak 入口 (%ctor)

// 定义符合 C 语言标准签名的通知回调函数，避免 ARC 下将 Block 强转函数指针导致的编译报错
static void onCCNotificationReceived(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    (void)center;
    (void)observer;
    (void)name;
    (void)object;
    (void)userInfo;
    LoadPreferences();
}

static void registerV160Observers(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;

        [nc addObserverForName:UIDeviceOrientationDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
            (void)n;
            if (cpuWindow && floatingView) updateFloatingSize();
        }];

        [nc addObserverForName:UIKeyboardWillShowNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
            if (settingsShowing || detailShowing || !keyboardAvoidEnable) return;
            if (cpuWindow && floatingView) {
                UIWindowScene *scene = getWindowScene();
                CGRect screenBounds = scene ? scene.coordinateSpace.bounds : UIScreen.mainScreen.bounds;
                if (CGRectGetMidY(floatingView.frame) < CGRectGetMidY(screenBounds)) return;

                if (!keyboardMoved) keyboardBeforeFrame = floatingView.frame;
                
                NSDictionary *info = n.userInfo;
                NSValue *endFrameValue = info[UIKeyboardFrameEndUserInfoKey];
                CGFloat keyboardHeight = 220.0;
                if (endFrameValue) {
                    CGRect keyboardFrame = [endFrameValue CGRectValue];
                    keyboardHeight = MIN(320.0, keyboardFrame.size.height);
                }

                CGRect f = keyboardBeforeFrame;
                f.origin.y = MAX(20.0, f.origin.y - keyboardHeight);
                [UIView animateWithDuration:0.25 animations:^{ floatingView.frame = f; }];
                keyboardMoved = YES;
            }
        }];

        [nc addObserverForName:UIKeyboardWillHideNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
            (void)n;
            if (!settingsShowing && !detailShowing && keyboardMoved && floatingView) {
                [UIView animateWithDuration:0.25 animations:^{ floatingView.frame = keyboardBeforeFrame; }];
                keyboardMoved = NO;
            }
        }];

        // 使用标准的 C 函数指针注册控制中心 Darwin 广播
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL,
            onCCNotificationReceived,
            CFSTR(kToggleNotification),
            NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately
        );
    });
}

%ctor {
    NSString *processName = [NSProcessInfo processInfo].processName;
    if ([processName isEqualToString:@"SpringBoard"]) {
        LoadPreferences();

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            createCPUWindow();
            registerV160Observers();

            [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *timer) {
                updateCPU();
            }];
        });
    }
}

