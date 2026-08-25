#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <mach/mach.h>
#import <signal.h>
#import <IOKit/IOKitLib.h>
#import <objc/runtime.h>

#ifndef kIOMainPortDefault
#define kIOMainPortDefault kIOMasterPortDefault
#endif

#define kPlistPath @"/var/mobile/Library/Preferences/com.yourname.sbcpufloating.plist"
#define kPrefChangedNotification "com.yourname.sbcpufloating.prefschanged"

#pragma mark - 全局共享配置变量
static BOOL sbcpuSmartChargeEnable = YES;
static NSInteger sbcpuChargeTempFast = 35;
static NSInteger sbcpuChargeTempReduce = 38;
static NSInteger sbcpuChargeTempPause = 40;
static NSInteger sbcpuChargeTempStop = 42;

// 全局强制断充状态 (由 powerd 与 SpringBoard 同步)
static BOOL g_ForcePauseCharging = NO;

#pragma mark - 读取配置函数
static void LoadPreferences() {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:kPlistPath];
    if (prefs) {
        if (prefs[@"sbcpuSmartChargeEnable"]) sbcpuSmartChargeEnable = [prefs[@"sbcpuSmartChargeEnable"] boolValue];
        if (prefs[@"sbcpuChargeTempFast"]) sbcpuChargeTempFast = [prefs[@"sbcpuChargeTempFast"] integerValue];
        if (prefs[@"sbcpuChargeTempReduce"]) sbcpuChargeTempReduce = [prefs[@"sbcpuChargeTempReduce"] integerValue];
        if (prefs[@"sbcpuChargeTempPause"]) sbcpuChargeTempPause = [prefs[@"sbcpuChargeTempPause"] integerValue];
        if (prefs[@"sbcpuChargeTempStop"]) sbcpuChargeTempStop = [prefs[@"sbcpuChargeTempStop"] integerValue];
    }
}

#pragma mark - 读取电池温度辅助函数
static double getBatteryTemperatureInternal() {
    io_iterator_t iterator = 0;
    io_service_t service = IO_OBJECT_NULL;
    CFMutableDictionaryRef matching = IOServiceMatching("AppleSmartBattery");
    if (!matching) return -1;

    if (IOServiceGetMatchingServices(kIOMasterPortDefault, matching, &iterator) != KERN_SUCCESS) return -1;

    while ((service = IOIteratorNext(iterator))) {
        CFTypeRef temp = IORegistryEntryCreateCFProperty(service, CFSTR("Temperature"), kCFAllocatorDefault, 0);
        if (temp) {
            double value = -1;
            if (CFGetTypeID(temp) == CFNumberGetTypeID()) {
                CFNumberGetValue((CFNumberRef)temp, kCFNumberDoubleType, &value);
            }
            CFRelease(temp);
            IOObjectRelease(service);
            IOObjectRelease(iterator);

            if (value > 1000 && value < 10000) value /= 100.0;
            else if (value > 200) value = value / 10.0 - 273.15;
            return value;
        }
        IOObjectRelease(service);
    }
    IOObjectRelease(iterator);
    return -1;
}

// ============================================================================
#pragma mark - 后端模块：powerd 核心充电控制 Hook
// ============================================================================

%group PowerdHooks

// Hook 系统的 PowerUISmartChargingManager，接管 pauseCharging 逻辑
%hook PowerUISmartChargingManager

- (BOOL)isChargingPaused {
    if (sbcpuSmartChargeEnable && g_ForcePauseCharging) {
        return YES; // 强行让系统 powerd 认为当前处于暂停充电状态
    }
    return %orig;
}

- (BOOL)isSmartChargingDisabled {
    if (sbcpuSmartChargeEnable && g_ForcePauseCharging) {
        return YES;
    }
    return %orig;
}

%end

// 定时监控 powerd 内部的电池温度并下发控制
static void powerdCheckTemperatureAndControl() {
    LoadPreferences();
    if (!sbcpuSmartChargeEnable) {
        g_ForcePauseCharging = NO;
        return;
    }

    double temp = getBatteryTemperatureInternal();
    if (temp <= 0) return;

    if (temp >= sbcpuChargeTempPause || temp >= sbcpuChargeTempStop) {
        g_ForcePauseCharging = YES;
    } else if (temp <= sbcpuChargeTempFast) {
        g_ForcePauseCharging = NO;
    }

    // 主动刷新 PowerUISmartChargingManager 单例
    Class managerClass = objc_getClass("PowerUISmartChargingManager");
    if (managerClass && [managerClass respondsToSelector:@selector(sharedInstance)]) {
        id manager = [managerClass performSelector:@selector(sharedInstance)];
        if (manager) {
            if ([manager respondsToSelector:@selector(setChargingPaused:)]) {
                typedef void (*SetPausedFunc)(id, SEL, BOOL);
                SetPausedFunc func = (SetPausedFunc)[manager methodForSelector:@selector(setChargingPaused:)];
                if (func) func(manager, @selector(setChargingPaused:), g_ForcePauseCharging);
            }
        }
    }
}

%end // end group PowerdHooks


// ============================================================================
#pragma mark - 前端模块：SpringBoard 界面与悬浮窗 UI
// ============================================================================

static UIWindow *cpuWindow = nil;
@class SBCPUDragView;

static UIView *containerView = nil;
static UILabel *label = nil;
static UIVisualEffectView *blurEffectView = nil;
static SBCPUDragView *cpuDragView = nil;

static CGFloat floatingScale = 1.0;
static CGFloat floatingFontSize = 13.0;
static CGFloat landscapeScale = 0.75;
static CGFloat landscapeFontSize = 12.0;

static BOOL settingsShowing = NO;

// 自动注销配置
static BOOL autoLogoutEnable = NO;
static double logoutCPUThreshold = 100.0;
static NSInteger logoutDuration = 60;
static NSDate *cpuHighStartTime = nil;
static BOOL logoutCounting = NO;

// 透明度配置
static BOOL floatingAlphaEnable = YES;
static CGFloat floatingAlpha = 0.70f;

// 布局与吸附控制配置
static BOOL autoWindowSizeEnable = NO;
static BOOL showBatteryPercent = YES;
static BOOL showBatteryTemperature = YES;
static BOOL showBatteryCurrent = YES;
static BOOL smartDockEnable = YES;
static NSInteger dockMode = 0;
static BOOL rememberPositionEnable = YES;

static void openSettings(void);
static void checkHighCPU(double cpu);
static void registerV160Observers(void);

@class SBCPUValuePickerController;
@class SBCPUTimePickerController;

#pragma mark - WindowScene 抓取
static UIWindowScene *getWindowScene() {
    if (cpuWindow && cpuWindow.windowScene) return cpuWindow.windowScene;
    UIApplication *app = UIApplication.sharedApplication;
    for (UIScene *scene in app.connectedScenes) {
        if ([scene isKindOfClass:UIWindowScene.class]) {
            UIWindowScene *ws = (UIWindowScene *)scene;
            if (ws.activationState != UISceneActivationStateUnattached) {
                return ws;
            }
        }
    }
    return nil;
}

#pragma mark - 精准 SpringBoard 进程 CPU 占用率计算 (mach_task_self)
static double getCPUUsage() {
    thread_array_t threads;
    mach_msg_type_number_t count = 0;

    kern_return_t kr = task_threads(mach_task_self(), &threads, &count);
    if (kr != KERN_SUCCESS) return 0.0;

    double totalCPU = 0.0;

    for (mach_msg_type_number_t i = 0; i < count; i++) {
        thread_info_data_t info;
        mach_msg_type_number_t infoCount = THREAD_INFO_MAX;

        kr = thread_info(threads[i], THREAD_BASIC_INFO, (thread_info_t)info, &infoCount);
        if (kr == KERN_SUCCESS) {
            thread_basic_info_t basic = (thread_basic_info_t)info;
            if (!(basic->flags & TH_FLAGS_IDLE)) {
                totalCPU += ((double)basic->cpu_usage / (double)TH_USAGE_SCALE) * 100.0;
            }
        }
    }

    vm_deallocate(mach_task_self(), (vm_address_t)threads, count * sizeof(thread_t));
    return totalCPU;
}

#pragma mark - 透明度刷新
static void applyFloatingAlpha() {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!containerView) return;
        containerView.alpha = floatingAlphaEnable ? floatingAlpha : 1.0;
    });
}

#pragma mark - 可穿透 Window 逻辑
@interface SBCPUWindow : UIWindow
@end

@implementation SBCPUWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (settingsShowing) return [super hitTest:point withEvent:event];
    UIView *view = [super hitTest:point withEvent:event];
    if (!view) return nil;

    if (containerView && ([view isDescendantOfView:containerView] || view == containerView)) {
        return view;
    }

    UIView *root = self.rootViewController.view;
    if (root) {
        for (UIView *subview in root.subviews) {
            if (subview != containerView && [subview isKindOfClass:NSClassFromString(@"SBCPUDragView")]) {
                CGRect frame = [subview.superview convertRect:subview.frame toView:self];
                if (CGRectContainsPoint(frame, point)) return subview;
            }
        }
    }
    return nil;
}
@end

#pragma mark - 拖动视图手势层
@interface SBCPUDragView : UIView
@property (nonatomic, assign) CGPoint lastPoint;
@end

@implementation SBCPUDragView

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    UITouch *touch = touches.anyObject;
    if (!touch) return;
    self.lastPoint = [touch locationInView:self.superview];
    [super touchesBegan:touches withEvent:event];
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
    UITouch *touch = touches.anyObject;
    if (!touch) return;

    CGPoint now = [touch locationInView:self.superview];
    CGFloat dx = now.x - self.lastPoint.x;
    CGFloat dy = now.y - self.lastPoint.y;

    if (!containerView) return;

    CGPoint center = containerView.center;
    center.x += dx;
    center.y += dy;

    CGSize size = self.superview.bounds.size;
    CGFloat halfW = containerView.bounds.size.width / 2.0;
    CGFloat halfH = containerView.bounds.size.height / 2.0;

    if (center.x < halfW) center.x = halfW;
    if (center.x > size.width - halfW) center.x = size.width - halfW;
    if (center.y < halfH + 40) center.y = halfH + 40;
    if (center.y > size.height - halfH) center.y = size.height - halfH;

    containerView.center = center;
    self.center = center;
    self.lastPoint = now;

    [super touchesMoved:touches withEvent:event];
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    [super touchesEnded:touches withEvent:event];
    if (!containerView) return;

    if (!smartDockEnable) {
        if (rememberPositionEnable) {
            [[NSUserDefaults standardUserDefaults] setObject:NSStringFromCGRect(containerView.frame) forKey:@"SBCPU.LastFrame"];
            [[NSUserDefaults standardUserDefaults] synchronize];
        }
        return;
    }

    CGSize size = self.superview.bounds.size;
    CGRect frame = containerView.frame;
    CGFloat left = CGRectGetMinX(frame);
    CGFloat right = size.width - CGRectGetMaxX(frame);
    CGFloat top = CGRectGetMinY(frame);
    CGFloat bottom = size.height - CGRectGetMaxY(frame);

    CGFloat minDistance = MIN(MIN(left, right), MIN(top, bottom));
    CGPoint center = containerView.center;

    if (dockMode > 0) {
        if (dockMode == 1) { center.x = containerView.bounds.size.width / 2.0 + 10; }
        else if (dockMode == 2) { center.x = size.width - containerView.bounds.size.width / 2.0 - 10; }
        else if (dockMode == 3) { center.y = containerView.bounds.size.height / 2.0 + 10; }
        else if (dockMode == 4) { center.y = size.height - containerView.bounds.size.height / 2.0 - 10; }
    } else if (minDistance == left) { center.x = containerView.bounds.size.width / 2.0 + 10; }
    else if (minDistance == right) { center.x = size.width - containerView.bounds.size.width / 2.0 - 10; }
    else if (minDistance == top) { center.y = containerView.bounds.size.height / 2.0 + 10; }
    else if (minDistance == bottom) { center.y = size.height - containerView.bounds.size.height / 2.0 - 10; }

    [UIView animateWithDuration:0.25 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        containerView.center = center;
        self.center = center;
    } completion:nil];
}
@end

#pragma mark - 双击触发设置页面
@interface SBCPUAction : NSObject
@end

@implementation SBCPUAction
+ (void)doubleTapAction {
    dispatch_async(dispatch_get_main_queue(), ^{
        settingsShowing = NO;
        openSettings();
    });
}
@end

#pragma mark - 创建悬浮窗 UI
static void createCPUWindow() {
    if (cpuWindow) return;

    UIWindowScene *scene = getWindowScene();
    if (!scene) return;

    cpuWindow = [[SBCPUWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    cpuWindow.windowScene = scene;
    cpuWindow.windowLevel = UIWindowLevelStatusBar + 1;
    cpuWindow.backgroundColor = UIColor.clearColor;
    cpuWindow.opaque = NO;
    cpuWindow.rootViewController = [UIViewController new];
    cpuWindow.rootViewController.view.backgroundColor = UIColor.clearColor;
    cpuWindow.hidden = NO;

    containerView = [[UIView alloc] initWithFrame:CGRectMake(30, 200, 115, 48)];
    containerView.backgroundColor = UIColor.clearColor;

    containerView.layer.shadowColor = [UIColor blackColor].CGColor;
    containerView.layer.shadowOpacity = 0.25f;
    containerView.layer.shadowOffset = CGSizeMake(0, 3);
    containerView.layer.shadowRadius = 6.0f;
    containerView.layer.masksToBounds = NO;
    containerView.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:containerView.bounds cornerRadius:14].CGPath;

    UIBlurEffect *blurEffect = nil;
    if (@available(iOS 13.0, *)) {
        blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark];
    } else {
        blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
    }
    blurEffectView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
    blurEffectView.frame = containerView.bounds;
    blurEffectView.layer.cornerRadius = 14;
    blurEffectView.layer.masksToBounds = YES;
    blurEffectView.layer.borderWidth = 0.5f;
    blurEffectView.layer.borderColor = [UIColor colorWithWhite:1.0f alpha:0.2f].CGColor;
    [containerView addSubview:blurEffectView];

    label = [[UILabel alloc] initWithFrame:blurEffectView.contentView.bounds];
    label.backgroundColor = UIColor.clearColor;
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = 0;
    label.textColor = UIColor.whiteColor;
    label.font = [UIFont monospacedDigitSystemFontOfSize:floatingFontSize weight:UIFontWeightBold];
    label.text = @"SB CPU\n0%";
    [blurEffectView.contentView addSubview:label];

    cpuDragView = [[SBCPUDragView alloc] initWithFrame:containerView.frame];
    cpuDragView.backgroundColor = UIColor.clearColor;
    cpuDragView.userInteractionEnabled = YES;
    cpuDragView.multipleTouchEnabled = NO;

    [cpuWindow.rootViewController.view addSubview:containerView];
    [cpuWindow.rootViewController.view addSubview:cpuDragView];

    UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:[SBCPUAction class] action:@selector(doubleTapAction)];
    doubleTap.numberOfTapsRequired = 2;
    [cpuDragView addGestureRecognizer:doubleTap];

    applyFloatingAlpha();
}

#pragma mark - 自动注销逻辑
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

static BOOL isLandscapeMode() {
    CGSize size = UIScreen.mainScreen.bounds.size;
    return size.width > size.height;
}

static NSInteger getBatteryPercent() {
    UIDevice *device = [UIDevice currentDevice];
    device.batteryMonitoringEnabled = YES;
    float level = device.batteryLevel;
    return (level < 0) ? -1 : (NSInteger)(level * 100.0f);
}

static double getBatteryCurrent() {
    io_iterator_t iterator = 0;
    io_service_t service = IO_OBJECT_NULL;
    CFMutableDictionaryRef matching = IOServiceMatching("AppleSmartBattery");
    if (!matching) return -1;

    if (IOServiceGetMatchingServices(kIOMasterPortDefault, matching, &iterator) != KERN_SUCCESS) return -1;

    while ((service = IOIteratorNext(iterator))) {
        CFTypeRef value = IORegistryEntryCreateCFProperty(service, CFSTR("Amperage"), kCFAllocatorDefault, 0);
        if (value) {
            double current = -1;
            if (CFGetTypeID(value) == CFNumberGetTypeID()) {
                CFNumberGetValue((CFNumberRef)value, kCFNumberDoubleType, &current);
            }
            CFRelease(value);
            IOObjectRelease(service);
            IOObjectRelease(iterator);
            return current;
        }
        IOObjectRelease(service);
    }
    IOObjectRelease(iterator);
    return -1;
}

static BOOL isCharging() {
    io_service_t service = IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceMatching("AppleSmartBattery"));
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

#pragma mark - 浮窗尺寸更新
static void updateFloatingSize() {
    if (!containerView || !label || !blurEffectView) return;

    if (autoWindowSizeEnable) {
        CGSize maxSize = CGSizeMake(UIScreen.mainScreen.bounds.size.width - 40, 200);
        CGSize textSize = [label sizeThatFits:maxSize];
        CGSize targetSize = CGSizeMake(textSize.width + 24, textSize.height + 16);

        if (targetSize.width < 90) targetSize.width = 90;
        if (targetSize.height < 42) targetSize.height = 42;

        CGPoint center = containerView.center;
        CGRect frame = containerView.frame;
        frame.size = targetSize;
        containerView.frame = frame;
        containerView.center = center;

        blurEffectView.frame = containerView.bounds;
        label.frame = blurEffectView.contentView.bounds;

        if (cpuDragView) cpuDragView.frame = containerView.frame;

        containerView.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:containerView.bounds cornerRadius:14].CGPath;
        [label setNeedsLayout];
        return;
    }

    BOOL landscape = isLandscapeMode();
    CGFloat scale = landscape ? landscapeScale : floatingScale;
    CGSize targetSize = landscape ? CGSizeMake(135 * scale, 58 * scale) : CGSizeMake(115 * scale, 48 * scale);

    if (!CGSizeEqualToSize(containerView.bounds.size, targetSize)) {
        CGRect frame = containerView.frame;
        CGPoint center = containerView.center;
        frame.size = targetSize;
        containerView.frame = frame;
        containerView.center = center;

        blurEffectView.frame = containerView.bounds;
        label.frame = blurEffectView.contentView.bounds;

        if (cpuDragView) cpuDragView.frame = containerView.frame;

        containerView.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:containerView.bounds cornerRadius:14].CGPath;
        [label setNeedsLayout];
    }
}

static NSString *smartChargeStateText() {
    double temp = getBatteryTemperatureInternal();
    if (temp >= sbcpuChargeTempStop) return @"🔴 保护断充";
    if (temp >= sbcpuChargeTempPause) return @"🟠 暂停充电";
    if (temp >= sbcpuChargeTempReduce) return @"🟡 降低功率";
    return @"🟢 正常充电";
}

#pragma mark - CPU 与数据定时刷新
static void updateCPU() {
    double cpu = getCPUUsage();
    checkHighCPU(cpu);

    dispatch_async(dispatch_get_main_queue(), ^{
        if (!label) return;

        label.font = [UIFont systemFontOfSize:(isLandscapeMode() ? landscapeFontSize : floatingFontSize)];

        NSInteger battery = getBatteryPercent();
        double temp = getBatteryTemperatureInternal();
        double current = getBatteryCurrent();
        BOOL charging = isCharging();

        NSString *batteryText = (battery >= 0) ? [NSString stringWithFormat:@"%ld%%", (long)battery] : @"";
        NSString *tempText = (temp > 0 && temp < 100) ? [NSString stringWithFormat:@"%.1f℃", temp] : @"";
        NSString *currentText = (current != -1) ? [NSString stringWithFormat:@"%.0fmA", current] : @"";
        NSString *chargeText = charging ? @"⚡" : @"";

        NSMutableArray *displayLines = [NSMutableArray array];
        [displayLines addObject:[NSString stringWithFormat:@"SB CPU %.1f%%", cpu]];

        NSMutableArray *batteryLine = [NSMutableArray array];
        if (showBatteryPercent && battery >= 0) [batteryLine addObject:[NSString stringWithFormat:@"🔋%@", batteryText]];
        if (showBatteryTemperature && tempText.length) [batteryLine addObject:[NSString stringWithFormat:@"🌡%@", tempText]];
        if (batteryLine.count) [displayLines addObject:[batteryLine componentsJoinedByString:@" "]];

        if (showBatteryCurrent && currentText.length) [displayLines addObject:[NSString stringWithFormat:@"%@%@", chargeText, currentText]];
        if (sbcpuSmartChargeEnable && charging) [displayLines addObject:smartChargeStateText()];

        label.text = [displayLines componentsJoinedByString:@"\n"];
        label.textColor = (cpu >= 80.0) ? UIColor.systemRedColor : UIColor.whiteColor;

        updateFloatingSize();
    });
}

#pragma mark - 温度编辑控制器
@interface SBChargeTempEditController : UIViewController
@property (nonatomic, assign) NSInteger tempValue;
@property (nonatomic, copy) NSString *tempTitle;
@property (nonatomic, copy) void (^finishBlock)(NSInteger value);
@end

@implementation SBChargeTempEditController {
    UILabel *_valueLabel;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    self.title = self.tempTitle;

    UIButton *minus = [UIButton buttonWithType:UIButtonTypeSystem];
    [minus setTitle:@"-" forState:UIControlStateNormal];
    minus.titleLabel.font = [UIFont systemFontOfSize:36 weight:UIFontWeightBold];
    [minus addTarget:self action:@selector(changeMinus) forControlEvents:UIControlEventTouchUpInside];

    UIButton *plus = [UIButton buttonWithType:UIButtonTypeSystem];
    [plus setTitle:@"+" forState:UIControlStateNormal];
    plus.titleLabel.font = [UIFont systemFontOfSize:36 weight:UIFontWeightBold];
    [plus addTarget:self action:@selector(changePlus) forControlEvents:UIControlEventTouchUpInside];

    _valueLabel = [[UILabel alloc] init];
    _valueLabel.textAlignment = NSTextAlignmentCenter;
    _valueLabel.font = [UIFont boldSystemFontOfSize:32];

    UIButton *done = [UIButton buttonWithType:UIButtonTypeSystem];
    [done setTitle:@"完成" forState:UIControlStateNormal];
    done.titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightMedium];
    [done addTarget:self action:@selector(doneClick) forControlEvents:UIControlEventTouchUpInside];

    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[minus, _valueLabel, plus]];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.distribution = UIStackViewDistributionEqualSpacing;
    row.alignment = UIStackViewAlignmentCenter;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[row, done]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 30;

    [self.view addSubview:stack];
    stack.translatesAutoresizingMaskIntoConstraints = NO;

    [NSLayoutConstraint activateConstraints:@[
        [stack.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [stack.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [stack.widthAnchor constraintEqualToConstant:220]
    ]];

    [self refresh];
}

- (void)refresh {
    _valueLabel.text = [NSString stringWithFormat:@"%ld℃", (long)self.tempValue];
}

- (void)changeMinus {
    if (self.tempValue > 0) self.tempValue--;
    [self refresh];
}

- (void)changePlus {
    if (self.tempValue < 100) self.tempValue++;
    [self refresh];
}

- (void)doneClick {
    if (self.finishBlock) self.finishBlock(self.tempValue);
    [self.navigationController popViewControllerAnimated:YES];
}
@end

#pragma mark - CPU 触发值 Picker 控制器
@interface SBCPUValuePickerController : UITableViewController
@end

@implementation SBCPUValuePickerController
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return 7; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return @"CPU触发值"; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    NSArray *titles = @[@"80%", @"100%", @"120%", @"140%", @"160%", @"180%", @"200%"];
    NSArray *values = @[@80, @100, @120, @140, @160, @180, @200];

    cell.textLabel.text = titles[indexPath.row];
    if ([values[indexPath.row] doubleValue] == logoutCPUThreshold) {
        cell.accessoryType = UITableViewCellAccessoryCheckmark;
    } else {
        cell.accessoryType = UITableViewCellAccessoryNone;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSArray *values = @[@80, @100, @120, @140, @160, @180, @200];
    logoutCPUThreshold = [values[indexPath.row] doubleValue];
    [[NSUserDefaults standardUserDefaults] setDouble:logoutCPUThreshold forKey:@"SBCPU.CPUThreshold"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [tableView reloadData];
}
@end

#pragma mark - 持续时间 Picker 控制器
@interface SBCPUTimePickerController : UITableViewController
@end

@implementation SBCPUTimePickerController
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return 7; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return @"持续时间"; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    NSArray *titles = @[@"10秒", @"30秒", @"60秒", @"120秒", @"180秒", @"300秒", @"600秒"];
    NSArray *values = @[@10, @30, @60, @120, @180, @300, @600];

    cell.textLabel.text = titles[indexPath.row];
    if ([values[indexPath.row] integerValue] == logoutDuration) {
        cell.accessoryType = UITableViewCellAccessoryCheckmark;
    } else {
        cell.accessoryType = UITableViewCellAccessoryNone;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSArray *values = @[@10, @30, @60, @120, @180, @300, @600];
    logoutDuration = [values[indexPath.row] integerValue];
    [[NSUserDefaults standardUserDefaults] setInteger:logoutDuration forKey:@"SBCPU.LogoutTime"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [tableView reloadData];
}
@end

#pragma mark - 设置主控制器
@interface SBCPUSettingsController : UITableViewController
@end

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
    }];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return 18; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return @"自动注销 / 悬浮窗 / 智能温控"; }

- (void)changeScaleSlider:(UISlider *)slider {
    floatingScale = slider.value;
    [[NSUserDefaults standardUserDefaults] setFloat:floatingScale forKey:@"SBCPU.FloatingScale"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    updateFloatingSize();
    [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:5 inSection:0]] withRowAnimation:UITableViewRowAnimationNone];
}

- (void)changeFontSlider:(UISlider *)slider {
    floatingFontSize = slider.value;
    [[NSUserDefaults standardUserDefaults] setFloat:floatingFontSize forKey:@"SBCPU.FloatingFontSize"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    if (label) label.font = [UIFont systemFontOfSize:floatingFontSize];
    [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:6 inSection:0]] withRowAnimation:UITableViewRowAnimationNone];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];

    if (indexPath.row == 0) {
        cell.textLabel.text = @"自动注销";
        UISwitch *sw = [[UISwitch alloc] init];
        sw.on = autoLogoutEnable;
        [sw addTarget:self action:@selector(changeLogout:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
    } else if (indexPath.row == 1) {
        cell.textLabel.text = @"CPU触发值";
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%.0f%%", logoutCPUThreshold];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if (indexPath.row == 2) {
        cell.textLabel.text = @"持续时间";
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%ld秒", (long)logoutDuration];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if (indexPath.row == 3) {
        cell.textLabel.text = @"透明度开关";
        UISwitch *sw = [[UISwitch alloc] init];
        sw.on = floatingAlphaEnable;
        [sw addTarget:self action:@selector(changeAlpha:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
    } else if (indexPath.row == 4) {
        cell.textLabel.text = @"透明度";
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%.0f%%", floatingAlpha * 100.0];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if (indexPath.row == 5) {
        cell.textLabel.text = @"浮窗大小";
        UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(0, 0, 140, 30)];
        slider.minimumValue = 0.4;
        slider.maximumValue = 1.6;
        slider.value = floatingScale;
        [slider addTarget:self action:@selector(changeScaleSlider:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = slider;
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%.0f%%", floatingScale * 100];
    } else if (indexPath.row == 6) {
        cell.textLabel.text = @"字体大小";
        UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(0, 0, 140, 30)];
        slider.minimumValue = 8.0;
        slider.maximumValue = 15.0;
        slider.value = floatingFontSize;
        [slider addTarget:self action:@selector(changeFontSlider:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = slider;
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%.0fpt", floatingFontSize];
    } else if (indexPath.row == 7) {
        cell.textLabel.text = @"自动调整浮窗大小";
        UISwitch *sw = [[UISwitch alloc] init];
        sw.on = autoWindowSizeEnable;
        [sw addTarget:self action:@selector(changeAutoWindowSize:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
    } else if (indexPath.row == 8) {
        cell.textLabel.text = @"智能吸附";
        UISwitch *sw = [[UISwitch alloc] init];
        sw.on = smartDockEnable;
        [sw addTarget:self action:@selector(changeSmartDock:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
    } else if (indexPath.row == 9) {
        cell.textLabel.text = @"吸附模式";
        NSArray *modes = @[@"自动", @"左侧", @"右侧", @"顶部", @"底部"];
        cell.detailTextLabel.text = (dockMode >= 0 && dockMode < modes.count) ? modes[dockMode] : @"自动";
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if (indexPath.row == 10) {
        cell.textLabel.text = @"显示电池百分比";
        UISwitch *sw = [[UISwitch alloc] init];
        sw.on = showBatteryPercent;
        [sw addTarget:self action:@selector(changeShowBattery:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
    } else if (indexPath.row == 11) {
        cell.textLabel.text = @"显示电池温度";
        UISwitch *sw = [[UISwitch alloc] init];
        sw.on = showBatteryTemperature;
        [sw addTarget:self action:@selector(changeShowTemperature:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
    } else if (indexPath.row == 12) {
        cell.textLabel.text = @"显示实时电流";
        UISwitch *sw = [[UISwitch alloc] init];
        sw.on = showBatteryCurrent;
        [sw addTarget:self action:@selector(changeShowCurrent:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
    } else if (indexPath.row == 13) {
        cell.textLabel.text = @"智能温控";
        UISwitch *sw = [[UISwitch alloc] init];
        sw.on = sbcpuSmartChargeEnable;
        [sw addTarget:self action:@selector(changeSmartCharge:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
    } else if (indexPath.row >= 14 && indexPath.row <= 17) {
        NSArray *chargeTitles = @[@"保持快充温度", @"降低功率温度", @"暂停充电温度", @"断充保护温度"];
        NSArray *chargeValues = @[@(sbcpuChargeTempFast), @(sbcpuChargeTempReduce), @(sbcpuChargeTempPause), @(sbcpuChargeTempStop)];
        NSInteger i = indexPath.row - 14;
        cell.textLabel.text = chargeTitles[i];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%ld℃", (long)[chargeValues[i] integerValue]];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return cell;
}

- (void)savePreferencesAndNotify() {
    NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithContentsOfFile:kPlistPath] ?: [NSMutableDictionary dictionary];
    dict[@"sbcpuSmartChargeEnable"] = @(sbcpuSmartChargeEnable);
    dict[@"sbcpuChargeTempFast"] = @(sbcpuChargeTempFast);
    dict[@"sbcpuChargeTempReduce"] = @(sbcpuChargeTempReduce);
    dict[@"sbcpuChargeTempPause"] = @(sbcpuChargeTempPause);
    dict[@"sbcpuChargeTempStop"] = @(sbcpuChargeTempStop);
    [dict writeToFile:kPlistPath atomically:YES];

    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR(kPrefChangedNotification),
        NULL, NULL, YES
    );
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.row == 1) {
        SBCPUValuePickerController *vc = [[SBCPUValuePickerController alloc] initWithStyle:UITableViewStyleInsetGrouped];
        [self.navigationController pushViewController:vc animated:YES];
    } else if (indexPath.row == 2) {
        SBCPUTimePickerController *vc = [[SBCPUTimePickerController alloc] initWithStyle:UITableViewStyleInsetGrouped];
        [self.navigationController pushViewController:vc animated:YES];
    } else if (indexPath.row == 4) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"透明度" message:@"选择悬浮窗透明度" preferredStyle:UIAlertControllerStyleActionSheet];
        NSArray *titles = @[@"20%", @"40%", @"60%", @"70%", @"80%", @"100%"];
        NSArray *values = @[@0.2, @0.4, @0.6, @0.7, @0.8, @1.0];

        for (NSInteger i = 0; i < titles.count; i++) {
            [alert addAction:[UIAlertAction actionWithTitle:titles[i] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                floatingAlpha = [values[i] floatValue];
                [[NSUserDefaults standardUserDefaults] setFloat:floatingAlpha forKey:@"SBCPU.FloatingAlpha"];
                [[NSUserDefaults standardUserDefaults] synchronize];
                applyFloatingAlpha();
                [self.tableView reloadData];
            }]];
        }
        [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    } else if (indexPath.row == 9) {
        NSArray *modes = @[@"自动", @"左侧", @"右侧", @"顶部", @"底部"];
        dockMode = (dockMode + 1) % modes.count;
        [[NSUserDefaults standardUserDefaults] setInteger:dockMode forKey:@"SBCPU.DockMode"];
        [[NSUserDefaults standardUserDefaults] synchronize];
        [tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
    } else if (indexPath.row >= 14 && indexPath.row <= 17) {
        NSInteger type = indexPath.row - 14;
        NSInteger current = 35;
        NSString *title = @"温度";

        if (type == 0) { current = sbcpuChargeTempFast; title = @"保持快充温度"; }
        if (type == 1) { current = sbcpuChargeTempReduce; title = @"降低功率温度"; }
        if (type == 2) { current = sbcpuChargeTempPause; title = @"暂停充电温度"; }
        if (type == 3) { current = sbcpuChargeTempStop; title = @"断充保护温度"; }

        SBChargeTempEditController *vc = [SBChargeTempEditController new];
        vc.tempValue = current;
        vc.tempTitle = title;
        vc.finishBlock = ^(NSInteger value) {
            if (type == 0) sbcpuChargeTempFast = value;
            if (type == 1) sbcpuChargeTempReduce = value;
            if (type == 2) sbcpuChargeTempPause = value;
            if (type == 3) sbcpuChargeTempStop = value;
            [self savePreferencesAndNotify];
            [self.tableView reloadData];
        };
        [self.navigationController pushViewController:vc animated:YES];
    }
}

- (void)changeLogout:(UISwitch *)sw {
    autoLogoutEnable = sw.isOn;
    [[NSUserDefaults standardUserDefaults] setBool:autoLogoutEnable forKey:@"SBCPU.AutoLogout"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)changeAlpha:(UISwitch *)sw {
    floatingAlphaEnable = sw.isOn;
    [[NSUserDefaults standardUserDefaults] setBool:floatingAlphaEnable forKey:@"SBCPU.FloatingAlphaEnable"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    applyFloatingAlpha();
}

- (void)changeAutoWindowSize:(UISwitch *)sw {
    autoWindowSizeEnable = sw.isOn;
    [[NSUserDefaults standardUserDefaults] setBool:autoWindowSizeEnable forKey:@"SBCPU.AutoWindowSize"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    updateFloatingSize();
}

- (void)changeSmartDock:(UISwitch *)sw {
    smartDockEnable = sw.isOn;
    [[NSUserDefaults standardUserDefaults] setBool:smartDockEnable forKey:@"SBCPU.SmartDock"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)changeShowBattery:(UISwitch *)sw {
    showBatteryPercent = sw.isOn;
    [[NSUserDefaults standardUserDefaults] setBool:showBatteryPercent forKey:@"SBCPU.ShowBattery"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    updateFloatingSize();
}

- (void)changeShowTemperature:(UISwitch *)sw {
    showBatteryTemperature = sw.isOn;
    [[NSUserDefaults standardUserDefaults] setBool:showBatteryTemperature forKey:@"SBCPU.ShowTemperature"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    updateFloatingSize();
}

- (void)changeShowCurrent:(UISwitch *)sw {
    showBatteryCurrent = sw.isOn;
    [[NSUserDefaults standardUserDefaults] setBool:showBatteryCurrent forKey:@"SBCPU.ShowCurrent"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    updateFloatingSize();
}

- (void)changeSmartCharge:(UISwitch *)sw {
    sbcpuSmartChargeEnable = sw.isOn;
    [self savePreferencesAndNotify];
}
@end

#pragma mark - 打开设置控制器
static void openSettings() {
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

#pragma mark - 通知与事件监听注册
static void registerV160Observers() {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;

        [nc addObserverForName:UIDeviceOrientationDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
            if (cpuWindow && containerView) {
                CGRect f = containerView.frame;
                CGSize s = cpuWindow.bounds.size;
                if (CGRectGetMaxX(f) > s.width) f.origin.x = s.width - f.size.width - 10;
                if (CGRectGetMaxY(f) > s.height) f.origin.y = s.height - f.size.height - 10;
                if (f.origin.x < 0) f.origin.x = 10;
                if (f.origin.y < 0) f.origin.y = 10;
                containerView.frame = f;
                if (cpuDragView) cpuDragView.frame = f;
            }
        }];
    });
}

// ============================================================================
#pragma mark - 构造函数 (%ctor)
// ============================================================================

%ctor {
    NSString *processName = [NSProcessInfo processInfo].processName;

    // 1. 如果注入在 powerd 进程：运行后台精准断充 Hook 引擎
    if ([processName isEqualToString:@"powerd"]) {
        %init(PowerdHooks);
        
        LoadPreferences();
        
        // 监听来自 SpringBoard 设置改动的 Darwin 通知
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL,
            (CFNotificationCallback)powerdCheckTemperatureAndControl,
            CFSTR(kPrefChangedNotification),
            NULL,
            CFNotificationSuspensionBehaviorCoalesce
        );

        // 每 2 秒轮询监测电池温度并驱动断充
        [NSTimer scheduledTimerWithTimeInterval:2.0 repeats:YES block:^(NSTimer *timer) {
            powerdCheckTemperatureAndControl();
        }];
        return;
    }

    // 2. 如果注入在 SpringBoard 进程：运行悬浮窗与 UI 控制面板
    if ([processName isEqualToString:@"SpringBoard"]) {
        LoadPreferences();

        NSUserDefaults *def = NSUserDefaults.standardUserDefaults;
        autoWindowSizeEnable = [def boolForKey:@"SBCPU.AutoWindowSize"];
        autoLogoutEnable = [def boolForKey:@"SBCPU.AutoLogout"];

        floatingScale = [def floatForKey:@"SBCPU.FloatingScale"];
        if (floatingScale < 0.4 || floatingScale > 1.6) floatingScale = 1.0;

        floatingFontSize = [def floatForKey:@"SBCPU.FloatingFontSize"];
        if (floatingFontSize < 8.0 || floatingFontSize > 15.0) floatingFontSize = 13.0;

        dockMode = [def integerForKey:@"SBCPU.DockMode"];

        double cpu = [def doubleForKey:@"SBCPU.CPUThreshold"];
        if (cpu >= 80.0 && cpu <= 1000.0) logoutCPUThreshold = cpu;

        NSInteger time = [def integerForKey:@"SBCPU.LogoutTime"];
        if (time >= 10) logoutDuration = time;

        if ([def objectForKey:@"SBCPU.FloatingAlphaEnable"]) {
            floatingAlphaEnable = [def boolForKey:@"SBCPU.FloatingAlphaEnable"];
        }

        CGFloat alpha = [def floatForKey:@"SBCPU.FloatingAlpha"];
        if (alpha >= 0.2 && alpha <= 1.0) floatingAlpha = alpha;

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            createCPUWindow();
            registerV160Observers();

            [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *timer) {
                updateCPU();
            }];
        });
    }
}
