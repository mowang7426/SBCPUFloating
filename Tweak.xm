#import <UIKit/UIKit.h>
#import <mach/mach.h>
#import <signal.h>


static UIWindow *cpuWindow;
static UILabel *label;


// =======================
// v1.4 自动注销功能
// =======================

static NSTimeInterval cpuHighStartTime = 0;

static BOOL isAutoLogout = NO;





#pragma mark - SpringBoard CPU


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



    for(int i = 0; i < threadCount; i++)
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





// =======================
// v1.4 CPU持续高负载检测
// =======================


static void checkHighCPU(double cpu)
{


    if(isAutoLogout)
        return;



    if(cpu >= 100)
    {


        if(cpuHighStartTime == 0)
        {

            cpuHighStartTime =
            [[NSDate date] timeIntervalSince1970];

        }



        NSTimeInterval now =
        [[NSDate date] timeIntervalSince1970];



        NSTimeInterval duration =
        now - cpuHighStartTime;



        // CPU >=100 持续60秒

        if(duration >= 60)
        {


            isAutoLogout = YES;



            dispatch_async(
            dispatch_get_main_queue(),
            ^{


                kill(getpid(), SIGTERM);


            });


        }


    }
    else
    {

        cpuHighStartTime = 0;

    }


}






static void updateCPU()
{

    double cpu =
    getCPUUsage();



    // v1.4 新增检测
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
#pragma mark - Drag View


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







#pragma mark - Window


@interface SBCPUWindow : UIWindow
@end



@implementation SBCPUWindow
@end







%ctor
{


NSString *process =
[[NSProcessInfo processInfo] processName];



if(![process isEqualToString:@"SpringBoard"])
{
    return;
}




dispatch_after(
dispatch_time(
DISPATCH_TIME_NOW,
5*NSEC_PER_SEC),
dispatch_get_main_queue(),
^{



cpuWindow =
[[SBCPUWindow alloc]
initWithFrame:
UIScreen.mainScreen.bounds];





for(UIScene *scene in
UIApplication.sharedApplication.connectedScenes)
{

    if([scene isKindOfClass:UIWindowScene.class])
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
initWithFrame:label.frame];



drag.backgroundColor =
UIColor.clearColor;



drag.userInteractionEnabled = YES;







[cpuWindow.rootViewController.view
 addSubview:label];



[cpuWindow.rootViewController.view
 addSubview:drag];








[NSTimer scheduledTimerWithTimeInterval:1
repeats:YES
block:^(NSTimer *timer)
{

    updateCPU();

}];




});



}
