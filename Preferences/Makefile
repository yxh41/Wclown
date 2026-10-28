include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = WCRClownSettings
WCRClownSettings_FILES = WCRClownSettingsController.m
WCRClownSettings_INSTALL_PATH = /Library/PreferenceBundles
WCRClownSettings_FRAMEWORKS = UIKit
WCRClownSettings_PRIVATE_FRAMEWORKS = Preferences
WCRClownSettings_CFLAGS = -fobjc-arc
# theos 不会自动把 bundle 根的 Info.plist 打进 .bundle；缺它则自定义
# PSListController 加载失败，设置页只剩文字、PSToggleSwitchCell 不渲染开关。
WCRClownSettings_INFOPLIST_PATH = Info.plist

include $(THEOS_MAKE_PATH)/bundle.mk
