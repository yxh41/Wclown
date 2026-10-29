#import "WCRClownLogView.h"
#import "WCRClownLog.h"

@implementation WCRClownLogViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"诊断日志";
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    UITextView *tv = [[UITextView alloc] initWithFrame:self.view.bounds];
    tv.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    tv.editable = NO;
    tv.selectable = YES;
    tv.font = [UIFont fontWithName:@"Menlo" size:11] ?: [UIFont systemFontOfSize:11];
    NSArray<NSString *> *reversed = [[[WCRClownLog shared].allLines reverseObjectEnumerator] allObjects];
    NSString *text = [reversed componentsJoinedByString:@"\n"];
    tv.text = text.length ? text : @"暂无日志。请先在「小丑功能」里打开「启用诊断 Hook」，杀掉并重新打开微信，再回来查看。";
    [self.view addSubview:tv];

    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                      target:self
                                                      action:@selector(wcr_done)];
    UIBarButtonItem *copy = [[UIBarButtonItem alloc] initWithTitle:@"复制"
                                                            style:UIBarButtonItemStylePlain
                                                           target:self
                                                           action:@selector(wcr_copy)];
    UIBarButtonItem *clear = [[UIBarButtonItem alloc] initWithTitle:@"清空"
                                                             style:UIBarButtonItemStylePlain
                                                            target:self
                                                            action:@selector(wcr_clear)];
    self.navigationItem.leftBarButtonItems = @[copy, clear];
}

- (void)wcr_done {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)wcr_copy {
    NSArray<NSString *> *lines = [WCRClownLog shared].allLines;
    NSString *text = [lines componentsJoinedByString:@"\n"];
    if (text.length) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        UIPasteboard.generalPasteboard.string = text;
#pragma clang diagnostic pop
    }
}

- (void)wcr_clear {
    [[WCRClownLog shared] clear];
    [self.navigationController popViewControllerAnimated:YES];
}

@end
