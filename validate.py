#!/usr/bin/env python3
from pathlib import Path
import sys
root = Path(__file__).resolve().parent
kWCRClownDomain = 'com.zlhkf.wclown'
errors = []

def read(p):
    return p.read_text(encoding='utf-8', errors='replace') if p.exists() else ''

# 收集主目录源码 + Preferences 子工程
src_files = {}
for p in sorted(root.rglob('*')):
    if p.is_file() and (p.suffix in {'.m', '.h', '.xm'} or p.name in {'Makefile', 'control', 'WCRClownStandalone.plist', 'Root.plist', 'entry.plist'}):
        src_files[p.name] = read(p)

tweak = src_files.get('Tweak.xm', '')
config_h = src_files.get('WCRClownConfig.h', '')
root_plist = read(root / 'Preferences' / 'Resources' / 'Root.plist')
makefile = read(root / 'Makefile')
plist = src_files.get('WCRClownStandalone.plist', '')

required = ['enabled', 'textEnabled', 'imageEnabled', 'messageTimeEnabled',
            'messageSortEnabled', 'chatTimeEnabled', 'yinYangEnabled',
            'transferAmountEnabled', 'transferPersistOnExitChat']

# 1) 配置属性齐全
for key in required:
    if key not in config_h:
        errors.append(f'missing config property {key}')

# 2) 设置页开关齐全（Root.plist 用 PSListController 的 <key>key</key><string>键名</string> 绑定）
for key in required:
    if f'<key>key</key><string>{key}</string>' not in root_plist:
        errors.append(f'missing settings item {key} in Root.plist')

# 2b) 设置页必须声明 defaults 域，否则 PreferenceLoader 写入 com.apple.Preferences，
#     与 tweak 读取的 com.minis.wcrclownstandalone 错位，开关永远不生效
if f'<key>defaults</key><string>{kWCRClownDomain}</string>' not in root_plist:
    errors.append(f'Root.plist missing defaults domain {kWCRClownDomain} (toggles would not reach tweak)')

# 2c) Root.plist / Info.plist 必须是合法 plist，否则设置 App 会崩溃
import plistlib
for name, path in [('Root.plist', root / 'Preferences' / 'Resources' / 'Root.plist'),
                   ('Preferences/Info.plist', root / 'Preferences' / 'Info.plist')]:
    try:
        plistlib.loads(read(path).encode('utf-8'))
    except Exception as e:
        errors.append(f'{name} is not valid plist: {e}')

# 3) 危险支付/网络 selector 禁止出现（本地显示覆盖，绝不改真实支付）
for dangerous in ['startTransferMoneyLogic', 'OnConfirmTransferMoney',
                  'onTransferMoneyControlLogic', 'OpenRedEnvelopesRequest']:
    if any(dangerous in s for s in src_files.values()):
        errors.append(f'dangerous payment/network selector present: {dangerous}')

# 4) Hook 安全：允许 %hook，但必须有 WCRClassAndSelectorAvailable 保护 + 受控 %init
if '%hook' in tweak or 'MSHookMessageEx' in tweak:
    if 'WCRClassAndSelectorAvailable' not in tweak:
        errors.append('hooks present but missing WCRClassAndSelectorAvailable safety guard')
    if '%init(' not in tweak:
        errors.append('hooks present but no guarded %init group dispatch')

# 5) 进程退出清理保留
if 'clearAll' not in tweak:
    errors.append('missing process-exit cleanup')

# 6) 微信 bundle 过滤
if 'com.tencent.xin' not in plist:
    errors.append('missing WeChat bundle filter')

# 7) 注入方案必须 roothide
if 'THEOS_PACKAGE_SCHEME = roothide' not in makefile:
    errors.append('THEOS_PACKAGE_SCHEME must be roothide')

print('files', len(src_files), 'errors', len(errors))
for e in errors:
    print('ERROR', e)
sys.exit(bool(errors))
