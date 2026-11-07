#import <UIKit/UIKit.h>
#import <AudioToolbox/AudioToolbox.h>
#include <math.h>

// Slider 100% = +kMaxDb. Aloita pienellä arvolla ja pidä puhelimen volyymi alhaalla.
static const float kMaxDb = 20.0f;
static volatile float gGainLin = 1.0f;

typedef struct {
    AudioUnit au;
    AURenderCallbackStruct orig;
    AudioStreamBasicDescription fmt;
    BOOL hasFmt;
} Slot;

static Slot gSlots[8];
static int gN = 0;

static int slotFor(AudioUnit u, BOOL create) {
    for (int i = 0; i < gN; i++) if (gSlots[i].au == u) return i;
    if (!create || gN >= 8) return -1;
    memset(&gSlots[gN], 0, sizeof(Slot));
    gSlots[gN].au = u;
    return gN++;
}

static inline float softclip(float v) {
    float a = fabsf(v);
    if (a <= 0.9f) return v;
    float o = 0.9f + 0.1f * tanhf((a - 0.9f) / 0.1f);
    return v < 0 ? -o : o;
}

static OSStatus gainCB(void *ref, AudioUnitRenderActionFlags *flags, const AudioTimeStamp *ts,
                       UInt32 bus, UInt32 frames, AudioBufferList *io) {
    Slot *s = &gSlots[(int)(intptr_t)ref];
    OSStatus r = s->orig.inputProc(s->orig.inputProcRefCon, flags, ts, bus, frames, io);
    float g = gGainLin;
    if (r != noErr || !io || g == 1.0f || !s->hasFmt) return r;
    if (flags && (*flags & kAudioUnitRenderAction_OutputIsSilence)) return r;
    BOOL isFloat = (s->fmt.mFormatFlags & kAudioFormatFlagIsFloat) != 0;
    for (UInt32 b = 0; b < io->mNumberBuffers; b++) {
        AudioBuffer *buf = &io->mBuffers[b];
        if (!buf->mData) continue;
        if (isFloat && s->fmt.mBitsPerChannel == 32) {
            float *p = (float *)buf->mData;
            UInt32 n = buf->mDataByteSize / 4;
            for (UInt32 k = 0; k < n; k++) p[k] = softclip(p[k] * g);
        } else if (!isFloat && s->fmt.mBitsPerChannel == 16) {
            int16_t *p = (int16_t *)buf->mData;
            UInt32 n = buf->mDataByteSize / 2;
            for (UInt32 k = 0; k < n; k++)
                p[k] = (int16_t)(softclip(p[k] / 32768.0f * g) * 32767.0f);
        }
    }
    return r;
}

%hookf(OSStatus, AudioUnitSetProperty, AudioUnit inUnit, AudioUnitPropertyID inID,
       AudioUnitScope inScope, AudioUnitElement inElement, const void *inData, UInt32 inDataSize) {
    if (inID == kAudioUnitProperty_StreamFormat && inData &&
        inDataSize >= sizeof(AudioStreamBasicDescription)) {
        int i = slotFor(inUnit, YES);
        if (i >= 0) {
            gSlots[i].fmt = *(const AudioStreamBasicDescription *)inData;
            gSlots[i].hasFmt = YES;
        }
    }
    if (inID == kAudioUnitProperty_SetRenderCallback && inData &&
        inDataSize >= sizeof(AURenderCallbackStruct)) {
        AURenderCallbackStruct in = *(const AURenderCallbackStruct *)inData;
        int i = slotFor(inUnit, YES);
        if (in.inputProc && i >= 0 && in.inputProc != gainCB) {
            gSlots[i].orig = in;
            AURenderCallbackStruct mine = { gainCB, (void *)(intptr_t)i };
            return %orig(inUnit, inID, inScope, inElement, &mine, inDataSize);
        }
    }
    return %orig;
}

static void applyGain(float pct) {
    gGainLin = powf(10.0f, (pct / 100.0f * kMaxDb) / 20.0f);
}

@interface SPTEqualizerView : UIView @end

%hook SPTEqualizerView
- (void)didMoveToWindow {
    %orig;
    if (!self.window || [self viewWithTag:0x6741]) return;
    UILabel *l = [UILabel new];
    l.tag = 0x6741;
    l.text = @"Gain: +0.0 dB";
    l.textColor = UIColor.whiteColor;
    l.font = [UIFont boldSystemFontOfSize:14];
    UISlider *s = [UISlider new];
    s.minimumValue = 0;
    s.maximumValue = 100;
    s.value = 0;
    s.tintColor = [UIColor colorWithRed:0.11 green:0.73 blue:0.33 alpha:1];
    [s addTarget:self action:@selector(sg_changed:) forControlEvents:UIControlEventValueChanged];
    for (UIView *v in @[l, s]) {
        v.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:v];
    }
    [NSLayoutConstraint activateConstraints:@[
        [l.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:20],
        [l.bottomAnchor constraintEqualToAnchor:s.topAnchor constant:-4],
        [s.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:20],
        [s.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-20],
        [s.bottomAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.bottomAnchor constant:-16]]];
}
%new - (void)sg_changed:(UISlider *)s {
    UILabel *l = (UILabel *)[self viewWithTag:0x6741];
    l.text = [NSString stringWithFormat:@"Gain: +%.1f dB", s.value / 100.0f * kMaxDb];
    applyGain(s.value);
}
%end
