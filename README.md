# Harbor Player for iPhone

Native SwiftUI/libmpv external player for Stremio, iOS 17+. Built-in Anime4K GPU shaders, MKV/HLS playback, embedded and external ASS/SRT subtitles, audio/subtitle track menus, playback speed, seek controls, brightness/volume swipes, AniSkip and TheIntroDB integration.

## Install and connect

The Actions artifact contains an **unsigned IPA**. Sign with your own Apple ID using your sideloading setup before installing. This repository does not contain Apple certificates or provisioning profiles.

In the **native Stremio app → Settings → external player**, select **Infuse**. Harbor accepts its `infuse://x-callback-url/play` protocol, including the saved `position` in seconds. On closing the player with the upper-left button, Harbor returns the actual playback position and original stream URL through Stremio's `x-success` callback. This requires a Stremio version that supplies these parameters. No additional Stremio login is needed. Do not keep the original Infuse installed at the same time: iOS does not reliably select between apps registering the same scheme. This is a compatibility bridge, not an official Stremio integration.

**VLC** and **Outplayer** links remain supported, without their original apps installed, but Stremio does not supply resume/callback data through those integrations. Plain stream URLs cannot synchronize progress. Force-quitting Harbor cannot deliver a callback; use the player close button. Failed stream opens do not send zero progress. The callback payload is regression-tested; synchronization with a real native Stremio account has not been verified on a physical iPhone.

Stremio replaces the original HTTP/HTTPS scheme with `outplayer`. Harbor defaults to HTTPS. For HTTP-only local servers, use the player's Info → connection switch or paste the original HTTP URL on the home screen. No silent downgrade of authenticated HTTPS streams is performed.

Direct integration: `harborplayer://play?url=<percent-encoded-HTTP(S)-URL>&title=Title&id=tt1234567&season=1&episode=2&anime=0&start=0`. Anime IDs may use `mal:5114` or `kitsu:1`; `anime=1` enables AniSkip. Optional `subtitle` accepts an encoded HTTP(S) subtitle URL. Direct URLs preserve query strings and signed tokens. Torrent/magnet URLs need an external streaming server providing HTTP(S).

## Controls

- Tap video: show/hide controls and large central play/pause.
- Playback automatically opens in landscape; closing returns home to portrait.
- Double-tap left/right: seek backward/forward, preserving playback/pause state.
- Bottom left: back, play/pause, forward. Default seek interval: 15 seconds; configurable to 5/10/15/30/60 seconds in Languages & Controls.
- Bottom right: speed, Anime4K, audio language, subtitle language and style.
- Swipe vertically on left/right: screen brightness/system volume.
- Info: content identity, episode, skip lookup, independent intro/recap/credits auto-skip.

Harbor subtitle settings include shadow/outline/background, font/import, bold, size, opacity, bottom offset, alignment, text/outline/background colors, outline width, background opacity, ASS override and synchronization delay. Settings persist. The preview is approximate; libass renders the actual subtitles.

Preferred audio and subtitle languages persist independently. With **Prefer forced** enabled (default), audio in the preferred language selects forced subtitles in the preferred subtitle language; other audio selects full subtitles in that language. With this toggle off, full subtitles are preferred. If a matching subtitle type/language is absent, subtitles are disabled. Language tags and the forced flag/title must be present in the media. A manual subtitle selection (including Off or an imported subtitle) takes precedence until automatic selection is restored or the next video is opened. Manually changing audio still updates automatic subtitle selection.

## Skip Intro limitations

An external stream URL often has no content ID or episode. Chapter detection works without IDs; network lookup requires metadata supplied by the deep link or entered in Info. Coverage depends on AniSkip/TheIntroDB; this is not audio-based intro recognition. MAL IDs identify individual seasons; use the correct season ID and episode numbering. Metadata queries send the entered ID/episode/duration to the respective public service; the video URL is not sent.

## Build

Standard macOS GitHub Actions runners in this **public** repository do not consume included private-repository minutes. The workflow refuses to run if the repository is private. Artifacts expire after seven days.

On a Mac: install XcodeGen, run `xcodegen generate`, then build the HarborPlayer scheme. CI runs pure Swift regression tests, builds the unsigned iPhone IPA, and exercises automatic landscape, resume, double-tap seeking, actual audio/forced/full subtitle selection and the outgoing native Stremio callback in an iPhone Simulator using an original synthetic fixture. This does not verify physical iPhone GPU performance or Stremio account synchronization.

## Sources and licenses

App source is MIT (see LICENSE). Intro lookup and playback patterns adapted from the supplied Harbor TV/iOS projects. AniZen and CinePlayer were consulted as UX references; their code and CinePlayer's proprietary SDK are not bundled.

- MPVKit 1.0.0 **LGPL** product: https://github.com/mpvkit/MPVKit/tree/1.0.0 (upstream build sources and dependency licenses).
- Anime4K: https://github.com/bloc97/Anime4K/tree/7684e9586f8dcc738af08a1cdceb024cc184f426 (MIT license bundled).
- Inter: Google Fonts / Rasmus Andersson (SIL OFL bundled in Resources/Fonts).
- AniSkip: https://api.aniskip.com and TheIntroDB: https://theintrodb.org.

The Stremio callback follows the [Infuse external player API](https://support.firecore.com/hc/en-us/articles/215090997-API-for-Third-Party-Apps-Services) and [Stremio core deep links](https://github.com/Stremio/stremio-core/blob/development/src/deep_links/mod.rs).

This is an independent application, not affiliated with Stremio, Infuse, Outplayer or CinePlayer.
