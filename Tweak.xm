#import <UIKit/UIKit.h>


static UILabel *label;


// 保存位置
static NSString *posXKey = @"SBCPUFloating_X";
static NSString *posYKey = @"SBCPUFloating_Y";



static void updateCPU()
{

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





// ======================
// 拖动处理
// ======================

@interface SBCPUDrag : NSObject
@end


@implementation SBCPUDrag


- (void)pan:(UIPanGestureRecognizer *)gesture
{

    UIView *view =
    gesture.view;


    CGPoint move =
    [gesture translationInView:view.superview];


    CGPoint center =
    view.center;


    center.x += move.x;
    center.y += move.y;



    CGSize screen =
    UIScreen.mainScreen.bounds.size;



    CGFloat halfW =
    view.bounds.size.width/2;


    CGFloat halfH =
    view.bounds.size.height/2;



    //限制左右

    if(center.x < halfW)
        center.x = halfW;


    if(center.x > screen.width-halfW)
        center.x = screen.width-halfW;




    //限制上下

    if(center.y < halfH+40)
        center.y = halfH+40;


    if(center.y > screen.height-halfH)
        center.y = screen.height-halfH;



    view.center=center;



    [[NSUserDefaults standardUserDefaults]
     setFloat:center.x
     forKey:posXKey];


    [[NSUserDefaults standardUserDefaults]
     setFloat:center.y
     forKey:posYKey];


    [[NSUserDefaults standardUserDefaults]
     synchronize];



    [gesture setTranslation:
     CGPointZero
     inView:view.superview];

}


@end



static SBCPUDrag *dragObject;




%ctor
{


NSString *processName =
[[NSProcessInfo processInfo] processName];


if (![processName isEqualToString:@"SpringBoard"])
{
    return;
}



dispatch_after(
dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC),
dispatch_get_main_queue(),
^{



UIWindow *window = nil;



for (UIScene *scene in
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
                window=w;
                break;
            }

        }

    }


    if(window)
        break;

}




label =
[[UILabel alloc]
 initWithFrame:
 CGRectMake(30,200,100,50)];




NSUserDefaults *def =
[NSUserDefaults standardUserDefaults];



float oldX =
[def floatForKey:posXKey];


float oldY =
[def floatForKey:posYKey];



if(oldX > 0 && oldY > 0)
{

    label.center =
    CGPointMake(oldX,oldY);

}
else
{

    label.frame =
    CGRectMake(30,200,100,50);

}





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



// 开启触摸

label.userInteractionEnabled=YES;



// 添加拖动

dragObject =
[SBCPUDrag new];



UIPanGestureRecognizer *pan =
[[UIPanGestureRecognizer alloc]
 initWithTarget:dragObject
 action:@selector(pan:)];



[label addGestureRecognizer:pan];





[window addSubview:label];





[NSTimer scheduledTimerWithTimeInterval:3
repeats:YES
block:^(NSTimer *t)
{

    updateCPU();

}];



});


}
