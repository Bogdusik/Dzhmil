# Джміль

A small turquoise drone that lives on your macOS desktop. It flies around the screen, talks to you by voice, and controls your Mac when you ask it to. It always asks before doing anything risky.

Built with Swift 6, SwiftUI + AppKit, WhisperKit (on-device speech recognition) and the Claude API.

## Requirements

- macOS 15 or later, Apple Silicon
- Xcode 27 and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- An Anthropic API key from [Claude Console](https://platform.claude.com)

## Build

```bash
cd app
xcodegen generate
open Dzhmil.xcodeproj
```

Pick your own signing team in the target settings, then Run. A stable "Apple Development" signature keeps macOS permissions (microphone, automation) across rebuilds.

Core logic lives in the `DzhmilKit` Swift package and is tested with:

```bash
swift test --package-path app/DzhmilKit
```

## First launch

Джміль asks for your API key and stores it in the macOS Keychain.
