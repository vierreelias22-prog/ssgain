# SpotifyGain
Gain/bass slider on Spotify's Equalizer screen (Settings > Playback > Equalizer).

Build (Mac with Theos): `make package` -> .deb -> extract `SpotifyGain.dylib`,
inject into the IPA (Sideloadly: Advanced > Inject dylibs, or Azule/cyan), sign, install.
No Mac: GitHub Actions with a Theos runner.

Finding selectors: open the Equalizer screen, long-press "Gain" label. It lists
SPTEqualizerModel's methods. Put the band setter/getter into kSetBandSel/kGetBandSel
(and fix the argument order/types in applyGain if they differ), rebuild.
Max is capped at +12 dB (kMaxGainDb); 100 dB is not possible and is unsafe.
