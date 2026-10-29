#import "WCRClownPanel.h"
#import "WCRClownConfig.h"
#import "WCRClownEntry.h"
#import "WCRClownLog.h"
#import "WCRClownLogView.h"
#import <objc/runtime.h>

static NSString *const kWCRClownToggleCellID = @"WCRClownToggleCell";
static char kWCRClownSwitchKeyChar;

@interface WCRClownPanelController ()
@property(nonatomic, copy) NSArray<NSArray<NSDictionary<NSString *, NSString *> *> *> *sections;
@property(nonatomic, copy) NSArray<NSString *> *footers;
@end

@implementation WCRClownPanelController

+ (void)presentFrom:(UIViewController *)presenter {
    if (!presenter) return;
    WCRClownPanelController *panel = [[self alloc] initWithStyle:UITableViewStyleInsetGrouped];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:panel];
    nav.modalPresentationStyle = UIModalPresentationPageSheet;
    [presenter presentViewController:nav animated:YES completion:nil];
}

- (instancetype)initWithStyle:(UITableViewStyle)style {
    if ((self = [super initWithStyle:style])) {
        self.title = @"小丑功能";
        [self wcr_loadModel];
    }
    return self;
}

- (void)wcr_loadModel {
    self.sections = @[
        @[
            @{@"t": @"启用小丑功能", @"k": @"enabled", @"d": @"总开关"},
            @{@"t": @"聊天文字",     @"k": @"textEnabled",         @"d": @"覆盖消息文本内容"},
            @{@"t": @"聊天图片",     @"k": @"imageEnabled",        @"d": @"覆盖消息图片"},
            @{@"t": @"消息时间",     @"k": @"messageTimeEnabled",  @"d": @"覆盖消息时间显示"},
            @{@"t": @"消息排序",     @"k": @"messageSortEnabled",  @"d": @"调整消息先后顺序"},
            @{@"t": @"聊天时间",     @"k": @"chatTimeEnabled",     @"d": @"覆盖会话时间分隔"},
            @{@"t": @"颠倒阴阳",     @"k": @"yinYangEnabled",      @"d": @"左右交换消息方位，不改真实发送者"},
            @{@"t": @"修改转账",     @"k": @"transferAmountEnabled", @"d": @"覆盖转账金额显示"},
            @{@"t": @"退出保持",     @"k": @"transferPersistOnExitChat", @"d": @"退出会话后仍保留转账修改"}
        ],
        @[
            @{@"t": @"启用诊断 Hook", @"k": @"diagnosticHooksEnabled", @"d": @"下次启动微信后生效"},
            @{@"t": @"诊断日志", @"action": @"log", @"d": @"在手机上直接查看本机诊断输出（无需电脑）"}
        ],
        @[
            @{@"t": @"悬浮入口",     @"k": @"floatingEntryEnabled", @"d": @"显示可拖动的悬浮按钮，点击打开本面板"},
            @{@"t": @"长按菜单入口", @"k": @"menuEntryEnabled",     @"d": @"往微信长按菜单注入「小丑」；历史版本会闪退，默认关闭"}
        ]
    ];
    NSString *build = @"unknown";
    @try {
        build = [NSString stringWithUTF8String:kWCRClownBuildTag];
    } @catch (NSException *e) {
        build = @"unknown";
    }
    self.footers = @[
        @"所有修改仅影响本机显示，不改动服务器数据；返回会话后重新渲染即可看到效果。",
        [@"诊断 Hook 会在下次启动微信时打印候选类/selector 存在性。点上方「诊断日志」即可在手机上直接查看（无需电脑）。\n当前构建: " stringByAppendingString:build],
        @"悬浮入口是打开本面板的安全方式（不触碰微信内部数据）。长按菜单入口仅供排查用，开启后若微信闪退请立即关掉。"
    ];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                      target:self
                                                      action:@selector(wcr_done)];
}

- (void)wcr_done {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)wcr_switchChanged:(UISwitch *)sender {
    NSString *key = objc_getAssociatedObject(sender, &kWCRClownSwitchKeyChar);
    if (key.length == 0) return;
    [[WCRClownConfig shared] setValue:@(sender.on) forKey:key];
    // 悬浮入口即时生效，省去重启微信（其余开关随渲染/下次启动生效）
    if ([key isEqualToString:@"floatingEntryEnabled"]) [WCRClownEntry setVisible:sender.on];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(__unused UITableView *)tableView {
    return (NSInteger)self.sections.count;
}

- (NSInteger)tableView:(__unused UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section < 0 || section >= (NSInteger)self.sections.count) return 0;
    return (NSInteger)self.sections[section].count;
}

- (NSString *)tableView:(__unused UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section < 0 || section >= (NSInteger)self.footers.count) return nil;
    return self.footers[section];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kWCRClownToggleCellID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                      reuseIdentifier:kWCRClownToggleCellID];
    }
    NSDictionary<NSString *, NSString *> *item = self.sections[indexPath.section][indexPath.row];
    cell.textLabel.text = item[@"t"];
    cell.detailTextLabel.text = item[@"d"];
    cell.detailTextLabel.numberOfLines = 0;

    NSString *key = item[@"k"];
    NSString *action = item[@"action"];
    if (action.length) {
        // 行为型行（如「诊断日志」）：可点击跳转，不加开关
        cell.accessoryView = nil;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    } else {
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectZero];
        sw.on = [[[WCRClownConfig shared] valueForKey:key] boolValue];
        objc_setAssociatedObject(sw, &kWCRClownSwitchKeyChar, key, OBJC_ASSOCIATION_COPY_NONATOMIC);
        [sw addTarget:self action:@selector(wcr_switchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary<NSString *, NSString *> *item = self.sections[indexPath.section][indexPath.row];
    if ([item[@"action"] isEqualToString:@"log"]) {
        WCRClownLogViewController *vc = [WCRClownLogViewController new];
        [self.navigationController pushViewController:vc animated:YES];
    }
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

@end
