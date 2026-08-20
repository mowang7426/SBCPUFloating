#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <mach/mach.h>
#import <signal.h>


#pragma mark - SBCPUFloating V1.5.8


static UIWindow *cpuWindow;

static UILabel *label;



#pragma mark - 设置状态


static BOOL settingsShowing = NO;



#pragma mark - 自动注销


static BOOL autoLogoutEnable = NO;

static double logoutCPUThreshold = 100.0;

static NSInteger logoutDuration = 60;

static NSDate *cpuHighStartTime = nil;

static BOOL logoutCounting = NO;



#pragma mark - 透明度


static BOOL floatingAlphaEnable = YES;

static CGFloat floatingAlpha = 0.7f;



#pragma mark - 横竖屏


static BOOL landscapeMode = NO;



#pragma mark - 前置声明


static void openSettings(void);

static void updateOrientation(void);

static void updateFloatingText(void);




#pragma mark - 获取当前方向


static BOOL isLandscape()
{

    UIInterfaceOrientation orientation =
    UIApplication.sharedApplication
    .windows.firstObject.windowScene.interfaceOrientation;


    return
    orientation ==
    UIInterfaceOrientationLandscapeLeft
    ||
    orientation ==
    UIInterfaceOrientationLandscapeRight;

}




#pragma mark - 获取电量


static NSInteger getBatteryLevel()
{

    UIDevice *device =
    UIDevice.currentDevice;


    device.batteryMonitoringEnabled = YES;


    float level =
    device.batteryLevel;



    if(level < 0)
    {
        return 0;
    }


    return
    (NSInteger)(level*100);

}
#pragma mark - CPU 获取


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



    for(int i=0;i<count;i++)
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





#pragma mark - 更新透明度


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





#pragma mark - 横竖屏更新


static void updateOrientation()
{

    dispatch_async(
        dispatch_get_main_queue(),
        ^{


            if(!label)
                return;



            BOOL nowLandscape =
            isLandscape();



            if(nowLandscape ==
               landscapeMode)
            {
                return;
            }



            landscapeMode =
            nowLandscape;



            if(landscapeMode)
            {

                /*
                 横屏
                 */

                label.frame =
                CGRectMake(
                    30,
                    120,
                    180,
                    50
                );



                label.font =
                [
                 UIFont
                 monospacedDigitSystemFontOfSize:
                 16
                 weight:
                 UIFontWeightBold
                ];



            }
            else
            {

                /*
                 竖屏
                 */

                label.frame =
                CGRectMake(
                    30,
                    200,
                    100,
                    50
                );



                label.font =
                [
                 UIFont
                 monospacedDigitSystemFontOfSize:
                 14
                 weight:
                 UIFontWeightBold
                ];


            }



            updateFloatingText();


        });

}





#pragma mark - 更新悬浮文字


static void updateFloatingText()
{

    if(!label)
        return;



    double cpu =
    getCPUUsage();




    if(landscapeMode)
    {

        NSInteger battery =
        getBatteryLevel();



        label.text =
        [
         NSString
         stringWithFormat:
         @"SB CPU %.1f%%\n🔋 %ld%%",
         cpu,
         (long)battery
        ];

    }
    else
    {

        label.text =
        [
         NSString
         stringWithFormat:
         @"SB CPU\n%.1f%%",
         cpu
        ];

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

}





#pragma mark - 监听旋转


static void registerOrientationObserver()
{

    [[NSNotificationCenter defaultCenter]
     addObserverForName:
     UIDeviceOrientationDidChangeNotification
     object:nil
     queue:
     [NSOperationQueue mainQueue]
     usingBlock:
     ^(NSNotification *n)
     {

        updateOrientation();

     }];


    UIDevice *device =
    UIDevice.currentDevice;


    device
    .batteryMonitoringEnabled = YES;


}
#pragma mark - 拖动层 V1.5.8


@interface SBCPUDragView : UIView

@property(nonatomic,assign)
CGPoint lastPoint;

@end



@implementation SBCPUDragView



- (void)touchesBegan:(NSSet *)touches
           withEvent:(UIEvent *)event
{

    UITouch *touch =
    touches.anyObject;


    self.lastPoint =
    [touch locationInView:
     self.superview];

}





- (void)touchesMoved:(NSSet *)touches
           withEvent:(UIEvent *)event
{


    UITouch *touch =
    touches.anyObject;



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





    /*
     V1.5.8

     使用 Window 实际大小

     不再使用 UIScreen

     修复横屏游戏拖动
     */


    CGSize size =
    cpuWindow.bounds.size;




    CGFloat halfW =
    label.bounds.size.width / 2;



    CGFloat halfH =
    label.bounds.size.height / 2;





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




    if(center.y < halfH+30)
    {
        center.y =
        halfH+30;
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


}



@end







#pragma mark - Window


@interface SBCPUWindow : UIWindow

@end



@implementation SBCPUWindow



/*
 V1.5.8

 允许旋转

 */

- (BOOL)shouldAutorotate
{
    return YES;
}



- (UIInterfaceOrientationMask)
supportedInterfaceOrientations
{

    return UIInterfaceOrientationMaskAll;

}


@end







#pragma mark - 双击


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





    for(UIScene *scene in
        UIApplication.sharedApplication.connectedScenes)
    {


        if([scene
            isKindOfClass:
            UIWindowScene.class])
        {

            cpuWindow.windowScene =
            (UIWindowScene *)scene;


            break;

        }

    }






    /*
     V1.5.8

     保持显示

     但是不抢触摸

     */

    cpuWindow.windowLevel =
    UIWindowLevelAlert + 1;



    cpuWindow.backgroundColor =
    UIColor.clearColor;



    cpuWindow.rootViewController =
    [UIViewController new];



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
    [
     UIColor.blackColor
     colorWithAlphaComponent:
     0.7
    ];



    label.textAlignment =
    NSTextAlignmentCenter;



    label.numberOfLines =
    2;



    label.layer.cornerRadius =
    12;



    label.clipsToBounds =
    YES;



    label.textColor =
    UIColor.whiteColor;



    label.font =
    [
     UIFont
     monospacedDigitSystemFontOfSize:
     14
     weight:
     UIFontWeightBold
    ];



    label.text =
    @"SB CPU\n0%";





    /*
     拖动透明层
     */


    SBCPUDragView *drag =
    [
     [SBCPUDragView alloc]
     initWithFrame:
     label.frame
    ];



    drag.backgroundColor =
    UIColor.clearColor;



    drag.userInteractionEnabled =
    YES;





    [cpuWindow.rootViewController.view
     addSubview:label];



    [cpuWindow.rootViewController.view
     addSubview:drag];






    /*
     双击打开设置

     */

    UITapGestureRecognizer *doubleTap =
    [
     [UITapGestureRecognizer alloc]
     initWithTarget:
     [SBCPUAction class]
     action:
     @selector(doubleTapAction)
    ];



    doubleTap.numberOfTapsRequired =
    2;



    [drag addGestureRecognizer:
     doubleTap];






    applyFloatingAlpha();



    /*
     注册旋转监听

     */

    registerOrientationObserver();



    /*
     初始化方向

     */

    updateOrientation();


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


                UIAlertController *alert =
                [
                 UIAlertController
                 alertControllerWithTitle:
                 @"SpringBoard CPU过高"
                 message:
                 @"5秒后自动注销"
                 preferredStyle:
                 UIAlertControllerStyleAlert
                ];






                [alert addAction:
                 [
                  UIAlertAction
                  actionWithTitle:
                  @"取消"
                  style:
                  UIAlertActionStyleCancel
                  handler:
                  ^(UIAlertAction *a)
                  {

                    logoutCounting = NO;

                    cpuHighStartTime = nil;

                  }
                 ]
                ];






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
                return;




            /*
             V1.5.8

             根据当前方向显示

             */

            updateFloatingText();



        });


}









#pragma mark - 设置加载


static void loadSettings()
{

    NSUserDefaults *def =
    NSUserDefaults.standardUserDefaults;




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

}









#pragma mark - 初始化


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






    loadSettings();







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
