#import "WCRClownEditor.h"
#import "WCRClownConfig.h"
#import "WCRClownStore.h"
#import "WCRClownRuntime.h"
#import "WCRClownLog.h"
#import <objc/runtime.h>

@interface WCRClownEditorViewController ()
@property(nonatomic, copy) NSString *msgKey;
@property(nonatomic, strong) id msgWrap;
@property(nonatomic, weak) UIViewController *host;
@property(nonatomic) UITextView *textView;
@property(nonatomic) UILabel *statusLabel;
@end

@implementation WCRClownEditorViewController

- (instancetype)initWithMessageKey:(NSString *)key wrap:(id)wrap host:(UIViewController *)host {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _msgKey = [key copy];
        _msgWrap = wrap;
        _host = host;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"编辑本条";
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                      target:self
                                                      action:@selector(wcr_cancel)];
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"保存"
                                         style:UIBarButtonItemStyleDone
                                        target:self
                                        action:@selector(wcr_save)];

    UIStackView *stack = [[UIStackView alloc] init];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 12.0;
    stack.layoutMargins = UIEdgeInsetsMake(16.0, 16.0, 16.0, 16.0);
    stack.layoutMarginsRelativeArrangement = YES;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:stack];

    UILayoutGuide *sa = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:sa.topAnchor constant:16.0],
        [stack.leadingAnchor constraintEqualToAnchor:sa.leadingAnchor constant:16.0],
        [stack.trailingAnchor constraintEqualToAnchor:sa.trailingAnchor constant:-16.0]
    ]];

    UILabel *keyLabel = [[UILabel alloc] init];
    keyLabel.font = [UIFont systemFontOfSize:12.0];
    keyLabel.textColor = UIColor.secondaryLabelColor;
    keyLabel.numberOfLines = 0;
    keyLabel.text = [@"消息标识: " stringByAppendingString:self.msgKey];
    [stack addArrangedSubview:keyLabel];

    UILabel *tHint = [[UILabel alloc] init];
    tHint.font = [UIFont boldSystemFontOfSize:15.0];
    tHint.text = @"文字覆盖";
    [stack addArrangedSubview:tHint];

    _textView = [[UITextView alloc] init];
    _textView.layer.borderWidth = 1.0;
    _textView.layer.borderColor = UIColor.separatorColor.CGColor;
    _textView.layer.cornerRadius = 8.0;
    _textView.font = [UIFont systemFontOfSize:15.0];
    [_textView.heightAnchor constraintEqualToConstant:140.0].active = YES;
    NSDictionary *ov = [[WCRClownStore shared] overridesForKey:self.msgKey];
    _textView.text = ov[@"text"] ?: @"";
    [stack addArrangedSubview:_textView];

    _statusLabel = [[UILabel alloc] init];
    _statusLabel.font = [UIFont systemFontOfSize:12.0];
    _statusLabel.textColor = UIColor.secondaryLabelColor;
    _statusLabel.numberOfLines = 0;
    _statusLabel.text = @"保存后该条会立即刷新（无需退出聊天）。留空＝清除覆盖。\n（开启「编辑入口(长按)」后，长按消息即打开本面板，会替代微信原生菜单。）";
    [stack addArrangedSubview:_statusLabel];

    [_textView becomeFirstResponder];
}

- (void)wcr_cancel {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)wcr_save {
    NSString *t = [self.textView.text stringByTrimmingCharactersInSet:
                   [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (t.length) {
        [[WCRClownStore shared] setText:t quotedText:nil forKey:self.msgKey];
    } else {
        [[WCRClownStore shared] setText:nil quotedText:nil forKey:self.msgKey];
    }
    // 保证覆盖真正生效：主动编辑即代表用户想要本条显示。若主开关 / 文字开关此前被关（无论是
    // 默认值还是用户在设置里关过），此处显式打开，否则 applyOverridesToMessage 会 early-return，
    // 出现「编辑没效果」。开关有 setter 持久化，打开后保持开启，用户仍可在设置里手动关闭。
    WCRClownConfig *cfg = [WCRClownConfig shared];
    if (!cfg.enabled) { cfg.enabled = YES; WCRLog("editor auto-enable enabled"); }
    if (!cfg.textEnabled) { cfg.textEnabled = YES; WCRLog("editor auto-enable textEnabled"); }
    if (self.host) {
        WCRSafeCall0(self.host, NSSelectorFromString(@"wcr_reloadChat"));
        WCRLog("editor saved key=%@ reloaded host=%@", self.msgKey, NSStringFromClass(object_getClass(self.host)));
    } else {
        WCRLog("editor saved key=%@ but host nil (no reload)", self.msgKey);
    }
    // 0.4.4 闪退复盘：在保存按钮调用栈里同步遍历视图树 + forceDisplayInSync（同步绘制），
    // 命中离屏/未布局的复用 Cell 直接 SIGABRT。改为 dismiss 完成后再异步到下一个 runloop 扫，
    // 彻底避开当前调用栈与布局/绘制中途。savedKey 为局部强引用，block 不捕获 self。
    NSString *savedKey = self.msgKey;
    [self dismissViewControllerAnimated:YES completion:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            WCRForceRefreshVisibleTextCellsForKey(savedKey);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                WCRForceRefreshVisibleTextCellsForKey(savedKey);
            });
        });
    }];
}

@end
