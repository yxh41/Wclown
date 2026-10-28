ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:15.0
THEOS_PACKAGE_SCHEME = roothide
INSTALL_TARGET_PROCESSES = WeChat

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = WCRClownStandalone
WCRClownStandalone_FILES = Tweak.xm WCRClownConfig.m WCRClownStore.m WCRClownRuntime.m WCRClownEntryInstaller.m
WCRClownStandalone_CFLAGS = -fobjc-arc -Werror -Wno-cast-function-type
WCRClownStandalone_FRAMEWORKS = UIKit Foundation Photos

include $(THEOS_MAKE_PATH)/tweak.mk

# 偏好设置子工程（PSListController bundle，随 tweak 一起打进 roothide .deb）
SUBPROJECTS = Preferences
include $(THEOS_MAKE_PATH)/aggregate.mk

# 注入过滤 plist + PreferenceLoader 入口 plist（随 tweak 一起打进 roothide .deb）
internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/MobileSubstrate/DynamicLibraries$(ECHO_END)
	$(ECHO_NOTHING)cp WCRClownStandalone.plist $(THEOS_STAGING_DIR)/Library/MobileSubstrate/DynamicLibraries/WCRClownStandalone.plist$(ECHO_END)
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp entry.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/WCRClown.plist$(ECHO_END)
	# theos 的 bundle.mk 不会自动把 bundle 根的 Info.plist 打进 .bundle；缺它则
	# NSPrincipalClass(WCRClownSettingsController) 加载失败，设置页只剩文字、开关不渲染。
	# 这里在 staging 阶段强制拷入（与上面 dylib/entry.plist 拷入同一上下文、repo 根路径）。
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceBundles/WCRClownSettings.bundle$(ECHO_END)
	$(ECHO_NOTHING)cp $(THEOS_PROJECT_DIR)/Preferences/Info.plist $(THEOS_STAGING_DIR)/Library/PreferenceBundles/WCRClownSettings.bundle/Info.plist$(ECHO_END)

# 安装后重载 backboardd，让微信重新注入
after-install::
	install.exec "killall -9 backboardd" 2>/dev/null || true
