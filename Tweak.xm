#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <mach/mach.h>
#import <signal.h>
#import <IOKit/IOKitLib.h>

#ifndef kIOMainPortDefault
#define kIOMainPortDefault kIOMasterPortDefault
#endif

#pragma mark - 全局变量声明
static UIWindow *cpuWindow;
@class SBCPUDragView;

static UILabel *label;
static UIVisualEffectView *blurEffectView;
static SBCPUDragView *cpuDragView;

static CGFloat floatingScale = 1.0;
static CGFloat floatingFontSize = 14.0;
static CGFloat landscapeScale = 0.75;
static CGFloat batteryFontSize = 12.0;
static CGFloat landscapeFontSize = 12.0;

// SmartCharge 全局参数
static BOOL sbcpuSmartChargeEnable = YES;
static NSInteger sbcpuChargeTempFast = 35;
static NSInteger sbcpuChargeTempReduce = 38;
static NSInteger sbcpuChargeTempPause = 40;
static NSInteger sbcpuChargeTempStop = 42;

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

// 布局控制配置
static BOOL smartLayoutEnable = YES;
static BOOL autoWindowSizeEnable = NO;
static BOOL showBatteryPercent = YES;
static BOOL showBatteryTemperature = YES;
static BOOL showBatteryCurrent = YES;
static BOOL keyboardAvoidEnable = YES;
static BOOL hideControlCenterEnable = YES;

static CGRect lastFloatingFrame;
static CGRect lastUserFrame;
static BOOL keyboardShowing = NO;
static CGRect keyboardBeforeFrame = CGRectZero;
static BOOL keyboardMoved = NO;

static NSInteger dockSide = 0;
static BOOL smartDockEnable = YES;
static NSInteger dockMode = 0; // 0自动 1左 2右 3上 4下
static BOOL rememberPositionEnable = YES;

// 前置函数声明
static void openSettings(void);
static void checkHighCPU(double cpu);
static void applySmartLayout(void);
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

#pragma mark - 精准 SpringBoard 单进程 CPU 占用率计算 (mach_task_self)
static double getCPUUsage() {
    thread_array_t threads;
    mach_msg_type_number_t count = 0;

    // 仅计算当前 SpringBoard 进程的 Task 线程
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
        if (!label) return;
        label.alpha = floatingAlphaEnable ? floatingAlpha : 1.0;
        if (blurEffectView) {
            blurEffectView.alpha = floatingAlphaEnable ? floatingAlpha : 1.0;
        }
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

    if ([view isDescendantOfView:label]) return view;

    UIView *root = self.rootViewController.view;
    if (root) {
        for (UIView *subview in root.subviews) {
            if (subview != label && [subview isKindOfClass:NSClassFromString(@"SBCPUDragView")]) {
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

    CGPoint center = label.center;
    center.x += dx;
    center.y += dy;

    CGSize size = self.superview.bounds.size;
    CGFloat halfW = label.bounds.size.width / 2.0;
    CGFloat halfH = label.bounds.size.height / 2.0;

    if (center.x < halfW) center.x = halfW;
    if (center.x > size.width - halfW) center.x = size.width - halfW;
    if (center.y < halfH + 40) center.y = halfH + 40;
    if (center.y > size.height - halfH) center.y = size.height - halfH;

    label.center = center;
    self.center = center;
    self.lastPoint = now;

    [super touchesMoved:touches withEvent:event];
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    [super touchesEnded:touches withEvent:event];
    if (!label) return;

    if (!smartDockEnable) {
        dockSide = 0;
        if (rememberPositionEnable) {
            [[NSUserDefaults standardUserDefaults] setObject:NSStringFromCGRect(label.frame) forKey:@"SBCPU.LastFrame"];
            [[NSUserDefaults standardUserDefaults] synchronize];
        }
        return;
    }

    CGSize size = self.superview.bounds.size;
    CGRect frame = label.frame;
    CGFloat left = CGRectGetMinX(frame);
    CGFloat right = size.width - CGRectGetMaxX(frame);
    CGFloat top = CGRectGetMinY(frame);
    CGFloat bottom = size.height - CGRectGetMaxY(frame);

    CGFloat minDistance = MIN(MIN(left, right), MIN(top, bottom));
    CGPoint center = label.center;

    if (dockMode > 0) {
        if (dockMode == 1) { center.x = label.bounds.size.width / 2.0 + 10; dockSide = 1; }
        else if (dockMode == 2) { center.x = size.width - label.bounds.size.width / 2.0 - 10; dockSide = 2; }
        else if (dockMode == 3) { center.y = label.bounds.size.height / 2.0 + 10; dockSide = 3; }
        else if (dockMode == 4) { center.y = size.height - label.bounds.size.height / 2.0 - 10; dockSide = 4; }
    } else if (minDistance == left) { center.x = label.bounds.size.width / 2.0 + 10; dockSide = 1; }
    else if (minDistance == right) { center.x = size.width - label.bounds.size.width / 2.0 - 10; dockSide = 2; }
    else if (minDistance == top) { center.y = label.bounds.size.height / 2.0 + 10; dockSide = 3; }
    else if (minDistance == bottom) { center.y = size.height - label.bounds.size.height / 2.0 - 10; dockSide = 4; }
    else { dockSide = 0; }

    [UIView animateWithDuration:0.25 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        label.center = center;
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

#pragma mark - 创建精致悬浮窗 UI
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

    label = [[UILabel alloc] initWithFrame:CGRectMake(30, 200, 150, 75)];
    label.backgroundColor = UIColor.clearColor; // 父视图背景透明，避免重影虚影
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = 0;
    label.textColor = UIColor.whiteColor;
    label.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightBold];
    label.text = @"SB CPU\n0%";

    // 添加 iOS 极简暗色超薄毛玻璃视图
    UIBlurEffect *blurEffect = nil;
    if (@available(iOS 13.0, *)) {
        blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark];
    } else {
        blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
    }
    blurEffectView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
    blurEffectView.frame = label.bounds;
    blurEffectView.layer.cornerRadius = 14;
    blurEffectView.layer.masksToBounds = YES;
    blurEffectView.layer.borderWidth = 0.5f;
    blurEffectView.layer.borderColor = [UIColor colorWithWhite:1.0f alpha:0.2f].CGColor;
    
    // 阴影与圆角路径严格对齐，彻底清除底层多余虚影
    label.layer.shadowColor = [UIColor blackColor].CGColor;
    label.layer.shadowOpacity = 0.25f;
    label.layer.shadowOffset = CGSizeMake(0, 3);
    label.layer.shadowRadius = 6.0f;
    label.layer.masksToBounds = NO;
    label.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:label.bounds cornerRadius:14].CGPath;

    [label insertSubview:blurEffectView atIndex:0];

    cpuDragView = [[SBCPUDragView alloc] initWithFrame:label.frame];
    cpuDragView.backgroundColor = UIColor.clearColor;
    cpuDragView.userInteractionEnabled = YES;
    cpuDragView.multipleTouchEnabled = NO;

    [cpuWindow.rootViewController.view addSubview:label];
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

static double getBatteryTemperature() {
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

static void updateFloatingSize() {
    if (!label) return;

    BOOL landscape = isLandscapeMode();
    CGFloat scale = landscape ? landscapeScale : floatingScale;
    CGSize targetSize = landscape ? CGSizeMake(135 * scale, 58 * scale) : CGSizeMake(115 * scale, 48 * scale);

    if (!CGSizeEqualToSize(label.bounds.size, targetSize)) {
        CGRect frame = label.frame;
        CGPoint center = label.center;
        frame.size = targetSize;
        label.frame = frame;
        label.center = center;

        if (cpuDragView) cpuDragView.frame = label.frame;
        if (blurEffectView) blurEffectView.frame = label.bounds;

        label.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:label.bounds cornerRadius:14].CGPath;
        [label setNeedsLayout];
    }
}

#pragma mark - 真实智能温控 Engine (IOKit 充电调控)
typedef NS_ENUM(NSInteger, SBCPUSmartChargeState) {
    SBCPUSmartChargeNormal = 0,
    SBCPUSmartChargeReduce,
    SBCPUSmartChargePause,
    SBCPUSmartChargeStop
};

static SBCPUSmartChargeState smartChargeState = SBCPUSmartChargeNormal;

static NSString *smartChargeStateText() {
    switch (smartChargeState) {
        case SBCPUSmartChargeReduce: return @"🟡 降低功率";
        case SBCPUSmartChargePause: return @"🟠 暂停充电";
        case SBCPUSmartChargeStop: return @"🔴 保护断充";
        default: return @"🟢 正常充电";
    }
}

// 设置底层硬件 ChargingEnabled / InhibitCharging 属性
static void setBatteryChargingEnabled(BOOL enable) {
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"));
    if (!service) return;

    CFBooleanRef boolVal = enable ? kCFBooleanTrue : kCFBooleanFalse;
    IORegistryEntrySetCFProperty(service, CFSTR("ChargingEnabled"), boolVal);
    IORegistryEntrySetCFProperty(service, CFSTR("InhibitCharging"), enable ? kCFBooleanFalse : kCFBooleanTrue);
    IOObjectRelease(service);
}

// 设置底层硬件 ChargeCurrentLimit 电流限制 (mA)
static void setBatteryChargeCurrentLimit(int limitmA) {
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"));
    if (!service) return;

    CFNumberRef numVal = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &limitmA);
    if (numVal) {
        IORegistryEntrySetCFProperty(service, CFSTR("ChargeCurrentLimit"), numVal);
        IORegistryEntrySetCFProperty(service, CFSTR("CurrentLimit"), numVal);
        CFRelease(numVal);
    }
    IOObjectRelease(service);
}

static void updateSmartChargeState(double temperature) {
    if (!sbcpuSmartChargeEnable || temperature <= 0 || !isCharging()) {
        if (smartChargeState != SBCPUSmartChargeNormal) {
            setBatteryChargingEnabled(YES);
            setBatteryChargeCurrentLimit(3000); // 恢复全速充电
        }
        smartChargeState = SBCPUSmartChargeNormal;
        return;
    }

    if (temperature >= sbcpuChargeTempStop) {
        setBatteryChargingEnabled(NO);
        setBatteryChargeCurrentLimit(0);
        smartChargeState = SBCPUSmartChargeStop;
    } else if (temperature >= sbcpuChargeTempPause) {
        setBatteryChargingEnabled(NO);
        setBatteryChargeCurrentLimit(0);
        smartChargeState = SBCPUSmartChargePause;
    } else if (temperature >= sbcpuChargeTempReduce) {
        setBatteryChargingEnabled(YES);
        setBatteryChargeCurrentLimit(500); // 限制 500mA 低功率充电
        smartChargeState = SBCPUSmartChargeReduce;
    } else if (temperature <= sbcpuChargeTempFast) {
        setBatteryChargingEnabled(YES);
        setBatteryChargeCurrentLimit(3000);
        smartChargeState = SBCPUSmartChargeNormal;
    }
}

#pragma mark - CPU 与数据定时刷新
static void updateCPU() {
    double cpu = getCPUUsage(); // 只针对 SpringBoard 进程计算
    checkHighCPU(cpu);

    dispatch_async(dispatch_get_main_queue(), ^{
        if (!label) return;
        updateFloatingSize();

        label.font = [UIFont systemFontOfSize:(isLandscapeMode() ? landscapeFontSize : floatingFontSize)];

        NSInteger battery = getBatteryPercent();
        double temp = getBatteryTemperature();
        double current = getBatteryCurrent();
        BOOL charging = isCharging();

        updateSmartChargeState(temp);

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
    });
}

#pragma mark - CPU 触发值 Picker 控制器 (Fix 点击保存打勾)
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

#pragma mark - 持续时间 Picker 控制器 (Fix 点击保存打勾)
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
        [cpuWindow setNeedsLayout];
    }];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return 18; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return @"自动注销 / 悬浮窗 / 智能温控"; }

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
    } else if (indexPath.row == 5) {
        cell.textLabel.text = @"智能吸附";
        UISwitch *sw = [[UISwitch alloc] init];
        sw.on = smartDockEnable;
        [sw addTarget:self action:@selector(changeSmartDock:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
    } else if (indexPath.row == 6) {
        cell.textLabel.text = @"显示电池百分比";
        UISwitch *sw = [[UISwitch alloc] init];
        sw.on = showBatteryPercent;
        [sw addTarget:self action:@selector(changeShowBattery:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
    } else if (indexPath.row == 7) {
        cell.textLabel.text = @"显示电池温度";
        UISwitch *sw = [[UISwitch alloc] init];
        sw.on = showBatteryTemperature;
        [sw addTarget:self action:@selector(changeShowTemperature:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
    } else if (indexPath.row == 8) {
        cell.textLabel.text = @"显示实时电流";
        UISwitch *sw = [[UISwitch alloc] init];
        sw.on = showBatteryCurrent;
        [sw addTarget:self action:@selector(changeShowCurrent:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
    } else if (indexPath.row == 9) {
        cell.textLabel.text = @"智能温控";
        UISwitch *sw = [[UISwitch alloc] init];
        sw.on = sbcpuSmartChargeEnable;
        [sw addTarget:self action:@selector(changeSmartCharge:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
    } else if (indexPath.row >= 10 && indexPath.row <= 13) {
        NSArray *chargeTitles = @[@"保持快充温度", @"降低功率温度", @"暂停充电温度", @"断充保护温度"];
        NSArray *chargeValues = @[@(sbcpuChargeTempFast), @(sbcpuChargeTempReduce), @(sbcpuChargeTempPause), @(sbcpuChargeTempStop)];
        NSInteger i = indexPath.row - 10;
        cell.textLabel.text = chargeTitles[i];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%ld℃", (long)[chargeValues[i] integerValue]];
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.row == 1) {
        SBCPUValuePickerController *vc = [[SBCPUValuePickerController alloc] initWithStyle:UITableViewStyleInsetGrouped];
        [self.navigationController pushViewController:vc animated:YES];
    } else if (indexPath.row == 2) {
        SBCPUTimePickerController *vc = [[SBCPUTimePickerController alloc] initWithStyle:UITableViewStyleInsetGrouped];
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
    [[NSUserDefaults standardUserDefaults] setBool:sbcpuSmartChargeEnable forKey:@"SBCPU.SmartCharge"];
    [[NSUserDefaults standardUserDefaults] synchronize];
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
    keyboardShowing = NO;

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
            if (cpuWindow && label) {
                CGRect f = label.frame;
                CGSize s = cpuWindow.bounds.size;
                if (CGRectGetMaxX(f) > s.width) f.origin.x = s.width - f.size.width - 10;
                if (CGRectGetMaxY(f) > s.height) f.origin.y = s.height - f.size.height - 10;
                if (f.origin.x < 0) f.origin.x = 10;
                if (f.origin.y < 0) f.origin.y = 10;
                label.frame = f;
                cpuDragView.frame = f;
                lastFloatingFrame = f;
            }
        }];
    });
}

#pragma mark - Tweak 入口
%ctor {
    NSString *process = NSProcessInfo.processInfo.processName;
    if (![process isEqualToString:@"SpringBoard"]) return;

    NSUserDefaults *def = NSUserDefaults.standardUserDefaults;
    autoLogoutEnable = [def boolForKey:@"SBCPU.AutoLogout"];
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

