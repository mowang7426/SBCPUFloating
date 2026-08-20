#import <UIKit/UIKit.h>
#import <mach/mach.h>


static UILabel *label;



#pragma mark - Real SpringBoard CPU


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




#pragma mark - Drag Label


@interface SBCPUFloatingLabel : UILabel

@property(nonatomic,assign) CGPoint lastPoint;

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




    CGSize size =
    UIScreen.mainScreen.bounds.size;



    CGFloat halfW =
    self.bounds.size.width/2;


    CGFloat halfH =
    self.bounds.size.height/2;



    if(center.x < halfW)
        center.x = halfW;


    if(center.x > size.width-halfW)
        center.x = size.width-halfW;




    if(center.y < halfH+40)
        center.y = halfH+40;


    if(center.y > size.height-halfH)
        center.y = size.height-halfH;



    self.center = center;


    self.lastPoint = now;


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


        UIWindowScene *windowScene =
        (UIWindowScene *)scene;



        for(UIWindow *w in windowScene.windows)
        {


            if(w.isKeyWindow)
            {

                window = w;
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



label.userInteractionEnabled = YES;



[window addSubview:label];





[NSTimer scheduledTimerWithTimeInterval:1
repeats:YES
block:^(NSTimer *timer)
{

    updateCPU();

}];



});



}
