ARCHS = arm64
TARGET = iphone:16.5:15.0
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = TGExtra

$(TWEAK_NAME)_FILES = $(shell find Sources \( -name '*.swift' -o -name '*.m' -o -name '*.xm' \))
$(TWEAK_NAME)_SWIFTFLAGS = -ISources/tgapiC/include
$(TWEAK_NAME)_CFLAGS = -fobjc-arc -ISources/tgapiC/include -Wno-deprecated-declarations
$(TWEAK_NAME)_FRAMEWORKS = CoreServices
$(TWEAK_NAME)_LOGOS_DEFAULT_GENERATOR = internal

# Copy TGExtra.bundle manually during the packaging step
after-stage::
	@echo ">>> Copying TGExtra.bundle into rootless package..."
	@mkdir -p "$(THEOS_STAGING_DIR)$(THEOS_PACKAGE_INSTALL_PREFIX)/Library/Application Support/TGExtra"
	@cp -a TGExtra.bundle "$(THEOS_STAGING_DIR)$(THEOS_PACKAGE_INSTALL_PREFIX)/Library/Application Support/TGExtra/"

include $(THEOS_MAKE_PATH)/tweak.mk
