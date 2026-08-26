```makefile
# ⚠️ 必须开启 rootless，适配 iOS 15+ Dopamine / XinaA15 等无根越狱环境
THEOS_PACKAGE_SCHEME = rootless

# 包含 arm64 (A11及以下) 和 arm64e (A12及以上，包括你的 iPhone 13 Pro Max)
ARCHS = arm64 arm64e

# SDK 使用 latest，最低兼容到 iOS 15.0
TARGET = iphone:clang:latest:15.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = SBCPUFloating

SBCPUFloating_FILES = Tweak.xm
SBCPUFloating_CFLAGS = -fobjc-arc
SBCPUFloating_FRAMEWORKS = UIKit Foundation
SBCPUFloating_PRIVATE_FRAMEWORKS = PowerUI IOKit

include $(THEOS_MAKE_PATH)/tweak.mk

INSTALL_TARGET_PROCESSES = SpringBoard powerd smartchargingd thermalmonitord

```
