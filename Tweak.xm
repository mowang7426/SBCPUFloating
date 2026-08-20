#import <UIKit/UIKit.h>
#import <mach/mach.h>
#import <signal.h>

#pragma mark - V1.5.5 全局

static UIWindow *cpuWindow;
static UILabel *label;

/*
 * 记录打开设置前原来的 Key Window。
 * 设置关闭后恢复，避免悬浮窗长期占用 Key Window。
 */
static __weak UIWindow *previousKeyWindow;

/* 设置页面提前声明 */
static void openSettings(void);

#pragma mark - 自动注销配置

static BOOL autoLogoutEnable = NO;

static double logoutCPUThreshold = 100.0;

static NSInteger logoutDuration = 60;

static NSDate *cpuHighStartTime = nil;

static BOOL logoutCounting = NO;

#pragma mark - V1.5.4 悬浮窗透明度

static BOOL floatingAlphaEnable = YES;

/* 透明度范围：0.20 ~ 1.00 */
static CGFloat floatingAlpha = 0.70f;

#pragma mark - 获取真实 SpringBoard CPU

static double getCPUUsage()
{
    thread_array_t threads;
    mach_msg_type_number_t threadCount = 0;

    kern_return_t kr =
    task_threads(
        mach_task_self(),
        &threads,
        &threadCount
    );

    if(kr != KERN_SUCCESS)
    {
        return 0;
    }

    double total = 0;

    for(int i = 0;
        i < threadCount;
        i++)
    {
        thread_info_data_t info;

        mach_msg_type_number_t count =
        THREAD_INFO_MAX;

        kr =
        thread_info(
            threads[i],
            THREAD_BASIC_INFO,
            (thread_info_t)info,
            &count
        );

        if(kr == KERN_SUCCESS)
        {
            thread_basic_info_t basic =
            (thread_basic_info_t)info;

            if(!(basic->flags & TH_FLAGS_IDLE))
            {
                total +=
                (double)basic->cpu_usage /
                TH_USAGE_SCALE *
                100.0;
            }
        }
    }

    vm_deallocate(
        mach_task_self(),
        (vm_address_t)threads,
        threadCount * sizeof(thread_t)
    );

    return total;
}

#pragma mark - 应用悬浮窗透明度

static void applyFloatingAlpha()
{
    dispatch_async(
        dispatch_get_main_queue(),
        ^{
            if(!label)
            {
                return;
            }

            if(floatingAlphaEnable)
            {
                label.alpha = floatingAlpha;
            }
            else
            {
                label.alpha = 1.0;
            }
        }
    );
}

#pragma mark - 自动注销检测

static void checkHighCPU(double cpu)
{
    if(!autoLogoutEnable)
    {
        cpuHighStartTime = nil;
        logoutCounting = NO;
        return;
    }

    if(cpu < logoutCPUThreshold)
    {
        cpuHighStartTime = nil;
        logoutCounting = NO;
        return;
    }

    if(cpuHighStartTime == nil)
    {
        cpuHighStartTime = [NSDate date];
        return;
    }

    NSTimeInterval time =
    [[NSDate date]
     timeIntervalSinceDate:
     cpuHighStartTime];

    if(time >= logoutDuration &&
       !logoutCounting)
    {
        logoutCounting = YES;

        dispatch_async(
            dispatch_get_main_queue(),
            ^{
                UIAlertController *alert =
                [UIAlertController
                 alertControllerWithTitle:
                 @"SpringBoard CPU过高"
                 message:
                 @"5秒后自动注销"
                 preferredStyle:
                 UIAlertControllerStyleAlert];

                UIAlertAction *cancel =
                [UIAlertAction
                 actionWithTitle:
                 @"取消"
                 style:
                 UIAlertActionStyleCancel
                 handler:
                 ^(UIAlertAction *action)
                 {
                    logoutCounting = NO;
                    cpuHighStartTime = nil;
                 }];

                [alert addAction:cancel];

                if(cpuWindow.rootViewController)
                {
                    [cpuWindow.rootViewController
                     presentViewController:
                     alert
                     animated:YES
                     completion:nil];
                }

                dispatch_after(
                    dispatch_time(
                        DISPATCH_TIME_NOW,
                        5 * NSEC_PER_SEC
                    ),
                    dispatch_get_main_queue(),
                    ^{
                        if(logoutCounting)
                        {
                            kill(getpid(), SIGTERM);
                        }
                    }
                );
            }
        );
    }
}

#pragma mark - 拖动视图

@interface SBCPUDragView : UIView

@property(nonatomic,assign) CGPoint lastPoint;

@end

@implementation SBCPUDragView

- (void)touchesBegan:(NSSet *)touches
           withEvent:(UIEvent *)event
{
    UITouch *touch =
    [touches anyObject];

    self.lastPoint =
    [touch locationInView:self.superview];
}

- (void)touchesMoved:(NSSet *)touches
           withEvent:(UIEvent *)event
{
    UITouch *touch =
    [touches anyObject];

    CGPoint now =
    [touch locationInView:self.superview];

    CGFloat dx =
    now.x - self.lastPoint.x;

    CGFloat dy =
    now.y - self.lastPoint.y;

    CGPoint center =
    label.center;

    center.x += dx;
    center.y += dy;

    CGSize size =
    UIScreen.mainScreen.bounds.size;

    CGFloat halfW =
    label.bounds.size.width / 2;

    CGFloat halfH =
    label.bounds.size.height / 2;

    if(center.x < halfW)
        center.x = halfW;

    if(center.x > size.width - halfW)
        center.x = size.width - halfW;

    if(center.y < halfH + 40)
        center.y = halfH + 40;

    if(center.y > size.height - halfH)
        center.y = size.height - halfH;

    label.center = center;
    self.center = center;

    self.lastPoint = now;
}

@end

#pragma mark - Window

@interface SBCPUWindow : UIWindow
@end

@implementation SBCPUWindow
@end

#pragma mark - 双击处理

@interface SBCPUAction : NSObject
@end

@implementation SBCPUAction

+ (void)doubleTapAction
{
    openSettings();
}

@end

#pragma mark - 创建浮窗

static void createCPUWindow()
{
    cpuWindow =
    [[SBCPUWindow alloc]
     initWithFrame:
     UIScreen.mainScreen.bounds];

    for(UIScene *scene in
        UIApplication.sharedApplication.connectedScenes)
    {
        if([scene isKindOfClass:
            UIWindowScene.class])
        {
            cpuWindow.windowScene =
            (UIWindowScene *)scene;

            break;
        }
    }

    cpuWindow.windowLevel =
    UIWindowLevelAlert + 1;

    cpuWindow.backgroundColor =
    UIColor.clearColor;

    cpuWindow.rootViewController =
    [UIViewController new];

    cpuWindow.hidden = NO;

    label =
    [[UILabel alloc]
     initWithFrame:
     CGRectMake(30,200,100,50)];

    label.backgroundColor =
    [[UIColor blackColor]
     colorWithAlphaComponent:0.7];

    label.textAlignment =
    NSTextAlignmentCenter;

    label.numberOfLines = 2;

    label.layer.cornerRadius = 12;

    label.clipsToBounds = YES;

    label.textColor =
    UIColor.whiteColor;

    label.font =
    [UIFont
     monospacedDigitSystemFontOfSize:14
     weight:UIFontWeightBold];

    label.text =
    @"SB CPU\n0%";

    /*
     V1.5.3 稳定拖动层
     */
    SBCPUDragView *drag =
    [[SBCPUDragView alloc]
     initWithFrame:
     label.frame];

    drag.backgroundColor =
    UIColor.clearColor;

    drag.userInteractionEnabled = YES;

    [cpuWindow.rootViewController.view
     addSubview:label];

    [cpuWindow.rootViewController.view
     addSubview:drag];

    /*
     V1.5.3 双击设置
     */
    UITapGestureRecognizer *doubleTap =
    [[UITapGestureRecognizer alloc]
     initWithTarget:
     [SBCPUAction class]
     action:
     @selector(doubleTapAction)];

    doubleTap.numberOfTapsRequired = 2;

    [drag addGestureRecognizer:doubleTap];

    drag.userInteractionEnabled = YES;

    /*
     V1.5.4 透明度
     */
    applyFloatingAlpha();
}

#pragma mark - 设置页面

@interface SBCPUSettingsController : UITableViewController
@end

@implementation SBCPUSettingsController

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.title =
    @"SBCPUFloating 设置";

    /*
     V1.5.5
     增加完成按钮。
     */
    self.navigationItem.rightBarButtonItem =
    [[UIBarButtonItem alloc]
     initWithBarButtonSystemItem:
     UIBarButtonSystemItemDone
     target:self
     action:@selector(closeSettings)];
}

#pragma mark - 关闭设置

- (void)closeSettings
{
    /*
     先关闭设置页面。
     */
    [self dismissViewControllerAnimated:YES
                             completion:
     ^{
         /*
          恢复打开设置之前的 Key Window。
          */
         if(previousKeyWindow &&
            previousKeyWindow != cpuWindow)
         {
             [previousKeyWindow makeKeyWindow];
         }

         previousKeyWindow = nil;
     }];
}

#pragma mark - 行数

- (NSInteger)tableView:(UITableView *)tableView
 numberOfRowsInSection:(NSInteger)section
{
    return 5;
}

#pragma mark - 标题

- (NSString *)tableView:(UITableView *)tableView
 titleForHeaderInSection:(NSInteger)section
{
    return @"自动注销 / 悬浮窗设置";
}

#pragma mark - Cell

- (UITableViewCell *)tableView:(UITableView *)tableView
 cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell =
    [[UITableViewCell alloc]
     initWithStyle:
     UITableViewCellStyleValue1
     reuseIdentifier:nil];

    /*
     自动注销
     */
    if(indexPath.row == 0)
    {
        cell.textLabel.text =
        @"自动注销";

        UISwitch *sw =
        [[UISwitch alloc] init];

        sw.on =
        autoLogoutEnable;

        [sw addTarget:self
               action:@selector(changeSwitch:)
     forControlEvents:UIControlEventValueChanged];

        cell.accessoryView =
        sw;
    }

    /*
     CPU触发值
     */
    if(indexPath.row == 1)
    {
        cell.textLabel.text =
        @"CPU触发值";

        cell.detailTextLabel.text =
        [NSString stringWithFormat:
         @"%.0f%%",
         logoutCPUThreshold];
    }

    /*
     持续时间
     */
    if(indexPath.row == 2)
    {
        cell.textLabel.text =
        @"持续时间";

        cell.detailTextLabel.text =
        [NSString stringWithFormat:
         @"%ld秒",
         (long)logoutDuration];
    }

    /*
     透明度开关
     */
    if(indexPath.row == 3)
    {
        cell.textLabel.text =
        @"悬浮窗透明度";

        UISwitch *sw =
        [[UISwitch alloc] init];

        sw.on =
        floatingAlphaEnable;

        [sw addTarget:self
               action:@selector(alphaSwitchChanged:)
     forControlEvents:UIControlEventValueChanged];

        cell.accessoryView =
        sw;
    }

    /*
     透明度滑动条
     */
    if(indexPath.row == 4)
    {
        cell.textLabel.text =
        @"透明度";

        cell.detailTextLabel.text =
        [NSString stringWithFormat:
         @"%.0f%%",
         floatingAlpha * 100.0];

        UISlider *slider =
        [[UISlider alloc]
         initWithFrame:
         CGRectMake(0,0,150,30)];

        slider.minimumValue =
        0.20f;

        slider.maximumValue =
        1.00f;

        slider.value =
        floatingAlpha;

        slider.enabled =
        floatingAlphaEnable;

        [slider addTarget:self
                   action:@selector(alphaSliderChanged:)
         forControlEvents:
         UIControlEventValueChanged];

        cell.accessoryView =
        slider;
    }

    return cell;
}

#pragma mark - 自动注销开关

- (void)changeSwitch:(UISwitch *)sw
{
    autoLogoutEnable =
    sw.isOn;

    [[NSUserDefaults standardUserDefaults]
     setBool:autoLogoutEnable
     forKey:@"SBCPU.AutoLogout"];

    [[NSUserDefaults standardUserDefaults]
     synchronize];
}

#pragma mark - 透明度开关

- (void)alphaSwitchChanged:(UISwitch *)sw
{
    floatingAlphaEnable =
    sw.isOn;

    [[NSUserDefaults standardUserDefaults]
     setBool:floatingAlphaEnable
     forKey:@"SBCPU.FloatingAlphaEnable"];

    [[NSUserDefaults standardUserDefaults]
     synchronize];

    NSIndexPath *path =
    [NSIndexPath
     indexPathForRow:4
     inSection:0];

    [self.tableView
     reloadRowsAtIndexPaths:
     @[path]
     withRowAnimation:
     UITableViewRowAnimationNone];

    applyFloatingAlpha();
}

#pragma mark - 透明度滑动条

- (void)alphaSliderChanged:(UISlider *)slider
{
    CGFloat value =
    slider.value;

    if(value < 0.20f)
    {
        value = 0.20f;
    }

    if(value > 1.00f)
    {
        value = 1.00f;
    }

    floatingAlpha =
    value;

    [[NSUserDefaults standardUserDefaults]
     setFloat:floatingAlpha
     forKey:@"SBCPU.FloatingAlpha"];

    [[NSUserDefaults standardUserDefaults]
     synchronize];

    /*
     不在滑动过程中 reloadRows。
     避免滑块因为 reload 而跳动。
     */
    cell.detailTextLabel.text =
    [NSString stringWithFormat:
     @"%.0f%%",
     floatingAlpha * 100.0];

    applyFloatingAlpha();
}

#pragma mark - 设置项目点击

- (void)tableView:(UITableView *)tableView
 didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    /*
     CPU触发值
     */
    if(indexPath.row == 1)
    {
        UIAlertController *alert =
        [UIAlertController
         alertControllerWithTitle:
         @"CPU触发值"
         message:
         @"范围 80-200"
         preferredStyle:
         UIAlertControllerStyleAlert];

        [alert addTextFieldWithConfigurationHandler:
         ^(UITextField *tf)
         {
            tf.text =
            [NSString stringWithFormat:
             @"%.0f",
             logoutCPUThreshold];

            /*
             V1.5.5
             数字键盘。
             */
            tf.keyboardType =
            UIKeyboardTypeDecimalPad;

            tf.clearButtonMode =
            UITextFieldViewModeWhileEditing;
         }];

        UIAlertAction *ok =
        [UIAlertAction
         actionWithTitle:
         @"保存"
         style:
         UIAlertActionStyleDefault
         handler:
         ^(UIAlertAction *a)
         {
            double value =
            [alert.textFields[0].text
             doubleValue];

            if(value < 80)
                value = 80;

            if(value > 200)
                value = 200;

            logoutCPUThreshold =
            value;

            [[NSUserDefaults standardUserDefaults]
             setDouble:value
             forKey:@"SBCPU.CPUThreshold"];

            [[NSUserDefaults standardUserDefaults]
             synchronize];

            [self.tableView reloadData];
         }];

        [alert addAction:ok];

        UIAlertAction *cancel =
        [UIAlertAction
         actionWithTitle:
         @"取消"
         style:
         UIAlertActionStyleCancel
         handler:nil];

        [alert addAction:cancel];

        [self presentViewController:
         alert
         animated:YES
         completion:
         ^{
             /*
              V1.5.5
              强制让输入框成为第一响应者。
              */
             UITextField *tf =
             alert.textFields.firstObject;

             [tf becomeFirstResponder];
         }];
    }

    /*
     持续时间
     */
    if(indexPath.row == 2)
    {
        UIAlertController *alert =
        [UIAlertController
         alertControllerWithTitle:
         @"持续时间"
         message:
         @"范围 10-600秒"
         preferredStyle:
         UIAlertControllerStyleAlert];

        [alert addTextFieldWithConfigurationHandler:
         ^(UITextField *tf)
         {
            tf.text =
            [NSString stringWithFormat:
             @"%ld",
             (long)logoutDuration];

            /*
             V1.5.5
             数字键盘。
             */
            tf.keyboardType =
            UIKeyboardTypeNumberPad;

            tf.clearButtonMode =
            UITextFieldViewModeWhileEditing;
         }];

        UIAlertAction *ok =
        [UIAlertAction
         actionWithTitle:
         @"保存"
         style:
         UIAlertActionStyleDefault
         handler:
         ^(UIAlertAction *a)
         {
            NSInteger value =
            [alert.textFields[0].text
             integerValue];

            if(value < 10)
                value = 10;

            if(value > 600)
                value = 600;

            logoutDuration =
            value;

            [[NSUserDefaults standardUserDefaults]
             setInteger:value
             forKey:@"SBCPU.LogoutTime"];

            [[NSUserDefaults standardUserDefaults]
             synchronize];

            [self.tableView reloadData];
         }];

        [alert addAction:ok];

        UIAlertAction *cancel =
        [UIAlertAction
         actionWithTitle:
         @"取消"
         style:
         UIAlertActionStyleCancel
         handler:nil];

        [alert addAction:cancel];

        [self presentViewController:
         alert
         animated:YES
         completion:
         ^{
             /*
              V1.5.5
              强制弹出数字键盘。
              */
             UITextField *tf =
             alert.textFields.firstObject;

             [tf becomeFirstResponder];
         }];
    }
}

@end

#pragma mark - 打开设置

static void openSettings()
{
    if(!cpuWindow)
    {
        return;
    }

    /*
     V1.5.5 核心修复
     -------------------------
     保存当前 Key Window。
     */
    previousKeyWindow =
    [UIApplication.sharedApplication.keyWindow
     isEqual:cpuWindow]
     ? nil
     : UIApplication.sharedApplication.keyWindow;

    /*
     让悬浮窗暂时成为 Key Window。
     
     这样 UIAlertController 中的
     UITextField 才可以正常调用系统键盘。
     */
    [cpuWindow makeKeyAndVisible];

    SBCPUSettingsController *vc =
    [[SBCPUSettingsController alloc]
     initWithStyle:
     UITableViewStyleInsetGrouped];

    UINavigationController *nav =
    [[UINavigationController alloc]
     initWithRootViewController:vc];

    [cpuWindow.rootViewController
     presentViewController:
     nav
     animated:YES
     completion:nil];
}

#pragma mark - CPU刷新

static void updateCPU()
{
    double cpu =
    getCPUUsage();

    checkHighCPU(cpu);

    dispatch_async(
        dispatch_get_main_queue(),
        ^{
            if(!label)
            {
                return;
            }

            label.text =
            [NSString stringWithFormat:
             @"SB CPU\n%.1f%%",
             cpu];

            if(cpu >= 80)
            {
                label.textColor =
                UIColor.redColor;
            }
            else
            {
                label.textColor =
                UIColor.whiteColor;
            }
        }
    );
}

#pragma mark - 初始化

%ctor
{
    NSString *process =
    [[NSProcessInfo processInfo]
     processName];

    if(![process isEqualToString:@"SpringBoard"])
    {
        return;
    }

    NSUserDefaults *def =
    [NSUserDefaults standardUserDefaults];

    /*
     自动注销
     */
    autoLogoutEnable =
    [def boolForKey:
     @"SBCPU.AutoLogout"];

    double cpu =
    [def doubleForKey:
     @"SBCPU.CPUThreshold"];

    if(cpu >= 80)
    {
        logoutCPUThreshold =
        cpu;
    }

    NSInteger time =
    [def integerForKey:
     @"SBCPU.LogoutTime"];

    if(time >= 10)
    {
        logoutDuration =
        time;
    }

    /*
     透明度开关
     */
    if([def objectForKey:
        @"SBCPU.FloatingAlphaEnable"] != nil)
    {
        floatingAlphaEnable =
        [def boolForKey:
         @"SBCPU.FloatingAlphaEnable"];
    }

    /*
     透明度
     */
    CGFloat savedAlpha =
    [def floatForKey:
     @"SBCPU.FloatingAlpha"];

    if(savedAlpha >= 0.20f &&
       savedAlpha <= 1.00f)
    {
        floatingAlpha =
        savedAlpha;
    }

    /*
     延迟创建悬浮窗
     */
    dispatch_after(
        dispatch_time(
            DISPATCH_TIME_NOW,
            5 * NSEC_PER_SEC
        ),
        dispatch_get_main_queue(),
        ^{
            createCPUWindow();

            [NSTimer
             scheduledTimerWithTimeInterval:
             1.0
             repeats:YES
             block:^(NSTimer *timer)
             {
                updateCPU();
             }];
        }
    );
}
