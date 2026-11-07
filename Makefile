TARGET := iphone:clang:latest:15.0
ARCHS := arm64
INSTALL_TARGET_PROCESSES = Spotify
include $(THEOS)/makefiles/common.mk
TWEAK_NAME = SpotifyGain
SpotifyGain_FILES = Tweak.x
SpotifyGain_CFLAGS = -fobjc-arc
SpotifyGain_FRAMEWORKS = AudioToolbox UIKit
include $(THEOS_MAKE_PATH)/tweak.mk