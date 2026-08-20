#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <mach/mach.h>
#import <signal.h>


#pragma mark -
#pragma mark V1.5.9 Global
#pragma mark -


static UIWindow *cpuWindow;

static UILabel *label;


/*
 设置页面是否显示
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
 V1.5.9
 横屏状态
 */

static BOOL landscapeMode = NO;



#pragma mark -
#pragma mark 前置声明
#pragma mark -


static void openSettings(void);

static void checkHighCPU(double cpu);

static void updateOrientation(void);



@class SBCPUValuePickerController;
@class SBCPUTimePickerController;



#pragma mark -
#pragma mark WindowScene
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
#pragma mark V1.5.9 横屏电量
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

            if(!label)
            {
                return;
            }



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



            if(center.y < halfH+40)
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
#pragma mark SBCPUWindow
#pragma mark -


@interface SBCPUWindow : UIWindow

@end



@implementation SBCPUWindow


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
        center.x =
        halfW;
    }



    if(center.x >
       size.width-halfW)
    {
        center.x =
        size.width-halfW;
    }



    if(center.y < halfH+40)
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




    /*
     V1.5.9
     横屏监听
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
     weight:
     UIFontWeightBold];



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



    drag.multipleTouchEnabled =
    NO;



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
                        5 *
                        NSEC_PER_SEC),
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



            if(landscapeMode)
            {

                label.numberOfLines = 3;


                label.frame =
                CGRectMake(
                    label.frame.origin.x,
                    label.frame.origin.y,
                    100,
                    70
                );



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


                label.frame =
                CGRectMake(
                    label.frame.origin.x,
                    label.frame.origin.y,
                    100,
                    50
                );



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
#pragma mark CPU值选择
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



    cell.textLabel.text =
    titles[indexPath.row];



    return cell;

}


@end
