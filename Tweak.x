#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static const float kMaxGainDb   = 50.0f;
static const float kBassWeight  = 1.0f;
static const float kOtherWeight = 0.5f;
static NSString *const kSetBandSel = @"setGain:forBand:";
static NSString *const kGetBandSel = @"gainForBand:";
static const NSUInteger kBandCount = 6;

static NSMutableArray<NSNumber *> *baseGains;
static __weak id gModel;
static __weak id gVC;

static void applyGain(float pct) {
    id m = gModel;
    SEL set = NSSelectorFromString(kSetBandSel), get = NSSelectorFromString(kGetBandSel);
    if (!m || ![m respondsToSelector:set] || ![m respondsToSelector:get]) return;
    if (!baseGains) {
        baseGains = [NSMutableArray new];
        for (NSUInteger i = 0; i < kBandCount; i++) {
            float (*g)(id, SEL, NSUInteger) = (void *)[m methodForSelector:get];
            [baseGains addObject:@(g(m, get, i))];
        }
    }
    float offset = pct / 100.0f * kMaxGainDb;
    for (NSUInteger i = 0; i < kBandCount; i++) {
        float w = (i < 2) ? kBassWeight : kOtherWeight;
        float v = MAX(-kMaxGainDb, MIN(kMaxGainDb, baseGains[i].floatValue + offset * w));
        void (*s)(id, SEL, float, NSUInteger) = (void *)[m methodForSelector:set];
        s(m, set, v, i);
    }
}

static NSString *dumpObj(id obj) {
    NSMutableString *o = [NSMutableString new];
    for (Class c = [obj class]; c && c != [NSObject class]; c = class_getSuperclass(c)) {
        [o appendFormat:@"== %s\n", class_getName(c)];
        unsigned n;
        objc_property_t *ps = class_copyPropertyList(c, &n);
        for (unsigned i = 0; i < n; i++) [o appendFormat:@"@ %s\n", property_getName(ps[i])];
        free(ps);
        Method *ms = class_copyMethodList(c, &n);
        for (unsigned i = 0; i < n; i++) [o appendFormat:@"- %s\n", sel_getName(method_getName(ms[i]))];
        free(ms);
    }
    return o;
}

@interface SPTEqualizerViewController : UIViewController @end
@interface SPTEqualizerView : UIView @end

%hook SPTEqualizerViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    gVC = self;
    id m = nil;
    @try { m = [self valueForKey:@"model"]; } @catch (id e) {}
    gModel = m;
    UILabel *l = (UILabel *)[self.view viewWithTag:0x6741];
    if ([l isKindOfClass:[UILabel class]])
        l.text = m ? @"Gain: 0% (model OK)" : @"Gain: 0% (no model)";
}
%end

%hook SPTEqualizerView
- (void)didMoveToWindow {
    %orig;
    if (!self.window || [self viewWithTag:0x6741]) return;
    UILabel *l = [UILabel new];
    l.tag = 0x6741; l.text = @"Gain: 0%"; l.textColor = UIColor.whiteColor;
    l.font = [UIFont boldSystemFontOfSize:14]; l.userInteractionEnabled = YES;
    [l addGestureRecognizer:[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(sg_dump:)]];
    UISlider *s = [UISlider new];
    s.minimumValue = 0; s.maximumValue = 100;
    s.tintColor = [UIColor colorWithRed:0.11 green:0.73 blue:0.33 alpha:1];
    [s addTarget:self action:@selector(sg_changed:) forControlEvents:UIControlEventValueChanged];
    for (UIView *v in @[l, s]) { v.translatesAutoresizingMaskIntoConstraints = NO; [self addSubview:v]; }
    [NSLayoutConstraint activateConstraints:@[
        [l.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:20],
        [l.bottomAnchor constraintEqualToAnchor:s.topAnchor constant:-4],
        [s.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:20],
        [s.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-20],
        [s.bottomAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.bottomAnchor constant:-16]]];
}
%new - (void)sg_changed:(UISlider *)s {
    UILabel *l = (UILabel *)[self viewWithTag:0x6741];
    l.text = [NSString stringWithFormat:@"Gain: %.0f%% (+%.1f dB)", s.value, s.value / 100.0f * kMaxGainDb];
    applyGain(s.value);
}
%new - (void)sg_dump:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) return;
    id target = gModel ?: gVC ?: (id)self;
    NSString *txt = [NSString stringWithFormat:@"%@\n%@", gModel ? @"MODEL" : @"NO MODEL - dumping controller/view", dumpObj(target)];
    UIPasteboard.generalPasteboard.string = txt;
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Copied to clipboard"
        message:txt preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    UIViewController *vc = self.window.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    [vc presentViewController:a animated:YES completion:nil];
}
%end
