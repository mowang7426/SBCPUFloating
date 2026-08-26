
TARGET := iphone:clang:latest:14.0
INSTALL_TARGET_PROCESSES = SpringBoard thermalmonitord
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = SBCPUFloating

SBCPUFloating_FILES = Tweak.xm
SBCPUFloating_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-variable -Wno-unused-function
SBCPUFloating_FRAMEWORKS = UIKit QuartzCore CoreMotion IOKit

include $(THEOS_MAKE_PATH)/tweak.mk

