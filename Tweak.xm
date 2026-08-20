#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <mach/mach.h>
#import <signal.h>


#pragma mark - V1.5.7 Global


static UIWindow *cpuWindow;

static UILabel *label;


/*
 当前设置页面
 */
static UINavigationController *settingsNavigation;


/*
 设置状态
 */
static BOOL settingsShowing = NO;



#pragma mark - 自动注销


static BOOL autoLogoutEnable = NO;


static double logoutCPUThreshold = 100.0;


static NSInteger logoutDuration = 60;


static NSDate *cpuHighStartTime = nil;


static BOOL logoutCounting = NO;



#pragma mark - 透明度


static BOOL floatingAlphaEnable = YES;


static CGFloat floatingAlpha = 0.70f;



#pragma mark - 前置声明


static void openSettings(void);





#pragma mark - 获取 SpringBoard CPU


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





#pragma mark - 应用透明度


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
    UIScreen.mainScreen.bounds.size;




    CGFloat halfW =
    label.bounds.size.width/2;



    CGFloat halfH =
    label.bounds.size.height/2;




    if(center.x < halfW)
        center.x = halfW;



    if(center.x >
       size.width-halfW)
        center.x =
        size.width-halfW;



    if(center.y <
       halfH+40)
        center.y =
        halfH+40;



    if(center.y >
       size.height-halfH)
        center.y =
        size.height-halfH;



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









#pragma mark - 双击事件


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
     保持最高显示
     但是不抢 KeyWindow
     */

    cpuWindow.windowLevel =
    UIWindowLevelAlert+1;



    cpuWindow.backgroundColor =
    UIColor.clearColor;



    cpuWindow.rootViewController =
    [UIViewController new];



    cpuWindow.hidden =
    NO;







    label =
    [[UILabel alloc]
     initWithFrame:
     CGRectMake(30,200,100,50)];



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






    /*
     拖动透明层
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





    applyFloatingAlpha();


}
#pragma mark - 设置主页


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



#pragma mark - 关闭设置


- (void)closeSettings
{

    /*
     V1.5.7 修复触摸锁死

     不再隐藏 UIWindow
     不创建额外 Window

     只关闭当前控制器
     */


    [self dismissViewControllerAnimated:YES
                             completion:
     ^{

        /*
         恢复悬浮窗交互
         */


        cpuWindow.userInteractionEnabled = YES;


        cpuWindow.rootViewController.view
        .userInteractionEnabled = YES;



        if(previousKeyWindow)
        {
            [previousKeyWindow makeKeyWindow];
        }


        previousKeyWindow = nil;

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




#pragma mark - 标题


- (NSString *)tableView:
(UITableView *)tableView
titleForHeaderInSection:
(NSInteger)section
{

    return @"自动注销 / 悬浮窗";

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
     forControlEvents:
        UIControlEventValueChanged];


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
     forControlEvents:
        UIControlEventValueChanged];


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




#pragma mark - 自动注销


- (void)changeLogout:
(UISwitch *)sw

{

    autoLogoutEnable =
    sw.isOn;



    [[NSUserDefaults standardUserDefaults]
     setBool:autoLogoutEnable
     forKey:@"SBCPU.AutoLogout"];


    [[NSUserDefaults standardUserDefaults]
     synchronize];

}





#pragma mark - 透明度


- (void)changeAlpha:
(UISwitch *)sw

{

    floatingAlphaEnable =
    sw.isOn;



    [[NSUserDefaults standardUserDefaults]
     setBool:floatingAlphaEnable
     forKey:@"SBCPU.FloatingAlphaEnable"];



    [[NSUserDefaults standardUserDefaults]
     synchronize];


    applyFloatingAlpha();

}




#pragma mark - 点击项目


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
         pushViewController:
         vc
         animated:YES];

    }



    if(indexPath.row==2)
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



    if(indexPath.row==4)
    {

        UIAlertController *alert =
        [UIAlertController
         alertControllerWithTitle:
         @"透明度"
         message:
         @"选择透明度"
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



        for(int i=0;i<titles.count;i++)
        {

            [alert addAction:
             [UIAlertAction
              actionWithTitle:
              titles[i]
              style:
              UIAlertActionStyleDefault
              handler:
              ^(UIAlertAction *a)
              {


                floatingAlpha =
                [values[i] floatValue];


                [[NSUserDefaults standardUserDefaults]
                 setFloat:floatingAlpha
                 forKey:@"SBCPU.FloatingAlpha"];


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



    [tableView deselectRowAtIndexPath:indexPath
                             animated:YES];

}


@end
#pragma mark - 设置主页 V1.5.6 修复版


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



#pragma mark - 关闭设置


- (void)closeSettings
{

    /*
     V1.5.6 修复

     不再隐藏 Window
     不再切换 KeyWindow

     直接 dismiss
     */

    [self dismissViewControllerAnimated:YES
                             completion:nil];

}



#pragma mark - 行数


- (NSInteger)tableView:
(UITableView *)tableView
numberOfRowsInSection:
(NSInteger)section
{
    return 5;
}



#pragma mark - 标题


- (NSString *)tableView:
(UITableView *)tableView
titleForHeaderInSection:
(NSInteger)section
{

    return
    @"自动注销 / 悬浮窗";

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
     forControlEvents:
        UIControlEventValueChanged];



        cell.accessoryView =
        sw;

    }




    /*
     CPU触发值
     */

    if(indexPath.row==1)
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


    if(indexPath.row==2)
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
     forControlEvents:
        UIControlEventValueChanged];



        cell.accessoryView =
        sw;

    }





    /*
     透明度选择
     */


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




#pragma mark - 自动注销


- (void)changeLogout:
(UISwitch *)sw
{

    autoLogoutEnable =
    sw.isOn;



    [[NSUserDefaults standardUserDefaults]
     setBool:autoLogoutEnable
     forKey:@"SBCPU.AutoLogout"];


    [[NSUserDefaults standardUserDefaults]
     synchronize];

}





#pragma mark - 透明度


- (void)changeAlpha:
(UISwitch *)sw
{

    floatingAlphaEnable =
    sw.isOn;



    [[NSUserDefaults standardUserDefaults]
     setBool:floatingAlphaEnable
     forKey:@"SBCPU.FloatingAlphaEnable"];



    [[NSUserDefaults standardUserDefaults]
     synchronize];



    applyFloatingAlpha();

}





#pragma mark - 点击设置项目


- (void)tableView:
(UITableView *)tableView
didSelectRowAtIndexPath:
(NSIndexPath *)indexPath
{


    /*
     CPU选择

     改成列表方式
     避免键盘
     */

    if(indexPath.row==1)
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
     时间选择

     改成列表方式
     */

    if(indexPath.row==2)
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
     透明度

     */

    if(indexPath.row==4)
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
              actionWithTitle:
              title[i]
              style:
              UIAlertActionStyleDefault
              handler:
              ^(UIAlertAction *a)
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



    [tableView deselectRowAtIndexPath:indexPath
                             animated:YES];

}



@end
#pragma mark - V1.5.6 修复版打开设置


static void openSettings()
{

    if(!cpuWindow)
    {
        return;
    }



    /*
     V1.5.6 核心

     不创建新的 UIWindow

     直接使用悬浮窗自己的
     rootViewController

     避免：
     
     1. 全屏触摸失效
     2. SpringBoard 锁死
     3. Alert 后无法操作

     */


    SBCPUSettingsController *vc =
    [[SBCPUSettingsController alloc]
     initWithStyle:
     UITableViewStyleInsetGrouped];



    UINavigationController *nav =
    [[UINavigationController alloc]
     initWithRootViewController:vc];



    /*
     设置透明背景

     避免影响 SpringBoard
     */


    nav.modalPresentationStyle =
    UIModalPresentationFullScreen;



    UIViewController *root =
    cpuWindow.rootViewController;



    if(!root)
    {
        return;
    }




    [root
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



            if(cpu>=80)
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




    if(cpu>=80)
    {
        logoutCPUThreshold =
        cpu;
    }





    NSInteger time =
    [def integerForKey:
     @"SBCPU.LogoutTime"];




    if(time>=10)
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




    if(alpha>=0.2 &&
       alpha<=1.0)
    {

        floatingAlpha =
        alpha;

    }






    /*
     延迟创建

     等 SpringBoard 完全启动

     */


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
