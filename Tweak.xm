#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <mach/mach.h>
#import <signal.h>
#import <IOKit/IOKitLib.h>


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
static BOOL landscapeRotated = NO;
static BOOL manualLandscapeMode = NO;

// V1.6.2 fix9 portrait state snapshot
static BOOL portraitStateSaved = NO;
static CGPoint portraitSavedCenter = CGPointZero;
static CGRect portraitSavedBounds = CGRectZero;
static CGAffineTransform portraitSavedTransform = CGAffineTransformIdentity;


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
 透明度
 */
static BOOL floatingAlphaEnable = YES;

static CGFloat floatingAlpha = 0.70f;

/*
 V1.6.0 智能布局
 */
static BOOL smartLayoutEnable = YES;
static BOOL autoMoveEnable __attribute__((unused)) = YES;
static BOOL keyboardAvoidEnable __attribute__((unused)) = YES;
static BOOL hideControlCenterEnable __attribute__((unused)) = YES;

static CGRect lastFloatingFrame;
static CGRect lastUserFrame;
static BOOL keyboardShowing = NO;

static CGRect keyboardBeforeFrame = CGRectZero;
static BOOL keyboardMoved = NO;

/*
 V1.6.2 EdgeDock Plus
 0自由 1左 2右 3上 4下
 */
static NSInteger dockSide = 0;

// V1.6.2.1 Smart Layout Control
static BOOL smartDockEnable = YES;
static NSInteger dockMode = 0; // 0自动 1左 2右 3上 4下
static BOOL rememberPositionEnable = YES;



/*
 前置声明
 */
static void openSettings(void);

static void checkHighCPU(double cpu);
static void applySmartLayout(void);
static void registerV160Observers(void);
static void updateCPUFloatingOrientation(void);
static void startV162OrientationMonitor(void);
static void restoreCPUFloatingPortrait(void);



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



- (void)touchesEnded:
(NSSet *)touches
withEvent:
(UIEvent *)event
{
    [super touchesEnded:touches withEvent:event];

    if(!label)
    {
        return;
    }

    // V1.6.2.1 Smart Layout
    // 关闭智能吸附时，释放后保持当前位置
    if(!smartDockEnable)
    {
        dockSide = 0;
        if(rememberPositionEnable)
        {
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

    CGFloat minDistance = MIN(MIN(left,right),MIN(top,bottom));

    CGPoint center = label.center;

    // 固定吸附模式
    if(dockMode > 0)
    {
        if(dockMode == 1)
        {
            center.x = label.bounds.size.width / 2.0 + 10;
            dockSide = 1;
        }
        else if(dockMode == 2)
        {
            center.x = size.width - label.bounds.size.width / 2.0 - 10;
            dockSide = 2;
        }
        else if(dockMode == 3)
        {
            center.y = label.bounds.size.height / 2.0 + 10;
            dockSide = 3;
        }
        else if(dockMode == 4)
        {
            center.y = size.height - label.bounds.size.height / 2.0 - 10;
            dockSide = 4;
        }
    }
    else if(minDistance == left)
    {
        center.x = label.bounds.size.width / 2.0 + 10;
        dockSide = 1;
    }
    else if(minDistance == right)
    {
        center.x = size.width - label.bounds.size.width / 2.0 - 10;
        dockSide = 2;
    }
    else if(minDistance == top)
    {
        center.y = label.bounds.size.height / 2.0 + 10;
        dockSide = 3;
    }
    else if(minDistance == bottom)
    {
        center.y = size.height - label.bounds.size.height / 2.0 - 10;
        dockSide = 4;
    }
    else
    {
        dockSide = 0;
    }

    [UIView animateWithDuration:0.25
                          delay:0
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:
     ^{
         label.center = center;
         self.center = center;
     }
                     completion:nil];
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


+ (void)landscapeSingleTapAction
{
    if(!label || !cpuWindow)
        return;

    CGSize screenSize = UIScreen.mainScreen.bounds.size;

    // 只处理横屏
    if(screenSize.width <= screenSize.height)
    {
        return;
    }

    // 第一次横屏旋转前保存竖屏状态
    if(!portraitStateSaved)
    {
        portraitStateSaved = YES;
        portraitSavedCenter = label.center;
        portraitSavedBounds = label.bounds;
        portraitSavedTransform = label.transform;
    }

    // 横屏状态：保持当前位置，只旋转显示层
    landscapeRotated = !landscapeRotated;
    manualLandscapeMode = YES;

    [UIView animateWithDuration:0.25 animations:^{
        CGAffineTransform t = landscapeRotated ? CGAffineTransformMakeRotation(M_PI_2) : portraitSavedTransform;
        label.transform = t;
        // 拖动层不旋转，避免破坏吸附和坐标计算
        cpuDragView.transform = CGAffineTransformIdentity;
    }];
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


    UITapGestureRecognizer *singleTap =
    [[UITapGestureRecognizer alloc]
     initWithTarget:
     [SBCPUAction class]
     action:@selector(landscapeSingleTapAction)];


    singleTap.numberOfTapsRequired = 1;
    singleTap.numberOfTouchesRequired = 1;

    [singleTap requireGestureRecognizerToFail:doubleTap];

    [drag addGestureRecognizer:
     singleTap];


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
#pragma mark V1.6.1 横屏电池温度
#pragma mark -

static double getBatteryTemperature()
{
    io_iterator_t iterator = 0;
    io_service_t service = IO_OBJECT_NULL;

    CFMutableDictionaryRef matching =
    IOServiceMatching("AppleSmartBattery");

    if(!matching)
        return -1;

    if(IOServiceGetMatchingServices(kIOMasterPortDefault,
                                    matching,
                                    &iterator) != KERN_SUCCESS)
        return -1;

    while((service = IOIteratorNext(iterator)))
    {
        CFTypeRef temp =
        IORegistryEntryCreateCFProperty(
            service,
            CFSTR("Temperature"),
            kCFAllocatorDefault,
            0);

        if(temp)
        {
            double value = -1;

            if(CFGetTypeID(temp) == CFNumberGetTypeID())
            {
                CFNumberGetValue((CFNumberRef)temp,
                                 kCFNumberDoubleType,
                                 &value);
            }

            CFRelease(temp);
            IOObjectRelease(service);
            IOObjectRelease(iterator);

            /*
             AppleSmartBattery Temperature:
             iOS usually returns centi-degrees Celsius.
             Example: 3650 = 36.50℃
             Some devices expose deci-Kelvin, keep compatibility.
            */
            if(value > 1000 && value < 10000)
            {
                value = value / 100.0;
            }
            else if(value > 200)
            {
                value = value / 10.0 - 273.15;
            }

            return value;
        }

        IOObjectRelease(service);
    }

    IOObjectRelease(iterator);

    return -1;
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
                    double temp = getBatteryTemperature();

                    if(temp > 0 && temp < 100)
                    {
                        label.text =
                        [NSString stringWithFormat:
                         @"SB CPU %.1f%%\n电量 %ld%% %.1f℃",
                         cpu,
                         (long)battery,
                         temp];
                    }
                    else
                    {
                        label.text =
                        [NSString stringWithFormat:
                         @"SB CPU %.1f%%\n电量 %ld%%",
                         cpu,
                         (long)battery];
                    }
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

    return 7;

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

    return 7;

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

    return 12;

}


- (NSString *)tableView:
(UITableView *)tableView
titleForHeaderInSection:
(NSInteger)section
{

    return
    @"自动注销 / 悬浮窗 / 智能布局";

}



#pragma mark 滑动调整

- (void)changeScaleSlider:(UISlider *)slider
{
    floatingScale = MAX(0.4, slider.value);
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
    landscapeScale = MAX(0.4, MIN(1.2, slider.value));
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
        slider.minimumValue = 0.4;
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
        cell.textLabel.text = @"智能吸附";
        UISwitch *sw = [[UISwitch alloc] init];
        sw.on = smartDockEnable;
        [sw addTarget:self action:@selector(changeSmartDock:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
    }

    if(indexPath.row == 10)
    {
        cell.textLabel.text = @"吸附模式";
        NSArray *modes = @[@"自动", @"左侧", @"右侧", @"顶部", @"底部"];
        cell.detailTextLabel.text = (dockMode >=0 && dockMode < modes.count) ? modes[dockMode] : @"自动";
    }

    if(indexPath.row == 11)
    {
        cell.textLabel.text = @"记忆悬浮窗位置";
        UISwitch *sw = [[UISwitch alloc] init];
        sw.on = rememberPositionEnable;
        [sw addTarget:self action:@selector(changeRemember:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
    }


    return cell;

}

#pragma mark 智能布局控制

- (void)changeSmartDock:(UISwitch *)sw
{
    smartDockEnable = sw.isOn;
    [[NSUserDefaults standardUserDefaults] setBool:smartDockEnable forKey:@"SBCPU.SmartDock"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)changeRemember:(UISwitch *)sw
{
    rememberPositionEnable = sw.isOn;
    [[NSUserDefaults standardUserDefaults] setBool:rememberPositionEnable forKey:@"SBCPU.RememberPosition"];
    [[NSUserDefaults standardUserDefaults] synchronize];
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

    if(indexPath.row == 10)
    {
        NSArray *modes = @[@"自动", @"左侧", @"右侧", @"顶部", @"底部"];
        dockMode = (dockMode + 1) % modes.count;
        [[NSUserDefaults standardUserDefaults] setInteger:dockMode forKey:@"SBCPU.DockMode"];
        [[NSUserDefaults standardUserDefaults] synchronize];
        [tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
        return;
    }

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

    keyboardShowing = NO;


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




#pragma mark -
#pragma mark V1.6.0 Smart Layout
#pragma mark -

static void applySmartLayout()
{
    if(!cpuWindow || !label || !smartLayoutEnable || settingsShowing)
        return;

    dispatch_async(dispatch_get_main_queue(), ^{

        UIWindowScene *scene = cpuWindow.windowScene;
        if(!scene)
            return;

        CGRect area = scene.coordinateSpace.bounds;
        UIEdgeInsets safe = scene.windows.firstObject.safeAreaInsets;

        CGSize size = label.bounds.size;
        CGRect target = lastUserFrame;

        if(CGRectIsEmpty(target))
        {
            target = CGRectMake(
                CGRectGetWidth(area)-size.width-safe.right-12,
                CGRectGetHeight(area)/2.0,
                size.width,
                size.height
            );
        }

        if(target.origin.x < safe.left)
            target.origin.x = safe.left + 5;

        if(CGRectGetMaxX(target) > CGRectGetWidth(area)-safe.right)
            target.origin.x = CGRectGetWidth(area)-safe.right-size.width-5;

        // V1.6.2 fixed2: 顶部吸附不再受横屏 safeArea 顶部偏移影响
        if(target.origin.y < 5)
            target.origin.y = 5;

        if(CGRectGetMaxY(target) > CGRectGetHeight(area)-safe.bottom)
            target.origin.y = CGRectGetHeight(area)-safe.bottom-size.height-5;

        label.frame = target;
        cpuDragView.frame = target;
        lastFloatingFrame = target;
    });
}


static void registerV160Observers()
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken,^{

        NSNotificationCenter *nc =
        NSNotificationCenter.defaultCenter;


        [nc addObserverForName:
         UIDeviceOrientationDidChangeNotification
         object:nil
         queue:NSOperationQueue.mainQueue
         usingBlock:^(NSNotification *n){

             // V1.6.1 fixed2: rotate only clamp/reposition, never reset style
             if(cpuWindow && label)
             {
                 CGRect f = label.frame;
                 CGSize s = cpuWindow.bounds.size;
                 if(CGRectGetMaxX(f) > s.width)
                     f.origin.x = s.width - f.size.width - 10;
                 if(CGRectGetMaxY(f) > s.height)
                     f.origin.y = s.height - f.size.height - 10;
                 if(f.origin.x < 0) f.origin.x = 10;
                 if(f.origin.y < 0) f.origin.y = 10;
                 label.frame = f;
                 cpuDragView.frame = f;
                 lastFloatingFrame = f;
             }

         }];


        if(keyboardAvoidEnable)
        {

            [nc addObserverForName:
             UIKeyboardWillShowNotification
             object:nil
             queue:NSOperationQueue.mainQueue
             usingBlock:^(NSNotification *n){

                 if(settingsShowing)
                    return;

                 keyboardShowing = YES;

                 if(cpuWindow && label)
                 {
                     // V1.6.1 fixed3 智能键盘避让
                     // 悬浮窗在屏幕上半部分时不避让键盘
                     UIWindowScene *scene = getWindowScene();
                     CGRect screenBounds = scene ? scene.coordinateSpace.bounds : UIScreen.mainScreen.bounds;

                     CGFloat centerY = CGRectGetMidY(label.frame);
                     CGFloat limitY = CGRectGetMidY(screenBounds);

                     if(centerY < limitY)
                     {
                         return;
                     }

                     // 只临时移动位置，不重新布局，不修改尺寸/透明度/圆角
                     if(!keyboardMoved)
                     {
                         keyboardBeforeFrame = label.frame;
                     }

                     CGRect f = keyboardBeforeFrame;
                     CGFloat keyboardHeight = 180.0;

                     NSDictionary *info = n.userInfo;
                     NSValue *endFrameValue = info[UIKeyboardFrameEndUserInfoKey];
                     if(endFrameValue)
                     {
                         CGRect keyboardFrame = [endFrameValue CGRectValue];
                         keyboardHeight = MIN(220.0, keyboardFrame.size.height);
                     }

                     f.origin.y = MAX(20, f.origin.y - keyboardHeight);

                     label.frame = f;
                     cpuDragView.frame = f;
                     keyboardMoved = YES;
                 }

             }];


            [nc addObserverForName:
             UIKeyboardWillHideNotification
             object:nil
             queue:NSOperationQueue.mainQueue
             usingBlock:^(NSNotification *n){

                 keyboardShowing = NO;

                 if(!settingsShowing && keyboardMoved)
                 {
                     // 恢复键盘前的位置，保持用户设置的大小、透明度、圆角
                     label.frame = keyboardBeforeFrame;
                     cpuDragView.frame = keyboardBeforeFrame;
                     lastFloatingFrame = keyboardBeforeFrame;
                     keyboardMoved = NO;
                 }

             }];
        }


        if(hideControlCenterEnable)
        {
            [nc addObserverForName:
             UIApplicationWillResignActiveNotification
             object:nil
             queue:NSOperationQueue.mainQueue
             usingBlock:^(NSNotification *n){

                 if(cpuWindow)
                     cpuWindow.hidden = YES;

             }];


            [nc addObserverForName:
             UIApplicationDidBecomeActiveNotification
             object:nil
             queue:NSOperationQueue.mainQueue
             usingBlock:^(NSNotification *n){

                 if(cpuWindow)
                     cpuWindow.hidden = NO;

             }];
        }

    });
}


static void startV162OrientationMonitor(void)
{
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        dispatch_source_t timer =
        dispatch_source_create(
            DISPATCH_SOURCE_TYPE_TIMER,
            0,
            0,
            dispatch_get_main_queue()
        );

        dispatch_source_set_timer(
            timer,
            dispatch_time(DISPATCH_TIME_NOW, 0),
            500ull * NSEC_PER_MSEC,
            50ull * NSEC_PER_MSEC
        );

        dispatch_source_set_event_handler(timer, ^{
            updateCPUFloatingOrientation();
        });

        dispatch_resume(timer);
    });
}


static void updateCPUFloatingOrientation(void)
{
    CGSize size = UIScreen.mainScreen.bounds.size;
    BOOL isLandscape = (size.width > size.height);

    if(cpuWindow && label)
    {
        // Landscape -> Portrait transition:
        // clear the temporary rotation applied by the click action.
        // fix14:
        // 不依赖系统方向通知，使用实际屏幕尺寸恢复检测。
        // 方向锁定开启时系统可能不会发送 Landscape->Portrait 回调。
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <mach/mach.h>
#import <signal.h>
#import <IOKit/IOKitLib.h>


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
static BOOL landscapeRotated = NO;
static BOOL manualLandscapeMode = NO;

// V1.6.2 fix9 portrait state snapshot
static BOOL portraitStateSaved = NO;
static CGPoint portraitSavedCenter = CGPointZero;
static CGRect portraitSavedBounds = CGRectZero;
static CGAffineTransform portraitSavedTransform = CGAffineTransformIdentity;


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
 透明度
 */
static BOOL floatingAlphaEnable = YES;

static CGFloat floatingAlpha = 0.70f;

/*
 V1.6.0 智能布局
 */
static BOOL smartLayoutEnable = YES;
static BOOL autoMoveEnable __attribute__((unused)) = YES;
static BOOL keyboardAvoidEnable __attribute__((unused)) = YES;
static BOOL hideControlCenterEnable __attribute__((unused)) = YES;

static CGRect lastFloatingFrame;
static CGRect lastUserFrame;
static BOOL keyboardShowing = NO;

static CGRect keyboardBeforeFrame = CGRectZero;
static BOOL keyboardMoved = NO;

/*
 V1.6.2 EdgeDock Plus
 0自由 1左 2右 3上 4下
 */
static NSInteger dockSide = 0;

// V1.6.2.1 Smart Layout Control
static BOOL smartDockEnable = YES;
static NSInteger dockMode = 0; // 0自动 1左 2右 3上 4下
static BOOL rememberPositionEnable = YES;



/*
 前置声明
 */
static void openSettings(void);

static void checkHighCPU(double cpu);
static void applySmartLayout(void);
static void registerV160Observers(void);
static void updateCPUFloatingOrientation(void);
static void startV162OrientationMonitor(void);
static void restoreCPUFloatingPortrait(void);



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



- (void)touchesEnded:
(NSSet *)touches
withEvent:
(UIEvent *)event
{
    [super touchesEnded:touches withEvent:event];

    if(!label)
    {
        return;
    }

    // V1.6.2.1 Smart Layout
    // 关闭智能吸附时，释放后保持当前位置
    if(!smartDockEnable)
    {
        dockSide = 0;
        if(rememberPositionEnable)
        {
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

    CGFloat minDistance = MIN(MIN(left,right),MIN(top,bottom));

    CGPoint center = label.center;

    // 固定吸附模式
    if(dockMode > 0)
    {
        if(dockMode == 1)
        {
            center.x = label.bounds.size.width / 2.0 + 10;
            dockSide = 1;
        }
        else if(dockMode == 2)
        {
            center.x = size.width - label.bounds.size.width / 2.0 - 10;
            dockSide = 2;
        }
        else if(dockMode == 3)
        {
            center.y = label.bounds.size.height / 2.0 + 10;
            dockSide = 3;
        }
        else if(dockMode == 4)
        {
            center.y = size.height - label.bounds.size.height / 2.0 - 10;
            dockSide = 4;
        }
    }
    else if(minDistance == left)
    {
        center.x = label.bounds.size.width / 2.0 + 10;
        dockSide = 1;
    }
    else if(minDistance == right)
    {
        center.x = size.width - label.bounds.size.width / 2.0 - 10;
        dockSide = 2;
    }
    else if(minDistance == top)
    {
        center.y = label.bounds.size.height / 2.0 + 10;
        dockSide = 3;
    }
    else if(minDistance == bottom)
    {
        center.y = size.height - label.bounds.size.height / 2.0 - 10;
        dockSide = 4;
    }
    else
    {
        dockSide = 0;
    }

    [UIView animateWithDuration:0.25
                          delay:0
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:
     ^{
         label.center = center;
         self.center = center;
     }
                     completion:nil];
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


+ (void)landscapeSingleTapAction
{
    if(!label || !cpuWindow)
        return;

    CGSize screenSize = UIScreen.mainScreen.bounds.size;

    // 只处理横屏
    if(screenSize.width <= screenSize.height)
    {
        return;
    }

    // 第一次横屏旋转前保存竖屏状态
    if(!portraitStateSaved)
    {
        portraitStateSaved = YES;
        portraitSavedCenter = label.center;
        portraitSavedBounds = label.bounds;
        portraitSavedTransform = label.transform;
    }

    // 横屏状态：保持当前位置，只旋转显示层
    landscapeRotated = !landscapeRotated;
    manualLandscapeMode = YES;

    [UIView animateWithDuration:0.25 animations:^{
        CGAffineTransform t = landscapeRotated ? CGAffineTransformMakeRotation(M_PI_2) : portraitSavedTransform;
        label.transform = t;
        // 拖动层不旋转，避免破坏吸附和坐标计算
        cpuDragView.transform = CGAffineTransformIdentity;
    }];
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


    UITapGestureRecognizer *singleTap =
    [[UITapGestureRecognizer alloc]
     initWithTarget:
     [SBCPUAction class]
     action:@selector(landscapeSingleTapAction)];


    singleTap.numberOfTapsRequired = 1;
    singleTap.numberOfTouchesRequired = 1;

    [singleTap requireGestureRecognizerToFail:doubleTap];

    [drag addGestureRecognizer:
     singleTap];


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
#pragma mark V1.6.1 横屏电池温度
#pragma mark -

static double getBatteryTemperature()
{
    io_iterator_t iterator = 0;
    io_service_t service = IO_OBJECT_NULL;

    CFMutableDictionaryRef matching =
    IOServiceMatching("AppleSmartBattery");

    if(!matching)
        return -1;

    if(IOServiceGetMatchingServices(kIOMasterPortDefault,
                                    matching,
                                    &iterator) != KERN_SUCCESS)
        return -1;

    while((service = IOIteratorNext(iterator)))
    {
        CFTypeRef temp =
        IORegistryEntryCreateCFProperty(
            service,
            CFSTR("Temperature"),
            kCFAllocatorDefault,
            0);

        if(temp)
        {
            double value = -1;

            if(CFGetTypeID(temp) == CFNumberGetTypeID())
            {
                CFNumberGetValue((CFNumberRef)temp,
                                 kCFNumberDoubleType,
                                 &value);
            }

            CFRelease(temp);
            IOObjectRelease(service);
            IOObjectRelease(iterator);

            /*
             AppleSmartBattery Temperature:
             iOS usually returns centi-degrees Celsius.
             Example: 3650 = 36.50℃
             Some devices expose deci-Kelvin, keep compatibility.
            */
            if(value > 1000 && value < 10000)
            {
                value = value / 100.0;
            }
            else if(value > 200)
            {
                value = value / 10.0 - 273.15;
            }

            return value;
        }

        IOObjectRelease(service);
    }

    IOObjectRelease(iterator);

    return -1;
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
                    double temp = getBatteryTemperature();

                    if(temp > 0 && temp < 100)
                    {
                        label.text =
                        [NSString stringWithFormat:
                         @"SB CPU %.1f%%\n电量 %ld%% %.1f℃",
                         cpu,
                         (long)battery,
                         temp];
                    }
                    else
                    {
                        label.text =
                        [NSString stringWithFormat:
                         @"SB CPU %.1f%%\n电量 %ld%%",
                         cpu,
                         (long)battery];
                    }
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

    return 7;

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

    return 7;

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

    return 12;

}


- (NSString *)tableView:
(UITableView *)tableView
titleForHeaderInSection:
(NSInteger)section
{

    return
    @"自动注销 / 悬浮窗 / 智能布局";

}



#pragma mark 滑动调整

- (void)changeScaleSlider:(UISlider *)slider
{
    floatingScale = MAX(0.4, slider.value);
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
    landscapeScale = MAX(0.4, MIN(1.2, slider.value));
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
        slider.minimumValue = 0.4;
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
        cell.textLabel.text = @"智能吸附";
        UISwitch *sw = [[UISwitch alloc] init];
        sw.on = smartDockEnable;
        [sw addTarget:self action:@selector(changeSmartDock:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
    }

    if(indexPath.row == 10)
    {
        cell.textLabel.text = @"吸附模式";
        NSArray *modes = @[@"自动", @"左侧", @"右侧", @"顶部", @"底部"];
        cell.detailTextLabel.text = (dockMode >=0 && dockMode < modes.count) ? modes[dockMode] : @"自动";
    }

    if(indexPath.row == 11)
    {
        cell.textLabel.text = @"记忆悬浮窗位置";
        UISwitch *sw = [[UISwitch alloc] init];
        sw.on = rememberPositionEnable;
        [sw addTarget:self action:@selector(changeRemember:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
    }


    return cell;

}

#pragma mark 智能布局控制

- (void)changeSmartDock:(UISwitch *)sw
{
    smartDockEnable = sw.isOn;
    [[NSUserDefaults standardUserDefaults] setBool:smartDockEnable forKey:@"SBCPU.SmartDock"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)changeRemember:(UISwitch *)sw
{
    rememberPositionEnable = sw.isOn;
    [[NSUserDefaults standardUserDefaults] setBool:rememberPositionEnable forKey:@"SBCPU.RememberPosition"];
    [[NSUserDefaults standardUserDefaults] synchronize];
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

    if(indexPath.row == 10)
    {
        NSArray *modes = @[@"自动", @"左侧", @"右侧", @"顶部", @"底部"];
        dockMode = (dockMode + 1) % modes.count;
        [[NSUserDefaults standardUserDefaults] setInteger:dockMode forKey:@"SBCPU.DockMode"];
        [[NSUserDefaults standardUserDefaults] synchronize];
        [tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
        return;
    }

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

    keyboardShowing = NO;


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




#pragma mark -
#pragma mark V1.6.0 Smart Layout
#pragma mark -

static void applySmartLayout()
{
    if(!cpuWindow || !label || !smartLayoutEnable || settingsShowing)
        return;

    dispatch_async(dispatch_get_main_queue(), ^{

        UIWindowScene *scene = cpuWindow.windowScene;
        if(!scene)
            return;

        CGRect area = scene.coordinateSpace.bounds;
        UIEdgeInsets safe = scene.windows.firstObject.safeAreaInsets;

        CGSize size = label.bounds.size;
        CGRect target = lastUserFrame;

        if(CGRectIsEmpty(target))
        {
            target = CGRectMake(
                CGRectGetWidth(area)-size.width-safe.right-12,
                CGRectGetHeight(area)/2.0,
                size.width,
                size.height
            );
        }

        if(target.origin.x < safe.left)
            target.origin.x = safe.left + 5;

        if(CGRectGetMaxX(target) > CGRectGetWidth(area)-safe.right)
            target.origin.x = CGRectGetWidth(area)-safe.right-size.width-5;

        // V1.6.2 fixed2: 顶部吸附不再受横屏 safeArea 顶部偏移影响
        if(target.origin.y < 5)
            target.origin.y = 5;

        if(CGRectGetMaxY(target) > CGRectGetHeight(area)-safe.bottom)
            target.origin.y = CGRectGetHeight(area)-safe.bottom-size.height-5;

        label.frame = target;
        cpuDragView.frame = target;
        lastFloatingFrame = target;
    });
}


static void registerV160Observers()
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken,^{

        NSNotificationCenter *nc =
        NSNotificationCenter.defaultCenter;


        [nc addObserverForName:
         UIDeviceOrientationDidChangeNotification
         object:nil
         queue:NSOperationQueue.mainQueue
         usingBlock:^(NSNotification *n){

             // V1.6.1 fixed2: rotate only clamp/reposition, never reset style
             if(cpuWindow && label)
             {
                 CGRect f = label.frame;
                 CGSize s = cpuWindow.bounds.size;
                 if(CGRectGetMaxX(f) > s.width)
                     f.origin.x = s.width - f.size.width - 10;
                 if(CGRectGetMaxY(f) > s.height)
                     f.origin.y = s.height - f.size.height - 10;
                 if(f.origin.x < 0) f.origin.x = 10;
                 if(f.origin.y < 0) f.origin.y = 10;
                 label.frame = f;
                 cpuDragView.frame = f;
                 lastFloatingFrame = f;
             }

         }];


        if(keyboardAvoidEnable)
        {

            [nc addObserverForName:
             UIKeyboardWillShowNotification
             object:nil
             queue:NSOperationQueue.mainQueue
             usingBlock:^(NSNotification *n){

                 if(settingsShowing)
                    return;

                 keyboardShowing = YES;

                 if(cpuWindow && label)
                 {
                     // V1.6.1 fixed3 智能键盘避让
                     // 悬浮窗在屏幕上半部分时不避让键盘
                     UIWindowScene *scene = getWindowScene();
                     CGRect screenBounds = scene ? scene.coordinateSpace.bounds : UIScreen.mainScreen.bounds;

                     CGFloat centerY = CGRectGetMidY(label.frame);
                     CGFloat limitY = CGRectGetMidY(screenBounds);

                     if(centerY < limitY)
                     {
                         return;
                     }

                     // 只临时移动位置，不重新布局，不修改尺寸/透明度/圆角
                     if(!keyboardMoved)
                     {
                         keyboardBeforeFrame = label.frame;
                     }

                     CGRect f = keyboardBeforeFrame;
                     CGFloat keyboardHeight = 180.0;

                     NSDictionary *info = n.userInfo;
                     NSValue *endFrameValue = info[UIKeyboardFrameEndUserInfoKey];
                     if(endFrameValue)
                     {
                         CGRect keyboardFrame = [endFrameValue CGRectValue];
                         keyboardHeight = MIN(220.0, keyboardFrame.size.height);
                     }

                     f.origin.y = MAX(20, f.origin.y - keyboardHeight);

                     label.frame = f;
                     cpuDragView.frame = f;
                     keyboardMoved = YES;
                 }

             }];


            [nc addObserverForName:
             UIKeyboardWillHideNotification
             object:nil
             queue:NSOperationQueue.mainQueue
             usingBlock:^(NSNotification *n){

                 keyboardShowing = NO;

                 if(!settingsShowing && keyboardMoved)
                 {
                     // 恢复键盘前的位置，保持用户设置的大小、透明度、圆角
                     label.frame = keyboardBeforeFrame;
                     cpuDragView.frame = keyboardBeforeFrame;
                     lastFloatingFrame = keyboardBeforeFrame;
                     keyboardMoved = NO;
                 }

             }];
        }


        if(hideControlCenterEnable)
        {
            [nc addObserverForName:
             UIApplicationWillResignActiveNotification
             object:nil
             queue:NSOperationQueue.mainQueue
             usingBlock:^(NSNotification *n){

                 if(cpuWindow)
                     cpuWindow.hidden = YES;

             }];


            [nc addObserverForName:
             UIApplicationDidBecomeActiveNotification
             object:nil
             queue:NSOperationQueue.mainQueue
             usingBlock:^(NSNotification *n){

                 if(cpuWindow)
                     cpuWindow.hidden = NO;

             }];
        }

    });
}


static void startV162OrientationMonitor(void)
{
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        dispatch_source_t timer =
        dispatch_source_create(
            DISPATCH_SOURCE_TYPE_TIMER,
            0,
            0,
            dispatch_get_main_queue()
        );

        dispatch_source_set_timer(
            timer,
            dispatch_time(DISPATCH_TIME_NOW, 0),
            500ull * NSEC_PER_MSEC,
            50ull * NSEC_PER_MSEC
        );

        dispatch_source_set_event_handler(timer, ^{
            updateCPUFloatingOrientation();
        });

        dispatch_resume(timer);
    });
}


static void updateCPUFloatingOrientation(void)
{
    CGSize size = UIScreen.mainScreen.bounds.size;
    BOOL isLandscape = (size.width > size.height);

    if(cpuWindow && label)
    {
        // Landscape -> Portrait transition:
        // clear the temporary rotation applied by the click action.
        // fix14:
        // 不依赖系统方向通知，使用实际屏幕尺寸恢复检测。
        // 方向锁定开启时系统可能不会发送 Landscape->Portrait 回调。
        if(manualLandscapeMode && !isLandscape)
        {
            // fix15: 模拟横屏状态下第二次点击恢复竖屏浮窗的效果。
            // 不等待系统方向回调，只把浮窗显示状态先恢复到竖屏。
            landscapeRotated = NO;
            manualLandscapeMode = NO;

            [UIView animateWithDuration:0.20 animations:^{
                label.transform = portraitSavedTransform;
                cpuDragView.transform = CGAffineTransformIdentity;
            } completion:^(BOOL finished){
                CGRect f = label.frame;
                label.frame = f;
                cpuDragView.frame = f;
                [label setNeedsDisplay];
                [label setNeedsLayout];
                [label layoutIfNeeded];
            }];

            portraitStateSaved = NO;
        }

    }
}


static void recreateCPUFloatingWindow(void)
{
    dispatch_async(dispatch_get_main_queue(), ^{

        if(label)
        {
            [label removeFromSuperview];
        }

        if(cpuDragView)
        {
            [cpuDragView removeFromSuperview];
        }

        if(cpuWindow)
        {
            cpuWindow.hidden = YES;
            cpuWindow.rootViewController = nil;
        }

        cpuWindow = nil;
        label = nil;
        cpuDragView = nil;

        landscapeRotated = NO;
        portraitStateSaved = NO;

        dispatch_after(
            dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)),
            dispatch_get_main_queue(),
            ^{
                createCPUWindow();
            }
        );

    });
}


static void restoreCPUFloatingPortrait(void)
{
    if(!cpuWindow)
        return;

    // V1.6.2 fix12:
    // 不再尝试恢复旧 transform。
    // 直接重建浮窗，模拟 SpringBoard 注销后的插件重新初始化。
    recreateCPUFloatingWindow();
}



%ctor
{

    NSString *process =
    NSProcessInfo.processInfo.processName;


    if(![process
         isEqualToString:@"SpringBoard"])
    {
        return;
    }


    [[NSNotificationCenter defaultCenter] addObserverForName:UISceneDidActivateNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note){
        UIWindowScene *scene = getWindowScene();
        UIInterfaceOrientation o = scene.interfaceOrientation;
        if(UIInterfaceOrientationIsPortrait(o))
        {
            restoreCPUFloatingPortrait();
        }
    }];


    NSUserDefaults *def =
    NSUserDefaults.standardUserDefaults;

    floatingScale = [def floatForKey:@"SBCPU.FloatingScale"];
    if(floatingScale < 0.4) floatingScale = 1.0;
    floatingFontSize = [def floatForKey:@"SBCPU.FloatingFontSize"];
    if(floatingFontSize < 1) floatingFontSize = 14.0;
    landscapeScale = [def floatForKey:@"SBCPU.LandscapeScale"];
    if(landscapeScale < 0.4) landscapeScale = 0.75;
    landscapeFontSize = [def floatForKey:@"SBCPU.LandscapeFontSize"];
    if(landscapeFontSize < 1) landscapeFontSize = 12.0;
    batteryFontSize = [def floatForKey:@"SBCPU.BatteryFontSize"];
    if(batteryFontSize < 1) batteryFontSize = 12.0;
    dockMode = [def integerForKey:@"SBCPU.DockMode"];


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

            // V1.6.0 Smart Layout
            registerV160Observers();
    startV162OrientationMonitor();
            applySmartLayout();


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
}
