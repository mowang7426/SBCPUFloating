#import "SmartChargeController.h"
#import <Foundation/Foundation.h>


@implementation SmartChargeController


// 停止充电
+ (BOOL)stopCharging
{

    NSLog(@"[SmartCharge] Stop Charging");

    /*
     这里接 Battman CH0C
    */

    return YES;
}


// 恢复充电
+ (BOOL)restoreCharging
{

    NSLog(@"[SmartCharge] Restore Charging");

    /*
     这里接 Battman CH0C restore
    */

    return YES;
}


// 限制电流
+ (BOOL)setCurrentLimit:(int)mA
{

    NSLog(@"[SmartCharge] Current Limit %d mA",mA);


    /*
      这里接 IOAccessoryManager
    */


    return YES;
}


@end
