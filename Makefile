ARCHS = arm64
TARGET = iphone:clang:latest:14.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = SBCPUFloating

SBCPUFloating_FILES = Tweak.xm SmartChargeController.mm

SBCPUFloating_CFLAGS = -fobjc-arc

SBCPUFloating_FRAMEWORKS = UIKit Foundation IOKit

include $(THEOS_MAKE_PATH)/tweak.mk
