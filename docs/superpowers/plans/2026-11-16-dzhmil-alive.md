# Джміль: живые анимации и взгляд на экран — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Дрон живой (жесты в покое, глаза за курсором, редкая игра за курсором) и по просьбе смотрит на экран через инструмент `look_at_screen`.

**Architecture:** Решения (какой жест, куда смотрят глаза, пора ли играть, как кодировать картинку, как собрать `tool_result` с изображением) — чистая логика в `DzhmilCore` с тестами. Приложение рисует жесты на Core Animation, снимает экран через ScreenCaptureKit и связывает всё в `DroneDirector`/`Companion`.

**Tech Stack:** Swift 6, Swift Testing, Core Animation, ScreenCaptureKit (macOS 14+), ImageIO.

**Spec:** `docs/superpowers/specs/2026-11-16-dzhmil-alive-design.md` (дополняет `2026-11-15-dzhmil-design.md`).

## Global Constraints

- Всё из Global Constraints плана `2026-11-15-dzhmil-v1.md` остаётся в силе (API, append-only история, коммиты без trailer-подписей, ветка `feature/dzhmil-v1`).
- Картинка для Claude: длинная сторона ≤ 1568 px, JPEG качество 0.75, блок `{"type":"image","source":{"type":"base64","media_type":"image/jpeg","data":…}}` внутри `tool_result.content`.
- `look_at_screen` безопасный (без подтверждения), но каждый снимок предваряется вспышкой и облачком «Смотрю на экран…». Окно Джмиля в снимок не попадает.
- Жесты только в `hover`, не в тихом режиме и не при полном экране; следующий через 8–20 с; без повторов подряд; бочка не чаще раза в 600 с.
- Глаза: радиус 450 pt, смещение до ±3 pt по X и ±2 pt по Y (координаты рисунка 240×180).
- Игра: «Редко» — никогда, «Нормально» — не чаще 1200 с, «Часто» — не чаще 600 с; курсор < 300 pt/с; дрон свободен; нет облачка; длительность ~4 с.
- В покое CPU < 3%.

## Review Focus

1. **Снимок без разрешения «Запись экрана».** Ожидается понятная ошибка с путём в настройках, а не пустая картинка. Тест в Task 2 (`deniedPermissionExplainsWhereToEnable`).
2. **Огромный экран (5K, 2 монитора).** Картинка всё равно ≤ 1568 px по длинной стороне. Тест в Task 1 (`fittedSize*`).
3. **Нет активного окна** (рабочий стол, Finder без окон). `window` откатывается на весь экран. Тест в Task 2 (`windowFallsBackToScreen`).
4. **Игра за курсором во время работы** (быстрая мышь, облачко, тихий режим). Не начинается. Тест в Task 3 (`ChasePolicyTests`).
5. **Спрятанный дрон.** Ни жестов, ни игры, ни глаз (уже гарантирует `lifeTick`/`hitTick` guard) — проверить в Task 5 вручную.

---

### Task 1: Картинки в результатах инструментов

**Files:**
- Create: `app/DzhmilKit/Sources/DzhmilCore/Tools/ImageEncoder.swift`
- Modify: `Tools/Tool.swift`, `Tools/ToolExecutor.swift`, `Conversation/Conversation.swift`
- Test: `ImageEncoderTests.swift`, `ToolExecutorTests.swift`, `ConversationTests.swift`

**Interfaces:**
- Produces: `public struct ToolImage: Equatable, Sendable { var mediaType: String; var base64: String }`
- Produces: `public struct ToolRichOutput: Sendable { var text: String; var images: [ToolImage] }`
- Produces: в `Tool` новый метод `func runRich(_ input: JSONValue) async throws -> ToolRichOutput` с реализацией по умолчанию через `run` (картинок нет). `ToolOutcome` получает `var images: [ToolImage] = []`.
- Produces: `public enum ImageEncoder { static func fittedSize(width: Int, height: Int, maxSide: Int = 1568) -> (width: Int, height: Int); static func jpegBase64(_ image: CGImage, maxSide: Int = 1568, quality: Double = 0.75) throws -> String }`

- [ ] **Step 1: Падающие тесты:** `fittedSize(3000, 2000) == (1568, 1045)`; `fittedSize(5120, 2880)` длинная сторона 1568; `fittedSize(800, 600) == (800, 600)`; `jpegBase64` для сгенерированного 2000×1000 CGImage декодируется в данные, начинающиеся с `FF D8`, и картинка ≤ 1568 по ширине. `ToolExecutorTests.imageToolReturnsImages`: фейковый инструмент с `runRich` → `outcome.images.count == 1`, `content == подпись`. `ConversationTests.imageToolResultBuildsBlocks`: `tool_result.content` — массив `[image-блок с source.data, text-блок]`; для инструмента без картинок `content` остаётся строкой.
- [ ] **Step 2:** `swift test --package-path app/DzhmilKit`. Expected: FAIL.
- [ ] **Step 3:** Реализовать (ImageIO `CGImageDestination` с `kCGImageDestinationLossyCompressionQuality`, масштабирование через `CGContext`).
- [ ] **Step 4:** Тесты. Expected: PASS всё.
- [ ] **Step 5:** Коммит `feat(tools): allow tools to return images`.

### Task 2: Инструмент `look_at_screen`

**Files:**
- Create: `app/DzhmilKit/Sources/DzhmilCore/Tools/Mac/ScreenTool.swift`
- Modify: `Tools/Mac/MacToolbox.swift`, `Conversation/PromptBuilder.swift`
- Test: `MacToolsTests.swift`, `PromptBuilderTests.swift`

**Interfaces:**
- Produces: `public enum CaptureTarget: String, Sendable { case window, screen }`
- Produces: `public struct CapturedImage: @unchecked Sendable { var image: CGImage; var appName: String?; var windowTitle: String? }`
- Produces: `public enum ScreenCaptureError: Error, Equatable { case permissionDenied, nothingToCapture }`
- Produces: `public protocol ScreenCapturer: Sendable { func capture(_ target: CaptureTarget) async throws -> CapturedImage }` (для `window` без активного окна реализация сама снимает экран)
- Produces: `MacToolbox.all(timers: TimerStore, screen: (any ScreenCapturer)? = nil, beforeCapture: @escaping @Sendable () async -> Void = {})` — 13 инструментов, если `screen` передан.

- [ ] **Step 1: Падающие тесты** (фейковый `ScreenCapturer`):
  - `lookAtScreenReturnsImageAndCaption`: подпись «Скриншот окна: Safari — Apple», 1 картинка.
  - `beforeCaptureRunsFirst`: хук вызван ровно раз и до `capture`.
  - `deniedPermissionExplainsWhereToEnable`: ошибка содержит «Запись экрана».
  - `windowFallsBackToScreen`: фейк для `window` бросает `.nothingToCapture` → инструмент повторяет с `screen`.
  - `look_at_screen` безопасный, схема `target` с enum `["window","screen"]`.
  - `exactToolSet` с экраном — 13 имён, без экрана — прежние 12.
  - `PromptBuilderTests`: системный промпт содержит «look_at_screen» и правило «только когда пользователь просит».
- [ ] **Step 2:** Запустить. Expected: FAIL.
- [ ] **Step 3:** Реализовать. Текст ошибки: «Нет доступа к записи экрана. Включи Джмиля в Системных настройках → Конфиденциальность и безопасность → Запись экрана, потом перезапусти меня.»
- [ ] **Step 4:** Тесты. Expected: PASS.
- [ ] **Step 5:** Коммит `feat(tools): add look_at_screen tool`.

### Task 3: Логика живости

**Files:**
- Create: `app/DzhmilKit/Sources/DzhmilCore/Behavior/Liveliness.swift`
- Test: `LivelinessTests.swift`

**Interfaces:**
- Produces: `public enum IdleGesture: CaseIterable, Sendable { case lookAround, tilt, hop, yawn, barrelRoll }`
- Produces: `public struct IdleAnimator { mutating func pick(now: Date, hour: Int, using rng: inout some RandomNumberGenerator) -> IdleGesture; static func delay(using rng: inout some RandomNumberGenerator) -> TimeInterval }`
- Produces: `public struct ChasePolicy { mutating func shouldChase(now: Date, chattiness: Chattiness, cursorSpeed: Double, canWander: Bool, bubbleVisible: Bool) -> Bool }` (запоминает время последней игры)
- Produces: `public enum EyeTracker { static func offset(droneCenter: CGPoint, cursor: CGPoint) -> CGVector }` (y вверх, как в AppKit)

- [ ] **Step 1: Падающие тесты:** нет одинаковых жестов подряд за 300 выборов; бочка не чаще раза в 600 с при выборах каждые 15 с; ночью (hour 23) зевков больше, чем днём (seeded RNG, 1000 выборов); `delay` в 8…20; `ChasePolicy`: `.rare` — никогда, `.normal` — не раньше 1200 с после последней, быстрый курсор / занят / облачко → false, первая игра разрешена сразу; `EyeTracker`: дальше 450 pt → `.zero`, курсор далеко справа (300 pt) → dx == 3, слева → −3, сверху → dy == 2, на 10 pt правее → 0 < dx < 1.
- [ ] **Step 2:** Запустить. Expected: FAIL.
- [ ] **Step 3:** Реализовать (зевок ×3 веса при hour ≥ 21 или < 7; смещение глаз = clamp(d/100 · max)).
- [ ] **Step 4:** Тесты. Expected: PASS.
- [ ] **Step 5:** Коммит `feat(behavior): add idle gestures, eye tracking and chase policy`.

### Task 4: Жесты на слое дрона

**Files:**
- Modify: `app/Dzhmil/Character/DroneView.swift`, `app/Dzhmil/Character/StateGallery.swift`

**Interfaces:**
- Produces: `enum DroneGesture { case idle(IdleGesture), wiggle, startle, cameraFlash }`, `DroneLayerView.play(_ g: DroneGesture)`, `DroneLayerView.setEyeOffset(_ v: CGVector)` (y переворачивается в координаты слоя)
- Produces: `CompanionViewModel.gesture: (id: Int, DroneGesture)?` и `eyeOffset: CGVector`, которые `DroneView` прокидывает в слой.

- [ ] **Step 1:** Жесты как одноразовые `CAAnimation` на слоях `action`/глаз/рта, без влияния на постоянные анимации: оглядывание (глаза ±4 pt за 1.2 с), наклон (±8°, держит 1 с), прыжок (−12 pt с отскоком), зевок (рот-овал + прищур 1.4 с), бочка (`transform.scale.x` 1→−1→1 за 0.8 с), покачивание (±6° ×3 + глаза-домики 1 с), испуг (глаза ×1.4 + отскок 0.4 с), вспышка (визор белеет и гаснет 0.35 с ×2, огонёк пульсирует).
- [ ] **Step 2:** Глаза: `setEyeOffset` двигает `eyesOpen` через неявную анимацию 0.15 с.
- [ ] **Step 3:** Галерея (DEBUG): кнопки для всех жестов и слайдеры смещения глаз.
- [ ] **Step 4:** Сборка Release, рендер PNG состояний (не сломались). Expected: `** BUILD SUCCEEDED **`, 9 PNG совпадают с прежними.
- [ ] **Step 5:** Коммит `feat(character): add idle gestures and eye offset to the drone`.

### Task 5: Жизнь в `DroneDirector`

**Files:**
- Modify: `app/Dzhmil/Flight/DroneDirector.swift`

- [ ] **Step 1:** `lifeTick`: если `hover` и не quiet/fullscreen и настал срок — `IdleAnimator.pick` → `model.gesture`; следующий срок через `delay`.
- [ ] **Step 2:** `hitTick` (20 Гц): `EyeTracker.offset` → `model.eyeOffset`, только если изменилось > 0.1; испуг при скорости курсора > 800 pt/с ближе 150 pt (кулдаун 5 с).
- [ ] **Step 3:** Покачивание при `wakeUp` и при возвращении после «Спрятать».
- [ ] **Step 4:** Игра: `ChasePolicy.shouldChase` раз в секунду → запоминает место, 4 с подлетает к `cursor + (120, 80)` (обновление цели каждые 0.3 с, `clamp`), затем `cruise` обратно. Прерывается нажатием ⌥Space, облачком или если дрон спрятали.
- [ ] **Step 5:** Сборка, запуск, замер CPU в hover 30 с. Expected: < 3%.
- [ ] **Step 6:** Коммит `feat(flight): bring idle gestures, eye tracking and cursor play to life`.

### Task 6: Снимок экрана в приложении

**Files:**
- Create: `app/Dzhmil/Companion/ScreenCapture.swift`
- Modify: `app/Dzhmil/Companion/Companion.swift`, `README.md`

- [ ] **Step 1:** `SCKScreenCapturer: ScreenCapturer`: `CGPreflightScreenCaptureAccess()`, иначе `CGRequestScreenCaptureAccess()` и `.permissionDenied`; `SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)`; `window` — самое большое окно слоя 0 фронтального приложения (не Джміль) → `SCContentFilter(desktopIndependentWindow:)`; `screen` — дисплей под курсором, `SCContentFilter(display:excludingWindows:)` с окнами Джмиля; `SCStreamConfiguration` с размером из `ImageEncoder.fittedSize` в пикселях; `SCScreenshotManager.captureImage`.
- [ ] **Step 2:** `Companion`: передать `SCKScreenCapturer()` и хук `beforeCapture` (на главном потоке: жест `cameraFlash` + облачко «Смотрю на экран…», пауза 0.4 с) в `MacToolbox.all`.
- [ ] **Step 3:** README: возможность «Look at my screen», приватность (скриншот уходит в Claude только по просьбе, со вспышкой), разрешение «Запись экрана».
- [ ] **Step 4:** Сборка Release, запуск, ручная проверка пользователем: «Глянь, что у меня на экране» → запрос разрешения → после разрешения и перезапуска — описание окна.
- [ ] **Step 5:** Коммит `feat(companion): let Dzhmil look at the screen on request`.

## Self-review

- Покрытие спеки: анимации → Task 3, 4, 5; глаза → 3, 4, 5; игра → 3, 5; `look_at_screen` → 1, 2, 6; промпт → 2; приватность и вспышка → 2, 6; CPU → 5.
- Имена согласованы: `ToolRichOutput`, `ToolImage`, `ScreenCapturer`, `CaptureTarget`, `CapturedImage`, `IdleGesture`, `DroneGesture`, `ChasePolicy`, `EyeTracker`.
