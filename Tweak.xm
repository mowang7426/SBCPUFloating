
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <mach/mach.h>
#import <signal.h>

#define kPlistPath @"/var/mobile/Library/Preferences/com.yourname.sbcpufloating.plist"
#define kPrefChangedNotification "com.yourname.sbcpufloating.prefschanged"

#pragma mark - 1:1 忠实复刻设计图的精美悬浮窗视图类
@interface SBCPUFloatingView : UIView
@property (nonatomic, strong) UIVisualEffectView *blurView;
@property (nonatomic, strong) UILabel *cpuTitleLabel;
@property (nonatomic, strong) UILabel *cpuValueLabel;
@property (nonatomic, strong) UIView *topDivider;

@property (nonatomic, strong) UIView *batteryContainer;
@property (nonatomic, strong) UILabel *batteryValueLabel;
@property (nonatomic, strong) UILabel *batteryTitleLabel;

@property (nonatomic, strong) UIView *midDivider;

@property (nonatomic, strong) UIView *tempContainer;
@property (nonatomic, strong) UILabel *tempValueLabel;
@property (nonatomic, strong) UILabel *tempTitleLabel;

@property (nonatomic, strong) UIView *bottomCapsule;
@property (nonatomic, strong) UILabel *currentLabel;
@property (nonatomic, strong) UILabel *statusLabel;

- (void)updateDataWithCPU:(double)cpu battery:(NSInteger)battery temp:(double)temp current:(double)current;
@end

@implementation SBCPUFloatingView

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.backgroundColor = [UIColor clearColor];
        self.layer.masksToBounds = NO;
        
        // 单层外阴影 (解决重影问题)
        self.layer.shadowColor = [UIColor blackColor].CGColor;
        self.layer.shadowOpacity = 0.30f;
        self.layer.shadowOffset = CGSizeMake(0, 4);
        self.layer.shadowRadius = 8.0f;

        // 1. 高透暗色超薄毛玻璃
        UIBlurEffect *blurEffect = nil;
        if (@available(iOS 13.0, *)) {
            blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark];
        } else {
            blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
        }

        _blurView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
        _blurView.layer.cornerRadius = 22.0f;
        _blurView.layer.masksToBounds = YES;
        _blurView.layer.borderWidth = 0.5f;
        _blurView.layer.borderColor = [UIColor colorWithWhite:1.0f alpha:0.25f].CGColor;
        [self addSubview:_blurView];

        UIView *content = _blurView.contentView;

        // 2. 顶行：CPU 使用率
        _cpuTitleLabel = [[UILabel alloc] init];
        _cpuTitleLabel.text = @"🔲 SB CPU";
        _cpuTitleLabel.textColor = [UIColor colorWithWhite:0.9f alpha:1.0f];
        _cpuTitleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightBold];
        [content addSubview:_cpuTitleLabel];

        _cpuValueLabel = [[UILabel alloc] init];
        _cpuValueLabel.textColor = [UIColor colorWithRed:0.2f green:0.9f blue:0.5f alpha:1.0f];
        _cpuValueLabel.font = [UIFont monospacedDigitSystemFontOfSize:16 weight:UIFontWeightBlack];
        _cpuValueLabel.textAlignment = NSTextAlignmentRight;
        [content addSubview:_cpuValueLabel];

        // 顶行分割线
        _topDivider = [[UIView alloc] init];
        _topDivider.backgroundColor = [UIColor colorWithWhite:1.0f alpha:0.15f];
        [content addSubview:_topDivider];

        // 3. 中行左列：电量
        _batteryValueLabel = [[UILabel alloc] init];
        _batteryValueLabel.textColor = [UIColor whiteColor];
        _batteryValueLabel.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightBold];
        [content addSubview:_batteryValueLabel];

        _batteryTitleLabel = [[UILabel alloc] init];
        _batteryTitleLabel.text = @"电量";
        _batteryTitleLabel.textColor = [UIColor colorWithWhite:0.6f alpha:1.0f];
        _batteryTitleLabel.font = [UIFont systemFontOfSize:9 weight:UIFontWeightMedium];
        [content addSubview:_batteryTitleLabel];

        // 中行竖直分割线
        _midDivider = [[UIView alloc] init];
        _midDivider.backgroundColor = [UIColor colorWithWhite:1.0f alpha:0.15f];
        [content addSubview:_midDivider];

        // 3. 中行右列：温度
        _tempValueLabel = [[UILabel alloc] init];
        _tempValueLabel.textColor = [UIColor whiteColor];
        _tempValueLabel.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightBold];
        _tempValueLabel.textAlignment = NSTextAlignmentRight;
        [content addSubview:_tempValueLabel];

        _tempTitleLabel = [[UILabel alloc] init];
        _tempTitleLabel.text = @"温度";
        _tempTitleLabel.textColor = [UIColor colorWithWhite:0.6f alpha:1.0f];
        _tempTitleLabel.font = [UIFont systemFontOfSize:9 weight:UIFontWeightMedium];
        _tempTitleLabel.textAlignment = NSTextAlignmentRight;
        [content addSubview:_tempTitleLabel];

        // 4. 底行胶囊框
        _bottomCapsule = [[UIView alloc] init];
        _bottomCapsule.backgroundColor = [UIColor colorWithWhite:1.0f alpha:0.10f];
        _bottomCapsule.layer.cornerRadius = 12.0f;
        _bottomCapsule.layer.borderWidth = 0.5f;
        _bottomCapsule.layer.borderColor = [UIColor colorWithWhite:1.0f alpha:0.12f].CGColor;
        [content addSubview:_bottomCapsule];

        _currentLabel = [[UILabel alloc] init];
        _currentLabel.textColor = [UIColor colorWithRed:1.0f green:0.85f blue:0.2f alpha:1.0f];
        _currentLabel.font = [UIFont monospacedDigitSystemFontOfSize:11 weight:UIFontWeightBold];
        [_bottomCapsule addSubview:_currentLabel];

        _statusLabel = [[UILabel alloc] init];
        _statusLabel.text = @"🟢 正在充电";
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
    self.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:self.bounds cornerRadius:22.0f].CGPath;

    CGFloat w = self.bounds.size.width - 24;

    // 顶行
    _cpuTitleLabel.frame = CGRectMake(12, 10, 80, 18);
    _cpuValueLabel.frame = CGRectMake(12 + w - 80, 10, 80, 18);
    _topDivider.frame = CGRectMake(12, 32, w, 0.5f);

    // 中行
    CGFloat colW = (w - 12) / 2.0f;
    _batteryValueLabel.frame = CGRectMake(12, 36, colW, 14);
    _batteryTitleLabel.frame = CGRectMake(12, 50, colW, 12);

    _midDivider.frame = CGRectMake(12 + colW + 5, 38, 0.5f, 22);

    _tempValueLabel.frame = CGRectMake(12 + colW + 12, 36, colW, 14);
    _tempTitleLabel.frame = CGRectMake(12 + colW + 12, 50, colW, 12);

    // 底行胶囊
    _bottomCapsule.frame = CGRectMake(12, 66, w, 24);
    _currentLabel.frame = CGRectMake(8, 3, colW, 18);
    _statusLabel.frame = CGRectMake(w - colW - 8, 3, colW, 18);
}

- (void)updateDataWithCPU:(double)cpu battery:(NSInteger)battery temp:(double)temp current:(double)current {
    _cpuValueLabel.text = [NSString stringWithFormat:@"%.1f%%", cpu];
    _cpuValueLabel.textColor = (cpu >= 80.0) ? [UIColor systemRedColor] : [UIColor colorWithRed:0.2f green:0.9f blue:0.5f alpha:1.0f];

    _batteryValueLabel.text = [NSString stringWithFormat:@"🔋 %ld%%", (long)battery];
    _tempValueLabel.text = [NSString stringWithFormat:@"🌡 %.1f°C", temp];
    _currentLabel.text = [NSString stringWithFormat:@"⚡ %.0fmA", current];
}

@end

#pragma mark - 全局变量声明
static UIWindow *cpuWindow = nil;
static SBCPUFloatingView *floatingView = nil;
@class SBCPUDragView;
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

static CGRect keyboardBeforeFrame;
static BOOL keyboardMoved = NO;

// 前置函数声明
static void openSettings(void);
static void checkHighCPU(double cpu);

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

#pragma mark - 可穿透 Window 逻辑
@interface SBCPUWindow : UIWindow
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
            if (subview != floatingView && [subview isKindOfClass:NSClassFromString(@"SBCPUDragView")]) {
                CGRect frame = [subview.superview convertRect:subview.frame toView:self];
                if (CGRectContainsPoint(frame, point)) return subview;
            }
        }
    }
    return nil;
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

    floatingView = [[SBCPUFloatingView alloc] initWithFrame:CGRectMake(20, 160, 205, 100)];

    cpuDragView = [[SBCPUDragView alloc] initWithFrame:floatingView.frame];
    cpuDragView.backgroundColor = UIColor.clearColor;
    cpuDragView.userInteractionEnabled = YES;
    cpuDragView.multipleTouchEnabled = NO;

    [cpuWindow.rootViewController.view addSubview:floatingView];
    [cpuWindow.rootViewController.view addSubview:cpuDragView];

    UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:[SBCPUAction class] action:@selector(doubleTapAction)];
    doubleTap.numberOfTapsRequired = 2;
    [cpuDragView addGestureRecognizer:doubleTap];
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

#pragma mark - 定时数据刷新
static void updateCPU() {
    double cpu = getCPUUsage();
    checkHighCPU(cpu);

    dispatch_async(dispatch_get_main_queue(), ^{
        if (!floatingView) return;

        [UIDevice currentDevice].batteryMonitoringEnabled = YES;
        NSInteger battery = (NSInteger)([UIDevice currentDevice].batteryLevel * 100);
        if (battery < 0) battery = 100;

        [floatingView updateDataWithCPU:cpu battery:battery temp:36.8 current:-775];
    });
}

#pragma mark - 卡片式设置主控制器 (1:1 忠实复刻设计图)
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

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 3; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 3; // 自动控制
    if (section == 1) return 4; // 悬浮窗外观
    return 3;                   // 智能选项
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"⚡ 自动控制";
    if (section == 1) return @"🔲 悬浮窗外观";
    return @"🧠 智能选项";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];

    if (indexPath.section == 0) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"自动注销";
            cell.detailTextLabel.text = @"当 CPU 触发值达到设定值时自动注销";
            UISwitch *sw = [UISwitch new];
            sw.on = autoLogoutEnable;
            cell.accessoryView = sw;
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"CPU 触发值";
            cell.detailTextLabel.text = @"达到此百分比时触发";
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        } else if (indexPath.row == 2) {
            cell.textLabel.text = @"持续时间";
            cell.detailTextLabel.text = @"持续达到触发值的时间";
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }
    } else if (indexPath.section == 1) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"透明度开关";
            cell.detailTextLabel.text = @"启用透明背景效果";
            UISwitch *sw = [UISwitch new];
            sw.on = floatingAlphaEnable;
            cell.accessoryView = sw;
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"透明度";
            cell.detailTextLabel.text = @"悬浮窗背景透明度";
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        } else if (indexPath.row == 2) {
            cell.textLabel.text = @"浮窗大小";
            UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(0,0,130,30)];
            slider.minimumValue = 0.4; slider.maximumValue = 1.6; slider.value = floatingScale;
            cell.accessoryView = slider;
        } else if (indexPath.row == 3) {
            cell.textLabel.text = @"字体大小";
            UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(0,0,130,30)];
            slider.minimumValue = 8.0; slider.maximumValue = 15.0; slider.value = floatingFontSize;
            cell.accessoryView = slider;
        }
    } else if (indexPath.section == 2) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"键盘避让";
            cell.detailTextLabel.text = @"自动避开键盘区域";
            UISwitch *sw = [UISwitch new];
            sw.on = keyboardAvoidEnable;
            cell.accessoryView = sw;
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"智能吸附";
            cell.detailTextLabel.text = @"拖动到边缘自动吸附";
            UISwitch *sw = [UISwitch new];
            sw.on = smartDockEnable;
            cell.accessoryView = sw;
        } else if (indexPath.row == 2) {
            cell.textLabel.text = @"吸附模式";
            cell.detailTextLabel.text = @"选择吸附方式";
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }
    }
    return cell;
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

#pragma mark - Tweak 入口 (%ctor)
%ctor {
    NSString *processName = [NSProcessInfo processInfo].processName;
    if ([processName isEqualToString:@"SpringBoard"]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            createCPUWindow();

            [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *timer) {
                updateCPU();
            }];
        });
    }
}

