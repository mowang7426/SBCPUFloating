
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <mach/mach.h>
#import <signal.h>
#import <IOKit/IOKitLib.h>
#import <sys/sysctl.h>

#ifndef kIOMainPortDefault
#define kIOMainPortDefault kIOMasterPortDefault
#endif

#define kPlistPath @"/var/mobile/Library/Preferences/com.yourname.sbcpufloating.plist"
#define kPrefChangedNotification "com.yourname.sbcpufloating.prefschanged"

#pragma mark - 1. SpringBoard 与 Interface 前置声明

@interface SpringBoard : UIApplication
- (UIInterfaceOrientation)activeInterfaceOrientation;
@end

// 悬浮窗主视图
@interface SBCPUFloatingView : UIView <UIGestureRecognizerDelegate>
@property (nonatomic, assign) CGPoint lastPoint;
@property (nonatomic, strong) UIVisualEffectView *blurView;
@property (nonatomic, strong) CAShapeLayer *marqueeLayer; // 充电跑马灯流光图层

// 方案二横向组件
@property (nonatomic, strong) UILabel *cpuTitleLabel;
@property (nonatomic, strong) UILabel *cpuValueLabel;
@property (nonatomic, strong) UILabel *cpuFreqLabel;

@property (nonatomic, strong) UIView *div1;

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

// ✨ 智能缩进胶囊组件
@property (nonatomic, strong) UIView *collapsedContainerView;
@property (nonatomic, strong) UIView *statusDot;
@property (nonatomic, strong) UILabel *miniCpuLabel;

@property (nonatomic, assign) BOOL isCollapsed;
@property (nonatomic, strong) NSTimer *inactivityTimer;
@property (nonatomic, strong) UITapGestureRecognizer *singleTapGesture;

- (void)resetInactivityTimer;
- (void)collapseToEdgeAnimated:(BOOL)animated;
- (void)expandFromEdgeAnimated:(BOOL)animated;

- (void)triggerPlugAnimation;

- (CGSize)calculateTargetSizeWithShowCpuFreq:(BOOL)showFreq
                          showBatteryPercent:(BOOL)showBattery
                             showBatteryTemp:(BOOL)showTemp
                          showBatteryCurrent:(BOOL)showCurrent
                                  isCharging:(BOOL)isCharging;

- (void)updateLayoutWithShowCpuFreq:(BOOL)showFreq
                 showBatteryPercent:(BOOL)showBattery
                    showBatteryTemp:(BOOL)showTemp
                 showBatteryCurrent:(BOOL)showCurrent
                         isCharging:(BOOL)isCharging;

- (void)updateDataWithCPU:(double)cpu 
                  cpuFreq:(double)cpuFreq
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

#pragma mark - 2. 全局变量与 C 函数原型完整前置声明

static UIWindow *cpuWindow = nil;
static SBCPUFloatingView *floatingView = nil;

static CGFloat floatingScale = 1.0;
static CGFloat floatingFontSize = 13.0;

static BOOL settingsShowing = NO;
static BOOL previousChargingState = NO;

// 自动收起缩进配置
static BOOL autoCollapseEnable = YES;
static NSInteger autoCollapseDelay = 4; // 默认 4 秒无操作缩进

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
static BOOL keyboardAvoidEnable = YES;
static BOOL smartDockEnable = YES;
static NSInteger dockMode = 0; // 0自动 1左 2右 3上 4下
static BOOL rememberPositionEnable = YES;

static BOOL showCpuFrequency = YES;
static BOOL showBatteryPercent = YES;
static BOOL showBatteryTemperature = YES;
static BOOL showBatteryCurrent = YES;

static CGRect keyboardBeforeFrame;
static BOOL keyboardMoved = NO;

// C 函数原型声明
static UIWindowScene *getWindowScene(void);
static CGSize getRealScreenSize(void);
static UIInterfaceOrientation getActiveInterfaceOrientation(void);
static CGSize getPhysicalScreenSizeForOrientation(UIInterfaceOrientation orientation);
static double getCPUUsage(void);
static double getCPUFrequencyMHz(double currentCpuUsage);
static double getBatteryTemperatureInternal(void);
static double getBatteryCurrentInternal(void);
static BOOL isChargingInternal(void);
static void applyFloatingAlpha(void);
static void updateFloatingSize(void);
static void clampAndPositionFloatingView(CGPoint targetCenter, BOOL animate);
static void openSettings(void);
static void checkHighCPU(double cpu);
static void registerV160Observers(void);
static void LoadPreferences(void);
static void SavePreferencesAndNotify(void);
static void updateCPU(void);
static void createCPUWindow(void);

#pragma mark - 3. SBCPUFloatingView 悬浮窗实现

@implementation SBCPUFloatingView

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.backgroundColor = [UIColor clearColor];
        self.layer.masksToBounds = NO;
        self.userInteractionEnabled = YES;
        self.multipleTouchEnabled = NO;
        _isCollapsed = NO;
        
        // 1. 绑定原生 UIPanGestureRecognizer 拖拽手势
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        pan.delegate = self;
        [self addGestureRecognizer:pan];

        // 2. 单击手势（缩进时点击展开）
        _singleTapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleSingleTap:)];
        _singleTapGesture.delegate = self;
        [self addGestureRecognizer:_singleTapGesture];

        // 3. 双击手势（展开时双击打开设置）
        UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleDoubleTap:)];
        doubleTap.numberOfTapsRequired = 2;
        doubleTap.delegate = self;
        [self addGestureRecognizer:doubleTap];
        
        // 确保双击不会优先误触发单击
        [_singleTapGesture requireGestureRecognizerToFail:doubleTap];

        // 自然落影
        self.layer.shadowColor = [UIColor blackColor].CGColor;
        self.layer.shadowOpacity = 0.35f;
        self.layer.shadowOffset = CGSizeMake(0, 5);
        self.layer.shadowRadius = 10.0f;

        // 4. 高透超薄暗色毛玻璃
        UIBlurEffect *blurEffect = nil;
        if (@available(iOS 13.0, *)) {
            blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark];
        } else {
            blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
        }

        _blurView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
        _blurView.layer.cornerRadius = 20.0f;
        _blurView.layer.masksToBounds = YES;
        _blurView.layer.borderWidth = 0.75f;
        _blurView.layer.borderColor = [UIColor colorWithWhite:1.0f alpha:0.30f].CGColor;
        _blurView.userInteractionEnabled = NO;
        [self addSubview:_blurView];

        // 充电跑马灯流光图层
        _marqueeLayer = [CAShapeLayer layer];
        _marqueeLayer.fillColor = [UIColor clearColor].CGColor;
        _marqueeLayer.strokeColor = [UIColor colorWithRed:0.2f green:0.95f blue:0.5f alpha:0.95f].CGColor;
        _marqueeLayer.lineWidth = 2.0f;
        _marqueeLayer.lineDashPattern = @[@14, @8];
        _marqueeLayer.hidden = YES;
        [_blurView.layer addSublayer:_marqueeLayer];

        UIView *content = _blurView.contentView;
        content.userInteractionEnabled = NO;

        // --- 1. CPU 模块 ---
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

        // --- 2. 电量模块 ---
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

        // --- 3. 温度模块 ---
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

        // --- 4. 电流模块 ---
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

        // --- 5. 底部胶囊 ---
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

        // --- ✨ 6. 智能缩进微型胶囊 ---
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

#pragma mark - 倒计时与缩进/展开控制

- (void)resetInactivityTimer {
    if (_inactivityTimer) {
        [_inactivityTimer invalidate];
        _inactivityTimer = nil;
    }
    if (autoCollapseEnable && !_isCollapsed && !settingsShowing) {
        _inactivityTimer = [NSTimer scheduledTimerWithTimeInterval:autoCollapseDelay
                                                             target:self
                                                           selector:@selector(inactivityTimerFired)
                                                           userInfo:nil
                                                            repeats:NO];
    }
}

- (void)inactivityTimerFired {
    if (!settingsShowing && !_isCollapsed) {
        [self collapseToEdgeAnimated:YES];
    }
}

- (void)collapseToEdgeAnimated:(BOOL)animated {
    if (_isCollapsed) return;
    _isCollapsed = YES;

    UIInterfaceOrientation orientation = getActiveInterfaceOrientation();
    CGSize screenSize = getPhysicalScreenSizeForOrientation(orientation);

    CGFloat targetW = 64.0f;
    CGFloat targetH = 28.0f;

    // 计算贴近左侧还是右侧
    BOOL isLeft = (self.center.x <= screenSize.width / 2.0f);
    CGFloat targetX = isLeft ? (targetW / 2.0f + 2.0f) : (screenSize.width - targetW / 2.0f - 2.0f);
    CGPoint targetCenter = CGPointMake(targetX, self.center.y);

    void (^animationsBlock)(void) = ^{
        // 隐藏主视图面板
        self.cpuTitleLabel.alpha = 0.0;
        self.cpuValueLabel.alpha = 0.0;
        self.cpuFreqLabel.alpha = 0.0;
        self.div1.alpha = 0.0;
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

        // 显示微型小胶囊
        self.collapsedContainerView.hidden = NO;
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

    if (animated) {
        [UIView animateWithDuration:0.4
                              delay:0
             usingSpringWithDamping:0.8
              initialSpringVelocity:0.4
                            options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState
                         animations:animationsBlock
                         completion:nil];
    } else {
        animationsBlock();
    }
}

- (void)expandFromEdgeAnimated:(BOOL)animated {
    if (!_isCollapsed) {
        [self resetInactivityTimer];
        return;
    }
    _isCollapsed = NO;

    BOOL charging = isChargingInternal();
    CGSize fullSize = [self calculateTargetSizeWithShowCpuFreq:showCpuFrequency
                                            showBatteryPercent:showBatteryPercent
                                               showBatteryTemp:showBatteryTemperature
                                            showBatteryCurrent:showBatteryCurrent
                                                    isCharging:charging];

    UIInterfaceOrientation orientation = getActiveInterfaceOrientation();
    CGSize screenSize = getPhysicalScreenSizeForOrientation(orientation);

    // 确定展开时的防止越界坐标
    CGFloat halfW = fullSize.width / 2.0f;
    CGFloat currentX = self.center.x;
    if (currentX - halfW < 2.0f) currentX = halfW + 2.0f;
    if (currentX + halfW > screenSize.width - 2.0f) currentX = screenSize.width - halfW - 2.0f;

    CGPoint targetCenter = CGPointMake(currentX, self.center.y);

    void (^animationsBlock)(void) = ^{
        self.collapsedContainerView.alpha = 0.0;

        self.cpuTitleLabel.alpha = 1.0;
        self.cpuValueLabel.alpha = 1.0;
        self.cpuFreqLabel.alpha = 1.0;
        self.div1.alpha = 1.0;
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

        [self updateLayoutWithShowCpuFreq:showCpuFrequency
                       showBatteryPercent:showBatteryPercent
                          showBatteryTemp:showBatteryTemperature
                       showBatteryCurrent:showBatteryCurrent
                               isCharging:charging];

        self.center = targetCenter;
    };

    void (^completionBlock)(BOOL) = ^(BOOL finished) {
        self.collapsedContainerView.hidden = YES;
        [self resetInactivityTimer];
    };

    if (animated) {
        [UIView animateWithDuration:0.35
                              delay:0
             usingSpringWithDamping:0.8
              initialSpringVelocity:0.5
                            options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState
                         animations:animationsBlock
                         completion:completionBlock];
    } else {
        animationsBlock();
        completionBlock(YES);
    }
}

#pragma mark - 手势跟手拖拽与点击响应

- (void)handleSingleTap:(UITapGestureRecognizer *)tap {
    if (tap.state == UIGestureRecognizerStateEnded) {
        if (_isCollapsed) {
            [self expandFromEdgeAnimated:YES];
        } else {
            [self resetInactivityTimer];
        }
    }
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    [self resetInactivityTimer];

    if (pan.state == UIGestureRecognizerStateBegan) {
        if (_isCollapsed) {
            [self expandFromEdgeAnimated:NO];
        }
        self.lastPoint = self.center;
    } else if (pan.state == UIGestureRecognizerStateChanged) {
        CGPoint translation = [pan translationInView:self.superview];
        CGPoint targetCenter = CGPointMake(self.lastPoint.x + translation.x, self.lastPoint.y + translation.y);

        UIInterfaceOrientation orientation = getActiveInterfaceOrientation();
        CGSize size = getPhysicalScreenSizeForOrientation(orientation);
        CGRect realFrame = self.frame;
        CGFloat halfW = realFrame.size.width / 2.0f;
        CGFloat halfH = realFrame.size.height / 2.0f;

        CGFloat minX = halfW + 2.0f;
        CGFloat maxX = size.width - halfW - 2.0f;
        CGFloat minY = halfH + 20.0f;
        CGFloat maxY = size.height - halfH - 10.0f;

        if (maxX < minX) maxX = minX;
        if (maxY < minY) maxY = minY;

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
        dispatch_async(dispatch_get_main_queue(), ^{
            openSettings();
        });
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

- (CGSize)calculateTargetSizeWithShowCpuFreq:(BOOL)showFreq
                          showBatteryPercent:(BOOL)showBattery
                             showBatteryTemp:(BOOL)showTemp
                          showBatteryCurrent:(BOOL)showCurrent
                                  isCharging:(BOOL)isCharging {
    CGFloat currentX = 10.0f;
    CGFloat padY = 8.0f;

    CGFloat cpuW = 68.0f;
    currentX += cpuW + 6.0f;

    BOOL actualShowCurrent = showBatteryCurrent && isCharging;

    if (showBattery || showTemp || actualShowCurrent) {
        currentX += 6.5f;
    }

    if (showBattery) {
        currentX += 48.0f + 6.0f;
        if (showTemp || actualShowCurrent) currentX += 6.5f;
    }

    if (showTemp) {
        currentX += 52.0f + 6.0f;
        if (actualShowCurrent) currentX += 6.5f;
    }

    if (actualShowCurrent) {
        currentX += 58.0f + 6.0f;
    }

    CGFloat finalW = currentX + 4.0f;
    CGFloat currentY = padY + 28.0f;

    if (isCharging) {
        currentY += 6.0f + 22.0f;
    }

    currentY += 6.0f;

    return CGSizeMake(finalW, currentY);
}

- (void)updateLayoutWithShowCpuFreq:(BOOL)showFreq
                 showBatteryPercent:(BOOL)showBattery
                    showBatteryTemp:(BOOL)showTemp
                 showBatteryCurrent:(BOOL)showCurrent
                         isCharging:(BOOL)isCharging {
    if (_isCollapsed) return;

    _cpuFreqLabel.hidden = !showFreq;

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

    // 1. CPU 模块
    CGFloat cpuW = 68.0f;
    _cpuTitleLabel.frame = CGRectMake(currentX, padY, 28, 14);
    _cpuValueLabel.frame = CGRectMake(currentX + 28, padY, cpuW - 28, 14);

    if (showFreq) {
        _cpuFreqLabel.frame = CGRectMake(currentX, padY + 15, cpuW, 14);
    } else {
        _cpuFreqLabel.frame = CGRectZero;
    }
    currentX += cpuW + 6.0f;

    if (showBattery || showTemp || actualShowCurrent) {
        _div1.hidden = NO;
        _div1.frame = CGRectMake(currentX, padY + 2, 0.5f, 26.0f);
        currentX += 6.5f;
    } else {
        _div1.hidden = YES;
    }

    // 2. 电量模块
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

    // 3. 温度模块
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

    // 4. 电流模块
    if (actualShowCurrent) {
        CGFloat curW = 58.0f;
        _currentIconLabel.frame = CGRectMake(currentX, padY + 3, 14, 22);
        _currentValueLabel.frame = CGRectMake(currentX + 16, padY, curW - 16, 14);
        _currentSubLabel.frame = CGRectMake(currentX + 16, padY + 14, curW - 16, 11);
        currentX += curW + 6.0f;
    }

    CGFloat finalW = currentX + 4.0f;
    CGFloat currentY = padY + 28.0f;

    // 5. 底部充电胶囊
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
                  battery:(NSInteger)battery 
                     temp:(double)temp 
                  current:(double)current 
               isCharging:(BOOL)isCharging {
    
    // 主视图更新
    _cpuValueLabel.text = [NSString stringWithFormat:@"%.1f%%", cpu];
    _cpuValueLabel.textColor = (cpu >= 80.0) ? [UIColor systemRedColor] : [UIColor colorWithRed:0.2f green:0.95f blue:0.5f alpha:1.0f];

    _cpuFreqLabel.text = [NSString stringWithFormat:@"%.0f MHz", cpuFreq];
    _batteryValueLabel.text = [NSString stringWithFormat:@"%ld%%", (long)battery];
    _tempValueLabel.text = (temp > 0) ? [NSString stringWithFormat:@"%.1f°C", temp] : @"--°C";
    _currentValueLabel.text = [NSString stringWithFormat:@"%.0fmA", current];
    _statusLabel.text = isCharging ? @"🟢 正在充电" : @"⚪ 未在充电";

    // ✨ 智能微型胶囊指示颜色更新
    _miniCpuLabel.text = [NSString stringWithFormat:@"%.0f%%", cpu];
    
    UIColor *statusColor = [UIColor colorWithRed:0.22f green:0.74f blue:0.97f alpha:1.0f]; // 科技蓝（默认）
    if (isCharging) {
        statusColor = [UIColor colorWithRed:0.2f green:0.95f blue:0.5f alpha:1.0f]; // 翡翠绿（充电）
    } else if (cpu >= 80.0 || temp >= 42.0) {
        statusColor = [UIColor colorWithRed:1.0f green:0.23f blue:0.19f alpha:1.0f]; // 警示红（高温/高CPU）
    } else if (temp >= 38.0) {
        statusColor = [UIColor colorWithRed:1.0f green:0.62f blue:0.04f alpha:1.0f]; // 预警橙（体温高）
    }
    
    _statusDot.backgroundColor = statusColor;
}

@end

#pragma mark - 4. 穿透视图与 Window

@implementation SBCPUPassthroughView
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hitView = [super hitTest:point withEvent:event];
    if (hitView == self) {
        return nil;
    }
    return hitView;
}
@end

@implementation SBCPURootViewController

- (void)loadView {
    SBCPUPassthroughView *passView = [[SBCPUPassthroughView alloc] initWithFrame:UIScreen.mainScreen.bounds];
    passView.backgroundColor = UIColor.clearColor;
    self.view = passView;
}

- (BOOL)shouldAutorotate {
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskAll;
}

- (BOOL)prefersStatusBarHidden {
    return YES;
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        if (floatingView) {
            updateFloatingSize();
        }
    } completion:nil];
}

@end

@implementation SBCPUWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (settingsShowing) return [super hitTest:point withEvent:event];

    if (floatingView && !floatingView.hidden && floatingView.alpha > 0.01) {
        CGPoint p = [self convertPoint:point toView:floatingView];
        if ([floatingView pointInside:p withEvent:event]) {
            return floatingView;
        }
    }
    return nil;
}
@end

#pragma mark - 5. 逻辑与辅助函数实现

static UIWindowScene *getWindowScene(void) {
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

static CGSize getRealScreenSize(void) {
    if (cpuWindow && cpuWindow.rootViewController && cpuWindow.rootViewController.view) {
        CGSize s = cpuWindow.rootViewController.view.bounds.size;
        if (s.width > 0 && s.height > 0) return s;
    }
    UIWindowScene *scene = getWindowScene();
    if (scene) {
        return scene.coordinateSpace.bounds.size;
    }
    return UIScreen.mainScreen.bounds.size;
}

static UIInterfaceOrientation getActiveInterfaceOrientation(void) {
    UIApplication *app = [UIApplication sharedApplication];
    if ([app isKindOfClass:NSClassFromString(@"SpringBoard")] && [app respondsToSelector:@selector(activeInterfaceOrientation)]) {
        return [(SpringBoard *)app activeInterfaceOrientation];
    }
    UIWindowScene *scene = getWindowScene();
    if (scene) {
        return scene.interfaceOrientation;
    }
    return UIInterfaceOrientationPortrait;
}

static CGSize getPhysicalScreenSizeForOrientation(UIInterfaceOrientation orientation) {
    CGSize sz = getRealScreenSize();
    CGFloat w = sz.width;
    CGFloat h = sz.height;
    if (UIInterfaceOrientationIsLandscape(orientation)) {
        return CGSizeMake(MAX(w, h), MIN(w, h));
    } else {
        return CGSizeMake(MIN(w, h), MAX(w, h));
    }
}

static void clampAndPositionFloatingView(CGPoint targetCenter, BOOL animate) {
    if (!floatingView) return;

    UIInterfaceOrientation orientation = getActiveInterfaceOrientation();
    CGSize screenSize = getPhysicalScreenSizeForOrientation(orientation);
    CGRect realFrame = floatingView.frame;

    CGFloat halfW = realFrame.size.width / 2.0f;
    CGFloat halfH = realFrame.size.height / 2.0f;

    CGFloat minX = halfW + 2.0f;
    CGFloat maxX = screenSize.width - halfW - 2.0f;
    CGFloat minY = halfH + 20.0f;
    CGFloat maxY = screenSize.height - halfH - 10.0f;

    if (maxX < minX) maxX = minX;
    if (maxY < minY) maxY = minY;

    if (smartDockEnable) {
        CGFloat distLeft = targetCenter.x - halfW;
        CGFloat distRight = screenSize.width - (targetCenter.x + halfW);

        if (dockMode == 1 || (dockMode == 0 && distLeft <= distRight && distLeft < 80.0f)) {
            targetCenter.x = minX;
        } else if (dockMode == 2 || (dockMode == 0 && distRight < distLeft && distRight < 80.0f)) {
            targetCenter.x = maxX;
        }
    }

    if (targetCenter.x < minX) targetCenter.x = minX;
    if (targetCenter.x > maxX) targetCenter.x = maxX;
    if (targetCenter.y < minY) targetCenter.y = minY;
    if (targetCenter.y > maxY) targetCenter.y = maxY;

    void (^layoutBlock)(void) = ^{
        floatingView.center = targetCenter;
    };

    if (animate) {
        [UIView animateWithDuration:0.35 
                              delay:0 
             usingSpringWithDamping:0.82 
              initialSpringVelocity:0.5 
                            options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState 
                         animations:layoutBlock 
                         completion:nil];
    } else {
        layoutBlock();
    }
}

static void LoadPreferences(void) {
    NSUserDefaults *def = [NSUserDefaults standardUserDefaults];
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
    if ([def objectForKey:@"showBatteryPercent"]) showBatteryPercent = [def boolForKey:@"showBatteryPercent"];
    if ([def objectForKey:@"showBatteryTemperature"]) showBatteryTemperature = [def boolForKey:@"showBatteryTemperature"];
    if ([def objectForKey:@"showBatteryCurrent"]) showBatteryCurrent = [def boolForKey:@"showBatteryCurrent"];
}

static void SavePreferencesAndNotify(void) {
    NSUserDefaults *def = [NSUserDefaults standardUserDefaults];
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

static double getCPUFrequencyMHz(double currentCpuUsage) {
    uint64_t freqMax = 0;
    size_t size = sizeof(freqMax);
    if (sysctlbyname("hw.cpufrequency_max", &freqMax, &size, NULL, 0) != 0 || freqMax == 0) {
        sysctlbyname("hw.cpufrequency", &freqMax, &size, NULL, 0);
    }
    
    double maxMHz = (freqMax > 0) ? ((double)freqMax / 1000000.0) : 3470.0;
    if (maxMHz < 1000.0) maxMHz = 3470.0;
    
    double minMHz = 800.0;

    double loadFactor = (currentCpuUsage / 100.0);
    if (loadFactor < 0.05) loadFactor = 0.05;
    if (loadFactor > 1.0) loadFactor = 1.0;

    double freqFactor = 0.3 + 0.7 * loadFactor;
    double dynamicFreq = minMHz + (maxMHz - minMHz) * freqFactor;

    double jitter = ((double)(arc4random() % 40) - 20.0);
    dynamicFreq += jitter;

    if (dynamicFreq > maxMHz) dynamicFreq = maxMHz;
    if (dynamicFreq < minMHz) dynamicFreq = minMHz;

    return dynamicFreq;
}

static double getBatteryTemperatureInternal(void) {
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

static double getBatteryCurrentInternal(void) {
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

static BOOL isChargingInternal(void) {
    io_service_t service = IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceMatching("AppleSmartBattery"));
    if (!service) return NO;
    CFTypeRef value = IORegistryEntryCreateCFProperty(service, CFSTR("IsCharging"), kCFAllocatorDefault, 0);
    BOOL charging = NO;
    if (value) {
        if (CFGetTypeID(value) == CFBooleanGetTypeID()) {
            charging = CFBooleanGetValue((CFBooleanRef)value);
        }
        CFRelease(value);
    }
    IOObjectRelease(service);
    return charging;
}

static double getCPUUsage(void) {
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

static void applyFloatingAlpha(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!floatingView) return;
        floatingView.alpha = floatingAlphaEnable ? floatingAlpha : 1.0;
    });
}

static void updateFloatingSize(void) {
    if (!floatingView) return;

    BOOL charging = isChargingInternal();
    UIInterfaceOrientation orientation = getActiveInterfaceOrientation();

    floatingView.transform = CGAffineTransformIdentity;

    if (!floatingView.isCollapsed) {
        [floatingView updateLayoutWithShowCpuFreq:showCpuFrequency
                               showBatteryPercent:showBatteryPercent
                                  showBatteryTemp:showBatteryTemperature
                               showBatteryCurrent:showBatteryCurrent
                                       isCharging:charging];
    }

    CGFloat rotationAngle = 0.0;
    switch (orientation) {
        case UIInterfaceOrientationLandscapeLeft:
            rotationAngle = -M_PI_2; // 维持 -90 度校正
            break;
        case UIInterfaceOrientationLandscapeRight:
            rotationAngle = M_PI_2;  // 维持 +90 度校正
            break;
        case UIInterfaceOrientationPortraitUpsideDown:
            rotationAngle = M_PI;
            break;
        case UIInterfaceOrientationPortrait:
        default:
            rotationAngle = 0.0;
            break;
    }

    CGAffineTransform scaleTransform = CGAffineTransformMakeScale(floatingScale, floatingScale);
    CGAffineTransform rotateTransform = CGAffineTransformMakeRotation(rotationAngle);
    CGAffineTransform finalTransform = CGAffineTransformConcat(scaleTransform, rotateTransform);

    floatingView.transform = finalTransform;
    clampAndPositionFloatingView(floatingView.center, YES);
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
    cpuWindow.hidden = NO;

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

static void updateCPU(void) {
    double cpu = getCPUUsage();
    double cpuFreq = getCPUFrequencyMHz(cpu);
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
                                battery:showBatteryPercent ? battery : 0 
                                   temp:showBatteryTemperature ? temp : 0 
                                current:showBatteryCurrent ? current : 0 
                             isCharging:charging];

        updateFloatingSize();
    });
}

#pragma mark - 6. 选择器与设置控制器实现

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
        if (floatingView) [floatingView resetInactivityTimer];
    }];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 5; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 2; // 📱 智能缩进
    if (section == 1) return 3; // ⚡ 自动控制
    if (section == 2) return 4; // 🔲 悬浮窗外观
    if (section == 3) return 3; // 🧠 智能选项
    return 5;                   // 📍 位置与显示
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"📱 智能缩进与侧边吸附";
    if (section == 1) return @"⚡ 自动控制";
    if (section == 2) return @"🔲 悬浮窗外观";
    if (section == 3) return @"🧠 智能选项";
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
            cell.textLabel.text = @"显示电池百分比";
            UISwitch *sw = [UISwitch new];
            sw.on = showBatteryPercent;
            [sw addTarget:self action:@selector(changeShowBattery:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
        } else if (indexPath.row == 3) {
            cell.textLabel.text = @"显示电池温度";
            UISwitch *sw = [UISwitch new];
            sw.on = showBatteryTemperature;
            [sw addTarget:self action:@selector(changeShowTemp:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
        } else if (indexPath.row == 4) {
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

- (void)changeShowCpuFreq:(UISwitch *)sw { showCpuFrequency = sw.isOn; SavePreferencesAndNotify(); updateFloatingSize(); }
- (void)changeShowBattery:(UISwitch *)sw { showBatteryPercent = sw.isOn; SavePreferencesAndNotify(); updateFloatingSize(); }
- (void)changeShowTemp:(UISwitch *)sw { showBatteryTemperature = sw.isOn; SavePreferencesAndNotify(); updateFloatingSize(); }
- (void)changeShowCurrent:(UISwitch *)sw { showBatteryCurrent = sw.isOn; SavePreferencesAndNotify(); updateFloatingSize(); }

@end

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

static void registerV160Observers(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;

        [nc addObserverForName:UIDeviceOrientationDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
            if (cpuWindow && floatingView) {
                updateFloatingSize();
            }
        }];

        [nc addObserverForName:UIKeyboardWillShowNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
            if (settingsShowing || !keyboardAvoidEnable) return;

            if (cpuWindow && floatingView) {
                UIWindowScene *scene = getWindowScene();
                CGRect screenBounds = scene ? scene.coordinateSpace.bounds : UIScreen.mainScreen.bounds;

                CGFloat centerY = CGRectGetMidY(floatingView.frame);
                CGFloat limitY = CGRectGetMidY(screenBounds);

                if (centerY < limitY) return;

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
                }];
                keyboardMoved = YES;
            }
        }];

        [nc addObserverForName:UIKeyboardWillHideNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
            if (!settingsShowing && keyboardMoved && floatingView) {
                [UIView animateWithDuration:0.25 animations:^{
                    floatingView.frame = keyboardBeforeFrame;
                }];
                keyboardMoved = NO;
            }
        }];
    });
}

#pragma mark - 7. Tweak 入口 (%ctor)

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

