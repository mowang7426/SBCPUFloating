#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <mach/mach.h>
#import <signal.h>


#pragma mark - V1.5.5 全局

static UIWindow *cpuWindow;

static UIWindow *settingsWindow;

static UILabel *label;


/*
 * 设置打开之前的 Key Window
 */
static __weak UIWindow *previousKeyWindow;


/*
 * 设置页面提前声明
 */
static void openSettings(void);


#pragma mark - 自动注销配置

static BOOL autoLogoutEnable = NO;

static double logoutCPUThreshold = 100.0;

static NSInteger logoutDuration = 60;

static NSDate *cpuHighStartTime = nil;

static BOOL logoutCounting = NO;


#pragma mark - V1.5.4 悬浮窗透明度

static BOOL floatingAlphaEnable = YES;


/*
 * 透明度范围：
 *
 * 0.20 ~ 1.00
 */
static CGFloat floatingAlpha = 0.70f;


#pragma mark - 获取当前 Key Window

static UIWindow *getCurrentKeyWindow(void)
{
    UIApplication *app =
    [UIApplication sharedApplication];


    /*
     iOS 13+
     不使用已经废弃的 keyWindow。
     */

    for(UIScene *scene in app.connectedScenes)
    {
        if(![scene isKindOfClass:UIWindowScene.class])
        {
            continue;
        }


        UIWindowScene *windowScene =
        (UIWindowScene *)scene;


        if(windowScene.activationState ==
           UISceneActivationStateUnattached)
        {
            continue;
        }


        for(UIWindow *window in windowScene.windows)
        {
            if(window.isKeyWindow)
            {
                return window;
            }
        }
    }


    return nil;
}


#pragma mark - 获取 WindowScene

static UIWindowScene *getWindowScene(void)
{
    /*
     优先使用悬浮窗自己的 Scene
     */

    if(cpuWindow &&
       cpuWindow.windowScene)
    {
        return cpuWindow.windowScene;
    }


    /*
     如果悬浮窗不存在，
     从当前连接的 Scene 中寻找。
     */

    UIApplication *app =
    [UIApplication sharedApplication];


    for(UIScene *scene in app.connectedScenes)
    {
        if([scene isKindOfClass:UIWindowScene.class])
        {
            UIWindowScene *windowScene =
            (UIWindowScene *)scene;


            if(windowScene.activationState !=
               UISceneActivationStateUnattached)
            {
                return windowScene;
            }
        }
    }


    return nil;
}


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
                label.alpha =
                floatingAlpha;
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
        cpuHighStartTime =
        [NSDate date];

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
                if(!cpuWindow)
                {
                    logoutCounting = NO;

                    return;
                }


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


                UIViewController *root =
                cpuWindow.rootViewController;


                if(root)
                {
                    [root
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

@property(nonatomic,assign)
CGPoint lastPoint;

@end


@implementation SBCPUDragView


- (void)touchesBegan:(NSSet *)touches
           withEvent:(UIEvent *)event
{
    UITouch *touch =
    [touches anyObject];


    self.lastPoint =
    [touch locationInView:
     self.superview];
}


- (void)touchesMoved:(NSSet *)touches
           withEvent:(UIEvent *)event
{
    UITouch *touch =
    [touches anyObject];


    CGPoint now =
    [touch locationInView:
     self.superview];


    CGFloat dx =
    now.x -
    self.lastPoint.x;


    CGFloat dy =
    now.y -
    self.lastPoint.y;


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
    {
        center.x = halfW;
    }


    if(center.x >
       size.width - halfW)
    {
        center.x =
        size.width - halfW;
    }


    if(center.y <
       halfH + 40)
    {
        center.y =
        halfH + 40;
    }


    if(center.y >
       size.height - halfH)
    {
        center.y =
        size.height - halfH;
    }


    label.center =
    center;


    self.center =
    center;


    self.lastPoint =
    now;
}


@end


#pragma mark - CPU Window

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


#pragma mark - 创建悬浮窗

static void createCPUWindow()
{
    cpuWindow =
    [[SBCPUWindow alloc]
     initWithFrame:
     UIScreen.mainScreen.bounds];


    UIWindowScene *windowScene =
    getWindowScene();


    if(windowScene)
    {
        cpuWindow.windowScene =
        windowScene;
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
     CGRectMake(
         30,
         200,
         100,
         50
     )];


    label.backgroundColor =
    [[UIColor blackColor]
     colorWithAlphaComponent:0.7];


    label.textAlignment =
    NSTextAlignmentCenter;


    label.numberOfLines = 2;


    label.layer.cornerRadius =
    12;


    label.clipsToBounds =
    YES;


    label.textColor =
    UIColor.whiteColor;


    label.font =
    [UIFont
     monospacedDigitSystemFontOfSize:
     14
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


    drag.userInteractionEnabled =
    YES;


    [cpuWindow.rootViewController.view
     addSubview:label];


    [cpuWindow.rootViewController.view
     addSubview:drag];


    /*
     双击设置
     */

    UITapGestureRecognizer *doubleTap =
    [[UITapGestureRecognizer alloc]
     initWithTarget:
     [SBCPUAction class]
     action:
     @selector(doubleTapAction)];


    doubleTap.numberOfTapsRequired =
    2;


    [drag addGestureRecognizer:
     doubleTap];


    drag.userInteractionEnabled =
    YES;


    /*
     V1.5.4 透明度
     */

    applyFloatingAlpha();
}


#pragma mark - 设置页面

@interface SBCPUSettingsController
    : UITableViewController
@end


@implementation SBCPUSettingsController


#pragma mark - ViewDidLoad

- (void)viewDidLoad
{
    [super viewDidLoad];


    self.title =
    @"SBCPUFloating 设置";


    /*
     V1.5.5
     完成按钮
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
     先让键盘退出
     */

    [self.view endEditing:YES];


    /*
     关闭设置窗口
     */

    [self dismissViewControllerAnimated:YES
                             completion:
     ^{
         /*
          隐藏独立设置 Window
          */

         settingsWindow.hidden =
         YES;


         /*
          恢复之前的 Key Window
          */

         if(previousKeyWindow &&
            previousKeyWindow !=
            settingsWindow)
         {
             [previousKeyWindow
              makeKeyWindow];
         }


         previousKeyWindow =
         nil;


         settingsWindow =
         nil;
     }];
}


#pragma mark - 行数

- (NSInteger)tableView:
    (UITableView *)tableView
    numberOfRowsInSection:
    (NSInteger)section
{
    return 5;
}


#pragma mark - Section 标题

- (NSString *)tableView:
    (UITableView *)tableView
    titleForHeaderInSection:
    (NSInteger)section
{
    return
    @"自动注销 / 悬浮窗设置";
}


#pragma mark - Cell

- (UITableViewCell *)tableView:
    (UITableView *)tableView
    cellForRowAtIndexPath:
    (NSIndexPath *)indexPath
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
     forControlEvents:
        UIControlEventValueChanged];


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
     悬浮窗透明度开关
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
     forControlEvents:
        UIControlEventValueChanged];


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
         CGRectMake(
             0,
             0,
             150,
             30
         )];


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
     不 reload cell。
     直接更新当前 Cell 的文字。
     */

    NSIndexPath *path =
    [NSIndexPath
     indexPathForRow:4
     inSection:0];


    UITableViewCell *cell =
    [self.tableView
     cellForRowAtIndexPath:path];


    if(cell)
    {
        cell.detailTextLabel.text =
        [NSString stringWithFormat:
         @"%.0f%%",
         floatingAlpha * 100.0];

        [cell.detailTextLabel
         setNeedsLayout];
    }


    applyFloatingAlpha();
}


#pragma mark - 点击设置项目

- (void)tableView:
    (UITableView *)tableView
    didSelectRowAtIndexPath:
    (NSIndexPath *)indexPath
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


        [alert
         addTextFieldWithConfigurationHandler:
         ^(UITextField *tf)
         {
            tf.text =
            [NSString stringWithFormat:
             @"%.0f",
             logoutCPUThreshold];


            /*
             使用数字键盘
             */

            tf.keyboardType =
            UIKeyboardTypeNumberPad;


            tf.clearButtonMode =
            UITextFieldViewModeWhileEditing;


            tf.enablesReturnKeyAutomatically =
            NO;
         }];


        UIAlertAction *cancel =
        [UIAlertAction
         actionWithTitle:
         @"取消"
         style:
         UIAlertActionStyleCancel
         handler:nil];


        UIAlertAction *ok =
        [UIAlertAction
         actionWithTitle:
         @"保存"
         style:
         UIAlertActionStyleDefault
         handler:
         ^(UIAlertAction *action)
         {
            double value =
            [alert.textFields.firstObject.text
             doubleValue];


            if(value < 80)
            {
                value = 80;
            }


            if(value > 200)
            {
                value = 200;
            }


            logoutCPUThreshold =
            value;


            [[NSUserDefaults standardUserDefaults]
             setDouble:value
             forKey:@"SBCPU.CPUThreshold"];


            [[NSUserDefaults standardUserDefaults]
             synchronize];


            [self.tableView
             reloadData];
         }];


        [alert addAction:cancel];

        [alert addAction:ok];


        /*
         先显示 Alert
         */

        [self presentViewController:
         alert
         animated:YES
         completion:
         ^{
             /*
              关键修复：
              等 Alert 完成显示之后，
              再强制唤起键盘。
              */

             dispatch_async(
                 dispatch_get_main_queue(),
                 ^{
                    UITextField *tf =
                    alert.textFields.firstObject;


                    if(tf)
                    {
                        [tf becomeFirstResponder];
                    }
                 }
             );
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


        [alert
         addTextFieldWithConfigurationHandler:
         ^(UITextField *tf)
         {
            tf.text =
            [NSString stringWithFormat:
             @"%ld",
             (long)logoutDuration];


            /*
             秒数使用数字键盘
             */

            tf.keyboardType =
            UIKeyboardTypeNumberPad;


            tf.clearButtonMode =
            UITextFieldViewModeWhileEditing;


            tf.enablesReturnKeyAutomatically =
            NO;
         }];


        UIAlertAction *cancel =
        [UIAlertAction
         actionWithTitle:
         @"取消"
         style:
         UIAlertActionStyleCancel
         handler:nil];


        UIAlertAction *ok =
        [UIAlertAction
         actionWithTitle:
         @"保存"
         style:
         UIAlertActionStyleDefault
         handler:
         ^(UIAlertAction *action)
         {
            NSInteger value =
            [alert.textFields.firstObject.text
             integerValue];


            if(value < 10)
            {
                value = 10;
            }


            if(value > 600)
            {
                value = 600;
            }


            logoutDuration =
            value;


            [[NSUserDefaults standardUserDefaults]
             setInteger:value
             forKey:@"SBCPU.LogoutTime"];


            [[NSUserDefaults standardUserDefaults]
             synchronize];


            [self.tableView
             reloadData];
         }];


        [alert addAction:cancel];

        [alert addAction:ok];


        /*
         先显示 Alert
         */

        [self presentViewController:
         alert
         animated:YES
         completion:
         ^{
             /*
              关键修复：
              延迟一个 RunLoop，
              确保 Alert 已经进入 Window。
              */

             dispatch_async(
                 dispatch_get_main_queue(),
                 ^{
                    UITextField *tf =
                    alert.textFields.firstObject;


                    if(tf)
                    {
                        [tf becomeFirstResponder];
                    }
                 }
             );
         }];
    }


    [tableView deselectRowAtIndexPath:
     indexPath
     animated:YES];
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
     如果已经有设置窗口，
     不重复创建。
     */

    if(settingsWindow)
    {
        return;
    }


    /*
     保存当前真正的 Key Window。
     */

    previousKeyWindow =
    getCurrentKeyWindow();


    /*
     创建独立设置 Window
     */

    UIWindowScene *windowScene =
    getWindowScene();


    if(!windowScene)
    {
        previousKeyWindow = nil;

        return;
    }


    settingsWindow =
    [[UIWindow alloc]
     initWithWindowScene:
     windowScene];


    /*
     使用正常可交互的 Window 层级。
     */

    settingsWindow.windowLevel =
    UIWindowLevelAlert + 2;


    settingsWindow.backgroundColor =
    UIColor.systemBackgroundColor;


    /*
     独立设置 Root VC
     */

    SBCPUSettingsController *vc =
    [[SBCPUSettingsController alloc]
     initWithStyle:
     UITableViewStyleInsetGrouped];


    UINavigationController *nav =
    [[UINavigationController alloc]
     initWithRootViewController:vc];


    settingsWindow.rootViewController =
    nav;


    /*
     关键：
     设置 Window 主动成为 Key Window。
     
     键盘输入依赖这个 Window。
     */

    settingsWindow.hidden =
    NO;


    [settingsWindow
     makeKeyAndVisible];


    /*
     强制布局
     */

    [settingsWindow layoutIfNeeded];


    [nav.view layoutIfNeeded];
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


    /*
     只运行在 SpringBoard
     */

    if(![process
         isEqualToString:
         @"SpringBoard"])
    {
        return;
    }


    NSUserDefaults *def =
    [NSUserDefaults standardUserDefaults];


    #pragma mark 自动注销

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


    #pragma mark 透明度开关

    if([def objectForKey:
        @"SBCPU.FloatingAlphaEnable"]
       != nil)
    {
        floatingAlphaEnable =
        [def boolForKey:
         @"SBCPU.FloatingAlphaEnable"];
    }


    #pragma mark 透明度

    CGFloat savedAlpha =
    [def floatForKey:
     @"SBCPU.FloatingAlpha"];


    if(savedAlpha >= 0.20f &&
       savedAlpha <= 1.00f)
    {
        floatingAlpha =
        savedAlpha;
    }


    #pragma mark 延迟创建

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
             block:
             ^(NSTimer *timer)
             {
                updateCPU();
             }];
        }
    );
}
