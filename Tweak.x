// SpotifyGain 0.1 – gain/bass slider on Spotify's Equalizer screen (Settings > Playback > Equalizer)
// UNTESTED against 9.1.90. Fill in the two selector names below (see "Finding selectors").
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// ---- tune these -----------------------------------------------------------
// Spotify's EQ bands are limited (~±12 dB). 100 dB is not possible: digital audio
// clips at 0 dBFS, so >~12 dB is just distortion and can hurt ears/speakers.
static const float kMaxGainDb   = 12.0f;  // slider 100% = this many dB
static const float kBassWeight  = 1.0f;   // low shelf/low peak get full offset
static const float kOtherWeight = 0.5f;   // other bands get half (more bass-heavy "gain")
// Placeholders – replace after dumping SPTEqualizerModel (long-press the slider label):
static NSString *const kSetBandSel = @"setGain:forBand:";   // e.g. -(void)setGain:(float)g forBand:(NSUInteger)i
static NSString *const kGetBandSel = @"gainForBand:";       // e.g. -(float)gainForBand:(NSUInteger)i
static const NSUInteger kBandCount = 6;  // low shelf, low, low-mid, high-mid, high, high shelf
// ---------------------------------------------------------------------------

static NSMutableArray<NSNumber *> *baseGains;     // user's own EQ, captured once
static __weak id gModel;

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

static NSString *dumpMethods(id obj) {
    NSMutableString *out = [NSMutableString new];
    unsigned n; Method *ms = class_copyMethodList([obj class], &n);
    for (unsigned i = 0; i < n; i++) [out appendFormat:@"%s\n", sel_getName(method_getName(ms[i]))];
    free(ms); return out;
}

@interface SPTEqualizerView : UIView
@property (nonatomic, strong) id model;
@end

%hook SPTEqualizerView
- (void)didMoveToWindow {
    %orig;
    if (!self.window || [self viewWithTag:0x6741]) return;
    if ([self respondsToSelector:@selector(model)]) gModel = [self valueForKey:@"model"];

    UILabel *l = [UILabel new];
    l.tag = 0x6741; l.text = @"Gain: 0%"; l.textColor = UIColor.whiteColor;
    l.font = [UIFont boldSystemFontOfSize:14]; l.userInteractionEnabled = YES;
    [l addGestureRecognizer:[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(sg_dump:)]];
    UISlider *s = [UISlider new];
    s.minimumValue = 0; s.maximumValue = 100; s.tintColor = [UIColor colorWithRed:0.11 green:0.73 blue:0.33 alpha:1];
    [s addTarget:self action:@selector(sg_changed:) forControlEvents:UIControlEventValueChanged];
    s.tag = 0x6742;
    for (UIView *v in @[l, s]) { v.translatesAutoresizingMaskIntoConstraints = NO; [self addSubview:v]; }
    [NSLayoutConstraint activateConstraints:@[
        [l.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:20],
        [l.bottomAnchor constraintEqualToAnchor:s.topAnchor constant:-4],
        [s.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:20],
        [s.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-20],
        [s.bottomAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.bottomAnchor constant:-16]]];
}
%new - (void)sg_changed:(UISlider *)s {
    ((UILabel *)[self viewWithTag:0x6741]).text =
        [NSString stringWithFormat:@"Gain: %.0f%% (+%.1f dB)", s.value, s.value / 100.0f * kMaxGainDb];
    applyGain(s.value);
}
%new - (void)sg_dump:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan || !gModel) return;
    UIAlertController *a = [UIAlertController alertControllerWithTitle:NSStringFromClass([gModel class])
        message:dumpMethods(gModel) preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    UIViewController *vc = self.window.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    [vc presentViewController:a animated:YES completion:nil];
}
%end
