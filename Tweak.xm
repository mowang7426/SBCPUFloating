#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <mach/mach.h>
#import <signal.h>


#pragma mark -
#pragma mark V1.5.8 Global
#pragma mark -


static UIWindow *cpuWindow;

@class SBCPUDragView;

static UILabel *label;
static CGFloat floatingScale = 1.0;
static CGFloat floatingFontSize = 14.0;
static CGFloat landscapeScale = 0.75;
static CGFloat batteryFontSize = 12.0;
static CGFloat landscapeFontSize = 12.0;
static SBCPUDragView *cpuDragView;


/*
 设置页面是否正在显示
 */
static BOOL settingsShowing = NO;


/*
 自动注销
 */
static BOOL autoLogoutEnable = NO;

static double logoutCPUThreshold = 100.0;

static NSInteger logoutDuration = 60;

static NSDate *cpuHighStartTime = nil;

static BOOL logoutCounting = NO;

/*
 SpringBoard异常检测 V1.6.0 Alpha
 */
static double anomalyCPUThreshold = 90.0;
static NSInteger anomalyDuration = 10;
static NSDate *anomalyStartTime = nil;
static BOOL anomalyTriggered = NO;
static NSMutableArray *anomalyLogs = nil;



/*
 透明度
 */
static BOOL floatingAlphaEnable = YES;

static CGFloat floatingAlpha = 0.70f;


/*
 前置声明
 */
static void openSettings(void);

static void checkHighCPU(double cpu);
static void checkAnomalyCPU(double cpu);


/*
 提前声明两个控制器
 避免 Objective-C 未声明错误
 */
@class SBCPUValuePickerController;
@class SBCPUTimePickerController;



#pragma mark -
#pragma mark 获取 WindowScene
#pragma mark -


static UIWindowScene *getWindowScene()
{

    if(cpuWindow &&
       cpuWindow.windowScene)
    {
        return cpuWindow.windowScene;
    }


    UIApplication *app =
    UIApplication.sharedApplication;


    for(UIScene *scene in app.connectedScenes)
    {

        if([scene
            isKindOfClass:
            UIWindowScene.class])
        {

            UIWindowScene *ws =
            (UIWindowScene *)scene;


            if(ws.activationState !=
               UISceneActivationStateUnattached)
            {

                return ws;

            }

        }

    }


    return nil;
}



#pragma mark -
#pragma mark CPU
#pragma mark -


static double getCPUUsage()
{

    thread_array_t threads;

    mach_msg_type_number_t count = 0;


    kern_return_t kr =
    task_threads(
        mach_task_self(),
        &threads,
        &count
    );


    if(kr != KERN_SUCCESS)
    {
        return 0;
    }


    double total = 0;


    for(mach_msg_type_number_t i = 0;
        i < count;
        i++)
    {

        thread_info_data_t info;

        mach_msg_type_number_t infoCount =
        THREAD_INFO_MAX;


        kr =
        thread_info(
            threads[i],
            THREAD_BASIC_INFO,
            (thread_info_t)info,
            &infoCount
        );


        if(kr == KERN_SUCCESS)
        {

            thread_basic_info_t basic =
            (thread_basic_info_t)info;


            if(!(basic->flags &
                 TH_FLAGS_IDLE))
            {

                total +=
                ((double)basic->cpu_usage /
                 TH_USAGE_SCALE)
                *
                100.0;

            }

        }

    }


    vm_deallocate(
        mach_task_self(),
        (vm_address_t)threads,
        count * sizeof(thread_t)
    );


    return total;
}



#pragma mark -
#pragma mark 透明度
#pragma mark -


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

                label.alpha =
                1.0;

            }

        }
    );

}



#pragma mark -
#pragma mark 可穿透 Window
#pragma mark -


@interface SBCPUWindow : UIWindow

@end



@implementation SBCPUWindow


/*
 V1.5.8 最关键的触摸修复

 浮窗 Window 本身是全屏的。

 如果不重写 hitTest：
 即使背景透明，
 Window 仍然可能把整个屏幕的触摸吃掉。

 现在：

 1. 设置页面打开：
    正常接收全部触摸。

 2. 设置页面关闭：
    只有浮窗区域接收触摸。

 3. 其他区域：
    返回 nil，让 SpringBoard 接收。
 */


- (UIView *)hitTest:
( CGPoint)point
withEvent:
(UIEvent *)event
{

    if(settingsShowing)
    {

        return
        [super hitTest:
         point
         withEvent:event];

    }


    UIView *view =
    [super hitTest:
     point
     withEvent:event];


    if(!view)
    {
        return nil;
    }


    /*
     只有 label / drag 区域接受事件
     */


    if([view isDescendantOfView:
        label])
    {
        return view;
    }


    UIView *root =
    self.rootViewController.view;


    if(root)
    {

        for(UIView *subview in root.subviews)
        {

            if(subview != label &&
               [subview isKindOfClass:
                NSClassFromString(@"SBCPUDragView")])
            {

                CGRect frame =
                [subview.superview
                 convertRect:
                 subview.frame
                 toView:self];

                if(CGRectContainsPoint(
                    frame,
                    point))
                {
                    return subview;
                }

            }

        }

    }


    /*
     浮窗以外全部穿透
     */

    return nil;
}


@end



#pragma mark -
#pragma mark 拖动层
#pragma mark -


@interface SBCPUDragView : UIView

@property(nonatomic,assign)
CGPoint lastPoint;

@end



@implementation SBCPUDragView


- (void)touchesBegan:
(NSSet *)touches
withEvent:
(UIEvent *)event
{

    UITouch *touch =
    touches.anyObject;


    if(!touch)
    {
        return;
    }


    self.lastPoint =
    [touch locationInView:
     self.superview];



    [super touchesBegan:
     touches
     withEvent:event];

}



- (void)touchesMoved:
(NSSet *)touches
withEvent:
(UIEvent *)event
{

    UITouch *touch =
    touches.anyObject;


    if(!touch)
    {
        return;
    }


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
    self.superview.bounds.size;


    CGFloat halfW =
    label.bounds.size.width / 2.0;


    CGFloat halfH =
    label.bounds.size.height / 2.0;


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


    if(center.y < halfH + 40)
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


    [super touchesMoved:
     touches
     withEvent:event];

}


@end



#pragma mark -
#pragma mark 双击
#pragma mark -


@interface SBCPUAction : NSObject

@end



@implementation SBCPUAction


+ (void)doubleTapAction
{

    openSettings();

}


@end



#pragma mark -
#pragma mark 创建悬浮窗
#pragma mark -


static void createCPUWindow()
{

    if(cpuWindow)
    {
        return;
    }


    UIWindowScene *scene =
    getWindowScene();


    if(!scene)
    {
        return;
    }


    cpuWindow =
    [[SBCPUWindow alloc]
     initWithFrame:
     UIScreen.mainScreen.bounds];


    cpuWindow.windowScene =
    scene;


    /*
     不使用 Alert+1
     */

    cpuWindow.windowLevel =
    UIWindowLevelStatusBar + 1;


    cpuWindow.backgroundColor =
    UIColor.clearColor;


    cpuWindow.opaque =
    NO;


    cpuWindow.rootViewController =
    [UIViewController new];


    cpuWindow.rootViewController.view
        .backgroundColor =
        UIColor.clearColor;


    cpuWindow.hidden =
    NO;



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
     colorWithAlphaComponent:0.70];


    label.textAlignment =
    NSTextAlignmentCenter;


    label.numberOfLines =
    3;


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
     拖动区域
     */

    cpuDragView =
    [[SBCPUDragView alloc]
     initWithFrame:
     label.frame];

    SBCPUDragView *drag = cpuDragView;


    drag.backgroundColor =
    UIColor.clearColor;


    drag.userInteractionEnabled =
    YES;


    drag.multipleTouchEnabled =
    NO;


    [cpuWindow.rootViewController.view
     addSubview:label];


    [cpuWindow.rootViewController.view
     addSubview:drag];



    /*
     双击
     */

    UITapGestureRecognizer *doubleTap =
    [[UITapGestureRecognizer alloc]
     initWithTarget:
     [SBCPUAction class]
     action:@selector(doubleTapAction)];


    doubleTap.numberOfTapsRequired =
    2;


    doubleTap.numberOfTouchesRequired =
    1;


    [drag addGestureRecognizer:
     doubleTap];


    applyFloatingAlpha();

}



#pragma mark -
#pragma mark 自动注销
#pragma mark -


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


    if(!cpuHighStartTime)
    {

        cpuHighStartTime =
        [NSDate date];

        return;

    }


    NSTimeInterval duration =
    [[NSDate date]
     timeIntervalSinceDate:
     cpuHighStartTime];


    if(duration >= logoutDuration &&
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


                UIViewController *root =
                cpuWindow.rootViewController;


                if(!root)
                {
                    logoutCounting = NO;
                    return;
                }


                /*
                 防止重复弹窗
                 */

                if(root.presentedViewController)
                {
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


                [alert addAction:
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

                  }]];


                [root
                 presentViewController:
                 alert
                 animated:YES
                 completion:nil];


                dispatch_after(
                    dispatch_time(
                        DISPATCH_TIME_NOW,
                        5 * NSEC_PER_SEC),
                    dispatch_get_main_queue(),
                    ^{

                        if(logoutCounting)
                        {

                            kill(
                                getpid(),
                                SIGTERM
                            );

                        }

                    });

            }
        );

    }

}





#pragma mark -
#pragma mark V1.6.0 SpringBoard异常检测
#pragma mark -

static void checkAnomalyCPU(double cpu)
{
    if(anomalyCPUThreshold <= 0)
    {
        return;
    }

    if(cpu >= anomalyCPUThreshold)
    {
        if(!anomalyStartTime)
        {
            anomalyStartTime = [NSDate date];
        }

        NSTimeInterval duration =
        [[NSDate date] timeIntervalSinceDate:anomalyStartTime];

        if(duration >= anomalyDuration && !anomalyTriggered)
        {
            anomalyTriggered = YES;

            if(!anomalyLogs)
            {
                anomalyLogs = [NSMutableArray array];
            }

            NSDictionary *log =
            @{
              @"time":
                  [NSDate date],
              @"cpu":
                  @(cpu),
              @"duration":
                  @(duration)
              };

            [anomalyLogs addObject:log];

            if(anomalyLogs.count > 20)
            {
                [anomalyLogs removeObjectAtIndex:0];
            }

            [[NSUserDefaults standardUserDefaults]
             setObject:anomalyLogs
             forKey:@"SBCPU.AnomalyLogs"];

            [[NSUserDefaults standardUserDefaults]
             synchronize];
        }
    }
    else
    {
        anomalyStartTime = nil;
        anomalyTriggered = NO;
    }
}


static BOOL isLandscapeMode()
{
    CGSize size = UIScreen.mainScreen.bounds.size;
    return size.width > size.height;
}


static NSInteger getBatteryPercent()
{
    UIDevice *device = [UIDevice currentDevice];
    device.batteryMonitoringEnabled = YES;

    float level = device.batteryLevel;

    if(level < 0)
    {
        return -1;
    }

    return (NSInteger)(level * 100.0f);
}


#pragma mark -
#pragma mark 横竖屏尺寸调整
#pragma mark -

static void updateFloatingSize()
{
    if(!label)
    {
        return;
    }

    BOOL landscape = isLandscapeMode();

    CGFloat scale = landscape ? landscapeScale : floatingScale;

    CGSize targetSize =
    landscape ?
    CGSizeMake(135 * scale, 58 * scale) :
    CGSizeMake(100 * scale, 48 * scale);

    if(!CGSizeEqualToSize(label.bounds.size, targetSize))
    {
        CGRect frame = label.frame;

        CGPoint center = label.center;

        frame.size = targetSize;

        label.frame = frame;

        label.center = center;

        if(cpuDragView)
        {
            cpuDragView.frame = label.frame;
        }

        label.layer.cornerRadius =
        landscape ? 18 : 12;

        [label setNeedsLayout];
    }
}


#pragma mark -
#pragma mark CPU刷新
#pragma mark -


static void updateCPU()
{

    double cpu =
    getCPUUsage();


    checkHighCPU(cpu);
    checkAnomalyCPU(cpu);


    dispatch_async(
        dispatch_get_main_queue(),
        ^{

            if(!label)
            {
                return;
            }

            updateFloatingSize();

            label.font =
            [UIFont systemFontOfSize:(isLandscapeMode() ? landscapeFontSize : floatingFontSize)];


            if(isLandscapeMode())
            {
                NSInteger battery = getBatteryPercent();

                if(battery >= 0)
                {
                    label.text =
                    [NSString stringWithFormat:
                     @"SB CPU %.1f%%\n电量 %ld%%",
                     cpu,
                     (long)battery];
                }
                else
                {
                    label.text =
                    [NSString stringWithFormat:
                     @"SB CPU\n%.1f%%",
                     cpu];
                }
            }
            else
            {
                label.text =
                [NSString stringWithFormat:
                 @"SB CPU\n%.1f%%",
                 cpu];
            }


            if(cpu >= 80.0)
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



#pragma mark -
#pragma mark CPU选择页面
#pragma mark -


@interface SBCPUValuePickerController :
UITableViewController

@end



@implementation SBCPUValuePickerController


- (NSInteger)tableView:
(UITableView *)tableView
numberOfRowsInSection:
(NSInteger)section
{

    return 11;

}


- (NSString *)tableView:
(UITableView *)tableView
titleForHeaderInSection:
(NSInteger)section
{

    return @"CPU触发值";

}


- (UITableViewCell *)tableView:
(UITableView *)tableView
cellForRowAtIndexPath:
(NSIndexPath *)indexPath
{

    UITableViewCell *cell =
    [[UITableViewCell alloc]
     initWithStyle:
     UITableViewCellStyleDefault
     reuseIdentifier:nil];


    NSArray *titles =
    @[
      @"80%",
      @"100%",
      @"120%",
      @"140%",
      @"160%",
      @"180%",
      @"200%"
    ];


    NSArray *values =
    @[
      @80,
      @100,
      @120,
      @140,
      @160,
      @180,
      @200
    ];


    cell.textLabel.text =
    titles[indexPath.row];


    if([values[indexPath.row] doubleValue]
       ==
       logoutCPUThreshold)
    {

        cell.accessoryType =
        UITableViewCellAccessoryCheckmark;

    }


    return cell;

}


- (void)tableView:
(UITableView *)tableView
didSelectRowAtIndexPath:
(NSIndexPath *)indexPath
{

    NSArray *values =
    @[
      @80,
      @100,
      @120,
      @140,
      @160,
      @180,
      @200
    ];


    logoutCPUThreshold =
    [values[indexPath.row] doubleValue];


    [[NSUserDefaults standardUserDefaults]
     setDouble:
     logoutCPUThreshold
     forKey:
     @"SBCPU.CPUThreshold"];


    [[NSUserDefaults standardUserDefaults]
     synchronize];


    [self.tableView reloadData];


    [self.navigationController
     popViewControllerAnimated:YES];

}


@end



#pragma mark -
#pragma mark 时间选择页面
#pragma mark -


@interface SBCPUTimePickerController :
UITableViewController

@end



@implementation SBCPUTimePickerController


- (NSInteger)tableView:
(UITableView *)tableView
numberOfRowsInSection:
(NSInteger)section
{

    return 9;

}


- (NSString *)tableView:
(UITableView *)tableView
titleForHeaderInSection:
(NSInteger)section
{

    return @"持续时间";

}


- (UITableViewCell *)tableView:
(UITableView *)tableView
cellForRowAtIndexPath:
(NSIndexPath *)indexPath
{

    UITableViewCell *cell =
    [[UITableViewCell alloc]
     initWithStyle:
     UITableViewCellStyleDefault
     reuseIdentifier:nil];


    NSArray *titles =
    @[
      @"10秒",
      @"30秒",
      @"60秒",
      @"120秒",
      @"180秒",
      @"300秒",
      @"600秒"
    ];


    NSArray *values =
    @[
      @10,
      @30,
      @60,
      @120,
      @180,
      @300,
      @600
    ];


    cell.textLabel.text =
    titles[indexPath.row];


    if([values[indexPath.row] integerValue]
       ==
       logoutDuration)
    {

        cell.accessoryType =
        UITableViewCellAccessoryCheckmark;

    }


    return cell;

}


- (void)tableView:
(UITableView *)tableView
didSelectRowAtIndexPath:
(NSIndexPath *)indexPath
{

    NSArray *values =
    @[
      @10,
      @30,
      @60,
      @120,
      @180,
      @300,
      @600
    ];


    logoutDuration =
    [values[indexPath.row] integerValue];


    [[NSUserDefaults standardUserDefaults]
     setInteger:
     logoutDuration
     forKey:
     @"SBCPU.LogoutTime"];


    [[NSUserDefaults standardUserDefaults]
     synchronize];


    [self.tableView reloadData];


    [self.navigationController
     popViewControllerAnimated:YES];

}


@end



#pragma mark -
#pragma mark 设置主页
#pragma mark -


@interface SBCPUSettingsController :
UITableViewController

@end



@implementation SBCPUSettingsController


- (void)viewDidLoad
{

    [super viewDidLoad];


    self.title =
    @"SBCPUFloating 设置";


    self.navigationItem.rightBarButtonItem =
    [[UIBarButtonItem alloc]
     initWithBarButtonSystemItem:
     UIBarButtonSystemItemDone
     target:self
     action:@selector(closeSettings)];

}


#pragma mark 关闭


- (void)closeSettings
{

    settingsShowing = NO;


    [self dismissViewControllerAnimated:YES
                             completion:
     ^{

         /*
          重新刷新 Window 触摸状态
          */

         [cpuWindow setNeedsLayout];

     }];

}


#pragma mark Table


- (NSInteger)tableView:
(UITableView *)tableView
numberOfRowsInSection:
(NSInteger)section
{

    return 7;

}


- (NSString *)tableView:
(UITableView *)tableView
titleForHeaderInSection:
(NSInteger)section
{

    return
    @"自动注销 / 悬浮窗";

}



#pragma mark 滑动调整

- (void)changeScaleSlider:(UISlider *)slider
{
    floatingScale = slider.value;
    [[NSUserDefaults standardUserDefaults] setFloat:floatingScale forKey:@"SBCPU.FloatingScale"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    updateFloatingSize();
    [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:5 inSection:0]] withRowAnimation:UITableViewRowAnimationNone];
}

- (void)changeFontSlider:(UISlider *)slider
{
    floatingFontSize = slider.value;
    [[NSUserDefaults standardUserDefaults] setFloat:floatingFontSize forKey:@"SBCPU.FloatingFontSize"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    if(label)
        label.font = [UIFont systemFontOfSize:floatingFontSize];
    [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:6 inSection:0]] withRowAnimation:UITableViewRowAnimationNone];
}

- (void)changeLandscapeScaleSlider:(UISlider *)slider
{
    // 横屏独立悬浮窗大小
    // 范围 60% - 120%，避免横屏显示电量时框体过大
    landscapeScale = MAX(0.6, MIN(1.2, slider.value));
    [[NSUserDefaults standardUserDefaults] setFloat:landscapeScale forKey:@"SBCPU.LandscapeScale"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    updateFloatingSize();
}

- (void)changeLandscapeFontSlider:(UISlider *)slider
{
    landscapeFontSize = slider.value;
    [[NSUserDefaults standardUserDefaults] setFloat:landscapeFontSize forKey:@"SBCPU.LandscapeFontSize"];
    if(label && isLandscapeMode())
    {
        label.font = [UIFont systemFontOfSize:landscapeFontSize];
    }
}

- (void)changeBatteryFontSlider:(UISlider *)slider
{
    batteryFontSize = slider.value;
    [[NSUserDefaults standardUserDefaults] setFloat:batteryFontSize forKey:@"SBCPU.BatteryFontSize"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    updateFloatingSize();
}

#pragma mark Cell


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


    if(indexPath.row == 0)
    {

        cell.textLabel.text =
        @"自动注销";


        UISwitch *sw =
        [[UISwitch alloc] init];


        sw.on =
        autoLogoutEnable;


        [sw addTarget:self
               action:@selector(changeLogout:)
     forControlEvents:
      UIControlEventValueChanged];


        cell.accessoryView =
        sw;

    }


    if(indexPath.row == 1)
    {

        cell.textLabel.text =
        @"CPU触发值";


        cell.detailTextLabel.text =
        [NSString
         stringWithFormat:
         @"%.0f%%",
         logoutCPUThreshold];

    }


    if(indexPath.row == 2)
    {

        cell.textLabel.text =
        @"持续时间";


        cell.detailTextLabel.text =
        [NSString
         stringWithFormat:
         @"%ld秒",
         (long)logoutDuration];

    }


    if(indexPath.row == 3)
    {

        cell.textLabel.text =
        @"透明度开关";


        UISwitch *sw =
        [[UISwitch alloc] init];


        sw.on =
        floatingAlphaEnable;


        [sw addTarget:self
               action:@selector(changeAlpha:)
     forControlEvents:
      UIControlEventValueChanged];


        cell.accessoryView =
        sw;

    }


    if(indexPath.row == 4)
    {

        cell.textLabel.text =
        @"透明度";


        cell.detailTextLabel.text =
        [NSString stringWithFormat:@"%.0f%%", floatingAlpha * 100.0];

    }

    if(indexPath.row == 5)
    {
        cell.textLabel.text = @"浮窗大小";

        UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(0,0,150,30)];
        slider.minimumValue = 0.8;
        slider.maximumValue = 1.5;
        slider.value = floatingScale;
        [slider addTarget:self action:@selector(changeScaleSlider:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = slider;
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%.0f%%", floatingScale * 100];
    }

    if(indexPath.row == 6)
    {
        cell.textLabel.text = @"字体大小";

        UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(0,0,150,30)];
        slider.minimumValue = 10;
        slider.maximumValue = 24;
        slider.value = floatingFontSize;
        [slider addTarget:self action:@selector(changeFontSlider:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = slider;
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%.0f", floatingFontSize];
    }



    if(indexPath.row == 7)
    {
        cell.textLabel.text = @"横屏浮窗大小";

        UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(0,0,150,30)];
        slider.minimumValue = 0.8;
        slider.maximumValue = 1.5;
        slider.value = landscapeScale;
        [slider addTarget:self action:@selector(changeLandscapeScaleSlider:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = slider;
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%.0f%%", landscapeScale * 100];
    }

    if(indexPath.row == 8)
    {
        cell.textLabel.text = @"电量字体大小";

        UISlider *landscapeFontSlider = [[UISlider alloc] initWithFrame:CGRectMake(0,0,150,30)];
        landscapeFontSlider.minimumValue = 8;
        landscapeFontSlider.maximumValue = 20;
        landscapeFontSlider.value = landscapeFontSize;
        [landscapeFontSlider addTarget:self action:@selector(changeLandscapeFontSlider:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = landscapeFontSlider;
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%.0f", landscapeFontSize];

    }

    if(indexPath.row == 9)
    {
        cell.textLabel.text = @"异常检测阈值";
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%.0f%%", anomalyCPUThreshold];
    }

    if(indexPath.row == 10)
    {
        cell.textLabel.text = @"异常持续时间";
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%ld秒", (long)anomalyDuration];
    }

    return cell;

}


#pragma mark 自动注销


- (void)changeLogout:
(UISwitch *)sw
{

    autoLogoutEnable =
    sw.isOn;


    [[NSUserDefaults standardUserDefaults]
     setBool:
     autoLogoutEnable
     forKey:
     @"SBCPU.AutoLogout"];


    [[NSUserDefaults standardUserDefaults]
     synchronize];

}


#pragma mark 透明度


- (void)changeAlpha:
(UISwitch *)sw
{

    floatingAlphaEnable =
    sw.isOn;


    [[NSUserDefaults standardUserDefaults]
     setBool:
     floatingAlphaEnable
     forKey:
     @"SBCPU.FloatingAlphaEnable"];


    [[NSUserDefaults standardUserDefaults]
     synchronize];


    applyFloatingAlpha();

}


#pragma mark 点击项目


- (void)tableView:
(UITableView *)tableView
didSelectRowAtIndexPath:
(NSIndexPath *)indexPath
{

    if(indexPath.row == 1)
    {

        SBCPUValuePickerController *vc =
        [[SBCPUValuePickerController alloc]
         initWithStyle:
         UITableViewStyleInsetGrouped];


        [self.navigationController
         pushViewController:
         vc
         animated:YES];

    }


    if(indexPath.row == 2)
    {

        SBCPUTimePickerController *vc =
        [[SBCPUTimePickerController alloc]
         initWithStyle:
         UITableViewStyleInsetGrouped];


        [self.navigationController
         pushViewController:
         vc
         animated:YES];

    }


    if(indexPath.row == 4)
    {

        UIAlertController *alert =
        [UIAlertController
         alertControllerWithTitle:
         @"透明度"
         message:
         @"选择悬浮窗透明度"
         preferredStyle:
         UIAlertControllerStyleActionSheet];


        NSArray *titles =
        @[
          @"20%",
          @"40%",
          @"60%",
          @"70%",
          @"80%",
          @"100%"
        ];


        NSArray *values =
        @[
          @0.2,
          @0.4,
          @0.6,
          @0.7,
          @0.8,
          @1.0
        ];


        for(NSInteger i = 0;
            i < titles.count;
            i++)
        {

            [alert addAction:
             [UIAlertAction
              actionWithTitle:
              titles[i]
              style:
              UIAlertActionStyleDefault
              handler:
              ^(UIAlertAction *action)
              {

                  floatingAlpha =
                  [values[i] floatValue];


                  [[NSUserDefaults standardUserDefaults]
                   setFloat:
                   floatingAlpha
                   forKey:
                   @"SBCPU.FloatingAlpha"];


                  [[NSUserDefaults standardUserDefaults]
                   synchronize];


                  applyFloatingAlpha();


                  [self.tableView reloadData];

              }]];

        }


        [alert addAction:
         [UIAlertAction
          actionWithTitle:
          @"取消"
          style:
          UIAlertActionStyleCancel
          handler:nil]];


        [self presentViewController:
         alert
         animated:YES
         completion:nil];

    }


    [tableView deselectRowAtIndexPath:
     indexPath
     animated:YES];

}


@end



#pragma mark -
#pragma mark 打开设置
#pragma mark -


static void openSettings()
{

    if(settingsShowing)
    {
        return;
    }


    if(!cpuWindow)
    {
        return;
    }


    UIViewController *root =
    cpuWindow.rootViewController;


    if(!root)
    {
        return;
    }


    /*
     防止重复打开
     */

    if(root.presentedViewController)
    {
        return;
    }


    settingsShowing = YES;


    SBCPUSettingsController *vc =
    [[SBCPUSettingsController alloc]
     initWithStyle:
     UITableViewStyleInsetGrouped];


    UINavigationController *nav =
    [[UINavigationController alloc]
     initWithRootViewController:vc];


    /*
     设置页面期间允许整个 Window 接收触摸
     */

    nav.modalPresentationStyle =
    UIModalPresentationFullScreen;


    [root
     presentViewController:
     nav
     animated:YES
     completion:nil];

}



#pragma mark -
#pragma mark 初始化
#pragma mark -


%ctor
{

    NSString *process =
    NSProcessInfo.processInfo.processName;


    if(![process
         isEqualToString:@"SpringBoard"])
    {
        return;
    }


    NSUserDefaults *def =
    NSUserDefaults.standardUserDefaults;

    anomalyCPUThreshold =
    [def doubleForKey:@"SBCPU.AnomalyThreshold"];

    if(anomalyCPUThreshold <= 0)
    {
        anomalyCPUThreshold = 90.0;
    }

    anomalyDuration =
    [def integerForKey:@"SBCPU.AnomalyDuration"];

    if(anomalyDuration <= 0)
    {
        anomalyDuration = 10;
    }

    NSArray *savedLogs =
    [def objectForKey:@"SBCPU.AnomalyLogs"];

    if(savedLogs)
    {
        anomalyLogs = [savedLogs mutableCopy];
    }
    else
    {
        anomalyLogs = [NSMutableArray array];
    }


    /*
     自动注销
     */

    autoLogoutEnable =
    [def boolForKey:
     @"SBCPU.AutoLogout"];


    double cpu =
    [def doubleForKey:
     @"SBCPU.CPUThreshold"];


    if(cpu >= 80.0 &&
       cpu <= 1000.0)
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
        @"SBCPU.FloatingAlphaEnable"])
    {

        floatingAlphaEnable =
        [def boolForKey:
         @"SBCPU.FloatingAlphaEnable"];

    }


    /*
     透明度
     */

    CGFloat alpha =
    [def floatForKey:
     @"SBCPU.FloatingAlpha"];


    if(alpha >= 0.2 &&
       alpha <= 1.0)
    {

        floatingAlpha =
        alpha;

    }


    /*
     等 SpringBoard 完全启动
     */

    dispatch_after(
        dispatch_time(
            DISPATCH_TIME_NOW,
            5 * NSEC_PER_SEC),
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
