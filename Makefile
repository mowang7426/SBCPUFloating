ARCHS = arm64
TARGET = iphone:clang:latest:15.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = SBCPUFloating

SBCPUFloating_FILES = Tweak.xm SmartChargeController.mm

SBCPUFloating_CFLAGS = -fobjc-arc
SBCPUFloating_CFLAGS += -Wno-deprecated-declarations
SBCPUFloating_CFLAGS += -Wno-module-import-in-extern-c

SBCPUFloating_FRAMEWORKS = UIKit Foundation

SBCPUFloating_LDFLAGS += -framework IOKit

include $(THEOS_MAKE_PATH)/tweak.mk
