#import "WCRClownEditor.h"
#import "WCRClownConfig.h"
#import "WCRClownStore.h"
#import "WCRClownRuntime.h"
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
    if (self.host) {
        WCRSafeCall0(self.host, NSSelectorFromString(@"wcr_reloadChat"));
    }
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end
