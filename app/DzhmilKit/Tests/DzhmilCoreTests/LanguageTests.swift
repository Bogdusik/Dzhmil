import Foundation
import Testing
@testable import DzhmilCore

private func isCyrillic(_ s: String) -> Bool {
    s.unicodeScalars.contains { (0x0400...0x04FF).contains($0.value) }
}

@Suite struct LanguageSettingsTests {
    @Test func englishByDefault() {
        #expect(AppSettings().language == .english)
        #expect(AppSettings().conversation.language == .english)
    }

    @Test func survivesSaving() throws {
        var s = AppSettings()
        s.language = .russian
        let restored = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
        #expect(restored.language == .russian)
        #expect(restored.conversation.language == .russian)
    }

    @Test(arguments: [#"{"voiceEnabled":false}"#, #"{"language":"klingon","voiceEnabled":false}"#])
    func missingOrUnknownLanguageKeepsTheRest(_ json: String) throws {
        let s = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        #expect(s.language == .english)
        #expect(!s.voiceEnabled)
    }
}

@Suite struct RussianPromptTests {
    @Test func asksForRussianReplies() {
        for prompt in [PromptBuilder.system(profile: "", language: .russian), PromptBuilder.proactive(profile: "", language: .russian)] {
            #expect(prompt.contains("Always reply in Russian"))
            #expect(!prompt.contains("Always reply in English"))
            #expect(prompt.contains("Джмиль"))
        }
    }

    @Test func englishPromptStaysEnglish() {
        let s = PromptBuilder.system(profile: "")
        #expect(s.contains("Always reply in English"))
        #expect(!isCyrillic(s))
    }
}

@Suite struct RussianVoiceTests {
    let voices = [
        VoiceInfo(identifier: "gb", language: "en-GB", quality: 3, name: "Serena"),
        VoiceInfo(identifier: "ru.compact", language: "ru-RU", quality: 1, name: "Milena"),
        VoiceInfo(identifier: "ru.enhanced", language: "ru-RU", quality: 2, name: "Yuri (Enhanced)"),
    ]

    @Test func picksTheBestVoiceOfTheLanguage() {
        #expect(VoiceSelector.pick(for: .russian, from: voices)?.identifier == "ru.enhanced")
        #expect(VoiceSelector.pick(for: .english, from: voices)?.identifier == "gb")
        #expect(VoiceSelector.pick(for: .russian, from: [voices[0]]) == nil)
    }

    @Test func nameIsPronouncedInRussian() {
        #expect(SpeechText.forSpeech("Я Dzhmil, привет!", language: .russian) == "Я Джмиль, привет!")
        #expect(SpeechText.forSpeech("I'm Dzhmil.", language: .english) == "I'm Dzhmil.")
    }
}

@Suite struct RussianListeningTests {
    @Test(arguments: ["Да", "да, закрой", "Ага.", "угу", "давай", "конечно", "окей", "ну давай", "да, пожалуйста", "хорошо", "выполняй", "запускай"])
    func yes(_ s: String) { #expect(YesNoParser.parse(s) == true) }

    @Test(arguments: ["Нет", "неа", "не надо", "отмена", "отмени", "стоп", "да нет", "не закрывай", "ни в коем случае не надо"])
    func no(_ s: String) { #expect(YesNoParser.parse(s) == false) }

    @Test(arguments: ["а что это", "подожди, что делает эта команда", "может быть", "да, но зачем", "это можно?", "а можно?", "можно"])
    func unclear(_ s: String) { #expect(YesNoParser.parse(s) == nil) }

    @Test(arguments: ["Продолжение следует...", "Субтитры сделал DimaTorzok", "Спасибо за просмотр!", "Подписывайтесь на канал", "Всем пока."])
    func dropsRussianHallucinations(_ raw: String) { #expect(TranscriptFilter.clean(raw) == nil) }

    @Test func keepsRussianSpeech() {
        #expect(TranscriptFilter.clean(" Открой Safari ") == "Открой Safari")
        #expect(TranscriptFilter.clean("Да") == "Да")
    }

    @Test func abbreviationsDoNotEndARussianSentence() {
        var splitter = SentenceSplitter()
        #expect(splitter.feed("Открой настройки, напр. звук. Потом закрой. ") == ["Открой настройки, напр. звук.", "Потом закрой."])
    }
}

@Suite struct RussianPhraseTests {
    @Test func pickChoosesByLanguage() {
        #expect(Language.english.pick("Yes", "Да") == "Yes")
        #expect(Language.russian.pick("Yes", "Да") == "Да")
    }

    @Test(arguments: [ChatError.missingKey, .invalidKey, .insufficientCredit, .rateLimited, .overloaded, .network, .refusal, .incomplete,
                      .unknownModel, .localServerDown, .keyBlocked, .api(status: 500, message: "x")])
    func errorsAreTranslated(_ error: ChatError) {
        #expect(isCyrillic(error.userMessage(in: .russian)))
        #expect(!isCyrillic(error.userMessage(in: .english)))
        #expect(error.userMessage(in: .english) == error.userMessage)
    }

    @Test func proactiveTemplatesAreTranslated() {
        for trigger in [ProactiveTrigger.dailyGreeting, .breakReminder, .lowBattery(12), .timer("чайник")] {
            #expect(isCyrillic(PhraseWriter.template(trigger, language: .russian)))
        }
        #expect(PhraseWriter.template(.timer("чайник"), language: .russian) == "Напоминание: чайник")
        #expect(PhraseWriter.template(.lowBattery(12), language: .russian).contains("12%"))
    }

    @Test func proactiveWriterUsesTheLanguage() async {
        let client = FakeChatClient([.fail(.network)])
        let settings = ConversationSettings(model: "claude-haiku-5-5", effort: "low", language: .russian)
        let phrase = await PhraseWriter.write(.dailyGreeting, client: client, settings: settings, profile: "")
        #expect(isCyrillic(phrase))
        #expect(client.requests.first?.system == PromptBuilder.proactive(profile: "", language: .russian))
    }

    @Test(arguments: [
        ("quit_app", JSONValue.object(["app": "Safari"])), ("force_quit_app", .object(["app": "Safari"])),
        ("open_url", .object(["url": "https://example.com/a"])), ("run_shell", .object(["command": "ls"])),
        ("run_applescript", .object(["script": "beep"])), ("system_power", .object(["action": "sleep"])),
        ("system_power", .object(["action": "restart"])), ("system_power", .object(["action": "shutdown"])),
        ("system_power", .object(["action": "lock"])), ("remember", .object(["fact": "x"])), ("forget", .object(["query": "abc"])),
    ])
    func confirmationsAreTranslated(_ name: String, _ input: JSONValue) throws {
        let profile = ProfileStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let tools = MacToolbox.all(timers: TimerStore(file: profile.directory.appendingPathComponent("t.json")), profile: profile)
        let tool = try #require(tools.first { $0.name == name })
        let russian = tool.confirmation(for: input, language: .russian)
        let english = tool.confirmation(for: input, language: .english)
        #expect(isCyrillic(russian.question))
        #expect(!isCyrillic(english.question))
        #expect((russian.detail == nil) == (english.detail == nil))
    }
}

@Suite struct ConversationLanguageTests {
    @Test func changingLanguageStartsAFreshSession() async {
        let client = FakeChatClient([Fixtures.text("Hi."), Fixtures.text("Привет."), Fixtures.text("Ещё раз.")])
        let language = LanguageBox()
        let conversation = Conversation(client: client, executor: ToolExecutor(tools: [], confirmer: ScriptedConfirmer(mode: .no)),
                                        settings: { ConversationSettings(model: "claude-opus-5-5", effort: "low", language: language.value) },
                                        profile: { "" })
        for await _ in await conversation.send("hello") {}
        language.value = .russian
        for await _ in await conversation.send("привет") {}
        for await _ in await conversation.send("ещё") {}
        let requests = client.requests
        #expect(requests[1].system.contains("Always reply in Russian"))
        #expect(requests[1].messages.count == 1)
        #expect(requests[2].messages.count == 3)
    }

    @Test func confirmationsAndFallbackFollowTheLanguage() async {
        let tool = RecordingTool(name: "danger", dangerous: true)
        let confirmer = RecordingConfirmer()
        let call = Fixtures.toolCall([("t1", "danger", ["x": "1"])])
        let client = FakeChatClient(Array(repeating: call, count: 8))
        let conversation = Conversation(client: client, executor: ToolExecutor(tools: [tool], confirmer: confirmer),
                                        settings: { ConversationSettings(model: "claude-opus-5-5", effort: "low", language: .russian) },
                                        profile: { "" })
        var spoken: [String] = []
        for await event in await conversation.send("давай") {
            if case .sentence(let s) = event { spoken.append(s) }
        }
        #expect(await confirmer.questions.first == "Выполнить danger?")
        #expect(spoken.last.map(isCyrillic) == true)
    }
}

final class LanguageBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = Language.english
    var value: Language {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
}

actor RecordingConfirmer: ConfirmationProvider {
    var questions: [String] = []

    func confirm(_ request: ConfirmationRequest) async -> Bool {
        questions.append(request.question)
        return false
    }
}
