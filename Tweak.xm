#import <UIKit/UIKit.h>


static NSString *posXKey = @"SBCPUFloating_X";
static NSString *posYKey = @"SBCPUFloating_Y";


static UIWindow *floatWindow;
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





@interface SBCPUFloatingView : UILabel

@property(nonatomic,assign) CGPoint lastPoint;

@end



@implementation SBCPUFloatingView



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
    self.center;


    center.x += dx;
    center.y += dy;



    CGSize screen =
    UIScreen.mainScreen.bounds.size;



    CGFloat halfW =
    self.bounds.size.width/2;


    CGFloat halfH =
    self.bounds.size.height/2;



    center.x =
    MAX(halfW,
    MIN(screen.width-halfW,
    center.x));



    center.y =
    MAX(halfH+40,
    MIN(screen.height-halfH,
    center.y));



    self.center=center;



    self.lastPoint=now;



    [[NSUserDefaults standardUserDefaults]
     setFloat:center.x
     forKey:posXKey];


    [[NSUserDefaults standardUserDefaults]
     setFloat:center.y
     forKey:posYKey];


    [[NSUserDefaults standardUserDefaults]
     synchronize];

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



floatWindow =
[[UIWindow alloc]
initWithFrame:
UIScreen.mainScreen.bounds];



floatWindow.windowLevel =
UIWindowLevelAlert + 100;



floatWindow.backgroundColor =
UIColor.clearColor;



floatWindow.rootViewController =
[UIViewController new];



floatWindow.hidden = NO;




SBCPUFloatingView *view =
[[SBCPUFloatingView alloc]
initWithFrame:
CGRectMake(30,200,100,50)];



label=view;



NSUserDefaults *def =
[NSUserDefaults standardUserDefaults];



float x =
[def floatForKey:posXKey];


float y =
[def floatForKey:posYKey];



if(x>0 && y>0)
{
    view.center =
    CGPointMake(x,y);
}



view.backgroundColor =
[[UIColor blackColor]
colorWithAlphaComponent:0.7];



view.textAlignment =
NSTextAlignmentCenter;


view.numberOfLines=2;


view.layer.cornerRadius=12;


view.clipsToBounds=YES;


view.textColor =
UIColor.whiteColor;



view.userInteractionEnabled=YES;



[floatWindow.rootViewController.view
 addSubview:view];



[NSTimer scheduledTimerWithTimeInterval:3
repeats:YES
block:^(NSTimer *timer)
{
    updateCPU();

}];



});

}
