ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:15.0
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = WiFiToggle18
WiFiToggle18_BUNDLE_EXTENSION = bundle
WiFiToggle18_FILES = src/WiFiToggle18.m
WiFiToggle18_CFLAGS = -fobjc-arc
WiFiToggle18_FRAMEWORKS = Foundation UIKit
WiFiToggle18_PRIVATE_FRAMEWORKS = ControlCenterUIKit
WiFiToggle18_INSTALL_PATH = /Library/ControlCenter/Bundles

include $(THEOS_MAKE_PATH)/bundle.mk
