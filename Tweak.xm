#import <UIKit/UIKit.h>
#import <mach/mach.h>


#pragma mark - v1.5 配置


static UIWindow *cpuWindow;

static UILabel *label;



// 自动注销设置

static BOOL autoLogoutEnable = NO;


// CPU触发值

static double logoutCPUThreshold = 100.0;


// 持续时间

static NSInteger logoutDuration = 60;



// 高CPU开始时间

static NSDate *cpuHighStartTime = nil;



// 防止重复触发

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



    for(int i = 0;
        i < threadCount;
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






#pragma mark - v1.5 自动注销检测


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




    if(time >= logoutDuration
       &&
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
             @"将在5秒后注销"
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

                 logoutCounting = NO;

                 cpuHighStartTime = nil;

             }];



            [alert addAction:cancel];




            UIViewController *vc =
            cpuWindow.rootViewController;



            [vc presentViewController:
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

                    // SpringBoard注销

                    kill(
                    getpid(),
                    SIGTERM
                    );


                }


            });



        });


    }


}
#pragma mark - 拖动视图
// v1.4成功版本 保留


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




    // 左右限制

    if(center.x < halfW)

        center.x = halfW;



    if(center.x > size.width-halfW)

        center.x = size.width-halfW;





    // 上下限制


    if(center.y < halfH+40)

        center.y = halfH+40;



    if(center.y > size.height-halfH)

        center.y = size.height-halfH;






    label.center = center;


    self.center = center;



    self.lastPoint = now;



}



@end







#pragma mark - Window


@interface SBCPUWindow : UIWindow

@end



@implementation SBCPUWindow

@end







#pragma mark - 双击手势


static void addDoubleTap()
{


    label.userInteractionEnabled = YES;



    UITapGestureRecognizer *tap =
    [[UITapGestureRecognizer alloc]
     initWithTarget:nil
     action:nil];



    tap.numberOfTapsRequired = 2;



    [label addGestureRecognizer:tap];



}









#pragma mark - 创建浮窗



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





cpuWindow.windowLevel =
UIWindowLevelAlert + 1;



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
[UIFont monospacedDigitSystemFontOfSize:14
weight:UIFontWeightBold];



label.text =
@"SB CPU\n0%";





SBCPUDragView *drag =
[[SBCPUDragView alloc]
 initWithFrame:
 label.frame];



drag.backgroundColor =
UIColor.clearColor;



drag.userInteractionEnabled = YES;





[cpuWindow.rootViewController.view
 addSubview:label];



[cpuWindow.rootViewController.view
 addSubview:drag];





// 双击检测

UITapGestureRecognizer *doubleTap =
[[UITapGestureRecognizer alloc]
 initWithTarget:nil
 action:nil];


doubleTap.numberOfTapsRequired = 2;



[label addGestureRecognizer:doubleTap];





return;

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


    self.tableView =
    [[UITableView alloc]
     initWithFrame:CGRectZero
     style:UITableViewStyleInsetGrouped];

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
     initWithStyle:UITableViewCellStyleValue1
     reuseIdentifier:nil];



    NSUserDefaults *def =
    [NSUserDefaults standardUserDefaults];



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
               action:@selector(switchChanged:)
     forControlEvents:UIControlEventValueChanged];



        cell.accessoryView = sw;


    }


    else if(indexPath.row == 1)
    {


        cell.textLabel.text =
        @"CPU触发值";



        cell.detailTextLabel.text =
        [NSString stringWithFormat:
         @"%.0f%%",
         logoutCPUThreshold];


    }



    else if(indexPath.row == 2)
    {


        cell.textLabel.text =
        @"持续时间";



        cell.detailTextLabel.text =
        [NSString stringWithFormat:
         @"%ld秒",
         logoutDuration];

    }



    return cell;


}





- (void)switchChanged:(UISwitch *)sw
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
         @"请输入CPU百分比"
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
         @"请输入秒数"
         preferredStyle:
         UIAlertControllerStyleAlert];



        [alert addTextFieldWithConfigurationHandler:
         ^(UITextField *tf)
         {

             tf.text =
             [NSString stringWithFormat:
              @"%ld",
              logoutDuration];

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







#pragma mark - 双击绑定


static void setupDoubleTap()
{


    UITapGestureRecognizer *tap =
    [[UITapGestureRecognizer alloc]
     initWithTarget:
     [NSBlockOperation class]
     action:nil];



    tap.numberOfTapsRequired = 2;



    [label addGestureRecognizer:tap];


}
