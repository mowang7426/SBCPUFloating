#import <UIKit/UIKit.h>
#import <mach/mach.h>
#import <mach/task_info.h>
#import <mach/mach_time.h>


static UIWindow *cpuWindow;
static UILabel *label;



static uint64_t lastCPUTime = 0;
static uint64_t lastTime = 0;





static double getSpringBoardCPU()
{

    task_thread_times_info_data_t info;

    mach_msg_type_number_t count =
    TASK_THREAD_TIMES_INFO_COUNT;



    kern_return_t kr =
    task_info(
        mach_task_self(),
        TASK_THREAD_TIMES_INFO,
        (task_info_t)&info,
        &count
    );



    if(kr != KERN_SUCCESS)
    {
        return 0;
    }



    uint64_t cpuTime =
    ((uint64_t)info.user_time.seconds +
     info.system_time.seconds)
    *
    1000000000ULL
    +
    info.user_time.nanoseconds
    +
    info.system_time.nanoseconds;



    uint64_t now =
    mach_absolute_time();



    if(lastCPUTime == 0)
    {

        lastCPUTime = cpuTime;
        lastTime = now;

        return 0;

    }



    mach_timebase_info_data_t timebase;

    mach_timebase_info(&timebase);



    uint64_t elapsed =
    (now-lastTime)
    *
    timebase.numer
    /
    timebase.denom;



    uint64_t cpuDelta =
    cpuTime-lastCPUTime;



    lastCPUTime = cpuTime;
    lastTime = now;



    if(elapsed == 0)
        return 0;



    double cpu =
    ((double)cpuDelta /
    (double)elapsed)
    *
    100.0;



    return cpu;

}








static void updateCPU()
{


    double cpu =
    getSpringBoardCPU();



    dispatch_async(dispatch_get_main_queue(), ^{


        label.text =
        [NSString stringWithFormat:
        @"SB CPU\n%.1f%%",
        cpu];



        if(cpu >= 100)
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



    label.center=center;


    self.center=center;



    self.lastPoint=now;


}



@end











%ctor
{


NSString *processName =
[[NSProcessInfo processInfo] processName];



if(![processName isEqualToString:@"SpringBoard"])
{
    return;
}





dispatch_after(
dispatch_time(DISPATCH_TIME_NOW,
5*NSEC_PER_SEC),
dispatch_get_main_queue(),
^{



cpuWindow =
[[UIWindow alloc]
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



label.numberOfLines=2;



label.layer.cornerRadius=12;



label.clipsToBounds=YES;



label.textColor =
UIColor.whiteColor;



label.text =
@"SB CPU\n0%";









SBCPUDragView *drag =
[[SBCPUDragView alloc]
initWithFrame:
label.frame];



drag.backgroundColor =
UIColor.clearColor;



drag.userInteractionEnabled=YES;



[cpuWindow.rootViewController.view
 addSubview:label];



[cpuWindow.rootViewController.view
 addSubview:drag];








[NSTimer scheduledTimerWithTimeInterval:3
repeats:YES
block:^(NSTimer *timer)
{

    updateCPU();

}];




});


}
