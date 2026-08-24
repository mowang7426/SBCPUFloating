#import <Foundation/Foundation.h>

@interface SmartChargeController : NSObject

+ (BOOL)stopCharging;
+ (BOOL)restoreCharging;
+ (BOOL)setCurrentLimit:(int)mA;

@end
