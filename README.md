# Harbor Player for iPhone

Native SwiftUI/libmpv external player for Stremio, iOS 17+. Built-in Anime4K GPU shaders, MKV/HLS playback, embedded and external ASS/SRT subtitles, audio/subtitle track menus, playback speed, seek controls, brightness/volume swipes, AniSkip and TheIntroDB integration.

## Install and connect

The Actions artifact contains an **unsigned IPA**. Sign with your own Apple ID using your sideloading setup before installing. This repository does not contain Apple certificates or provisioning profiles.

In **Stremio Web → Settings → Player → external player**, select **VLC**. This app registers `vlc-x-callback://` as a compatibility bridge, preserving HTTP/HTTPS and query parameters. Do not keep the original VLC installed at the same time: iOS does not reliably select between apps registering the same scheme. Alternatively select **Outplayer**, without the original Outplayer installed. This is a compatibility bridge, not an official Stremio integration.

Stremio replaces the original HTTP/HTTPS scheme with `outplayer`. Harbor defaults to HTTPS. For HTTP-only local servers, use the player's Info → connection switch or paste the original HTTP URL on the home screen. No silent downgrade of authenticated HTTPS streams is performed.

Direct integration: `harborplayer://play?url=<percent-encoded-HTTP(S)-URL>&title=Title&id=tt1234567&season=1&episode=2&anime=0&start=0`. Anime IDs may use `mal:5114` or `kitsu:1`; `anime=1` enables AniSkip. Optional `subtitle` accepts an encoded HTTP(S) subtitle URL. Direct URLs preserve query strings and signed tokens. Torrent/magnet URLs need an external streaming server providing HTTP(S).

## Controls

- Tap video: show/hide controls and large central play/pause.
- Bottom left: back 10 seconds, play/pause, forward 10 seconds.
- Bottom right: speed, Anime4K, audio language, subtitle language and style.
- Swipe vertically on left/right: screen brightness/system volume.
- Info: content identity, episode, skip lookup, independent intro/recap/credits auto-skip.

Harbor subtitle settings include shadow/outline/background, font/import, bold, size, opacity, bottom offset, alignment, text/outline/background colors, outline width, background opacity, ASS override and synchronization delay. Settings persist. The preview is approximate; libass renders the actual subtitles.

## Skip Intro limitations

An external stream URL often has no content ID or episode. Chapter detection works without IDs; network lookup requires metadata supplied by the deep link or entered in Info. Coverage depends on AniSkip/TheIntroDB; this is not audio-based intro recognition. MAL IDs identify individual seasons; use the correct season ID and episode numbering. Metadata queries send the entered ID/episode/duration to the respective public service; the video URL is not sent.

## Build

Standard macOS GitHub Actions runners in this **public** repository do not consume included private-repository minutes. The workflow refuses to run if the repository is private. Artifacts expire after seven days.

On a Mac: install XcodeGen, run `xcodegen generate`, then build the HarborPlayer scheme. CI runs pure Swift regression tests before building for physical iPhones and packaging the IPA. A successful build is not a physical iPhone playback, GPU performance, or gesture test.

## Sources and licenses

App source is MIT (see LICENSE). Intro lookup and playback patterns adapted from the supplied Harbor TV/iOS projects. AniZen and CinePlayer were consulted as UX references; their code and CinePlayer's proprietary SDK are not bundled.

- MPVKit 1.0.0 **LGPL** product: https://github.com/mpvkit/MPVKit/tree/1.0.0 (upstream build sources and dependency licenses).
- Anime4K: https://github.com/bloc97/Anime4K/tree/7684e9586f8dcc738af08a1cdceb024cc184f426 (MIT license bundled).
- Inter: Google Fonts / Rasmus Andersson (SIL OFL bundled in Resources/Fonts).
- AniSkip: https://api.aniskip.com and TheIntroDB: https://theintrodb.org.

This is an independent application, not affiliated with Stremio, Outplayer or CinePlayer.
