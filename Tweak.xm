#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <mach/mach.h>
#import <signal.h>



#pragma mark - SBCPUFloating V1.5.8 FIX



static UIWindow *cpuWindow;


static UILabel *label;


static UIView *dragView;



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



#pragma mark - 横竖屏状态


static BOOL landscapeMode = NO;



#pragma mark - 前置声明


static void openSettings(void);


static void updateOrientation(void);


static void updateFloatingText(double cpu);



#pragma mark - 获取当前 UIWindowScene


static UIWindowScene *getCurrentWindowScene()
{

    UIApplication *app =
    UIApplication.sharedApplication;



    for(UIScene *scene in
        app.connectedScenes)
    {


        if([scene
            isKindOfClass:
            UIWindowScene.class])
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





#pragma mark - 判断横屏


static BOOL isLandscape()
{

    UIWindowScene *scene =
    getCurrentWindowScene();



    if(!scene)
    {
        return NO;
    }



    UIInterfaceOrientation orientation =
    scene.interfaceOrientation;



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







#pragma mark - 获取 SpringBoard CPU



static double getCPUUsage()
{

    thread_array_t threads;


    mach_msg_type_number_t count =
    0;



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



    for(int i = 0;
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







#pragma mark - 应用透明度



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
#pragma mark - Root Controller 支持旋转


@interface SBCPURootController : UIViewController

@end



@implementation SBCPURootController


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







#pragma mark - 拖动层



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


@end










#pragma mark - 更新横竖屏布局



static void updateOrientation()
{

    dispatch_async(
        dispatch_get_main_queue(),
        ^{


            if(!label)
                return;




            BOOL nowLandscape =
            isLandscape();





            landscapeMode =
            nowLandscape;





            if(nowLandscape)
            {


                /*
                 横屏模式

                 显示 CPU + 电量

                 */


                label.frame =
                CGRectMake(
                    40,
                    120,
                    170,
                    60
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
                 竖屏模式

                 只显示 CPU

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





            if(dragView)
            {

                dragView.frame =
                label.frame;

            }




        });

}








#pragma mark - 更新文字



static void updateFloatingText(double cpu)
{

    if(!label)
        return;




    if(landscapeMode)
    {


        NSInteger battery =
        getBatteryLevel();




        label.text =
        [
         NSString
         stringWithFormat:
         @"SB CPU\n%.1f%%\nBAT %ld%%",
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









#pragma mark - 创建悬浮窗



static void createCPUWindow()
{


    CGRect frame =
    UIScreen.mainScreen.bounds;



    cpuWindow =
    [[SBCPUWindow alloc]
     initWithFrame:
     frame];





    UIWindowScene *scene =
    getCurrentWindowScene();



    if(scene)
    {

        cpuWindow.windowScene =
        scene;

    }






    cpuWindow.windowLevel =
    UIWindowLevelAlert + 1;



    cpuWindow.backgroundColor =
    UIColor.clearColor;



    cpuWindow.rootViewController =
    [SBCPURootController new];



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
    3;



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






    dragView =
    [[SBCPUDragView alloc]
     initWithFrame:
     label.frame];



    dragView.backgroundColor =
    UIColor.clearColor;



    dragView.userInteractionEnabled =
    YES;







    [cpuWindow.rootViewController.view
     addSubview:label];



    [cpuWindow.rootViewController.view
     addSubview:dragView];





    UITapGestureRecognizer *tap =
    [[UITapGestureRecognizer alloc]
     initWithTarget:
     [SBCPUAction class]
     action:
     @selector(doubleTapAction)];



    tap.numberOfTapsRequired =
    2;



    [dragView addGestureRecognizer:
     tap];





    applyFloatingAlpha();



    updateOrientation();


}
#pragma mark - 双击事件


@interface SBCPUAction : NSObject

@end



@implementation SBCPUAction


+ (void)doubleTapAction
{

    openSettings();

}


@end








#pragma mark - 打开设置


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



    settingsShowing = YES;





    UIViewController *root =
    cpuWindow.rootViewController;



    if(!root)
    {
        settingsShowing = NO;
        return;
    }






    UITableViewController *vc =
    [[UITableViewController alloc]
     initWithStyle:
     UITableViewStyleInsetGrouped];



    vc.title =
    @"SBCPUFloating";





    UINavigationController *nav =
    [[UINavigationController alloc]
     initWithRootViewController:
     vc];



    nav.modalPresentationStyle =
    UIModalPresentationPageSheet;






    [root
     presentViewController:
     nav
     animated:YES
     completion:nil];



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
                  ^(UIAlertAction *action)
                  {

                    logoutCounting = NO;

                    cpuHighStartTime = nil;

                  }
                 ]
                ];






                UIViewController *root =
                cpuWindow.rootViewController;





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




            updateOrientation();



            updateFloatingText(cpu);



        });


}









#pragma mark - 监听旋转



static void registerRotation()
{


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




    UIDevice.currentDevice
    .batteryMonitoringEnabled = YES;


}









#pragma mark - 加载配置



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




    if(alpha >= 0.2 &&
       alpha <= 1.0)
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






    UIDevice.currentDevice
    .batteryMonitoringEnabled = YES;






    dispatch_after(
        dispatch_time(
            DISPATCH_TIME_NOW,
            5*NSEC_PER_SEC),
        dispatch_get_main_queue(),
        ^{


            createCPUWindow();




            registerRotation();






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
