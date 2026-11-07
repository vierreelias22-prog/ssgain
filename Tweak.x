#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// Slider 100% = nostaa kaistoja tämän verran normalisoidussa asteikossa.
// Spotifyn oma EQ-asteikko päättyy noin arvoon 1.0, joten isompi ei auta.
static const float kMaxOffset  = 0.5f;
static const float kClamp      = 1.0f;
static const float kBassWeight = 1.0f;   // 4 alinta kaistaa (32-250 Hz)
static const float kOtherWeight = 0.4f;  // muut kaistat

static __weak id gModel;
static NSArray<NSNumber *> *gBase;

static void applyGain(float pct) {
    id m = gModel;
    if (!m || !gBase.count) return;
    float off = pct / 100.0f * kMaxOffset;
    NSMutableArray *out = [NSMutableArray new];
    for (NSUInteger i = 0; i < gBase.count; i++) {
        float w = (i < 4) ? kBassWeight : kOtherWeight;
        float v = gBase[i].floatValue + off * w;
        [out addObject:@(MAX(-kClamp, MIN(kClamp, v)))];
    }
    if ([m respondsToSelector:@selector(setValues:)]) [m performSelector:@selector(setValues:) withObject:out];
    if ([m respondsToSelector:@selector(applyCoreEqualizer)]) [m performSelector:@selector(applyCoreEqualizer)];
}

static NSString *dumpModel(id m) {
    NSMutableString *o = [NSMutableString new];
    id v = nil;
    @try { v = [m valueForKey:@"values"]; } @catch (id e) {}
    [o appendFormat:@"values class: %@\nvalues: %@\n", NSStringFromClass([v class]), v];
    return o;
}

@interface SPTEqualizerViewController : UIViewController @end
@interface SPTEqualizerView : UIView @end

%hook SPTEqualizerViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    id m = nil;
    @try { m = [self valueForKey:@"model"]; } @catch (id e) {}
    gModel = m;
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
    [s addTarget:self action:@selector(sg_down:) forControlEvents:UIControlEventTouchDown];
    [s addTarget:self action:@selector(sg_changed:) forControlEvents:UIControlEventValueChanged];
    for (UIView *v in @[l, s]) { v.translatesAutoresizingMaskIntoConstraints = NO; [self addSubview:v]; }
    [NSLayoutConstraint activateConstraints:@[
        [l.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:20],
        [l.bottomAnchor constraintEqualToAnchor:s.topAnchor constant:-4],
        [s.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:20],
        [s.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-20],
        [s.bottomAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.bottomAnchor constant:-16]]];
}
%new - (void)sg_down:(UISlider *)s {
    id v = nil;
    @try { v = [gModel valueForKey:@"values"]; } @catch (id e) {}
    gBase = [v isKindOfClass:[NSArray class]] ? [(NSArray *)v copy] : nil;
}
%new - (void)sg_changed:(UISlider *)s {
    UILabel *l = (UILabel *)[self viewWithTag:0x6741];
    if (!gModel) { l.text = @"Gain: no model"; return; }
    if (!gBase.count) { l.text = @"Gain: values not NSArray"; return; }
    l.text = [NSString stringWithFormat:@"Gain: %.0f%% (+%.2f)", s.value, s.value / 100.0f * kMaxOffset];
    applyGain(s.value);
}
%new - (void)sg_dump:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) return;
    NSString *txt = gModel ? dumpModel(gModel) : @"NO MODEL";
    UIPasteboard.generalPasteboard.string = txt;
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"values" message:txt preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    UIViewController *vc = self.window.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    [vc presentViewController:a animated:YES completion:nil];
}
%end
