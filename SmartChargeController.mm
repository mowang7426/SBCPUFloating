#import "SmartChargeController.h"

@implementation SmartChargeController

+ (BOOL)stopCharging
{
    NSLog(@"SmartCharge stopCharging called");
    return NO;
}


+ (BOOL)restoreCharging
{
    NSLog(@"SmartCharge restoreCharging called");
    return NO;
}


+ (BOOL)setCurrentLimit:(int)mA
{
    NSLog(@"SmartCharge setCurrentLimit %d", mA);
    return NO;
}

@end
