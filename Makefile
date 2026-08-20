ARCHS = arm64e

TARGET = iphone:clang:17.0:17.0

THEOS_PACKAGE_SCHEME = roothide


include $(THEOS)/makefiles/common.mk


TWEAK_NAME = SBCPUFloating


SBCPUFloating_FILES = Tweak.xm

SBCPUFloating_CFLAGS = -fobjc-arc


include $(THEOS_MAKE_PATH)/tweak.mk


INSTALL_TARGET_PROCESSES = SpringBoard
