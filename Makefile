ARCHS = arm64e

TARGET = iphone:clang:16.5:16.5

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = SBCPUFloating

SBCPUFloating_FILES = Tweak.xm SmartChargeController.mm

SBCPUFloating_CFLAGS = -fobjc-arc

SBCPUFloating_FRAMEWORKS = UIKit Foundation IOKit

include $(THEOS_MAKE_PATH)/tweak.mk

INSTALL_TARGET_PROCESSES = SpringBoard
