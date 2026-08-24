#import <Foundation/Foundation.h>

@interface SmartChargeController : NSObject

// 停止充电
+ (BOOL)stopCharging;

// 恢复充电
+ (BOOL)restoreCharging;

// 设置充电电流
+ (BOOL)setCurrentLimit:(int)mA;

@end
