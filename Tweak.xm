
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <mach/mach.h>
#import <signal.h>
#import <IOKit/IOKitLib.h>

#ifndef kIOMainPortDefault
#define kIOMainPortDefault kIOMasterPortDefault
#endif

#define kPlistPath @"/var/mobile/Library/Preferences/com.yourname.sbcpufloating.plist"
#define kPrefChangedNotification "com.yourname.sbcpufloating.prefschanged"

#pragma mark - 1. 完整前置类 Interface 声明 (解决 Clang forward class 报错)

// 1:1 忠实复刻设计图的高颜值悬浮窗视图类
@interface SBCPUFloatingView : UIView
@property (nonatomic, strong) UIVisualEffectView *blurView;

@property (nonatomic, strong) UILabel *cpuTitleLabel;
@property (nonatomic, strong) UILabel *cpuValueLabel;
@property (nonatomic, strong) UIView *topDivider;

@property (nonatomic, strong) UILabel *batteryIconLabel;
@property (nonatomic, strong) UILabel *batteryValueLabel;
@property (nonatomic, strong) UILabel *batteryTitleLabel;

@property (nonatomic, strong) UIView *midDivider;

@property (nonatomic, strong) UILabel *tempIconLabel;
@property (nonatomic, strong) UILabel *tempValueLabel;
@property (nonatomic, strong) UILabel *tempTitleLabel;

@property (nonatomic, strong) UIView *bottomCapsule;
@property (nonatomic, strong) UILabel *currentLabel;
@property (nonatomic, strong) UILabel *statusLabel;

- (void)updateDataWithCPU:(double)cpu 
                  battery:(NSInteger)battery 
                     temp:(double)temp 
                  current:(double)current 
               isCharging:(BOOL)isCharging;
@end

// 拖动手势视图类 (前置完整声明，使所有函数可正常读取 .frame)
@interface SBCPUDragView : UIView
@property (nonatomic, assign) CGPoint lastPoint;
@end

// 可穿透全屏 Window
@interface SBCPUWindow : UIWindow
@end

// 温度编辑控制器
@interface SBChargeTempEditController : UIViewController
@property (nonatomic, assign) NSInteger tempValue;
@property (nonatomic, copy) NSString *tempTitle;
@property (nonatomic, copy) void (^finishBlock)(NSInteger value);
@end

// CPU 触发值选择控制器
@interface SBCPUValuePickerController : UITableViewController
@end

// 持续时间选择控制器
@interface SBCPUTimePickerController : UITableViewController
@end

// 设置主控制器
@interface SBCPUSettingsController : UITableViewController
@end

#pragma mark - 2. 全局变量声明

static UIWindow *cpuWindow = nil;
static SBCPUFloatingView *floatingView = nil;
static SBCPUDragView *cpuDragView = nil;

static CGFloat floatingScale = 1.0;
static CGFloat floatingFontSize = 13.0;

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

// 布局、吸附与键盘避让控制配置
static BOOL autoWindowSizeEnable = NO;
static BOOL keyboardAvoidEnable = YES;
static BOOL smartDockEnable = YES;
static NSInteger dockMode = 0; // 0自动 1左 2右 3上 4下
static BOOL rememberPositionEnable = YES;

static BOOL showBatteryPercent = YES;
static BOOL showBatteryTemperature = YES;
static BOOL showBatteryCurrent = YES;

static CGRect keyboardBeforeFrame;
static BOOL keyboardMoved = NO;

// 前置函数声明
static void openSettings(void);
static void checkHighCPU(double cpu);
static void registerV160Observers(void);

#pragma mark - 3. 类 Implementation 实现

@implementation SBCPUFloatingView

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.backgroundColor = [UIColor clearColor];
        self.layer.masksToBounds = NO;
        
        // 自然落影
        self.layer.shadowColor = [UIColor blackColor].CGColor;
        self.layer.shadowOpacity = 0.30f;
        self.layer.shadowOffset = CGSizeMake(0, 4);
        self.layer.shadowRadius = 8.0f;

        // 高透暗色超薄毛玻璃
        UIBlurEffect *blurEffect = nil;
        if (@available(iOS 13.0, *)) {
            blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark];
        } else {
            blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
        }

        _blurView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
        _blurView.layer.cornerRadius = 20.0f;
        _blurView.layer.masksToBounds = YES;
        _blurView.layer.borderWidth = 0.5f;
        _blurView.layer.borderColor = [UIColor colorWithWhite:1.0f alpha:0.25f].CGColor;
        [self addSubview:_blurView];

        UIView *content = _blurView.contentView;

        // 顶行：CPU 芯片标识与占用率
        _cpuTitleLabel = [[UILabel alloc] init];
        _cpuTitleLabel.text = @"🔲 SB CPU";
        _cpuTitleLabel.textColor = [UIColor colorWithWhite:0.9f alpha:1.0f];
        _cpuTitleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightBold];
        [content addSubview:_cpuTitleLabel];

        _cpuValueLabel = [[UILabel alloc] init];
        _cpuValueLabel.textColor = [UIColor colorWithRed:0.2f green:0.9f blue:0.5f alpha:1.0f];
        _cpuValueLabel.font = [UIFont monospacedDigitSystemFontOfSize:17 weight:UIFontWeightBlack];
        _cpuValueLabel.textAlignment = NSTextAlignmentRight;
        [content addSubview:_cpuValueLabel];

        _topDivider = [[UIView alloc] init];
        _topDivider.backgroundColor = [UIColor colorWithWhite:1.0f alpha:0.15f];
        [content addSubview:_topDivider];

        // 中行左列：电量
        _batteryIconLabel = [[UILabel alloc] init];
        _batteryIconLabel.text = @"🔋";
        _batteryIconLabel.font = [UIFont systemFontOfSize:14];
        [content addSubview:_batteryIconLabel];

        _batteryValueLabel = [[UILabel alloc] init];
        _batteryValueLabel.textColor = [UIColor whiteColor];
        _batteryValueLabel.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightBold];
        [content addSubview:_batteryValueLabel];

        _batteryTitleLabel = [[UILabel alloc] init];
        _batteryTitleLabel.text = @"电量";
        _batteryTitleLabel.textColor = [UIColor colorWithWhite:0.6f alpha:1.0f];
        _batteryTitleLabel.font = [UIFont systemFontOfSize:9 weight:UIFontWeightMedium];
        [content addSubview:_batteryTitleLabel];

        // 中行竖向分割线
        _midDivider = [[UIView alloc] init];
        _midDivider.backgroundColor = [UIColor colorWithWhite:1.0f alpha:0.15f];
        [content addSubview:_midDivider];

        // 中行右列：温度
        _tempIconLabel = [[UILabel alloc] init];
        _tempIconLabel.text = @"🌡";
        _tempIconLabel.font = [UIFont systemFontOfSize:14];
        [content addSubview:_tempIconLabel];

        _tempValueLabel = [[UILabel alloc] init];
        _tempValueLabel.textColor = [UIColor whiteColor];
        _tempValueLabel.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightBold];
        [content addSubview:_tempValueLabel];

        _tempTitleLabel = [[UILabel alloc] init];
        _tempTitleLabel.text = @"温度";
        _tempTitleLabel.textColor = [UIColor colorWithWhite:0.6f alpha:1.0f];
        _tempTitleLabel.font = [UIFont systemFontOfSize:9 weight:UIFontWeightMedium];
        [content addSubview:_tempTitleLabel];

        // 底行胶囊框
        _bottomCapsule = [[UIView alloc] init];
        _bottomCapsule.backgroundColor = [UIColor colorWithWhite:1.0f alpha:0.10f];
        _bottomCapsule.layer.cornerRadius = 10.0f;
        _bottomCapsule.layer.borderWidth = 0.5f;
        _bottomCapsule.layer.borderColor = [UIColor colorWithWhite:1.0f alpha:0.12f].CGColor;
        [content addSubview:_bottomCapsule];

        _currentLabel = [[UILabel alloc] init];
        _currentLabel.textColor = [UIColor colorWithRed:1.0f green:0.85f blue:0.2f alpha:1.0f];
        _currentLabel.font = [UIFont monospacedDigitSystemFontOfSize:11 weight:UIFontWeightBold];
        [_bottomCapsule addSubview:_currentLabel];

        _statusLabel = [[UILabel alloc] init];
        _statusLabel.textColor = [UIColor colorWithRed:0.2f green:0.9f blue:0.5f alpha:1.0f];
        _statusLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightMedium];
        _statusLabel.textAlignment = NSTextAlignmentRight;
        [_bottomCapsule addSubview:_statusLabel];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _blurView.frame = self.bounds;
    self.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:self.bounds cornerRadius:20.0f].CGPath;

    CGFloat w = self.bounds.size.width - 24;

    _cpuTitleLabel.frame = CGRectMake(12, 10, 85, 18);
    _cpuValueLabel.frame = CGRectMake(12 + w - 85, 8, 85, 20);
    _topDivider.frame = CGRectMake(12, 32, w, 0.5f);

    CGFloat colW = (w - 12) / 2.0f;
    _batteryIconLabel.frame = CGRectMake(12, 38, 18, 22);
    _batteryValueLabel.frame = CGRectMake(32, 36, colW - 20, 14);
    _batteryTitleLabel.frame = CGRectMake(32, 51, colW - 20, 11);

    _midDivider.frame = CGRectMake(12 + colW + 5, 38, 0.5f, 24);

    _tempIconLabel.frame = CGRectMake(12 + colW + 12, 38, 18, 22);
    _tempValueLabel.frame = CGRectMake(12 + colW + 30, 36, colW - 30, 14);
    _tempTitleLabel.frame = CGRectMake(12 + colW + 30, 51, colW - 30, 11);

    _bottomCapsule.frame = CGRectMake(12, 68, w, 24);
    _currentLabel.frame = CGRectMake(8, 3, (w - 16) / 2.0f, 18);
    _statusLabel.frame = CGRectMake(8 + (w - 16) / 2.0f, 3, (w - 16) / 2.0f, 18);
}

- (void)updateDataWithCPU:(double)cpu 
                  battery:(NSInteger)battery 
                     temp:(double)temp 
                  current:(double)current 
               isCharging:(BOOL)isCharging {
    _cpuValueLabel.text = [NSString stringWithFormat:@"%.1f%%", cpu];
    _cpuValueLabel.textColor = (cpu >= 80.0) ? [UIColor systemRedColor] : [UIColor colorWithRed:0.2f green:0.9f blue:0.5f alpha:1.0f];

    _batteryValueLabel.text = [NSString stringWithFormat:@"%ld%%", (long)battery];
    _tempValueLabel.text = (temp > 0) ? [NSString stringWithFormat:@"%.1f°C", temp] : @"--°C";
    _currentLabel.text = [NSString stringWithFormat:@"⚡ %.0fmA", current];
    _statusLabel.text = isCharging ? @"🟢 正在充电" : @"⚪ 未在充电";
}

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

    if (!floatingView) return;

    CGPoint center = floatingView.center;
    center.x += dx;
    center.y += dy;

    CGSize size = self.superview.bounds.size;
    CGFloat halfW = floatingView.bounds.size.width / 2.0;
    CGFloat halfH = floatingView.bounds.size.height / 2.0;

    if (center.x < halfW) center.x = halfW;
    if (center.x > size.width - halfW) center.x = size.width - halfW;
    if (center.y < halfH + 40) center.y = halfH + 40;
    if (center.y > size.height - halfH) center.y = size.height - halfH;

    floatingView.center = center;
    self.center = center;
    self.lastPoint = now;

    [super touchesMoved:touches withEvent:event];
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    [super touchesEnded:touches withEvent:event];
    if (!floatingView) return;

    if (rememberPositionEnable) {
        [[NSUserDefaults standardUserDefaults] setObject:NSStringFromCGRect(floatingView.frame) forKey:@"SBCPU.LastFrame"];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }

    if (!smartDockEnable) return;

    CGSize size = self.superview.bounds.size;
    CGRect frame = floatingView.frame;
    CGFloat left = CGRectGetMinX(frame);
    CGFloat right = size.width - CGRectGetMaxX(frame);
    CGFloat top = CGRectGetMinY(frame);
    CGFloat bottom = size.height - CGRectGetMaxY(frame);

    CGFloat minDistance = MIN(MIN(left, right), MIN(top, bottom));
    CGPoint center = floatingView.center;

    if (dockMode > 0) {
        if (dockMode == 1) { center.x = floatingView.bounds.size.width / 2.0 + 10; }
        else if (dockMode == 2) { center.x = size.width - floatingView.bounds.size.width / 2.0 - 10; }
        else if (dockMode == 3) { center.y = floatingView.bounds.size.height / 2.0 + 10; }
        else if (dockMode == 4) { center.y = size.height - floatingView.bounds.size.height / 2.0 - 10; }
    } else if (minDistance == left) { center.x = floatingView.bounds.size.width / 2.0 + 10; }
    else if (minDistance == right) { center.x = size.width - floatingView.bounds.size.width / 2.0 - 10; }
    else if (minDistance == top) { center.y = floatingView.bounds.size.height / 2.0 + 10; }
    else if (minDistance == bottom) { center.y = size.height - floatingView.bounds.size.height / 2.0 - 10; }

    [UIView animateWithDuration:0.25 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        floatingView.center = center;
        self.center = center;
    } completion:nil];
}
@end

@implementation SBCPUWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (settingsShowing) return [super hitTest:point withEvent:event];
    UIView *view = [super hitTest:point withEvent:event];
    if (!view) return nil;

    if (floatingView && ([view isDescendantOfView:floatingView] || view == floatingView)) {
        return view;
    }

    UIView *root = self.rootViewController.view;
    if (root) {
        for (UIView *subview in root.subviews) {
            if (subview != floatingView && [subview isKindOfClass:[SBCPUDragView class]]) {
                CGRect frame = [subview.superview convertRect:subview.frame toView:self];
                if (CGRectContainsPoint(frame, point)) return subview;
            }
        }
    }
    return nil;
}
@end

#pragma mark - 4. 逻辑与设置助手函数

static void LoadPreferences() {
    NSUserDefaults *def = [NSUserDefaults standardUserDefaults];
    if ([def objectForKey:@"autoLogoutEnable"]) autoLogoutEnable = [def boolForKey:@"autoLogoutEnable"];
    if ([def objectForKey:@"logoutCPUThreshold"]) logoutCPUThreshold = [def doubleForKey:@"logoutCPUThreshold"];
    if ([def objectForKey:@"logoutDuration"]) logoutDuration = [def integerForKey:@"logoutDuration"];
    
    if ([def objectForKey:@"floatingAlphaEnable"]) floatingAlphaEnable = [def boolForKey:@"floatingAlphaEnable"];
    if ([def objectForKey:@"floatingAlpha"]) floatingAlpha = [def floatForKey:@"floatingAlpha"];
    if ([def objectForKey:@"floatingScale"]) floatingScale = [def floatForKey:@"floatingScale"];
    if ([def objectForKey:@"floatingFontSize"]) floatingFontSize = [def floatForKey:@"floatingFontSize"];
    if ([def objectForKey:@"autoWindowSizeEnable"]) autoWindowSizeEnable = [def boolForKey:@"autoWindowSizeEnable"];
    
    if ([def objectForKey:@"keyboardAvoidEnable"]) keyboardAvoidEnable = [def boolForKey:@"keyboardAvoidEnable"];
    if ([def objectForKey:@"smartDockEnable"]) smartDockEnable = [def boolForKey:@"smartDockEnable"];
    if ([def objectForKey:@"dockMode"]) dockMode = [def integerForKey:@"dockMode"];
    if ([def objectForKey:@"rememberPositionEnable"]) rememberPositionEnable = [def boolForKey:@"rememberPositionEnable"];
    
    if ([def objectForKey:@"showBatteryPercent"]) showBatteryPercent = [def boolForKey:@"showBatteryPercent"];
    if ([def objectForKey:@"showBatteryTemperature"]) showBatteryTemperature = [def boolForKey:@"showBatteryTemperature"];
    if ([def objectForKey:@"showBatteryCurrent"]) showBatteryCurrent = [def boolForKey:@"showBatteryCurrent"];
}

static void SavePreferencesAndNotify() {
    NSUserDefaults *def = [NSUserDefaults standardUserDefaults];
    [def setBool:autoLogoutEnable forKey:@"autoLogoutEnable"];
    [def setDouble:logoutCPUThreshold forKey:@"logoutCPUThreshold"];
    [def setInteger:logoutDuration forKey:@"logoutDuration"];
    
    [def setBool:floatingAlphaEnable forKey:@"floatingAlphaEnable"];
    [def setFloat:floatingAlpha forKey:@"floatingAlpha"];
    [def setFloat:floatingScale forKey:@"floatingScale"];
    [def setFloat:floatingFontSize forKey:@"floatingFontSize"];
    [def setBool:autoWindowSizeEnable forKey:@"autoWindowSizeEnable"];
    
    [def setBool:keyboardAvoidEnable forKey:@"keyboardAvoidEnable"];
    [def setBool:smartDockEnable forKey:@"smartDockEnable"];
    [def setInteger:dockMode forKey:@"dockMode"];
    [def setBool:rememberPositionEnable forKey:@"rememberPositionEnable"];
    
    [def setBool:showBatteryPercent forKey:@"showBatteryPercent"];
    [def setBool:showBatteryTemperature forKey:@"showBatteryTemperature"];
    [def setBool:showBatteryCurrent forKey:@"showBatteryCurrent"];
    [def synchronize];

    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR(kPrefChangedNotification),
        NULL, NULL, YES
    );
}

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

static double getBatteryCurrentInternal() {
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

static BOOL isChargingInternal() {
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

static void applyFloatingAlpha() {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!floatingView) return;
        floatingView.alpha = floatingAlphaEnable ? floatingAlpha : 1.0;
    });
}

static void updateFloatingSize() {
    if (!floatingView) return;

    CGSize targetSize = CGSizeMake(210 * floatingScale, 105 * floatingScale);
    if (!CGSizeEqualToSize(floatingView.bounds.size, targetSize)) {
        CGPoint center = floatingView.center;
        CGRect frame = floatingView.frame;
        frame.size = targetSize;
        floatingView.frame = frame;
        floatingView.center = center;

        if (cpuDragView) cpuDragView.frame = floatingView.frame;
    }
}

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

    CGRect initFrame = CGRectMake(20, 160, 210, 105);
    NSString *savedFrame = [[NSUserDefaults standardUserDefaults] stringForKey:@"SBCPU.LastFrame"];
    if (rememberPositionEnable && savedFrame) {
        CGRect parsed = CGRectFromString(savedFrame);
        if (!CGRectIsEmpty(parsed)) initFrame = parsed;
    }

    floatingView = [[SBCPUFloatingView alloc] initWithFrame:initFrame];

    cpuDragView = [[SBCPUDragView alloc] initWithFrame:floatingView.frame];
    cpuDragView.backgroundColor = UIColor.clearColor;
    cpuDragView.userInteractionEnabled = YES;
    cpuDragView.multipleTouchEnabled = NO;

    [cpuWindow.rootViewController.view addSubview:floatingView];
    [cpuWindow.rootViewController.view addSubview:cpuDragView];

    UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:[SBCPUAction class] action:@selector(doubleTapAction)];
    doubleTap.numberOfTapsRequired = 2;
    [cpuDragView addGestureRecognizer:doubleTap];

    applyFloatingAlpha();
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

static void updateCPU() {
    double cpu = getCPUUsage();
    checkHighCPU(cpu);

    dispatch_async(dispatch_get_main_queue(), ^{
        if (!floatingView) return;

        [UIDevice currentDevice].batteryMonitoringEnabled = YES;
        NSInteger battery = (NSInteger)([UIDevice currentDevice].batteryLevel * 100);
        if (battery < 0) battery = 100;

        double temp = getBatteryTemperatureInternal();
        double current = getBatteryCurrentInternal();
        BOOL charging = isChargingInternal();

        [floatingView updateDataWithCPU:cpu 
                                battery:showBatteryPercent ? battery : 0 
                                   temp:showBatteryTemperature ? temp : 0 
                                current:showBatteryCurrent ? current : 0 
                             isCharging:charging];

        updateFloatingSize();
    });
}

#pragma mark - 5. 各 Pickers 与控制器 Implementation

@implementation SBCPUValuePickerController
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return 7; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return @"CPU 触发值"; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
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
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return 7; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return @"持续时间"; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
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

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 4; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 3; // ⚡ 自动控制
    if (section == 1) return 5; // 🔲 悬浮窗外观
    if (section == 2) return 3; // 🧠 智能选项
    return 4;                   // 📍 位置与显示
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"⚡ 自动控制";
    if (section == 1) return @"🔲 悬浮窗外观";
    if (section == 2) return @"🧠 智能选项";
    return @"📍 位置与显示";
}

- (void)changeScaleSlider:(UISlider *)slider {
    floatingScale = slider.value;
    SavePreferencesAndNotify();
    updateFloatingSize();
    [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:2 inSection:1]] withRowAnimation:UITableViewRowAnimationNone];
}

- (void)changeFontSlider:(UISlider *)slider {
    floatingFontSize = slider.value;
    SavePreferencesAndNotify();
    [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:3 inSection:1]] withRowAnimation:UITableViewRowAnimationNone];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];

    if (indexPath.section == 0) {
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
    } else if (indexPath.section == 1) {
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
        } else if (indexPath.row == 4) {
            cell.textLabel.text = @"自动调整浮窗大小";
            UISwitch *sw = [UISwitch new];
            sw.on = autoWindowSizeEnable;
            [sw addTarget:self action:@selector(changeAutoWindowSize:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
        }
    } else if (indexPath.section == 2) {
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
    } else if (indexPath.section == 3) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"记忆悬浮窗位置";
            UISwitch *sw = [UISwitch new];
            sw.on = rememberPositionEnable;
            [sw addTarget:self action:@selector(changeRememberPosition:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"显示电池百分比";
            UISwitch *sw = [UISwitch new];
            sw.on = showBatteryPercent;
            [sw addTarget:self action:@selector(changeShowBattery:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
        } else if (indexPath.row == 2) {
            cell.textLabel.text = @"显示电池温度";
            UISwitch *sw = [UISwitch new];
            sw.on = showBatteryTemperature;
            [sw addTarget:self action:@selector(changeShowTemp:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
        } else if (indexPath.row == 3) {
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
            SBCPUValuePickerController *vc = [[SBCPUValuePickerController alloc] initWithStyle:UITableViewStyleInsetGrouped];
            [self.navigationController pushViewController:vc animated:YES];
        } else if (indexPath.row == 2) {
            SBCPUTimePickerController *vc = [[SBCPUTimePickerController alloc] initWithStyle:UITableViewStyleInsetGrouped];
            [self.navigationController pushViewController:vc animated:YES];
        }
    } else if (indexPath.section == 1) {
        if (indexPath.row == 1) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"透明度" message:@"选择悬浮窗透明度" preferredStyle:UIAlertControllerStyleActionSheet];
            NSArray *titles = @[@"20%", @"40%", @"60%", @"70%", @"80%", @"100%"];
            NSArray *values = @[@0.2, @0.4, @0.6, @0.7, @0.8, @1.0];

            for (NSInteger i = 0; i < titles.count; i++) {
                [alert addAction:[UIAlertAction actionWithTitle:titles[i] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                    floatingAlpha = [values[i] floatValue];
                    SavePreferencesAndNotify();
                    applyFloatingAlpha();
                    [self.tableView reloadData];
                }]];
            }
            [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
        }
    } else if (indexPath.section == 2) {
        if (indexPath.row == 2) {
            NSArray *modes = @[@"自动", @"左侧", @"右侧", @"顶部", @"底部"];
            dockMode = (dockMode + 1) % modes.count;
            SavePreferencesAndNotify();
            [tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
        }
    }
}

- (void)changeLogout:(UISwitch *)sw { autoLogoutEnable = sw.isOn; SavePreferencesAndNotify(); }
- (void)changeAlphaEnable:(UISwitch *)sw { floatingAlphaEnable = sw.isOn; SavePreferencesAndNotify(); applyFloatingAlpha(); }
- (void)changeAutoWindowSize:(UISwitch *)sw { autoWindowSizeEnable = sw.isOn; SavePreferencesAndNotify(); updateFloatingSize(); }
- (void)changeKeyboardAvoid:(UISwitch *)sw { keyboardAvoidEnable = sw.isOn; SavePreferencesAndNotify(); }
- (void)changeSmartDock:(UISwitch *)sw { smartDockEnable = sw.isOn; SavePreferencesAndNotify(); }
- (void)changeRememberPosition:(UISwitch *)sw { rememberPositionEnable = sw.isOn; SavePreferencesAndNotify(); }
- (void)changeShowBattery:(UISwitch *)sw { showBatteryPercent = sw.isOn; SavePreferencesAndNotify(); }
- (void)changeShowTemp:(UISwitch *)sw { showBatteryTemperature = sw.isOn; SavePreferencesAndNotify(); }
- (void)changeShowCurrent:(UISwitch *)sw { showBatteryCurrent = sw.isOn; SavePreferencesAndNotify(); }

@end

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

static void registerV160Observers() {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;

        [nc addObserverForName:UIDeviceOrientationDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
            if (cpuWindow && floatingView) {
                CGRect f = floatingView.frame;
                CGSize s = cpuWindow.bounds.size;
                if (CGRectGetMaxX(f) > s.width) f.origin.x = s.width - f.size.width - 10;
                if (CGRectGetMaxY(f) > s.height) f.origin.y = s.height - f.size.height - 10;
                if (f.origin.x < 0) f.origin.x = 10;
                if (f.origin.y < 0) f.origin.y = 10;
                floatingView.frame = f;
                if (cpuDragView) cpuDragView.frame = f;
            }
        }];

        // 键盘避让逻辑 (基于中线智能判别)
        [nc addObserverForName:UIKeyboardWillShowNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
            if (settingsShowing || !keyboardAvoidEnable) return;

            if (cpuWindow && floatingView) {
                UIWindowScene *scene = getWindowScene();
                CGRect screenBounds = scene ? scene.coordinateSpace.bounds : UIScreen.mainScreen.bounds;

                CGFloat centerY = CGRectGetMidY(floatingView.frame);
                CGFloat limitY = CGRectGetMidY(screenBounds);

                if (centerY < limitY) return; // 悬浮窗在屏幕上半区，保持不动

                if (!keyboardMoved) {
                    keyboardBeforeFrame = floatingView.frame;
                }

                NSDictionary *info = n.userInfo;
                NSValue *endFrameValue = info[UIKeyboardFrameEndUserInfoKey];
                CGFloat keyboardHeight = 220.0;
                if (endFrameValue) {
                    CGRect keyboardFrame = [endFrameValue CGRectValue];
                    keyboardHeight = MIN(320.0, keyboardFrame.size.height);
                }

                CGRect f = keyboardBeforeFrame;
                f.origin.y = MAX(20.0, f.origin.y - keyboardHeight);

                [UIView animateWithDuration:0.25 animations:^{
                    floatingView.frame = f;
                    if (cpuDragView) cpuDragView.frame = f;
                }];
                keyboardMoved = YES;
            }
        }];

        [nc addObserverForName:UIKeyboardWillHideNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
            if (!settingsShowing && keyboardMoved && floatingView) {
                [UIView animateWithDuration:0.25 animations:^{
                    floatingView.frame = keyboardBeforeFrame;
                    if (cpuDragView) cpuDragView.frame = keyboardBeforeFrame;
                }];
                keyboardMoved = NO;
            }
        }];
    });
}

#pragma mark - 6. Tweak 入口 (%ctor)

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

