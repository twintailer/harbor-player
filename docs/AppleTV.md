# Kairo Player for Apple TV

This is the external player from the iPhone app, built for **tvOS 27 or newer**, with a dedicated Siri Remote interface. It shares libmpv/MPVKit, Anime4K shaders, playback URLs, Stremio progress callbacks, language policy, subtitle options and intro providers with iOS. It is separate from the full Harbor TV catalogue app.

## Install

Download the Apple TV IPA from the release. It is unsigned: sign it using your own Apple TV provisioning profile and install it through your tvOS sideloading setup. An iPhone provisioning profile cannot sign a tvOS application. The bundle identifier is `app.kairo.player.tvos`.

In a Stremio tvOS client supporting external Infuse playback, choose **Infuse**. Kairo registers the same play URL, so the original Infuse must not be installed alongside it. Start position, automatic media identity and the progress callback depend on the Stremio client supplying those fields. No additional Stremio login is required. Close normally to deliver the callback; force-quitting cannot return progress.

Direct integration: `kairoplayer://play?url=<encoded-stream>&id=tt2560140&season=3&episode=13`. `harborplayer`, `infuse`, `outplayer` and `vlc-x-callback` remain accepted. Plain HTTP(S) stream URLs work from the home screen too.

## Siri Remote

- Play/Pause controls playback and reveals the controls.
- Select with the controls hidden reveals the bottom bar.
- Left/Right with controls hidden skips by the configured interval, default 15 seconds.
- With controls visible, focus selects the bottom controls and settings. Left/Right on the focused timeline seeks by the same interval.
- Back closes settings first, then hides playback controls, then closes the player and returns progress.
- Volume buttons control the connected TV/receiver through the normal Apple TV configuration. Screen brightness is a television setting, not an iPhone-style swipe gesture.

The compact glass layout keeps Play/Pause in the bottom row, alongside backward/forward controls. Speed, Anime4K, audio, subtitles and preferences sit on the right. The episode title and season/episode appear above the buttons, with the timeline and elapsed/total time below. Focus remains visible on remote-controlled buttons; hidden video controls add no glass overlay.

Version 1.3.1 prefers AVFoundation audio output for multichannel HDMI/TV/soundbar routes, with AudioUnit as a fallback. tvOS negotiates the audio channel layout; this does not force unsupported bitstream passthrough. VideoToolbox uses direct hardware surfaces instead of copying decoded frames to CPU memory. The network cache reads up to 60 seconds ahead within a 128 MiB limit and refills an eight-second runway before resuming, where the source allows it. A slow server or Wi-Fi connection can still run out of data. Info shows the actual audio output, sample rate, decoder and cached seconds for troubleshooting.

Episode names are fetched using the detected media ID and episode, independently of playback and intro lookup. A public TMDB metadata addon supplies localized names when reachable; Cinemeta provides the fallback. If metadata is missing, the filename is shortened and season/episode remain visible. These requests send media identity/language only, not the playback URL or its tokens. Addon episode numbering and available translations can differ from your configured Stremio catalogue.

## Settings

Preferred audio/subtitle languages and forced/full subtitle selection are identical to iOS. Intro, recap and credits support separate automatic skip preferences, otherwise a Skip button appears during a recognized segment. ID/episode detection, AniZip/ARM anime-season mapping, AniSkip, TheIntroDB v3 and chapter fallback are shared with iOS. Missing community timestamps cannot be inferred from the video automatically.

Subtitle appearance includes font, weight, size, opacity, positioning, alignment, arbitrary hex colors, outline/shadow/background, ASS override and delay. Remote-friendly plus/minus controls replace touch sliders. External subtitles and custom TTF/OTF fonts load from HTTP(S) URLs; tvOS has no iPhone file-picker workflow. Fonts/media cache files may be purged by the operating system; preferences persist.

## Build

`xcodegen generate`, then build the `KairoTV` scheme with Xcode 27 and the Apple TV SDK. The public GitHub workflow uses the standard `xcode-27` preview runner, not a paid larger runner. It verifies the SDK version, runs shared logic/provider regression tests, builds an unsigned device IPA, and tests real playback, remote focus/seek, language selection, menus, intro/recap and the callback on the tvOS 27 Simulator. Physical Apple TV GPU performance, receiver volume and live Stremio account synchronization need device testing.
