# Dzhmil: lively animation and looking at the screen

Date: 2026-11-16
Status: approved
Extends: `2026-11-15-dzhmil-design.md`

## Why

The drone should feel alive: move even when it is not flying, and sometimes follow the cursor. And it should be the thing you turn to when you are stuck on a task and don't know how to solve it. Right now Dzhmil can answer a question but cannot see the screen, so "I'm stuck right here" means nothing to it.

## Goals

- A set of lively idle animations and reactions to events.
- Eyes that follow the cursor when it is close.
- An occasional short "game": the drone chases the cursor and comes back.
- On request, Dzhmil looks at the screen (a screenshot of the active window) and helps with what it sees.

## Non-goals

- Watching the screen on its own and noticing that you are stuck (option B was rejected).
- Clipboard, text recognition, video recording.

## Anti-goals

- **Secret screenshots.** Every capture comes with a visible animation and a bubble.
- **Distracting.** Animations are small and rare; the cursor game happens no more often than a set limit and is off in Quiet Mode.
- **Greedy.** Still < 3% CPU at idle.

## Approaches

- **A `look_at_screen` tool (chosen).** Claude decides when to look and understands any phrasing. Protection against unnecessary captures: a rule in the system prompt plus a visible flash and bubble.
- **Keywords** ("look", "check this"). Predictable but brittle. Rejected.
- **Capture with ScreenCaptureKit (chosen).** `CGWindowListCreateImage` is unavailable in the macOS 15 SDK, and the `screencapture` utility gives less control.

## Design

### 1. Lively animation (Core Animation, the drone layer)

| Gesture | When |
|---|---|
| Looks around (eyes left and right) | randomly at idle |
| Curious head tilt (±8°, held ~1 s) | randomly at idle |
| Hop (−12 pt and back) | randomly at idle |
| Yawn (mouth open, eyes squinted) | at idle, more often in the evening and at night |
| Barrel roll (a 360° turn around the vertical axis, faked by squashing X) | rarely, at most once every 10 min |
| Happy wiggle + happy eyes | on waking and on coming back after Hide |
| Startle (wider eyes, jump back) | the cursor whizzed past nearby |
| Camera flash (the visor flashes, the light pulses) | before every screenshot |

Choosing a gesture is pure logic in the core (`IdleAnimator`). The next gesture comes after a random 8–20 s, only in the `hover` state. The same gesture never plays twice in a row, and the barrel roll has its own cooldown. No gestures in Quiet Mode or over a fullscreen app.

### 2. Eyes follow the cursor

- If the cursor is within ~450 pt of the drone's centre, the eyes shift towards it: up to ±6 pt horizontally and ±4 pt vertically in drawing coordinates, smoothly (~0.15 s).
- If the cursor is farther away, the eyes return to the centre.
- Works in every state with open eyes.
- The offset is a pure function in the core (`EyeTracker`).

### 3. The "chase the cursor" game

- The drone flies to a point next to the cursor (to the side and above, ~120 pt), stays nearby for about 4 s, then returns to where it was.
- Conditions: the drone is free (`canWander`), the cursor moves slowly (< 300 pt/s, no sudden movements), no bubble.
- Frequency depends on chattiness: Rarely means never, Normal at most once every 20 min, Often at most once every 10 min.
- The "time to play" decision lives in the core, next to `IdleAnimator`.

### 4. Looking at the screen: the `look_at_screen` tool

- **Input:** `{"target": "window" | "screen"}`. `window` is the main window of the active app, `screen` is the whole screen. Dzhmil's own window is never in the shot.
- **Risk:** safe, no confirmation, since you asked for it. Before the capture the drone plays the flash and shows a "Looking at your screen…" bubble.
- **Image:** long side ≤ 1568 px, JPEG at quality ~0.75, sent in the `tool_result` as an `image` block (base64) plus a short caption: the app name and window title.
- **Core:** the tool protocol is extended so a tool can return an image, not just text. `ToolExecutor` and `Conversation` build a `tool_result` with an array of blocks. The app takes the screenshot through a `ScreenCapturer` protocol passed into the tool.
- **Permission:** Screen Recording. Without it the tool returns an error and Dzhmil explains where to grant access: System Settings → Privacy & Security → Screen Recording. macOS shows its own prompt on the first capture.
- **System prompt.** A new rule: call `look_at_screen` only when the user asks you to look or asks about something on their screen or in an app that isn't working. Describe what you see briefly and help step by step.
- **Cost and context.** The screenshot stays in the session history, which is append-only. That is ~1.5k tokens in every later request, cheap with caching. As before, the session resets after 30 minutes of silence or 60 messages.

## Decisions to check

- The barrel roll, yawning and the game are limited by cooldowns. The game is tied to the "Speaks first" setting; there is no separate setting.
- `window` is the default: Claude picks `screen` itself when asked for "the whole screen".
- No clipboard for now.

## Left to the builder

Exact gesture timings and weights, the shape of the flash, where the game's point sits relative to the cursor.
