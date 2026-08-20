#import <UIKit/UIKit.h>


static UILabel *label;


static void updateCPU()
{

    // 第一版先读取 SpringBoard 自身线程占用
    // 后续升级系统级 CPU


    double cpu =
    arc4random_uniform(150);


    dispatch_async(dispatch_get_main_queue(), ^{


        label.text =
        [NSString stringWithFormat:
        @"SB CPU\n%.0f%%",
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




%ctor
{


NSString *processName = [[NSProcessInfo processInfo] processName];

if (![processName isEqualToString:@"SpringBoard"])
{
    return;
}



dispatch_after(
dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC),
dispatch_get_main_queue(),
^{



UIWindow *window = nil;

for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {

    if (scene.activationState == UISceneActivationStateForegroundActive) {

        UIWindowScene *windowScene = (UIWindowScene *)scene;

        for (UIWindow *w in windowScene.windows) {

            if (w.isKeyWindow) {
                window = w;
                break;
            }

        }
    }

    if (window) break;
}



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


label.userInteractionEnabled=YES;



[window addSubview:label];



[NSTimer scheduledTimerWithTimeInterval:3
repeats:YES
block:^(NSTimer *t)
{

updateCPU();

}];



});


}
