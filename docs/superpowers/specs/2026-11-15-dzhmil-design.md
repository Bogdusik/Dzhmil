# Dzhmil: a drone companion for macOS

Date: 2026-11-15
Status: approved

## 1. Why

I wanted a "friend" on my Mac: a character you can see on screen that flies around now and then, says hello, asks how you are, talks about the computer, and on request (by voice or text) does things: opens and closes apps, controls the system and so on.

Two things in other people's demos hooked me: **the character's look and animation** and **a live voice conversation**. The character should feel like mine, not yet another cat.

## 2. Goals, non-goals, anti-goals

**v1 goals**
- An animated drone, Dzhmil, lives above all windows and Spaces: it flies, perches and falls asleep.
- Voice conversation: hold a key, speak, release, hear the answer and see it in a speech bubble.
- Text input as a fallback when speaking aloud is awkward.
- Reports on the Mac: battery, load, memory, disk, running apps.
- Acts on request through a set of tools. Risky actions only after confirmation.
- Sometimes speaks first, but rarely and unobtrusively.

**v1 non-goals** (maybe later)
- Always-on listening for a wake word.
- Long-term memory across launches.
- "Vision": screenshots and clicking for the user.
- Multiple displays (v1 lives on the screen with the cursor or the main window).
- Publishing to the App Store or distributing to others.

**Anti-goals** (failure even if everything technically works)
- **In the way.** Catches clicks on transparent areas, steals keyboard focus from the current app, talks too often, intrudes on fullscreen video or screen sharing.
- **Dangerous.** Quits an app with unsaved work, deletes files or runs an arbitrary command without an explicit "yes".
- **Greedy.** Noticeable CPU use at idle or battery drain.
- **Generic.** Looks like a default assistant rather than Dzhmil from the sketch.

## 3. Constraints

- Mac: Apple M1 Pro, 16 GB, macOS 27.2, Xcode 27.2, Swift 6.4.
- Personal use. The app is not sandboxed, otherwise it cannot control other apps.
- Signed with a stable "Apple Development" certificate from a free personal team. With ad-hoc signing macOS resets permissions (microphone, automation) after every rebuild.
- Anthropic has no official Swift SDK, so the Claude API is called directly over HTTP (`POST /v1/messages`, SSE streaming) with `URLSession`.
- Microphone audio never leaves the Mac. Only the recognised text and tool results go to the cloud.
- The API key lives in the Keychain, never in code or a plist. A dedicated key for the app is entered on first launch.
- Code lives in `app/`; the project root holds only `docs/` and the README.

## 4. Approaches

| | Approach | Pros | Cons |
|---|---|---|---|
| **A (chosen)** | One native Swift app: body, voice and brain together | macOS permissions go to one signed app and stick. Lightweight. | The agent logic is written in Swift, not Python |
| B | Swift body + Python brain (FastAPI, faster-whisper) over WebSocket | Brain in my main language | Permissions go to the Python interpreter or the terminal and get lost now and then. Two processes. |
| C | Electron or Tauri with TypeScript | One familiar language | 150+ MB of memory in the background; transparent click-through windows need hacks |

## 5. Decided

- Character: the turquoise quadcopter **Dzhmil**, as in the sketch: a visor with eyes, an antenna with a light, a blue-and-yellow strap on the battery, a turquoise body.
- States from the sketch: hovering, flying around the screen, listening, speaking, "job done" (a flip), sleeping on the Dock.
- Voice conversation is in v1.
- Technology: approach A.

## 6. Design

### 6.1 Character and rendering

- Vector, not sprites: the drone is drawn from the sketch geometry, so it stays sharp on Retina at any scale. Procedural animation: spinning propellers, bobbing, blinking, banking.
- States:

  | State | What you see |
  |---|---|
  | `hover` | hovers in place, gentle bobbing, blinks |
  | `flying` | flies to a point, banks into the direction of flight (bank proportional to speed) |
  | `listening` | wide eyes, a pulsing ring |
  | `thinking` | waiting for Claude: eyes dart, the antenna light blinks faster |
  | `speaking` | a "mouth" of bars on the visor moves while speech plays |
  | `confirming` | a bubble with a question and Yes / No buttons; the drone looks at the user |
  | `celebrating` | a 360° flip after a successful action, happy eyes |
  | `error` | sad eyes, a short "no" shake |
  | `sleeping` | sits on the Dock, propellers stopped, "z z z", dim light |

- Propeller sound: a quiet hum while flying, off by default, can be turned on in Settings.

### 6.2 Window and on-screen behaviour

- A small transparent borderless `NSPanel` around the drone (and the bubble). The window itself moves around the screen; no fullscreen transparent overlay.
- The panel is non-activating, above normal windows, visible on all Spaces and next to fullscreen apps. It never takes keyboard focus except while the text field is open.
- Clicks on transparent parts pass through to the app below. Only the drone and the bubble catch clicks.
- Motion: smooth acceleration and braking, banking into turns, a little inertia. It should feel like a drone, not a picture being moved.
- Idle life: every few minutes (randomly) it flies to a new spot, sometimes perches on the Dock or the top edge of a window. If the user is inactive for N minutes or it is late at night, it falls asleep on the Dock.
- When the cursor comes close, the drone moves aside so it does not cover what the user is doing.
- Drag with the mouse: you can grab it and move it, and it stays there for a while.
- Automatic quiet: if the active app is fullscreen or Quiet Mode is on, the drone does not fly or speak first. It moves to the edge or becomes semi-transparent (builder's choice).

### 6.3 Voice

- **Input:** press and hold. ⌥Space by default (changeable in Settings) or "Talk" in the menu. Release to stop recording. Holding the drone itself only drags it and never turns on the microphone.
- **Recognition:** WhisperKit (Whisper on CoreML, on-device on Apple Silicon). The model downloads on first launch and stays warm. Model size chosen by the builder for latency on an M1 Pro: under ~1.5 s for a 5-second phrase.
- **Text input:** double-clicking the drone opens a small text field next to it.
- **Spoken replies:** `AVSpeechSynthesizer`, preferring Enhanced/Premium voices. Replies are spoken sentence by sentence as they stream in, so there is no wait for the end. The text appears in the bubble at the same time.
- Spoken replies can be turned off in the menu (bubble only).
- *Changed 2026-11-17: the app speaks and understands English only.*

### 6.4 Brain (Claude API)

- `POST /v1/messages` with SSE streaming over `URLSession`, with a small client and SSE parser of our own. Before writing code, the builder checks the current API docs (request shape, stream events, tool use).
- Default model: `claude-opus-5-5` with `output_config.effort: "low"` for quick conversational replies. Model and effort can be changed in Settings. With caching, one exchange costs around a cent.
- Server-side fallbacks are on in case the model refuses (`fallbacks: "default"` with the matching beta header). `stop_reason` is checked before reading the reply.
- Prompt caching for the system prompt and the tool list, which do not change between turns.
- System prompt: Dzhmil's personality (friendly, a little playful, short because replies are spoken), the current date and time (at the end, after the cache breakpoint), plus a **profile**: an editable text file about the user, edited in Settings.
- Conversation history is kept in memory while the app runs and is not saved between launches (v1). History is only ever appended, never edited after the fact: Claude Opus 5.5 requires this (preserved thinking), and caching works better. So instead of trimming, a new session starts after 30 minutes of silence or 60 messages.
- Tool-use loop: Claude calls a tool → the app runs it (with confirmation if needed) → the result goes back to Claude → final reply. A tool error is returned with `is_error: true`.
- No network or an API error: the `error` state, a short phrase in the bubble ("I can't reach my brain. Check your internet."), no crash.

### 6.5 Hands (tools)

Every tool has a risk level. The policy is set by code, not by the model.

| Tool | What it does | Confirmation |
|---|---|---|
| `get_system_status` | battery and charging, CPU load, memory, free disk space, uptime | no |
| `list_running_apps` | list of running apps | no |
| `open_app` | open or activate an app by name | no |
| `open_url` | open a link or a search in the default browser | no |
| `set_volume` / `mute` | volume | no |
| `set_timer` | Dzhmil reminds you after N minutes | no |
| `quit_app` | quit an app gracefully (it asks about unsaved work itself) | **yes** |
| `force_quit_app` | force quit | **yes, always** |
| `system_power` | sleep, restart, shut down, lock the screen | **yes** (except lock) |
| `run_applescript` | arbitrary AppleScript for everything else | **yes, always, showing the script** |
| `run_shell` | a zsh command with a timeout; output is cut | **yes, always, showing the command** |

- Confirmation: the `confirming` state, a clear question in the bubble ("Quit Safari?") and Yes / No buttons. You can answer by voice. No answer within 20 seconds counts as "no".
- Permissions are requested when first needed: microphone on the first voice input, automation (Apple Events) on the first AppleScript. Accessibility is not needed in v1. If some AppleScript needs it, the drone explains where to turn it on.

### 6.6 Speaking first

Local code decides the triggers; Claude writes the phrase (templates as a fallback).

- First wake-up of the day: a greeting and "how are you?".
- More than 2 hours of continuous activity: suggest a break.
- Battery below 15% and not charging: a warning.
- A timer the user asked for.
- Limiter: at most one remark per ~45 minutes (except timers and battery); nothing in Quiet Mode, over a fullscreen app or at night. The frequency ("chattiness") is configurable: rarely / normal / often.
- If Dzhmil asks a question, the microphone does not turn on by itself. The bubble shows Reply and Later buttons, and you can also answer with the usual hotkey. After ~30 seconds without an answer the bubble disappears. The microphone turns on only on a user action.

### 6.7 Menu and settings

- Menu bar icon: Talk, Type, Quiet Mode, Hide / Show, Settings, Quit.
- Settings window: API key (Keychain), model and effort, hotkey, voice, voice volume, chattiness, propeller sound, the "about you" profile, open at login (`SMAppService`).
- The profile lives in `~/Library/Application Support/Dzhmil/profile.md`, not in the repository, so personal data never ends up in git. A template is created on first launch.
- First launch: a short introduction in the bubble. Dzhmil introduces itself, asks for the API key (a text field) and explains the hotkey.
- Running: from Xcode during development, later the built app in `/Applications` with open at login.

### 6.8 Code layout (guideline)

```
Dzhmil/
├── docs/superpowers/specs/      design documents
└── app/                         Xcode project
    └── Dzhmil/
        ├── App/                 entry point, menu bar, settings
        ├── Character/           drone drawing, states, animation
        ├── Flight/              panel window, motion, picking spots, click-through
        ├── Behavior/            state machine, initiative, quiet mode
        ├── Voice/               recording, WhisperKit, speech synthesis
        ├── Brain/               Claude API client, SSE, history, prompt
        ├── Tools/               tool registry, confirmation policy, implementations
        └── Support/             Keychain, system metrics, logs
```

Dependencies via Swift Package Manager: WhisperKit and KeyboardShortcuts (a global hotkey with key-down and key-up events). Nothing else unless necessary.

### 6.9 Quality

- Unit tests: the SSE parser, the tool-use loop (on recorded API replies), the confirmation policy (a risky tool never runs without a "yes"), the behaviour state machine, the initiative limiter.
- Manual checklist: transparent areas pass clicks through, focus is never stolen, works on another Space and next to a fullscreen app, first launch with permission prompts, no network.
- Resource budget: CPU < 3% at idle; animation no faster than the display refresh rate and slower while the drone sleeps; memory < 600 MB including the loaded Whisper model.

## 7. Left to the builder

- The exact WhisperKit model size (by measured latency).
- Animation timings and curves, how often it flies, choice of perches.
- How click-through is implemented (dynamic `ignoresMouseEvents` by cursor position or otherwise).
- Bubble in the same window or in a separate panel.
- Fullscreen behaviour: move to the edge or turn semi-transparent.
- Minimum macOS version (15 or later).
- Exact wording of the system prompt and tool descriptions.

## 8. Later (not v1)

A wake word, long-term memory, "vision" through screenshots and computer use, multiple displays, skins and accessories, easter eggs (for example, a reaction to Betaflight Configurator launching).
