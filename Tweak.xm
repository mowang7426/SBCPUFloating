#import <UIKit/UIKit.h>


static UILabel *label;



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





@interface SBCPUFloatingLabel : UILabel

@property(nonatomic,assign) CGPoint lastPoint;

@end





@implementation SBCPUFloatingLabel



// 强制接收触摸

- (UIView *)hitTest:(CGPoint)point
          withEvent:(UIEvent *)event
{

    return self;

}




- (void)touchesBegan:(NSSet<UITouch *> *)touches
           withEvent:(UIEvent *)event
{

    UITouch *touch =
    [touches anyObject];


    self.lastPoint =
    [touch locationInView:self.superview];


    NSLog(@"[SBCPUFloating] touch begin");

}





- (void)touchesMoved:(NSSet<UITouch *> *)touches
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
    self.bounds.size.width / 2;


    CGFloat halfH =
    self.bounds.size.height / 2;



    // 限制左右

    if(center.x < halfW)
        center.x = halfW;


    if(center.x > size.width-halfW)
        center.x = size.width-halfW;



    // 限制上下

    if(center.y < halfH+40)
        center.y = halfH+40;


    if(center.y > size.height-halfH)
        center.y = size.height-halfH;



    self.center=center;



    self.lastPoint=now;


    NSLog(@"[SBCPUFloating] moving");

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



UIWindow *window=nil;



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
                window=w;
                break;
            }

        }

    }


    if(window)
        break;

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


label.numberOfLines=2;



label.layer.cornerRadius=12;


label.clipsToBounds=YES;



label.textColor =
UIColor.whiteColor;



label.userInteractionEnabled=YES;



[window addSubview:label];





[NSTimer scheduledTimerWithTimeInterval:3
repeats:YES
block:^(NSTimer *timer)
{

    updateCPU();

}];



});


}
