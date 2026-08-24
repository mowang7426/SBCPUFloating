#import "SmartChargeController.h"

@implementation SmartChargeController

+ (BOOL)stopCharging
{
    NSLog(@"SmartCharge stopCharging called");

    // 后续接 Battman 停止充电接口
    return YES;
}


+ (BOOL)restoreCharging
{
    NSLog(@"SmartCharge restoreCharging called");

    // 后续接 Battman 恢复充电接口
    return YES;
}


+ (BOOL)setCurrentLimit:(int)mA
{
    NSLog(@"SmartCharge setCurrentLimit %d mA", mA);

    // 后续接 Battman 电流限制接口
    return YES;
}

@end
