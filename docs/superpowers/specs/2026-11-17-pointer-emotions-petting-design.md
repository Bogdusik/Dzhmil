# Pointer, emotions, petting — design

Date: 2026-11-17. Ideas taken from Clicky (pointer), TypePet (emotions) and Desktop Mate (petting).

## Why

Dzhmil already looks at the screen and explains what to press, but only in words. Users stuck in an unfamiliar app want to *see* where to click. Emotions and petting make the drone feel alive at low cost.

## Goals

1. **Pointer.** After `look_at_screen`, Claude can call `point_at(x, y, label)`. Dzhmil flies next to that spot and draws an arrow to a pulsing ring with a label. Several calls in one reply point step by step.
2. **Emotions.** Claude may put a tag (`<happy>`, `<laugh>`, `<surprised>`, `<thinking>`, `<sad>`) before a sentence. The tag is never spoken or shown; the drone plays the matching animation when that sentence starts being spoken.
3. **Petting.** Moving the cursor back and forth over the drone (no button held) makes it squint happily, rock gently and purr; keep going and a heart floats up.

## Non-goals

- Clicking for the user. The pointer only shows.
- Accessibility-API element lookup (needs an extra permission, poor coverage in Electron apps and web).
- New emotion art beyond the existing eye sets plus one heart.

## Anti-goals

- The pointer pointing at the wrong place with confidence. If there is no recent screenshot, or the point is outside it, the tool fails and Claude must look again.
- Tags leaking into speech or the bubble.
- Petting stealing drags, double-clicks, or making the drone dodge or startle.

## Approaches considered

- **Pointer:** (A) a `point_at` tool using screenshot pixel coordinates — *picked*: fits the tool loop, allows several points per reply, the mapping is unit-testable; costs one extra round-trip per point. (B) inline `[POINT:x,y:label]` tags like Clicky — no extra round-trip, but one point per reply and tags split across stream chunks. (C) Accessibility API — dropped, see non-goals.
- **Emotions:** inline tags (picked); an `express` tool would add a round-trip and a pause per emotion.
- **Petting:** one way — a direction-reversal detector over the drone's hit shape.

## Design

### Pointer

- `CapturedImage` gains `rect`: the captured area in global display points, top-left origin (CoreGraphics). The window path computes it from the picked rect clipped to the display; the screen path uses the display frame.
- `LookAtScreenTool` records `ScreenshotFrame(rect, pixelWidth, pixelHeight, takenAt)` in a shared `ScreenshotMemory` actor and adds the pixel size to its caption ("Image size W×H px").
- `PointAtTool` (safe, no confirmation): input `x`, `y` (integers, pixels of the latest screenshot) and `label`. Fails if there is no screenshot, if it is older than 10 minutes, or if the point is outside the image. Maps with `ScreenPointMapper.appKitPoint(pixel:frame:primaryHeight:)` and calls an app-provided `pointer` closure. If the drone is hidden it fails with a message.
- Current models (Opus 5.5 default) take images up to 2576 px with coordinates 1:1 to pixels; our screenshots are ≤ 1568 px, so no extra scaling.
- `PointerLayout.droneSpot(target:visibleFrame:droneSize:)` puts the drone about 130 pt diagonally above the target, on the side with more room, clamped to the screen. The arrow runs from the drone edge to the ring edge.
- App: a full-screen, click-through, transparent `PointerOverlay` panel below the drone panel draws a pulsing ring + label pill at the target immediately, and the arrow once the drone arrives. The eyes look at the target. It clears on the next `point_at`, a new turn, the bubble closing, a drag, hiding, or after 30 s.
- System prompt: after looking at the screen, when telling the user where to click, call `point_at` on that element, one step at a time.

### Emotions

- `EmotionFilter` (streaming): `feed(delta) -> [EmotionPiece]` where a piece is `.text(String)` or `.emotion(Emotion)`. A `<` starts buffering; a known `<name>` becomes an emotion, an unknown short `<letters>` tag is dropped, anything else (non-letter, longer than 12 chars) is flushed as text. `flush()` returns leftovers as text.
- `Conversation` runs text deltas through it before the sentence splitter and yields a new `ConversationEvent.emotion(Emotion)` in stream order. History keeps the raw assistant text.
- `Companion` holds the pending emotion and attaches it to the next sentence: `Speaker.enqueue(_:onStart:)` calls it when that utterance starts (immediately if voice is off). An emotion with no following sentence plays at once.
- Animations: happy → happy eyes 1.5 s + hop; laugh → wiggle; surprised → wide eyes + small jump; thinking → head tilt + eyes look up; sad → sad eyes 2 s + droop.
- Prompt: tags are optional, at most one per sentence, not in every reply, only from the list.

### Petting

- `PetDetector` (pure): fed at 20 Hz with cursor x, time, whether the cursor is over the drone and whether a button is held. Petting starts after 3 horizontal direction reversals, each stroke at least 6 pt, within 1.5 s. It stops when the cursor leaves the drone, a button is pressed, or there is no movement for 0.8 s. It reports `heart` every 3 s of continuous petting.
- Only while the drone state is hover and not dragging. While petting and 1 s after it, startle, dodge and chase are suppressed.
- Effects: happy eyes held, gentle rocking loop, purr (the propeller synth at a lower pitch with ~22 Hz amplitude modulation; it plays even if the propeller sound setting is off, but not in quiet mode), and a small heart that floats up and fades.

## Left to the builder

Exact colours, arrow styling, timings within the stated ranges, and test file layout.
