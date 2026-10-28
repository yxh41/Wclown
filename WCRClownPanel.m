#import "WCRClownPanel.h"
#import "WCRClownConfig.h"
#import <objc/runtime.h>

// Tweak.xm 中的构建标记，用于在面板上显示当前实际版本（避免装错旧包）
extern const char kWCRClownBuildTag[];

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
            @{@"t": @"启用诊断 Hook", @"k": @"diagnosticHooksEnabled", @"d": @"下次启动微信后生效"}
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
        [@"诊断 Hook 会在下次启动微信时打印候选类/selector 存在性（idevicesyslog 可见）。\n当前构建: " stringByAppendingString:build]
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
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    NSString *key = item[@"k"];
    UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectZero];
    sw.on = [[[WCRClownConfig shared] valueForKey:key] boolValue];
    objc_setAssociatedObject(sw, &kWCRClownSwitchKeyChar, key, OBJC_ASSOCIATION_COPY_NONATOMIC);
    [sw addTarget:self action:@selector(wcr_switchChanged:) forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = sw;
    return cell;
}

@end
