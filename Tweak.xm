#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <mach/mach.h>
#import <signal.h>


#pragma mark -
#pragma mark V1.5.8 Global
#pragma mark -


static UIWindow *cpuWindow;

static UILabel *label;



#pragma mark -
#pragma mark 设置入口
#pragma mark -


static void openSettings(void);





#pragma mark -
#pragma mark 自动注销配置
#pragma mark -


static BOOL autoLogoutEnable = NO;


static double logoutCPUThreshold = 100.0;


static NSInteger logoutDuration = 60;


static NSDate *cpuHighStartTime = nil;


static BOOL logoutCounting = NO;





#pragma mark -
#pragma mark 透明度
#pragma mark -


static BOOL floatingAlphaEnable = YES;


static CGFloat floatingAlpha = 0.70f;





#pragma mark -
#pragma mark V1.5.8 穿透 Window
#pragma mark -



@interface SBCPUPassthroughWindow : UIWindow

@end



@implementation SBCPUPassthroughWindow



/*
 *
 * 核心修复
 *
 * Window 不再吞掉 SpringBoard 触摸
 *
 */


- (UIView *)hitTest:(CGPoint)point
          withEvent:(UIEvent *)event
{

    UIView *view =
    [super hitTest:point
        withEvent:event];



    if(view == self.rootViewController.view)
    {
        return nil;
    }



    return view;

}


@end







#pragma mark -
#pragma mark 获取 Scene
#pragma mark -



static UIWindowScene *getWindowScene()
{

    for(UIScene *scene in
        UIApplication.sharedApplication.connectedScenes)
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
#pragma mark CPU 获取
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









#pragma mark -
#pragma mark 应用透明度
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
#pragma mark 拖动视图
#pragma mark -



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
    UIScreen.mainScreen.bounds.size;



    CGFloat halfW =
    label.bounds.size.width/2;



    CGFloat halfH =
    label.bounds.size.height/2;





    center.x =
    MAX(
        halfW,
        MIN(
            size.width-halfW,
            center.x
        )
    );




    center.y =
    MAX(
        halfH+40,
        MIN(
            size.height-halfH,
            center.y
        )
    );




    label.center =
    center;



    self.center =
    center;



    self.lastPoint =
    now;



}




@end
#pragma mark -
#pragma mark CPU Window
#pragma mark -


@interface SBCPUWindow : SBCPUPassthroughWindow

@end


@implementation SBCPUWindow

@end







#pragma mark -
#pragma mark 双击事件
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


    cpuWindow =
    [[SBCPUWindow alloc]
     initWithFrame:
     UIScreen.mainScreen.bounds];




    UIWindowScene *scene =
    getWindowScene();



    if(scene)
    {
        cpuWindow.windowScene =
        scene;
    }






    /*
     V1.5.8

     降低层级

     不再使用 Alert+1

     */


    cpuWindow.windowLevel =
    UIWindowLevelStatusBar + 1;






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
    [[UIColor blackColor]
     colorWithAlphaComponent:
     0.7];






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







    /*
     重要

     只允许浮窗区域接受事件

     */

    drag.exclusiveTouch =
    NO;







    [cpuWindow.rootViewController.view
     addSubview:label];





    [cpuWindow.rootViewController.view
     addSubview:drag];







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






    applyFloatingAlpha();


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






        });



}
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



    /*
     V1.5.8

     不 dismiss window
     不切换 keyWindow

     只关闭控制器

     */


    [self dismissViewControllerAnimated:YES
                             completion:nil];


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
        [[UISwitch alloc]
         init];



        sw.on =
        autoLogoutEnable;





        [sw addTarget:self
               action:@selector(changeLogout:)
     forControlEvents:UIControlEventValueChanged];




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
         logoutDuration];


    }









    if(indexPath.row == 3)
    {


        cell.textLabel.text =
        @"透明度开关";




        UISwitch *sw =
        [[UISwitch alloc]
         init];



        sw.on =
        floatingAlphaEnable;






        [sw addTarget:self
               action:@selector(changeAlpha:)
     forControlEvents:UIControlEventValueChanged];





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
         floatingAlpha*100];


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
     setBool:autoLogoutEnable
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
     setBool:floatingAlphaEnable
     forKey:
     @"SBCPU.FloatingAlphaEnable"];





    [[NSUserDefaults standardUserDefaults]
     synchronize];




    applyFloatingAlpha();


}









#pragma mark -
#pragma mark 点击项目
#pragma mark -



- (void)tableView:
(UITableView *)tableView
didSelectRowAtIndexPath:
(NSIndexPath *)indexPath

{


    /*
     CPU列表

     */


    if(indexPath.row == 1)
    {


        SBCPUValuePickerController *vc =
        [[SBCPUValuePickerController alloc]
         initWithStyle:
         UITableViewStyleInsetGrouped];




        [self.navigationController
         pushViewController:vc
         animated:YES];

    }







    /*
     时间列表
     */


    if(indexPath.row == 2)
    {


        SBCPUTimePickerController *vc =
        [[SBCPUTimePickerController alloc]
         initWithStyle:
         UITableViewStyleInsetGrouped];




        [self.navigationController
         pushViewController:vc
         animated:YES];

    }








    /*
     透明度

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







        NSArray *title =
        @[
          @"20%",
          @"40%",
          @"60%",
          @"70%",
          @"80%",
          @"100%"
        ];







        NSArray *value =
        @[
          @0.2,
          @0.4,
          @0.6,
          @0.7,
          @0.8,
          @1.0
        ];







        for(int i=0;i<title.count;i++)
        {


            [alert addAction:
             [UIAlertAction
              actionWithTitle:title[i]
              style:UIAlertActionStyleDefault
              handler:^(UIAlertAction *a)
              {


                floatingAlpha =
                [value[i] floatValue];




                [[NSUserDefaults standardUserDefaults]
                 setFloat:floatingAlpha
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
          actionWithTitle:@"取消"
          style:UIAlertActionStyleCancel
          handler:nil]];







        [self presentViewController:
         alert
         animated:YES
         completion:nil];



    }







    [tableView deselectRowAtIndexPath:indexPath
                             animated:YES];


}



@end
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



    NSArray *values =
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
    values[indexPath.row];




    if([values[indexPath.row]
        integerValue]
       ==
       (NSInteger)logoutCPUThreshold)
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
    [values[indexPath.row]
     doubleValue];




    [[NSUserDefaults standardUserDefaults]
     setDouble:
     logoutCPUThreshold
     forKey:
     @"SBCPU.CPUThreshold"];




    [[NSUserDefaults standardUserDefaults]
     synchronize];




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



    NSArray *times =
    @[
      @"10秒",
      @"30秒",
      @"60秒",
      @"120秒",
      @"180秒",
      @"300秒",
      @"600秒"
    ];



    cell.textLabel.text =
    times[indexPath.row];




    NSString *current =
    [times[indexPath.row]
     stringByReplacingOccurrencesOfString:
     @"秒"
     withString:@""];




    if(current.integerValue ==
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


    NSArray *times =
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
    [times[indexPath.row]
     integerValue];





    [[NSUserDefaults standardUserDefaults]
     setInteger:
     logoutDuration
     forKey:
     @"SBCPU.LogoutTime"];





    [[NSUserDefaults standardUserDefaults]
     synchronize];





    [self.navigationController
     popViewControllerAnimated:YES];


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




    settingsShowing = YES;





    SBCPUSettingsController *vc =
    [[SBCPUSettingsController alloc]
     initWithStyle:
     UITableViewStyleInsetGrouped];






    UINavigationController *nav =
    [[UINavigationController alloc]
     initWithRootViewController:
     vc];







    /*
     关键修复

     使用当前 Window

     不创建新 Window

     不 makeKeyWindow

     */


    nav.modalPresentationStyle =
    UIModalPresentationPageSheet;






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



    if(![process isEqualToString:
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
