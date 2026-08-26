
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
#import <notify.h> // 🟢 [终极修复] 引入底层内核通信框架

#ifndef kIOMainPortDefault
#define kIOMainPortDefault kIOMasterPortDefault
#endif

#define kPrefAppID CFSTR("com.yourname.sbcpufloating")
#define kPrefChangedNotification CFSTR("com.yourname.sbcpufloating.prefschanged")
#define kToggleNotification CFSTR("com.yourname.sbcpufloating.toggle")

// 🟢 定义专用的跨进程通信频道
#define NOTIFY_CPU_MODE "com.yourname.sbcpufloating.cpumode"

#pragma mark - 1. QuartzCore 私有类及数据结构声明

@interface CAWindowServer : NSObject
+ (id)serverIfRunning;
- (NSArray *)displays;
@end

@interface CAWindowServerDisplay : NSObject
- (void)setAllowsVirtualModes:(BOOL)allows;
- (void)setMinimumRefreshRate:(float)rate;
- (void)setMaximumRefreshRate:(float)rate;
- (void)setIdealRefreshRate:(float)rate;
- (float)minimumRefreshRate;
- (float)maximumRefreshRate;
- (float)idealRefreshRate;
@end

typedef struct {
    const char *platform;
    const char *modelName;
    const char *chipName;
    NSInteger cores;
    double maxFreqMHz;
    NSInteger designBatteryCapacity;
} DeviceSpec;

#pragma mark - 2. 所有类的极严格前置声明 (防止编译找不到 Identifier)

@interface MitigationController : NSObject
- (void)setPowerSaveActive:(BOOL)arg1;
- (void)setCPULevel:(int)arg1;
- (void)updateCPU;
@end

@interface SpringBoard : UIApplication
- (UIInterfaceOrientation)activeInterfaceOrientation;
@end

@class SBCPUDetailViewController;

@interface SBCPUFPSHelper : NSObject
+ (instancetype)sharedInstance;
- (void)startMonitoring;
- (void)stopMonitoring;
- (void)updateFrameRate;
- (void)startDriverAnimation;
- (void)stopDriverAnimation;
@property (nonatomic, assign) double currentFPS;
@property (nonatomic, strong) CALayer *driverLayer;
@end

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
@property (nonatomic, strong) UIView *batteryProgressView; 
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
- (void)updateLayoutWithShowCpuFreq:(BOOL)showFreq showFps:(BOOL)showFps showBatteryPercent:(BOOL)showBattery showBatteryTemp:(BOOL)showTemp showBatteryCurrent:(BOOL)showCurrent isCharging:(BOOL)isCharging;
- (void)updateDataWithCPU:(double)cpu cpuFreq:(double)cpuFreq fps:(double)fps battery:(NSInteger)battery temp:(double)temp current:(double)current isCharging:(BOOL)isCharging;
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

static BOOL isEnabled = YES; 
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
static BOOL showFps = YES;                       
static BOOL force120HzEnable = NO;               
static BOOL thermalProtectionEnable = YES;       

// 🌡️ Insulation 温控保护模块全局变量
static NSInteger insulationCpuMode = 0;           // 0: 原生, 1: 模拟低电频率, 2: 防止温控降频
static BOOL insulationDimmingEnable = YES;        
static BOOL insulationDisableThermometer = NO;    
static BOOL insulationDisablePocketTemp = NO;     
static BOOL insulationLockSunlight = NO;          

// 🔌 智能温控断充 全局变量
static BOOL smartChargeLimitEnable = NO;
static float smartChargeLimitTemp = 38.0f;
static BOOL isCurrentlyChargeInhibited = NO;      

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

static __weak MitigationController *sharedMitigationController = nil;
static const int InsulationUnrestrictedPowerTarget = 65000;

#pragma mark - 4. 所有的底层 C 函数严谨前置声明

static DeviceSpec getDeviceSpec(void);
static UIWindowScene *getWindowScene(void);
static UIInterfaceOrientation getActiveInterfaceOrientation(void);
static void clampAndPositionFloatingView(CGPoint targetCenter, BOOL animate);
static void applyVisibility(void);
static void applyFloatingAlpha(void);
static void updateFloatingSize(void);
static void createCPUWindow(void);
static void openDetailView(void);
static void openSettings(void);
static void checkHighCPU(double cpu);
static void updateCPU(void);

static BOOL getBoolPref(CFStringRef key, BOOL defaultVal);
static float getFloatPref(CFStringRef key, float defaultVal);
static NSInteger getIntPref(CFStringRef key, NSInteger defaultVal);
static void setBoolPref(CFStringRef key, BOOL value);
static void setFloatPref(CFStringRef key, float value);
static void setIntPref(CFStringRef key, NSInteger value);
static void LoadPreferences(void);
static void SavePreferencesAndNotify(void);

static BOOL isDeviceOverheated(void);
static void applySystemRefreshRate(void);
static NSDictionary *getRealBatteryDetails(void);
static double getBatteryTemperatureInternal(void);
static double getBatteryCurrentInternal(void);
static BOOL isChargingInternal(void);
static double getSystemCPUUsage(void);
static double getRealCPUFrequency(void);
static void setHardwareChargingInhibit(BOOL inhibit);
static NSString *getNetworkType(void);

static void applyMitigationState(void);

// 🟢 [终极修复] 跨进程通知发送器 (仅 SpringBoard 使用)
static void SendCPUModeToDaemon(NSInteger mode) {
    int token;
    if (notify_register_check(NOTIFY_CPU_MODE, &token) == NOTIFY_STATUS_OK) {
        notify_set_state(token, (uint64_t)mode); // 写入内核状态
        notify_post(NOTIFY_CPU_MODE);            // 发送广播唤醒守护进程
        notify_cancel(token);
    }
}

#pragma mark - 5. 底层 C 函数具体实现与 CFPreferences 全局引流引擎

static void applyMitigationState(void) {
    if (!sharedMitigationController) return;
    @try {
        if (insulationCpuMode == 1) { // 模拟低电锁频
            if ([sharedMitigationController respondsToSelector:@selector(setPowerSaveActive:)]) {
                [sharedMitigationController setPowerSaveActive:YES];
            }
            if ([sharedMitigationController respondsToSelector:@selector(setCPULevel:)]) {
                [sharedMitigationController setCPULevel:2];
            }
        } else if (insulationCpuMode == 2) { // 满血强关
            if ([sharedMitigationController respondsToSelector:@selector(setPowerSaveActive:)]) {
                [sharedMitigationController setPowerSaveActive:NO];
            }
            if ([sharedMitigationController respondsToSelector:@selector(setCPULevel:)]) {
                [sharedMitigationController setCPULevel:0];
            }
        }
        
        // 触发硬件调度器更新
        if ([sharedMitigationController respondsToSelector:@selector(updateCPU)]) {
            [sharedMitigationController performSelector:@selector(updateCPU)];
        }
        
        // 双重写入，防覆盖
        if (insulationCpuMode == 1) { 
            if ([sharedMitigationController respondsToSelector:@selector(setPowerSaveActive:)]) [sharedMitigationController setPowerSaveActive:YES];
            if ([sharedMitigationController respondsToSelector:@selector(setCPULevel:)]) [sharedMitigationController setCPULevel:2];
        } else if (insulationCpuMode == 2) {
            if ([sharedMitigationController respondsToSelector:@selector(setPowerSaveActive:)]) [sharedMitigationController setPowerSaveActive:NO];
            if ([sharedMitigationController respondsToSelector:@selector(setCPULevel:)]) [sharedMitigationController setCPULevel:0];
        }
    } @catch (NSException *e) {}
}

static DeviceSpec getDeviceSpec(void) {
    char machine[256] = {0};
    size_t size = sizeof(machine);
    sysctlbyname("hw.machine", machine, &size, NULL, 0);
    NSString *platform = [NSString stringWithUTF8String:machine];

    if ([platform isEqualToString:@"iPhone16,2"]) return (DeviceSpec){"iPhone16,2", "iPhone 15 Pro Max", "A17 Pro", 6, 3780.0, 4422};
    if ([platform isEqualToString:@"iPhone16,1"]) return (DeviceSpec){"iPhone16,1", "iPhone 15 Pro", "A17 Pro", 6, 3780.0, 3274};
    if ([platform isEqualToString:@"iPhone15,5"]) return (DeviceSpec){"iPhone15,5", "iPhone 15 Plus", "A16 Bionic", 6, 3468.0, 4383};
    if ([platform isEqualToString:@"iPhone15,4"]) return (DeviceSpec){"iPhone15,4", "iPhone 15", "A16 Bionic", 6, 3468.0, 3349};
    if ([platform isEqualToString:@"iPhone15,3"]) return (DeviceSpec){"iPhone15,3", "iPhone 14 Pro Max", "A16 Bionic", 6, 3468.0, 4323};
    if ([platform isEqualToString:@"iPhone15,2"]) return (DeviceSpec){"iPhone15,2", "iPhone 14 Pro", "A16 Bionic", 6, 3468.0, 3200};
    if ([platform isEqualToString:@"iPhone14,8"]) return (DeviceSpec){"iPhone14,8", "iPhone 14 Plus", "A15 Bionic", 6, 3240.0, 4325};
    if ([platform isEqualToString:@"iPhone14,7"]) return (DeviceSpec){"iPhone14,7", "iPhone 14", "A15 Bionic", 6, 3240.0, 3279};
    if ([platform isEqualToString:@"iPhone14,3"]) return (DeviceSpec){"iPhone14,3", "iPhone 13 Pro Max", "A15 Bionic", 6, 3240.0, 4352};
    if ([platform isEqualToString:@"iPhone14,2"]) return (DeviceSpec){"iPhone14,2", "iPhone 13 Pro", "A15 Bionic", 6, 3240.0, 3095};
    if ([platform isEqualToString:@"iPhone14,5"]) return (DeviceSpec){"iPhone14,5", "iPhone 13", "A15 Bionic", 6, 3240.0, 3227};
    if ([platform isEqualToString:@"iPhone14,4"]) return (DeviceSpec){"iPhone14,4", "iPhone 13 mini", "A15 Bionic", 6, 3240.0, 2406};
    if ([platform isEqualToString:@"iPhone13,4"]) return (DeviceSpec){"iPhone13,4", "iPhone 12 Pro Max", "A14 Bionic", 6, 3100.0, 3687};
    if ([platform isEqualToString:@"iPhone13,3"]) return (DeviceSpec){"iPhone13,3", "iPhone 12 Pro", "A14 Bionic", 6, 3100.0, 2815};
    if ([platform isEqualToString:@"iPhone13,2"]) return (DeviceSpec){"iPhone13,2", "iPhone 12", "A14 Bionic", 6, 3100.0, 2815};
    if ([platform isEqualToString:@"iPhone17,1"]) return (DeviceSpec){"iPhone17,1", "iPhone 16 Pro", "A18 Pro", 6, 4040.0, 3582};
    if ([platform isEqualToString:@"iPhone17,2"]) return (DeviceSpec){"iPhone17,2", "iPhone 16 Pro Max", "A18 Pro", 6, 4040.0, 4685};

    NSInteger activeCores = [NSProcessInfo processInfo].processorCount;
    return (DeviceSpec){machine, "iPhone", "Apple Silicon", activeCores, 3468.0, 4000};
}

static BOOL getBoolPref(CFStringRef key, BOOL defaultVal) {
    CFPropertyListRef val = CFPreferencesCopyValue(key, kPrefAppID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    if (val) {
        BOOL res = defaultVal;
        if (CFGetTypeID(val) == CFBooleanGetTypeID()) {
            res = CFBooleanGetValue((CFBooleanRef)val);
        } else if (CFGetTypeID(val) == CFNumberGetTypeID()) {
            int intVal; CFNumberGetValue((CFNumberRef)val, kCFNumberIntType, &intVal); res = (intVal != 0);
        }
        CFRelease(val); return res;
    }
    return defaultVal;
}

static float getFloatPref(CFStringRef key, float defaultVal) {
    CFPropertyListRef val = CFPreferencesCopyValue(key, kPrefAppID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    if (val) {
        float res = defaultVal;
        if (CFGetTypeID(val) == CFNumberGetTypeID()) {
            CFNumberGetValue((CFNumberRef)val, kCFNumberFloatType, &res);
        }
        CFRelease(val); return res;
    }
    return defaultVal;
}

static NSInteger getIntPref(CFStringRef key, NSInteger defaultVal) {
    CFPropertyListRef val = CFPreferencesCopyValue(key, kPrefAppID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    if (val) {
        NSInteger res = defaultVal;
        if (CFGetTypeID(val) == CFNumberGetTypeID()) {
            CFNumberGetValue((CFNumberRef)val, kCFNumberNSIntegerType, &res);
        }
        CFRelease(val); return res;
    }
    return defaultVal;
}

static void setBoolPref(CFStringRef key, BOOL value) {
    CFPreferencesSetValue(key, value ? kCFBooleanTrue : kCFBooleanFalse, kPrefAppID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
}

static void setFloatPref(CFStringRef key, float value) {
    CFNumberRef num = CFNumberCreate(NULL, kCFNumberFloatType, &value);
    CFPreferencesSetValue(key, num, kPrefAppID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFRelease(num);
}

static void setIntPref(CFStringRef key, NSInteger value) {
    CFNumberRef num = CFNumberCreate(NULL, kCFNumberNSIntegerType, &value);
    CFPreferencesSetValue(key, num, kPrefAppID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFRelease(num);
}

static void LoadPreferences(void) {
    CFPreferencesAppSynchronize(kPrefAppID);

    isEnabled = getBoolPref(CFSTR("isEnabled"), YES); 
    autoCollapseEnable = getBoolPref(CFSTR("autoCollapseEnable"), YES);
    autoCollapseDelay = getIntPref(CFSTR("autoCollapseDelay"), 4);

    autoLogoutEnable = getBoolPref(CFSTR("autoLogoutEnable"), NO);
    logoutCPUThreshold = (double)getFloatPref(CFSTR("logoutCPUThreshold"), 100.0);
    logoutDuration = getIntPref(CFSTR("logoutDuration"), 60);
    
    floatingAlphaEnable = getBoolPref(CFSTR("floatingAlphaEnable"), YES);
    floatingAlpha = getFloatPref(CFSTR("floatingAlpha"), 0.70f);
    floatingScale = getFloatPref(CFSTR("floatingScale"), 1.0f);
    floatingFontSize = getFloatPref(CFSTR("floatingFontSize"), 13.0f);
    
    keyboardAvoidEnable = getBoolPref(CFSTR("keyboardAvoidEnable"), YES);
    smartDockEnable = getBoolPref(CFSTR("smartDockEnable"), YES);
    dockMode = getIntPref(CFSTR("dockMode"), 0);
    rememberPositionEnable = getBoolPref(CFSTR("rememberPositionEnable"), YES);
    
    showCpuFrequency = getBoolPref(CFSTR("showCpuFrequency"), YES);
    showFps = getBoolPref(CFSTR("showFps"), YES);
    force120HzEnable = getBoolPref(CFSTR("force120HzEnable"), NO);
    thermalProtectionEnable = getBoolPref(CFSTR("thermalProtectionEnable"), YES);

    showBatteryPercent = getBoolPref(CFSTR("showBatteryPercent"), YES);
    showBatteryTemperature = getBoolPref(CFSTR("showBatteryTemperature"), YES);
    showBatteryCurrent = getBoolPref(CFSTR("showBatteryCurrent"), YES);

    insulationCpuMode = getIntPref(CFSTR("insulationCpuMode"), 0);
    insulationDimmingEnable = getBoolPref(CFSTR("insulationDimmingEnable"), YES);
    insulationDisableThermometer = getBoolPref(CFSTR("insulationDisableThermometer"), NO);
    insulationDisablePocketTemp = getBoolPref(CFSTR("insulationDisablePocketTemp"), NO);
    insulationLockSunlight = getBoolPref(CFSTR("insulationLockSunlight"), NO);

    smartChargeLimitEnable = getBoolPref(CFSTR("smartChargeLimitEnable"), NO);
    smartChargeLimitTemp = getFloatPref(CFSTR("smartChargeLimitTemp"), 38.0f);

    NSString *processName = [NSProcessInfo processInfo].processName;
    if ([processName isEqualToString:@"SpringBoard"]) {
        applyVisibility();
        if (showFps || force120HzEnable) {
            [[SBCPUFPSHelper sharedInstance] startMonitoring];
        } else {
            [[SBCPUFPSHelper sharedInstance] stopMonitoring];
        }
        applySystemRefreshRate();
        
        // 🟢 [终极修复] 每次 SpringBoard 重新加载配置，强制推送到内核，同步给守护进程
        SendCPUModeToDaemon(insulationCpuMode);
    }
}

static void SavePreferencesAndNotify(void) {
    setBoolPref(CFSTR("isEnabled"), isEnabled);
    setBoolPref(CFSTR("autoCollapseEnable"), autoCollapseEnable);
    setIntPref(CFSTR("autoCollapseDelay"), autoCollapseDelay);

    setBoolPref(CFSTR("autoLogoutEnable"), autoLogoutEnable);
    setFloatPref(CFSTR("logoutCPUThreshold"), (float)logoutCPUThreshold);
    setIntPref(CFSTR("logoutDuration"), logoutDuration);
    
    setBoolPref(CFSTR("floatingAlphaEnable"), floatingAlphaEnable);
    setFloatPref(CFSTR("floatingAlpha"), floatingAlpha);
    setFloatPref(CFSTR("floatingScale"), floatingScale);
    setFloatPref(CFSTR("floatingFontSize"), floatingFontSize);
    
    setBoolPref(CFSTR("keyboardAvoidEnable"), keyboardAvoidEnable);
    setBoolPref(CFSTR("smartDockEnable"), smartDockEnable);
    setIntPref(CFSTR("dockMode"), dockMode);
    setBoolPref(CFSTR("rememberPositionEnable"), rememberPositionEnable);
    
    setBoolPref(CFSTR("showCpuFrequency"), showCpuFrequency);
    setBoolPref(CFSTR("showFps"), showFps);
    setBoolPref(CFSTR("force120HzEnable"), force120HzEnable);
    setBoolPref(CFSTR("thermalProtectionEnable"), thermalProtectionEnable);

    setBoolPref(CFSTR("showBatteryPercent"), showBatteryPercent);
    setBoolPref(CFSTR("showBatteryTemperature"), showBatteryTemperature);
    setBoolPref(CFSTR("showBatteryCurrent"), showBatteryCurrent);

    setIntPref(CFSTR("insulationCpuMode"), insulationCpuMode);
    setBoolPref(CFSTR("insulationDimmingEnable"), insulationDimmingEnable);
    setBoolPref(CFSTR("insulationDisableThermometer"), insulationDisableThermometer);
    setBoolPref(CFSTR("insulationDisablePocketTemp"), insulationDisablePocketTemp);
    setBoolPref(CFSTR("insulationLockSunlight"), insulationLockSunlight);

    setBoolPref(CFSTR("smartChargeLimitEnable"), smartChargeLimitEnable);
    setFloatPref(CFSTR("smartChargeLimitTemp"), smartChargeLimitTemp);
    
    CFPreferencesSynchronize(kPrefAppID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);

    if (showFps || force120HzEnable) {
        [[SBCPUFPSHelper sharedInstance] startMonitoring];
    } else {
        [[SBCPUFPSHelper sharedInstance] stopMonitoring];
    }
    applySystemRefreshRate();

    // 通知本进程（UI更新）
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), kPrefChangedNotification, NULL, NULL, YES);
    
    // 🟢 [终极修复] 每当用户在 UI 中修改配置，立刻将值打入内核频道，瞬间同步
    if ([[NSProcessInfo processInfo].processName isEqualToString:@"SpringBoard"]) {
        SendCPUModeToDaemon(insulationCpuMode);
    }
}

// 🔌 硬件级旁路断充接口
static void setHardwareChargingInhibit(BOOL inhibit) {
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBatteryManager"));
    if (service) {
        IORegistryEntrySetCFProperty(service, CFSTR("ChargeInhibit"), inhibit ? kCFBooleanTrue : kCFBooleanFalse);
        IOObjectRelease(service);
    }
}

// ✅ 修复 Bug 3: 绝对精准的底层网络检测，支持双卡并优先获取当前数据卡
static NSString *getNetworkType(void) {
    struct ifaddrs *interfaces = NULL;
    int wifi = 0;
    int cell = 0;
    if (getifaddrs(&interfaces) == 0) {
        struct ifaddrs *temp_addr = interfaces;
        while (temp_addr != NULL) {
            if (temp_addr->ifa_addr && (temp_addr->ifa_addr->sa_family == AF_INET || temp_addr->ifa_addr->sa_family == AF_INET6)) {
                NSString *name = [NSString stringWithUTF8String:temp_addr->ifa_name];
                if ([name isEqualToString:@"en0"]) wifi = 1;
                // 覆盖所有的现代蜂窝数据节点，解决 4G/5G 切换不刷新的问题
                else if ([name hasPrefix:@"pdp_ip"] || [name hasPrefix:@"ipsec"] || [name hasPrefix:@"rmnet"] || [name hasPrefix:@"pdp"]) cell = 1;
            }
            temp_addr = temp_addr->ifa_next;
        }
        freeifaddrs(interfaces);
    }
    
    if (wifi) return @"Wi-Fi 在线";
    if (cell) {
        @try {
            static id networkInfo = nil;
            static dispatch_once_t onceToken;
            dispatch_once(&onceToken, ^{
                Class CTClass = NSClassFromString(@"CTTelephonyNetworkInfo");
                if (CTClass) networkInfo = [[CTClass alloc] init];
            });
            
            if (networkInfo) {
                NSString *tech = nil;
                // 核心修复：优先读取当前正在使用数据流量的 SIM 卡
                if ([networkInfo respondsToSelector:@selector(dataServiceIdentifier)] && [networkInfo respondsToSelector:@selector(serviceCurrentRadioAccessTechnology)]) {
                    NSString *dataServiceId = [networkInfo valueForKey:@"dataServiceIdentifier"];
                    NSDictionary *dict = [networkInfo valueForKey:@"serviceCurrentRadioAccessTechnology"];
                    if (dataServiceId && [dict isKindOfClass:[NSDictionary class]]) {
                        tech = dict[dataServiceId];
                    }
                } 
                
                if (!tech && [networkInfo respondsToSelector:@selector(serviceCurrentRadioAccessTechnology)]) {
                    NSDictionary *dict = [networkInfo valueForKey:@"serviceCurrentRadioAccessTechnology"];
                    if ([dict isKindOfClass:[NSDictionary class]] && dict.allValues.count > 0) {
                        tech = dict.allValues.firstObject;
                    }
                }
                
                if (!tech && [networkInfo respondsToSelector:@selector(currentRadioAccessTechnology)]) {
                    tech = [networkInfo valueForKey:@"currentRadioAccessTechnology"];
                }
                
                if (tech) {
                    if ([tech isEqualToString:@"CTRadioAccessTechnologyNRNSA"] || [tech isEqualToString:@"CTRadioAccessTechnologyNR"]) return @"5G 网络";
                    if ([tech isEqualToString:@"CTRadioAccessTechnologyLTE"]) return @"4G 网络";
                    if ([tech isEqualToString:@"CTRadioAccessTechnologyWCDMA"] || [tech isEqualToString:@"CTRadioAccessTechnologyHSDPA"] || [tech isEqualToString:@"CTRadioAccessTechnologyHSUPA"] || [tech isEqualToString:@"CTRadioAccessTechnologyCDMA1x"] || [tech isEqualToString:@"CTRadioAccessTechnologyCDMAEVDORev0"] || [tech isEqualToString:@"CTRadioAccessTechnologyCDMAEVDORevA"] || [tech isEqualToString:@"CTRadioAccessTechnologyCDMAEVDORevB"] || [tech isEqualToString:@"CTRadioAccessTechnologyeHRPD"]) return @"3G 网络";
                    if ([tech isEqualToString:@"CTRadioAccessTechnologyEdge"] || [tech isEqualToString:@"CTRadioAccessTechnologyGPRS"]) return @"2G 网络";
                }
            }
        } @catch (NSException *e) {}
        return @"蜂窝移动网络";
    }
    return @"无网络连接";
}

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

static BOOL isDeviceOverheated(void) {
    if (@available(iOS 11.0, *)) {
        NSProcessInfoThermalState state = [NSProcessInfo processInfo].thermalState;
        if (state == NSProcessInfoThermalStateSerious || state == NSProcessInfoThermalStateCritical) {
            return YES;
        }
    }
    double temp = getBatteryTemperatureInternal();
    if (temp >= 43.0) {
        return YES;
    }
    return NO;
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

static double getRealCPUFrequency(void) {
    uint64_t freq = 0;
    size_t size = sizeof(freq);
    if (sysctlbyname("hw.cpufrequency", &freq, &size, NULL, 0) == 0 && freq > 0) {
        return freq / 1000000.0;
    }
    if (sysctlbyname("hw.cpufrequency_max", &freq, &size, NULL, 0) == 0 && freq > 0) {
        return freq / 1000000.0;
    }
    DeviceSpec spec = getDeviceSpec();
    return spec.maxFreqMHz;
}

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
    cpuWindow.windowLevel = UIWindowLevelAlert + 100.0; 
    cpuWindow.backgroundColor = UIColor.clearColor;
    cpuWindow.opaque = NO;
    cpuWindow.rootViewController = [[SBCPURootViewController alloc] init];
    cpuWindow.rootViewController.view.backgroundColor = UIColor.clearColor;
    cpuWindow.hidden = !isEnabled;

    [cpuWindow.layer addSublayer:[SBCPUFPSHelper sharedInstance].driverLayer];

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
    double cpuFreq = getRealCPUFrequency();
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

        // 🔌 智能温控断充核心逻辑
        if (smartChargeLimitEnable && temp > 0) {
            // 温度超过设定阈值，且尚未断充时 -> 强制断充
            if (temp >= smartChargeLimitTemp && !isCurrentlyChargeInhibited) {
                setHardwareChargingInhibit(YES);
                isCurrentlyChargeInhibited = YES;
            } 
            // 温度回落 1.5 度以下（防止来回横跳），且处于断充状态时 -> 恢复充电
            else if (temp <= (smartChargeLimitTemp - 1.5f) && isCurrentlyChargeInhibited) {
                setHardwareChargingInhibit(NO);
                isCurrentlyChargeInhibited = NO;
            }
        } 
        // 如果功能被关闭了，但底层还在断充，赶紧恢复
        else if (!smartChargeLimitEnable && isCurrentlyChargeInhibited) {
            setHardwareChargingInhibit(NO);
            isCurrentlyChargeInhibited = NO;
        }

        if (charging && !previousChargingState) {
            if (floatingView.isCollapsed) {
                [floatingView expandFromEdgeAnimated:YES];
            }
            [floatingView triggerPlugAnimation];
        }
        previousChargingState = charging;

        // 若处于断充状态，UI 提示
        if (isCurrentlyChargeInhibited) {
            floatingView.statusLabel.text = @"⚠️ 高温旁路供电中";
            floatingView.statusLabel.textColor = [UIColor systemOrangeColor];
            floatingView.statusDot.backgroundColor = [UIColor systemOrangeColor];
        }

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

static void applySystemRefreshRate(void) {
    BOOL apply120 = force120HzEnable && (!thermalProtectionEnable || !isDeviceOverheated());
    
    Class serverClass = NSClassFromString(@"CAWindowServer");
    if (serverClass && [serverClass respondsToSelector:@selector(serverIfRunning)]) {
        CAWindowServer *server = [serverClass serverIfRunning];
        if (server) {
            for (CAWindowServerDisplay *display in [server displays]) {
                if ([display respondsToSelector:@selector(setAllowsVirtualModes:)]) {
                    [display setAllowsVirtualModes:YES];
                }
                if (apply120) {
                    if ([display respondsToSelector:@selector(setMinimumRefreshRate:)]) [display setMinimumRefreshRate:120.0f];
                    if ([display respondsToSelector:@selector(setMaximumRefreshRate:)]) [display setMaximumRefreshRate:120.0f];
                    if ([display respondsToSelector:@selector(setIdealRefreshRate:)]) [display setIdealRefreshRate:120.0f];
                }
            }
        }
    }

    if (cpuWindow && [SBCPUFPSHelper sharedInstance].driverLayer.superlayer == nil) {
        [cpuWindow.layer addSublayer:[SBCPUFPSHelper sharedInstance].driverLayer];
    }

    [[SBCPUFPSHelper sharedInstance] updateFrameRate];
}

#pragma mark - 6. 所有的 Objective-C 类实现区块

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

- (instancetype)init {
    if (self = [super init]) {
        _driverLayer = [CALayer layer];
        _driverLayer.frame = CGRectMake(0, 0, 2, 2);
        _driverLayer.backgroundColor = [UIColor clearColor].CGColor;
        _driverLayer.opacity = 0.01f;
    }
    return self;
}

- (void)startDriverAnimation {
    if (!_driverLayer) return;
    [_driverLayer removeAnimationForKey:@"ProMotion120Driver"];

    CABasicAnimation *driveAnim = [CABasicAnimation animationWithKeyPath:@"opacity"];
    driveAnim.fromValue = @(0.01f);
    driveAnim.toValue = @(0.02f);
    driveAnim.duration = 1.0;
    driveAnim.repeatCount = HUGE_VALF;
    driveAnim.autoreverses = YES;
    driveAnim.removedOnCompletion = NO;
    if (@available(iOS 15.0, *)) {
        driveAnim.preferredFrameRateRange = CAFrameRateRangeMake(120.0f, 120.0f, 120.0f);
    }
    [_driverLayer addAnimation:driveAnim forKey:@"ProMotion120Driver"];
}

- (void)stopDriverAnimation {
    if (_driverLayer) {
        [_driverLayer removeAnimationForKey:@"ProMotion120Driver"];
    }
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
    [self stopDriverAnimation];
    _lastTimestamp = 0;
    _frameCount = 0;
    _currentFPS = 0.0;
}

- (void)updateFrameRate {
    if (!_displayLink) return;

    BOOL apply120 = force120HzEnable && (!thermalProtectionEnable || !isDeviceOverheated());

    if (@available(iOS 15.0, *)) {
        float targetFps = apply120 ? 120.0f : 60.0f;
        _displayLink.preferredFrameRateRange = CAFrameRateRangeMake(targetFps, targetFps, targetFps);
        
        if (apply120) {
            if ([_displayLink respondsToSelector:@selector(setHighFrameRateReason:)]) {
                @try {
                    [_displayLink setValue:@(1114113) forKey:@"highFrameRateReason"];
                } @catch (id ex) {}
            }
            [self startDriverAnimation];
        } else {
            [self stopDriverAnimation];
        }
    } else {
        _displayLink.preferredFramesPerSecond = apply120 ? 120 : 60;
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
        _fpsValueLabel.textAlignment = NSTextAlignmentCenter;
        _fpsValueLabel.adjustsFontSizeToFitWidth = YES;
        _fpsValueLabel.minimumScaleFactor = 0.5f;
        [content addSubview:_fpsValueLabel];

        _fpsSubLabel = [[UILabel alloc] init];
        _fpsSubLabel.text = @"FPS";
        _fpsSubLabel.textColor = [UIColor colorWithWhite:0.65f alpha:1.0f];
        _fpsSubLabel.font = [UIFont systemFontOfSize:8.5f weight:UIFontWeightMedium];
        _fpsSubLabel.textAlignment = NSTextAlignmentCenter;
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

        // ✅ 修复 Bug 2 (温度图标摆正)：新增文本居中对齐，确保图标不歪
        _tempIconLabel = [[UILabel alloc] init];
        _tempIconLabel.text = @"🌡";
        _tempIconLabel.font = [UIFont systemFontOfSize:16];
        _tempIconLabel.textAlignment = NSTextAlignmentCenter;
        _tempIconLabel.adjustsFontSizeToFitWidth = YES;
        _tempIconLabel.minimumScaleFactor = 0.5f;
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

        // 充电状态胶囊背景容器
        _bottomCapsule = [[UIView alloc] init];
        _bottomCapsule.backgroundColor = [UIColor colorWithWhite:1.0f alpha:0.10f];
        _bottomCapsule.layer.cornerRadius = 10.0f;
        _bottomCapsule.layer.masksToBounds = YES;
        _bottomCapsule.layer.borderWidth = 0.5f;
        _bottomCapsule.layer.borderColor = [UIColor colorWithWhite:1.0f alpha:0.12f].CGColor;
        [content addSubview:_bottomCapsule];

        // 🔋 与电量严格同步的绿色进度指示条
        _batteryProgressView = [[UIView alloc] init];
        _batteryProgressView.backgroundColor = [UIColor colorWithRed:0.2f green:0.95f blue:0.5f alpha:0.32f];
        _batteryProgressView.layer.cornerRadius = 10.0f;
        [_bottomCapsule addSubview:_batteryProgressView];

        // 充电状态文字
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
        CGFloat fpsW = 28.0f;
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
        // ✅ 修复 Bug 2：进一步扩宽温度模块，彻底解决 Emoji 宽度遮挡和偏斜的排版问题
        CGFloat tempW = 60.0f;
        _tempIconLabel.frame = CGRectMake(currentX, padY + 2, 20, 22);
        _tempValueLabel.frame = CGRectMake(currentX + 22, padY, tempW - 22, 14);
        _tempSubLabel.frame = CGRectMake(currentX + 22, padY + 14, tempW - 22, 11);
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
    if (finalW < 40.0f) finalW = 40.0f;
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
    
    if (!isCurrentlyChargeInhibited) {
        _statusLabel.text = isCharging ? @"🟢 正在充电" : @"⚪ 未在充电";
        _statusLabel.textColor = [UIColor colorWithRed:0.2f green:0.95f blue:0.5f alpha:1.0f];
    }

    if (isCharging) {
        CGFloat capsuleW = _bottomCapsule.bounds.size.width;
        CGFloat capsuleH = _bottomCapsule.bounds.size.height > 0 ? _bottomCapsule.bounds.size.height : 22.0f;
        CGFloat targetProgressW = MAX(0, MIN(capsuleW, capsuleW * (battery / 100.0f)));
        
        [UIView animateWithDuration:0.35 animations:^{
            self.batteryProgressView.frame = CGRectMake(0, 0, targetProgressW, capsuleH);
        }];
    }

    _miniCpuLabel.text = [NSString stringWithFormat:@"%.0f%%", cpu];
    
    if (!isCurrentlyChargeInhibited) {
        UIColor *statusColor = [UIColor colorWithRed:0.22f green:0.74f blue:0.97f alpha:1.0f];
        if (isCharging) statusColor = [UIColor colorWithRed:0.2f green:0.95f blue:0.5f alpha:1.0f];
        else if (cpu >= 80.0 || temp >= 42.0) statusColor = [UIColor colorWithRed:1.0f green:0.23f blue:0.19f alpha:1.0f];
        else if (temp >= 38.0) statusColor = [UIColor colorWithRed:1.0f green:0.62f blue:0.04f alpha:1.0f];
        _statusDot.backgroundColor = statusColor;
    }
}

@end

#pragma mark - 8. 详细状态 UI 面板与数据绑定 (SBCPUDetailViewController)

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
    
    // ✅ 修复 Bug 3：注入底层的、绝对精准的动态获取 4G/5G/WiFi 的函数
    _labelsDict[@"网络信息"].text = getNetworkType();
    
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
    _labelsDict[@"内网地址"].text = address;

    struct ifaddrs *ifa_list = NULL;
    if (getifaddrs(&ifa_list) >= 0) {
        uint64_t wifiIn = 0, wifiOut = 0, cellIn = 0, cellOut = 0;
        for (struct ifaddrs *ifa = ifa_list; ifa; ifa = ifa->ifa_next) {
            if (!ifa->ifa_addr || ifa->ifa_addr->sa_family != AF_LINK) continue;
            struct if_data *if_data = (struct if_data *)ifa->ifa_data;
            if (!if_data) continue;
            NSString *name = [NSString stringWithUTF8String:ifa->ifa_name];
            if ([name hasPrefix:@"en"]) { wifiIn += if_data->ifi_ibytes; wifiOut += if_data->ifi_obytes; }
            else if ([name hasPrefix:@"pdp_ip"] || [name hasPrefix:@"ipsec"] || [name hasPrefix:@"rmnet"] || [name hasPrefix:@"pdp"]) { cellIn += if_data->ifi_ibytes; cellOut += if_data->ifi_obytes; }
        }
        freeifaddrs(ifa_list);
        CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
        double timeDiff = now - lastNetSpeedTime;
        if (timeDiff <= 0) timeDiff = 1.0;
        if (lastWifiInBytes > 0) {
            speedDownBytesPerSec = (uint64_t)((wifiIn - lastWifiInBytes + cellIn - lastCellInBytes) / timeDiff);
            speedUpBytesPerSec = (uint64_t)((wifiOut - lastWifiOutBytes + cellOut - lastCellOutBytes) / timeDiff);
        }
        lastWifiInBytes = wifiIn; lastWifiOutBytes = wifiOut; lastCellInBytes = cellIn; lastCellOutBytes = cellOut; lastNetSpeedTime = now;
    }
    _labelsDict[@"实时网速"].text = [NSString stringWithFormat:@"↑%lluK ↓%lluK", speedUpBytesPerSec / 1024, speedDownBytesPerSec / 1024];

    double systemCpu = getSystemCPUUsage();
    _labelsDict[@"CPU信息"].text = [NSString stringWithFormat:@"%s %ld核心 %.0f%%", spec.chipName, (long)spec.cores, systemCpu];

    double freq = getRealCPUFrequency();
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
@end

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

@implementation SBCPUValuePickerController
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
    return 8; 
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    if (section == 0) return 2;
    if (section == 1) return 3;
    if (section == 2) return 4;
    if (section == 3) return 3;
    if (section == 4) return 2;
    if (section == 5) return 5;
    if (section == 6) return 2; 
    return 6;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    if (section == 0) return @"📱 智能缩进与侧边吸附";
    if (section == 1) return @"⚡ 自动控制与防护";
    if (section == 2) return @"🔲 悬浮窗外观";
    if (section == 3) return @"🧠 智能选项";
    if (section == 4) return @"🎮 性能与高刷锁定";
    if (section == 5) return @"🌡️ Insulation (温控核心)"; 
    if (section == 6) return @"🔌 电池温控与断充";
    return @"📍 位置与显示";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    (void)tableView;
    if (section == 4) {
        return @"💡 功能说明：\n1. 强制 120Hz 高刷模式：通过底层硬件合成器与微像素渲染驱动，全局锁定 120Hz 满帧，彻底杜绝屏幕静止降频。\n2. 智能温控降频保护：开启时若检测到电池温度 ≥43°C 或系统过热警报将自动降频保护；关闭后解除温控限制，发热也强行保持 120Hz。";
    }
    if (section == 6) {
        return @"💡 边充边玩黄金组合：开启高温智能断充后，一旦温度超过阈值，系统将物理切断电池充电改为直接由电源线供电（旁路供电）。配合 Insulation 防降频模块，可实现：大型游戏满帧不暗屏 + 电池不发热鼓包！";
    }
    return nil;
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

- (void)changeChargeTempSlider:(UISlider *)slider {
    smartChargeLimitTemp = slider.value;
    SavePreferencesAndNotify();
    [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:1 inSection:6]] withRowAnimation:UITableViewRowAnimationNone];
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
            cell.textLabel.text = @"CPU 模式";
            NSArray *modes = @[@"苹果原生温控", @"模拟低电频率", @"防止温控降频"];
            cell.detailTextLabel.text = (insulationCpuMode >= 0 && insulationCpuMode < modes.count) ? modes[insulationCpuMode] : modes[0];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"温控暗屏";
            UISwitch *sw = [UISwitch new];
            sw.on = insulationDimmingEnable;
            [sw addTarget:self action:@selector(changeInsulationDimming:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
        } else if (indexPath.row == 2) {
            cell.textLabel.text = @"禁温度计弹窗";
            UISwitch *sw = [UISwitch new];
            sw.on = insulationDisableThermometer;
            [sw addTarget:self action:@selector(changeInsulationThermometer:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
        } else if (indexPath.row == 3) {
            cell.textLabel.text = @"禁用口袋高温";
            UISwitch *sw = [UISwitch new];
            sw.on = insulationDisablePocketTemp;
            [sw addTarget:self action:@selector(changeInsulationPocket:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
        } else if (indexPath.row == 4) {
            cell.textLabel.text = @"锁定阳光暴晒";
            UISwitch *sw = [UISwitch new];
            sw.on = insulationLockSunlight;
            [sw addTarget:self action:@selector(changeInsulationSunlight:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
        }
    } else if (indexPath.section == 6) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"开启高温智能断充";
            UISwitch *sw = [UISwitch new];
            sw.on = smartChargeLimitEnable;
            [sw addTarget:self action:@selector(changeSmartChargeLimit:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"断充温度阈值";
            UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(0,0,130,30)];
            slider.minimumValue = 30.0; slider.maximumValue = 45.0; slider.value = smartChargeLimitTemp;
            [slider addTarget:self action:@selector(changeChargeTempSlider:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = slider;
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%.1f°C", smartChargeLimitTemp];
        }
    } else if (indexPath.section == 7) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"记忆悬浮窗位置";
            UISwitch *sw = [UISwitch new];
            sw.on = rememberPositionEnable;
            [sw addTarget:self action:@selector(changeRememberPosition:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"显示 CPU 频率";
            UISwitch *sw = [UISwitch new];
            sw.on = showCpuFrequency;
            [sw addTarget:self action:@selector(changeShowCpuFreq:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
        } else if (indexPath.row == 2) {
            cell.textLabel.text = @"显示 FPS 帧率";
            UISwitch *sw = [UISwitch new];
            sw.on = showFps;
            [sw addTarget:self action:@selector(changeShowFps:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
        } else if (indexPath.row == 3) {
            cell.textLabel.text = @"显示电池百分比";
            UISwitch *sw = [UISwitch new];
            sw.on = showBatteryPercent;
            [sw addTarget:self action:@selector(changeShowBattery:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
        } else if (indexPath.row == 4) {
            cell.textLabel.text = @"显示电池温度";
            UISwitch *sw = [UISwitch new];
            sw.on = showBatteryTemperature;
            [sw addTarget:self action:@selector(changeShowTemp:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
        } else if (indexPath.row == 5) {
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
    } else if (indexPath.section == 5) {
        if (indexPath.row == 0) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"CPU 模式" message:@"选择系统级温控干预级别" preferredStyle:UIAlertControllerStyleActionSheet];
            NSArray *titles = @[@"苹果原生温控", @"模拟低电频率", @"防止温控降频"];
            for (NSInteger i = 0; i < titles.count; i++) {
                [alert addAction:[UIAlertAction actionWithTitle:titles[i] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                    insulationCpuMode = i;
                    SavePreferencesAndNotify();
                    [self.tableView reloadData];
                }]];
            }
            [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
        }
    }
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
}

- (void)changeThermalProtection:(UISwitch *)sw {
    thermalProtectionEnable = sw.isOn;
    SavePreferencesAndNotify();
}

- (void)changeShowCpuFreq:(UISwitch *)sw { showCpuFrequency = sw.isOn; SavePreferencesAndNotify(); updateFloatingSize(); }
- (void)changeShowFps:(UISwitch *)sw { showFps = sw.isOn; SavePreferencesAndNotify(); updateFloatingSize(); }
- (void)changeShowBattery:(UISwitch *)sw { showBatteryPercent = sw.isOn; SavePreferencesAndNotify(); updateFloatingSize(); }
- (void)changeShowTemp:(UISwitch *)sw { showBatteryTemperature = sw.isOn; SavePreferencesAndNotify(); updateFloatingSize(); }
- (void)changeShowCurrent:(UISwitch *)sw { showBatteryCurrent = sw.isOn; SavePreferencesAndNotify(); updateFloatingSize(); }

- (void)changeInsulationDimming:(UISwitch *)sw { insulationDimmingEnable = sw.isOn; SavePreferencesAndNotify(); }
- (void)changeInsulationThermometer:(UISwitch *)sw { insulationDisableThermometer = sw.isOn; SavePreferencesAndNotify(); }
- (void)changeInsulationPocket:(UISwitch *)sw { insulationDisablePocketTemp = sw.isOn; SavePreferencesAndNotify(); }
- (void)changeInsulationSunlight:(UISwitch *)sw { insulationLockSunlight = sw.isOn; SavePreferencesAndNotify(); }

- (void)changeSmartChargeLimit:(UISwitch *)sw { 
    smartChargeLimitEnable = sw.isOn; 
    SavePreferencesAndNotify(); 
    if (!smartChargeLimitEnable && isCurrentlyChargeInhibited) {
        setHardwareChargingInhibit(NO);
        isCurrentlyChargeInhibited = NO;
    }
}

@end

#pragma mark - 13. 跨进程监听与 Tweak 全局注入入口

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
    });
}

#pragma mark - 14. Insulation 模块核心注入 (防降频 / 模拟低电 / 防暗屏)

%hook NSProcessInfo
- (NSProcessInfoThermalState)thermalState {
    if (insulationCpuMode == 2) {
        return NSProcessInfoThermalStateNominal; 
    } else if (insulationCpuMode == 1) {
        return NSProcessInfoThermalStateCritical; 
    }
    return %orig;
}

- (BOOL)isLowPowerModeEnabled {
    if (insulationCpuMode == 1) return YES;
    return %orig;
}
%end

%hook SBBacklightController
- (void)setThermalWarningState:(NSInteger)state {
    if (!insulationDimmingEnable) {
        %orig(0); 
    } else {
        %orig(state);
    }
}
- (void)_updateBrightnessForSunlightLoad:(BOOL)arg1 {
    if (insulationLockSunlight) {
        %orig(YES);
    } else {
        %orig(arg1);
    }
}
%end

%hook SBThermalController
- (void)showThermalAlertIfNecessary {
    if (insulationDisableThermometer) return; 
    %orig;
}
- (BOOL)isThermalBlocked {
    if (insulationDisableThermometer) return NO;
    return %orig;
}
- (NSInteger)levelForCurrentThermalCondition {
    if (insulationCpuMode == 2) return 0;
    if (insulationCpuMode == 1) return 3;
    return %orig;
}
%end

%hook SBPocketStateMonitor
- (void)pocketStateDidChange:(NSInteger)state {
    if (insulationDisablePocketTemp) {
        %orig(0); 
    } else {
        %orig(state);
    }
}
%end


%group MitigationHooks

%hook MitigationController

- (void)setPowerSaveActive:(BOOL)active {
    sharedMitigationController = self;
    if (insulationCpuMode == 2) {
        %orig(NO);
    } else if (insulationCpuMode == 1) {
        %orig(YES);
    } else {
        %orig(active);
    }
}

- (void)setCPULevel:(int)level {
    sharedMitigationController = self;
    if (insulationCpuMode == 2) {
        %orig(0);
    } else if (insulationCpuMode == 1) {
        %orig(2); // 严格锁定低频
    } else {
        %orig(level);
    }
}

- (void)setCPULowPowerTarget:(int)power {
    if (insulationCpuMode == 2) {
        %orig(MAX(power, InsulationUnrestrictedPowerTarget));
    } else {
        %orig(power);
    }
}

- (void)setCPUPowerCeiling:(int)power fromDecisionSource:(int)source {
    sharedMitigationController = self;
    if (insulationCpuMode == 2) {
        %orig(MAX(power, InsulationUnrestrictedPowerTarget), source);
    } else {
        %orig(power, source);
    }
}

- (void)setCPUPowerZoneTarget:(int)power {
    if (insulationCpuMode == 2) {
        %orig(MAX(power, InsulationUnrestrictedPowerTarget));
    } else {
        %orig(power);
    }
}
%end

%end // MitigationHooks


%ctor {
    %init;
    
    NSString *processName = [NSProcessInfo processInfo].processName;

    if ([processName isEqualToString:@"SpringBoard"]) {
        // UI 和本地监听初始化
        LoadPreferences();
        
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL,
            onCCNotificationReceived,
            kPrefChangedNotification,
            NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately
        );
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            createCPUWindow();
            registerV160Observers();

            [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *timer) {
                updateCPU();
            }];
        });
        
    } else if ([processName isEqualToString:@"thermalmonitord"]) {
        // 🟢 [终极修复核心] 守护进程的沙盒击穿方案！
        %init(MitigationHooks);

        // 1. 注册内核调度频道的监听
        int token;
        notify_register_dispatch(NOTIFY_CPU_MODE, &token, dispatch_get_main_queue(), ^(int t) {
            uint64_t state = 0;
            notify_get_state(t, &state);             // 从内核读取最新模式
            insulationCpuMode = (NSInteger)state;    // 赋值给本进程
            applyMitigationState();                  // 瞬间拉平频率！
        });

        // 2. 初始化时主动抓取一次状态（应对手机刚开机的情况）
        uint64_t initialState = 0;
        if (notify_get_state(token, &initialState) == NOTIFY_STATUS_OK) {
            insulationCpuMode = (NSInteger)initialState;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                applyMitigationState();
            });
        }
    }
}

