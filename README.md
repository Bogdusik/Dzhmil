# Джміль

A small turquoise quadcopter that lives on your macOS desktop. It hovers over your windows, perches on the Dock, falls asleep when you step away, and talks to you by voice. Ask it how your Mac is doing, to open or close apps, change the volume, set a reminder, or run a script. It always asks before doing anything risky.

Built with Swift 6, SwiftUI + AppKit + Core Animation, WhisperKit (on-device speech recognition), AVSpeechSynthesizer, and the Claude API.

## What it does

- **Lives on screen.** A transparent, non-activating panel above all windows and Spaces. Clicks pass through everywhere except the drone itself. It wanders every few minutes, banks into its turns, sleeps on the Dock after 10 minutes idle, and dims itself next to fullscreen apps.
- **Talks.** Hold ⌥Space (or pick "Поговорить" in the menu bar), speak, release. Pressing and holding the drone only drags it. Speech is recognised locally with Whisper large-v3 turbo; replies are streamed from Claude and spoken sentence by sentence. Double-click the drone to type instead.
- **Acts.** Fourteen tools: look at the screen, point at something on it, system status, running apps, open app, open URL, volume, mute, timers, quit / force-quit, lock / sleep / restart / shut down, AppleScript, and zsh. Quitting apps, power actions, AppleScript and shell commands always show a confirmation bubble first; you can answer by button or by voice.
- **Looks at your screen when you ask.** "Глянь, что тут не так" makes Claude call a `look_at_screen` tool: the drone flashes its visor, says «Смотрю на экран…», captures the active window (or the whole screen) with ScreenCaptureKit, and Claude walks you through the fix. Dzhmil's own window is never in the shot. Needs the Screen Recording permission, asked once.
- **Points at things.** When it explains where to click, Claude calls `point_at` with a spot on the latest screenshot; the drone flies next to it and draws an arrow to a pulsing ring with a label, one step at a time.
- **Feels alive.** Idle gestures (looking around, head tilt, hop, yawn, a rare barrel roll), eyes that follow the cursor, a startle when the cursor whizzes past, a happy wiggle on waking, and now and then a few seconds of chasing the cursor. Claude can tag a sentence with an emotion (`<happy>`, `<laugh>`, `<surprised>`, `<thinking>`, `<sad>`); the tag is never spoken and the drone acts it out as the sentence starts. Rub the cursor back and forth over the drone to pet it: it squints, rocks, purrs, and lets out a heart now and then.
- **Speaks first, rarely.** A daily greeting, a break reminder after two hours of work, a low-battery warning, and your own timers. At most once every 20, 45 or 120 minutes depending on the chattiness setting, and never at night, in quiet mode or over a fullscreen app.

## Requirements

- macOS 15 or later, Apple Silicon
- Xcode 27 and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- An Anthropic API key from [Claude Console](https://platform.claude.com)

## Build and run

```bash
cd app
xcodegen generate
open Dzhmil.xcodeproj
```

Pick your own signing team in the target settings, then Run. A stable "Apple Development" signature keeps macOS permissions (microphone, automation) across rebuilds.

On first launch Джміль asks for your API key in a speech bubble and stores it in the macOS Keychain. The first voice request downloads the Whisper model (about 630 MB) into `~/Library/Application Support/Dzhmil/models`.

## Architecture

```
app/
├── DzhmilKit/            Swift package with all testable logic (no third-party dependencies)
│   └── Sources/DzhmilCore
│       ├── Claude/        Messages API client: SSE parser, request builder, stream accumulator, errors
│       ├── Conversation/  tool-use loop, prompt builder, sentence splitter
│       ├── Tools/         tool protocol, confirmation policy, macOS tools, process runner
│       ├── Behavior/      drone state machine, proactive scheduler
│       ├── Flight/        flight physics, perch planner, click-through hit shape
│       ├── Voice/         transcript filter, push-to-talk gate, yes/no parser, voice selection, audio blocks
│       └── Support/       settings, Keychain, profile
└── Dzhmil/               thin app target: panel, Core Animation drone, bubbles, voice I/O, menu, settings
```

The conversation history is append-only, so Claude's preserved thinking blocks stay valid and prompt caching stays warm; long or stale sessions start fresh instead of being trimmed.

```bash
swift test --package-path app/DzhmilKit
```

## Privacy

Audio never leaves the Mac: speech recognition runs on-device. Screenshots are taken only when you ask Dzhmil to look, always with a visible flash and bubble, and are sent to the Claude API as part of that conversation. Only the recognised text, tool results and your short profile (`~/Library/Application Support/Dzhmil/profile.md`, editable in Settings) are sent to the Claude API. The microphone turns on only while you hold the key. Timers are kept in `~/Library/Application Support/Dzhmil/timers.json`, so a reminder survives a restart; one that came due while Dzhmil was closed is told as soon as it starts.

Links that carry data (a path, query, fragment, login or port) open only after you confirm them; a bare site such as `youtube.com` opens directly. Terminal commands, AppleScript, quitting apps, sleep, restart and shutdown always ask first.

## Troubleshooting

Dzhmil writes errors and a record of every Mac action (tool name, whether you confirmed it, whether it ran) to the system log. Conversation text and command contents are not logged.

```sh
log show --last 1h --predicate 'subsystem == "com.bogdusik.dzhmil"'
log stream --predicate 'subsystem == "com.bogdusik.dzhmil"'
```

## Resource use

Measured on an M1 Pro (Release build):

| | |
|---|---|
| CPU while hovering | 0.3% |
| Memory with Whisper loaded | 81 MB steady; about 760 MB peak for ~10 s while the model loads at launch |
| Speech recognition, 5.6 s phrase (warm) | 1.1 s |
| Whisper model load from disk | 7.6 s, in the background at launch |

The drone's continuous animations run on Core Animation in the render server; an early SwiftUI version used about 11% CPU for the same animations.
