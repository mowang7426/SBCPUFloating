
TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = SBCPUFloating

SBCPUFloating_FILES = Tweak.xm
SBCPUFloating_CFLAGS = -fobjc-arc
SBCPUFloating_FRAMEWORKS = UIKit Foundation
SBCPUFloating_PRIVATE_FRAMEWORKS = PowerUI IOKit

include $(THEOS_MAKE_PATH)/tweak.mk

INSTALL_TARGET_PROCESSES = SpringBoard powerd smartchargingd thermalmonitord

