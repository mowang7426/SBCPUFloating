#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <mach/mach.h>
#import <signal.h>


#pragma mark -
#pragma mark SBCPUFloating V1.5.9.1
#pragma mark -


static UIWindow *cpuWindow = nil;

static UILabel *label = nil;


/*
 拖动视图保存引用
 修复：
 1. 横屏后拖动失效
 2. 双击失效
*/

static UIView *cpuDragView = nil;


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
 横屏状态
*/

static BOOL isLandscape = NO;



#pragma mark -
#pragma mark Controller声明
#pragma mark -


@interface SBCPUSettingsController :
UITableViewController

@end



@interface SBCPUValuePickerController :
UITableViewController

@end



@interface SBCPUTimePickerController :
UITableViewController

@end



#pragma mark -
#pragma mark 函数声明
#pragma mark -


static void openSettings(void);

static void updateOrientation(void);

static void applyFloatingAlpha(void);




#pragma mark -
#pragma mark 获取WindowScene
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
#pragma mark CPU获取
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



    for(mach_msg_type_number_t i=0;
        i<count;
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
#pragma mark Window触摸修复
#pragma mark -


@interface SBCPUWindow : UIWindow

@end



@implementation SBCPUWindow



- (UIView *)hitTest:
(CGPoint)point
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
     只允许浮窗区域
    */


    if(label &&
       [view isDescendantOfView:label])
    {

        return view;

    }



    if(cpuDragView &&
       [view isDescendantOfView:cpuDragView])
    {

        return view;

    }



    return nil;

}


@end




#pragma mark -
#pragma mark 拖动修复
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
        return;



    self.lastPoint =
    [touch locationInView:
     self.superview];



}



- (void)touchesMoved:
(NSSet *)touches
withEvent:
(UIEvent *)event
{


    UITouch *touch =
    touches.anyObject;


    if(!touch)
        return;



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
    label.bounds.size.width/2;



    CGFloat halfH =
    label.bounds.size.height/2;



    if(center.x < halfW)
        center.x = halfW;



    if(center.x >
       size.width-halfW)
    {
        center.x =
        size.width-halfW;
    }



    if(center.y < halfH+40)
        center.y = halfH+40;



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


}



@end
#pragma mark -
#pragma mark 透明度
#pragma mark -


static void applyFloatingAlpha()
{

    dispatch_async(
    dispatch_get_main_queue(),
    ^{

        if(!label)
            return;


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
#pragma mark 横屏处理
#pragma mark -
/*
 V1.5.9.3.2:
 不依赖设备方向。
 通过 UIScreen 实际尺寸判断游戏强制横屏。
 兼容方向锁定开启进入横屏游戏。
*/


static void updateOrientation()
{

    if(!cpuWindow ||
       !label)
    {
        return;
    }



    BOOL landscape =
    UIScreen.mainScreen.bounds.size.width >
    UIScreen.mainScreen.bounds.size.height;



    isLandscape = landscape;



    dispatch_async(
    dispatch_get_main_queue(),
    ^{


        if(isLandscape)
        {


            CGRect frame =
            label.frame;


            frame.size.height = 70;


            label.frame =
            frame;


            label.text =
            @"SB CPU\n--%";


        }
        else
        {


            CGRect frame =
            label.frame;


            frame.size.height = 50;


            label.frame =
            frame;


        }



        /*
         拖动层同步
        */


        if(cpuDragView)
        {

            cpuDragView.frame =
            label.frame;

        }


        /*
          防止横屏跑出屏幕
        */


        CGSize size =
        cpuWindow.bounds.size;


        CGPoint center =
        label.center;


        CGFloat halfW =
        label.bounds.size.width/2;


        CGFloat halfH =
        label.bounds.size.height/2;



        if(center.x < halfW)
            center.x = halfW;



        if(center.x >
           size.width-halfW)
        {
            center.x =
            size.width-halfW;
        }



        if(center.y < halfH+30)
            center.y = halfH+30;



        if(center.y >
           size.height-halfH)
        {
            center.y =
            size.height-halfH;
        }



        label.center =
        center;


        cpuDragView.center =
        center;



    });

}




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
        return;



    UIWindowScene *scene =
    getWindowScene();



    if(!scene)
        return;




    cpuWindow =
    [[SBCPUWindow alloc]
     initWithFrame:
     UIScreen.mainScreen.bounds];



    cpuWindow.windowScene =
    scene;



    cpuWindow.windowLevel =
    UIWindowLevelStatusBar + 1;



    cpuWindow.backgroundColor =
    UIColor.clearColor;



    cpuWindow.opaque =
    NO;



    UIViewController *root =
    [UIViewController new];



    root.view.backgroundColor =
    UIColor.clearColor;



    cpuWindow.rootViewController =
    root;



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
     colorWithAlphaComponent:
     0.7];



    label.textColor =
    UIColor.whiteColor;



    label.textAlignment =
    NSTextAlignmentCenter;



    label.numberOfLines =
    3;



    label.layer.cornerRadius =
    12;



    label.clipsToBounds =
    YES;



    label.font =
    [UIFont
     monospacedDigitSystemFontOfSize:
     14
     weight:
     UIFontWeightBold];



    label.text =
    @"SB CPU\n0%";





    /*
       拖动层
    */


    SBCPUDragView *drag =
    [[SBCPUDragView alloc]
     initWithFrame:
     label.frame];



    drag.backgroundColor =
    UIColor.clearColor;



    drag.userInteractionEnabled =
    YES;



    cpuDragView =
    drag;




    [root.view
     addSubview:label];



    [root.view
     addSubview:drag];





    /*
      双击
    */


    UITapGestureRecognizer *tap =
    [[UITapGestureRecognizer alloc]
     initWithTarget:
     [SBCPUAction class]
     action:
     @selector(doubleTapAction)];



    tap.numberOfTapsRequired =
    2;



    [drag
     addGestureRecognizer:tap];





    /*
      横屏监听
    */


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



    applyFloatingAlpha();



}






#pragma mark -
#pragma mark CPU刷新
#pragma mark -


static void updateCPU()
{

    double cpu =
    getCPUUsage();



    dispatch_async(
    dispatch_get_main_queue(),
    ^{


        // V1.5.9.3.2 OrientationLock Fix
        // 方向锁定开启时，游戏可能不会发送 UIDeviceOrientation 通知，
        // 所以每次刷新 CPU 时根据实际屏幕尺寸重新判断。
        updateOrientation();



        if(!label)
            return;



        if(isLandscape)
        {


            label.text =
            [NSString
             stringWithFormat:
             @"SB CPU\n%.1f%%",
             cpu];

        }
        else
        {


            label.text =
            [NSString
             stringWithFormat:
             @"SB CPU\n%.1f%%",
             cpu];

        }



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


    });



}
#pragma mark -
#pragma mark 自动注销检测
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


            UIViewController *root =
            cpuWindow.rootViewController;



            if(!root)
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
            5*NSEC_PER_SEC),
            dispatch_get_main_queue(),
            ^{


                if(logoutCounting)
                {


                    kill(
                    getpid(),
                    SIGTERM);


                }


            });



        });



    }



}







#pragma mark -
#pragma mark CPU值选择
#pragma mark -


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
    [NSString stringWithFormat:
     @"%@%%",
     values[indexPath.row]];



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
#pragma mark 时间选择
#pragma mark -


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
    [NSString stringWithFormat:
     @"%@秒",
     values[indexPath.row]];



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



- (void)closeSettings
{

    settingsShowing = NO;



    [self dismissViewControllerAnimated:YES
                             completion:nil];

}




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

    return @"SBCPU设置";

}




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



    if(indexPath.row==0)
    {


        cell.textLabel.text =
        @"自动注销";



        UISwitch *sw =
        [[UISwitch alloc]init];



        sw.on =
        autoLogoutEnable;



        [sw addTarget:self
               action:@selector(changeLogout:)
     forControlEvents:UIControlEventValueChanged];



        cell.accessoryView =
        sw;

    }





    if(indexPath.row==1)
    {


        cell.textLabel.text =
        @"CPU触发值";



        cell.detailTextLabel.text =
        [NSString stringWithFormat:
         @"%.0f%%",
         logoutCPUThreshold];

    }





    if(indexPath.row==2)
    {


        cell.textLabel.text =
        @"持续时间";



        cell.detailTextLabel.text =
        [NSString stringWithFormat:
         @"%ld秒",
         (long)logoutDuration];

    }





    if(indexPath.row==3)
    {


        cell.textLabel.text =
        @"透明度开关";



        UISwitch *sw =
        [[UISwitch alloc]init];



        sw.on =
        floatingAlphaEnable;



        [sw addTarget:self
               action:@selector(changeAlpha:)
     forControlEvents:UIControlEventValueChanged];



        cell.accessoryView =
        sw;

    }





    if(indexPath.row==4)
    {


        cell.textLabel.text =
        @"透明度";



        cell.detailTextLabel.text =
        [NSString stringWithFormat:
         @"%.0f%%",
         floatingAlpha*100];

    }



    return cell;

}






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


}




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



    applyFloatingAlpha();

}




- (void)tableView:
(UITableView *)tableView
didSelectRowAtIndexPath:
(NSIndexPath *)indexPath
{


    if(indexPath.row==1)
    {


        SBCPUValuePickerController *vc =
        [[SBCPUValuePickerController alloc]
         initWithStyle:
         UITableViewStyleInsetGrouped];



        [self.navigationController
         pushViewController:vc
         animated:YES];

    }



    if(indexPath.row==2)
    {


        SBCPUTimePickerController *vc =
        [[SBCPUTimePickerController alloc]
         initWithStyle:
         UITableViewStyleInsetGrouped];



        [self.navigationController
         pushViewController:vc
         animated:YES];

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






    /*
     透明度
     */


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







    /*
     等 SpringBoard 完全启动
     */


    dispatch_after(
    dispatch_time(
    DISPATCH_TIME_NOW,
    5*NSEC_PER_SEC),
    dispatch_get_main_queue(),
    ^{


        createCPUWindow();




        /*
          定时刷新
        */


        [NSTimer
         scheduledTimerWithTimeInterval:
         1.0
         repeats:YES
         block:
         ^(NSTimer *timer)
         {


             updateCPU();


             double cpu =
             getCPUUsage();


             checkHighCPU(cpu);



         }];



    });



}
