#import <UIKit/UIKit.h>
#import <mach/mach.h>


static NSString *posXKey = @"SBCPUFloating_X";
static NSString *posYKey = @"SBCPUFloating_Y";



#pragma mark - 获取 SpringBoard CPU


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



    double totalCPU = 0;



    for(int i=0;i<threadCount;i++)
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

                totalCPU +=
                basic->cpu_usage /
                (double)TH_USAGE_SCALE *
                100.0;

            }

        }


    }



    vm_deallocate(
        mach_task_self(),
        (vm_address_t)threads,
        threadCount * sizeof(thread_t)
    );



    return totalCPU;

}




#pragma mark - 拖动Label


@interface SBCPUFloatingLabel : UILabel

@property(nonatomic,assign)
CGPoint lastPoint;

@end





@implementation SBCPUFloatingLabel



-(void)touchesBegan:(NSSet<UITouch *> *)touches
          withEvent:(UIEvent *)event
{

    UITouch *touch =
    [touches anyObject];


    self.lastPoint =
    [touch locationInView:self.superview];

}




-(void)touchesMoved:(NSSet<UITouch *> *)touches
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
    self.center;



    center.x += dx;
    center.y += dy;



    CGSize screen =
    UIScreen.mainScreen.bounds.size;



    CGFloat halfW =
    self.bounds.size.width/2;


    CGFloat halfH =
    self.bounds.size.height/2;



    // 防止左右出去

    if(center.x < halfW)
        center.x = halfW;


    if(center.x > screen.width-halfW)
        center.x = screen.width-halfW;



    // 防止上下出去

    if(center.y < halfH+50)
        center.y = halfH+50;


    if(center.y > screen.height-halfH)
        center.y = screen.height-halfH;



    self.center = center;



    self.lastPoint = now;



    NSUserDefaults *def =
    [NSUserDefaults standardUserDefaults];


    [def setFloat:center.x
          forKey:posXKey];


    [def setFloat:center.y
          forKey:posYKey];


}

@end








static SBCPUFloatingLabel *label;



#pragma mark - 更新显示


static void updateCPU()
{


    double cpu =
    getCPUUsage();



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



UIWindow *window = nil;



for(UIScene *scene in
UIApplication.sharedApplication.connectedScenes)
{


    if(scene.activationState ==
       UISceneActivationStateForegroundActive)
    {


        UIWindowScene *ws =
        (UIWindowScene *)scene;



        for(UIWindow *w in ws.windows)
        {

            if(w.isKeyWindow)
            {

                window=w;
                break;

            }

        }


    }


    if(window)
        break;


}




if(!window)
{
    return;
}





label =
[[SBCPUFloatingLabel alloc]
 initWithFrame:
 CGRectMake(30,200,110,55)];





NSUserDefaults *def =
[NSUserDefaults standardUserDefaults];



float x =
[def floatForKey:posXKey];


float y =
[def floatForKey:posYKey];



if(x>0 && y>0)
{

    label.center =
    CGPointMake(x,y);

}







label.backgroundColor =
[[UIColor blackColor]
 colorWithAlphaComponent:0.75];



label.textAlignment =
NSTextAlignmentCenter;



label.numberOfLines = 2;



label.textColor =
UIColor.whiteColor;



label.font =
[UIFont monospacedDigitSystemFontOfSize:14
                                weight:UIFontWeightBold];



label.layer.cornerRadius = 12;



label.clipsToBounds = YES;



label.userInteractionEnabled = YES;



[window addSubview:label];





[NSTimer scheduledTimerWithTimeInterval:1
                                 repeats:YES
                                   block:
^(NSTimer *timer)
{

    updateCPU();


}];



});



}
