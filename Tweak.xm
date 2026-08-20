#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <mach/mach.h>
#import <signal.h>



#pragma mark -
#pragma mark SBCPUFloating V1.5.9 Global
#pragma mark -


static UIWindow *cpuWindow;

static UILabel *label;



/*
 设置页面状态
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
 V1.5.9 新增
 横屏状态
 */

static BOOL landscapeMode = NO;



#pragma mark -
#pragma mark 前置声明
#pragma mark -


static void openSettings(void);

static void checkHighCPU(double cpu);

static void updateOrientation(void);

static NSInteger getBatteryLevel(void);

static void applyFloatingAlpha(void);



/*
 控制器提前声明
 */

@class SBCPUValuePickerController;

@class SBCPUTimePickerController;

@class SBCPUSettingsController;



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
#pragma mark CPU读取
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
        count*sizeof(thread_t)
    );



    return total;

}





#pragma mark -
#pragma mark V1.5.9 电量
#pragma mark -


static NSInteger getBatteryLevel()
{

    UIDevice *device =
    UIDevice.currentDevice;



    device.batteryMonitoringEnabled =
    YES;



    float level =
    device.batteryLevel;



    if(level < 0)
    {
        return 0;
    }



    return
    (NSInteger)(level * 100);

}





#pragma mark -
#pragma mark V1.5.9 横屏检测
#pragma mark -


static void updateOrientation()
{

    UIDeviceOrientation orientation =
    UIDevice.currentDevice.orientation;



    if(orientation ==
       UIDeviceOrientationLandscapeLeft ||
       orientation ==
       UIDeviceOrientationLandscapeRight)
    {

        landscapeMode = YES;

    }
    else
    {

        landscapeMode = NO;

    }




    dispatch_async(
        dispatch_get_main_queue(),
        ^{


            if(!label ||
               !cpuWindow)
            {
                return;
            }



            /*
             屏幕旋转后重新限制浮窗位置
             */


            CGSize size =
            cpuWindow.bounds.size;



            CGPoint center =
            label.center;



            CGFloat halfW =
            label.bounds.size.width / 2.0;



            CGFloat halfH =
            label.bounds.size.height / 2.0;



            if(center.x < halfW)
            {
                center.x = halfW;
            }



            if(center.x >
               size.width-halfW)
            {
                center.x =
                size.width-halfW;
            }



            if(center.y <
               halfH+40)
            {
                center.y =
                halfH+40;
            }



            if(center.y >
               size.height-halfH)
            {
                center.y =
                size.height-halfH;
            }



            label.center =
            center;


        });

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

        });

}





#pragma mark -
#pragma mark 可穿透 Window
#pragma mark -


@interface SBCPUWindow : UIWindow

@end



@implementation SBCPUWindow



- (UIView *)hitTest:
( CGPoint)point
withEvent:
(UIEvent *)event
{

    /*
     设置页面打开
     全部交给系统处理
     */

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
     只有浮窗区域接收触摸
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

            if([NSStringFromClass(
                subview.class)
                isEqualToString:
                @"SBCPUDragView"])
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
     其它区域穿透
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
    label.bounds.size.width/2.0;



    CGFloat halfH =
    label.bounds.size.height/2.0;




    if(center.x < halfW)
    {
        center.x = halfW;
    }



    if(center.x >
       size.width-halfW)
    {
        center.x =
        size.width-halfW;
    }



    if(center.y <
       halfH+40)
    {
        center.y =
        halfH+40;
    }



    if(center.y >
       size.height-halfH)
    {
        center.y =
        size.height-halfH;
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



    cpuWindow.windowLevel =
    UIWindowLevelStatusBar+1;



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



    /*
     V1.5.9
     开启方向监听
     */

    UIDevice *device =
    UIDevice.currentDevice;


    device.batteryMonitoringEnabled =
    YES;



    [[NSNotificationCenter defaultCenter]
     addObserverForName:
     UIDeviceOrientationDidChangeNotification
     object:nil
     queue:
     [NSOperationQueue mainQueue]
     usingBlock:
     ^(NSNotification *note)
     {

         updateOrientation();

     }];




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
     colorWithAlphaComponent:
     0.70];



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


                UIViewController *root =
                cpuWindow.rootViewController;



                if(!root)
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
                        5*NSEC_PER_SEC),
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


            });

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



            /*
             V1.5.9
             横屏增加电量
             */


            if(landscapeMode)
            {

                label.numberOfLines = 3;


                label.text =
                [NSString
                 stringWithFormat:
                 @"SB CPU\n%.1f%%\n🔋%ld%%",
                 cpu,
                 (long)getBatteryLevel()];


            }
            else
            {

                label.numberOfLines = 2;


                label.text =
                [NSString
                 stringWithFormat:
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


        });

}




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



    settingsShowing = YES;



    SBCPUSettingsController *vc =
    [[SBCPUSettingsController alloc]
     initWithStyle:
     UITableViewStyleInsetGrouped];



    UINavigationController *nav =
    [[UINavigationController alloc]
     initWithRootViewController:vc];



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
    NSProcessInfo.processName;



    if(![process
         isEqualToString:
         @"SpringBoard"])
    {
        return;
    }



    NSUserDefaults *def =
    NSUserDefaults.standardUserDefaults;



    autoLogoutEnable =
    [def boolForKey:
     @"SBCPU.AutoLogout"];




    double cpu =
    [def doubleForKey:
     @"SBCPU.CPUThreshold"];



    if(cpu >= 80 &&
       cpu <= 1000)
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




    if([def objectForKey:
        @"SBCPU.FloatingAlphaEnable"])
    {

        floatingAlphaEnable =
        [def boolForKey:
         @"SBCPU.FloatingAlphaEnable"];

    }




    CGFloat alpha =
    [def floatForKey:
     @"SBCPU.FloatingAlpha"];



    if(alpha>=0.2 &&
       alpha<=1.0)
    {

        floatingAlpha =
        alpha;

    }




    dispatch_after(
        dispatch_time(
            DISPATCH_TIME_NOW,
            5*NSEC_PER_SEC),
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

        });

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



#pragma mark -
#pragma mark 关闭设置
#pragma mark -


- (void)closeSettings
{

    settingsShowing = NO;



    [self dismissViewControllerAnimated:YES
                             completion:
     ^{

         /*
          恢复浮窗穿透
          */

         [cpuWindow setNeedsLayout];

     }];

}



#pragma mark -
#pragma mark Table
#pragma mark -


- (NSInteger)tableView:
(UITableView *)tableView
numberOfRowsInSection:
(NSInteger)section
{

    return 5;

}




- (NSString *)tableView:
(UITableView *)tableView
titleForHeaderInSection:
(NSInteger)section
{

    return
    @"自动注销 / 悬浮窗";

}




#pragma mark -
#pragma mark Cell
#pragma mark -


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
        [NSString stringWithFormat:
         @"%.0f%%",
         logoutCPUThreshold];

    }





    if(indexPath.row == 2)
    {

        cell.textLabel.text =
        @"持续时间";



        cell.detailTextLabel.text =
        [NSString stringWithFormat:
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
        [NSString stringWithFormat:
         @"%.0f%%",
         floatingAlpha * 100.0];

    }




    return cell;

}




#pragma mark -
#pragma mark 自动注销开关
#pragma mark -


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





#pragma mark -
#pragma mark 透明度开关
#pragma mark -


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
#pragma mark -
#pragma mark 设置点击事件
#pragma mark -


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

        SBCPUValuePickerController *vc =
        [[SBCPUValuePickerController alloc]
         initWithStyle:
         UITableViewStyleInsetGrouped];



        [self.navigationController
         pushViewController:
         vc
         animated:YES];

    }




    /*
     持续时间
     */

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





    /*
     透明度选择
     */

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
         isEqualToString:
         @"SpringBoard"])
    {
        return;
    }




    NSUserDefaults *def =
    NSUserDefaults.standardUserDefaults;




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
     透明度数值
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






    dispatch_after(
        dispatch_time(
            DISPATCH_TIME_NOW,
            5 * NSEC_PER_SEC),
        dispatch_get_main_queue(),
        ^{


            createCPUWindow();




            /*
             V1.5.9
             开启横屏监听
             */

            UIDevice *device =
            UIDevice.currentDevice;



            device.batteryMonitoringEnabled =
            YES;



            [[NSNotificationCenter defaultCenter]
             addObserverForName:
             UIDeviceOrientationDidChangeNotification
             object:nil
             queue:
             [NSOperationQueue mainQueue]
             usingBlock:
             ^(NSNotification *note)
             {

                 updateOrientation();

             }];





            [NSTimer
             scheduledTimerWithTimeInterval:
             1.0
             repeats:YES
             block:
             ^(NSTimer *timer)
             {

                 updateCPU();

             }];



        });

}

