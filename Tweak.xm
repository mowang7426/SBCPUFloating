#import <UIKit/UIKit.h>
#import <mach/mach.h>
#import <signal.h>


#pragma mark - V1.5.3 全局


static UIWindow *cpuWindow;

static UILabel *label;



static void openSettings();





#pragma mark - 自动注销配置


static BOOL autoLogoutEnable = NO;


static double logoutCPUThreshold = 100.0;


static NSInteger logoutDuration = 60;



static NSDate *cpuHighStartTime = nil;


static BOOL logoutCounting = NO;






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



    for(int i=0;
        i<threadCount;
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
        threadCount*sizeof(thread_t)
    );



    return total;

}







#pragma mark - 自动注销检测


static void checkHighCPU(double cpu)
{


    if(!autoLogoutEnable)
    {

        cpuHighStartTime=nil;
        logoutCounting=NO;

        return;

    }




    if(cpu < logoutCPUThreshold)
    {

        cpuHighStartTime=nil;
        logoutCounting=NO;

        return;

    }





    if(cpuHighStartTime==nil)
    {

        cpuHighStartTime=[NSDate date];

        return;

    }





    NSTimeInterval time =
    [[NSDate date]
     timeIntervalSinceDate:
     cpuHighStartTime];




    if(time >= logoutDuration
       &&
       !logoutCounting)
    {


        logoutCounting=YES;



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



            UIAlertAction *cancel =
            [UIAlertAction
             actionWithTitle:
             @"取消"
             style:
             UIAlertActionStyleCancel
             handler:
             ^(UIAlertAction *action)
             {

                 logoutCounting=NO;
                 cpuHighStartTime=nil;

             }];



            [alert addAction:cancel];



            [cpuWindow.rootViewController
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

                    kill(getpid(),SIGTERM);

                }


            });



        });


    }


}
#pragma mark - 拖动视图 V1.5.3 保留


@interface SBCPUDragView : UIView

@property(nonatomic,assign) CGPoint lastPoint;

@end






@implementation SBCPUDragView



- (void)touchesBegan:(NSSet *)touches
           withEvent:(UIEvent *)event
{


    UITouch *touch =
    [touches anyObject];



    self.lastPoint =
    [touch locationInView:self.superview];


}







- (void)touchesMoved:(NSSet *)touches
           withEvent:(UIEvent *)event
{


    UITouch *touch =
    [touches anyObject];



    CGPoint now =
    [touch locationInView:self.superview];



    CGFloat dx =
    now.x - self.lastPoint.x;



    CGFloat dy =
    now.y - self.lastPoint.y;




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



    if(center.x > size.width-halfW)

        center.x = size.width-halfW;





    if(center.y < halfH+40)

        center.y = halfH+40;



    if(center.y > size.height-halfH)

        center.y = size.height-halfH;





    label.center = center;


    self.center = center;



    self.lastPoint = now;


}


@end







#pragma mark - Window V1.5.3 修复


@interface SBCPUWindow : UIWindow

@end






@implementation SBCPUWindow



// 修复桌面、控制中心触摸失效


- (UIView *)hitTest:(CGPoint)point
          withEvent:(UIEvent *)event
{


    UIView *view =
    [super hitTest:point
        withEvent:event];



    /*
     
     如果点到 Window 空白区域
     放行给 SpringBoard
     
     */


    if(view == self)
    {

        return nil;

    }



    return view;


}



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
#pragma mark - 创建浮窗 V1.5.3


static void createCPUWindow()
{


    cpuWindow =
    [[SBCPUWindow alloc]
     initWithFrame:
     UIScreen.mainScreen.bounds];






    for(UIScene *scene in
        UIApplication.sharedApplication.connectedScenes)
    {


        if([scene isKindOfClass:
            UIWindowScene.class])
        {


            cpuWindow.windowScene =
            (UIWindowScene *)scene;


            break;

        }


    }






    /*
     
     V1.5.3 修复
     
     不再压制 SpringBoard
     
     */


    cpuWindow.windowLevel =
    UIWindowLevelAlert;





    cpuWindow.backgroundColor =
    UIColor.clearColor;



    cpuWindow.rootViewController =
    [UIViewController new];



    cpuWindow.hidden = NO;







    label =
    [[UILabel alloc]
     initWithFrame:
     CGRectMake(30,200,100,50)];



    label.backgroundColor =
    [[UIColor blackColor]
     colorWithAlphaComponent:0.7];



    label.textAlignment =
    NSTextAlignmentCenter;



    label.numberOfLines = 2;



    label.layer.cornerRadius = 12;



    label.clipsToBounds = YES;



    label.textColor =
    UIColor.whiteColor;



    label.font =
    [UIFont
     monospacedDigitSystemFontOfSize:14
     weight:UIFontWeightBold];



    label.text =
    @"SB CPU\n0%";









    /*
     
     拖动层
     
     保留 V1.4
     
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
     
     绑定 drag
     
     避免 label 被覆盖
     
     */


    UITapGestureRecognizer *doubleTap =
    [[UITapGestureRecognizer alloc]
     initWithTarget:
     [SBCPUAction class]
     action:
     @selector(doubleTapAction)];



    doubleTap.numberOfTapsRequired = 2;



    [drag addGestureRecognizer:doubleTap];



    drag.userInteractionEnabled = YES;



}
#pragma mark - 设置页面


@interface SBCPUSettingsController : UITableViewController

@end




@implementation SBCPUSettingsController



- (void)viewDidLoad
{

    [super viewDidLoad];


    self.title =
    @"SBCPUFloating 设置";


}






- (NSInteger)tableView:(UITableView *)tableView
 numberOfRowsInSection:(NSInteger)section
{

    return 3;

}






- (NSString *)tableView:(UITableView *)tableView
titleForHeaderInSection:(NSInteger)section
{

    return @"自动注销设置";

}








- (UITableViewCell *)tableView:(UITableView *)tableView
cellForRowAtIndexPath:(NSIndexPath *)indexPath
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
               action:@selector(changeSwitch:)
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
         (long)logoutDuration];


    }



    return cell;


}








- (void)changeSwitch:(UISwitch *)sw
{


    autoLogoutEnable =
    sw.isOn;



    [[NSUserDefaults standardUserDefaults]
     setBool:autoLogoutEnable
     forKey:@"SBCPU.AutoLogout"];


}








- (void)tableView:(UITableView *)tableView
didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{


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



        [alert addTextFieldWithConfigurationHandler:
         ^(UITextField *tf)
         {

             tf.text =
             [NSString stringWithFormat:
              @"%.0f",
              logoutCPUThreshold];

         }];




        UIAlertAction *ok =
        [UIAlertAction
         actionWithTitle:
         @"保存"
         style:
         UIAlertActionStyleDefault
         handler:
         ^(UIAlertAction *a)
         {


             double value =
             [alert.textFields[0].text doubleValue];



             if(value < 80)
                 value = 80;



             if(value > 200)
                 value = 200;



             logoutCPUThreshold =
             value;



             [[NSUserDefaults standardUserDefaults]
              setDouble:value
              forKey:@"SBCPU.CPUThreshold"];



             [self.tableView reloadData];


         }];



        [alert addAction:ok];



        [self presentViewController:alert
                           animated:YES
                         completion:nil];


    }








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



        [alert addTextFieldWithConfigurationHandler:
         ^(UITextField *tf)
         {

             tf.text =
             [NSString stringWithFormat:
              @"%ld",
              (long)logoutDuration];

         }];





        UIAlertAction *ok =
        [UIAlertAction
         actionWithTitle:
         @"保存"
         style:
         UIAlertActionStyleDefault
         handler:
         ^(UIAlertAction *a)
         {


             NSInteger value =
             [alert.textFields[0].text integerValue];



             if(value < 10)
                 value = 10;



             if(value > 600)
                 value = 600;



             logoutDuration =
             value;



             [[NSUserDefaults standardUserDefaults]
              setInteger:value
              forKey:@"SBCPU.LogoutTime"];



             [self.tableView reloadData];


         }];



        [alert addAction:ok];



        [self presentViewController:alert
                           animated:YES
                         completion:nil];


    }



}


@end







#pragma mark - 打开设置


static void openSettings()
{


    SBCPUSettingsController *vc =
    [[SBCPUSettingsController alloc]
     initWithStyle:
     UITableViewStyleInsetGrouped];



    UINavigationController *nav =
    [[UINavigationController alloc]
     initWithRootViewController:vc];



    [cpuWindow.rootViewController
     presentViewController:nav
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








#pragma mark - 初始化


%ctor
{


    NSString *process =
    [[NSProcessInfo processInfo]
     processName];



    if(![process isEqualToString:@"SpringBoard"])
    {
        return;
    }







    NSUserDefaults *def =
    [NSUserDefaults standardUserDefaults];



    autoLogoutEnable =
    [def boolForKey:@"SBCPU.AutoLogout"];




    double cpu =
    [def doubleForKey:@"SBCPU.CPUThreshold"];



    if(cpu >= 80)
    {
        logoutCPUThreshold = cpu;
    }





    NSInteger time =
    [def integerForKey:@"SBCPU.LogoutTime"];



    if(time >= 10)
    {
        logoutDuration = time;
    }







    dispatch_after(
    dispatch_time(
    DISPATCH_TIME_NOW,
    5*NSEC_PER_SEC),
    dispatch_get_main_queue(),
    ^{


        createCPUWindow();



        [NSTimer scheduledTimerWithTimeInterval:1
        repeats:YES
        block:^(NSTimer *timer)
        {


            updateCPU();


        }];



    });



}
