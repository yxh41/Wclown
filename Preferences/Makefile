include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = WCRClownSettings
WCRClownSettings_FILES = WCRClownSettingsController.m
WCRClownSettings_INSTALL_PATH = /Library/PreferenceBundles
WCRClownSettings_FRAMEWORKS = UIKit
WCRClownSettings_PRIVATE_FRAMEWORKS = Preferences
WCRClownSettings_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/bundle.mk

# theos 的 bundle.mk 不会自动把 bundle 根的 Info.plist 打进 .bundle；
# 缺它则 NSPrincipalClass(WCRClownSettingsController) 加载失败，设置页只剩
# 文字、PSToggleSwitchCell 不渲染开关。这里在 staging 阶段强制拷入。
internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceBundles/WCRClownSettings.bundle$(ECHO_END)
	$(ECHO_NOTHING)cp $(THEOS_PROJECT_DIR)/Preferences/Info.plist $(THEOS_STAGING_DIR)/Library/PreferenceBundles/WCRClownSettings.bundle/Info.plist$(ECHO_END)
