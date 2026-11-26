import Foundation
import Security
import Testing
@testable import DzhmilCore

@Suite struct StoredKeyTests {
    @Test func readsASavedKey() throws {
        let key = StoredKey.from(status: errSecSuccess, data: Data("sk-1".utf8))
        #expect(key == .found("sk-1"))
        #expect(try key.value() == "sk-1")
    }

    @Test func noItemMeansNoKey() throws {
        let key = StoredKey.from(status: errSecItemNotFound, data: nil)
        #expect(key == .missing)
        #expect(try key.value() == nil)
    }

    @Test(arguments: [errSecUserCanceled, errSecAuthFailed, errSecInteractionNotAllowed, errSecNotAvailable])
    func aRefusedKeyIsNotAMissingKey(_ status: OSStatus) {
        let key = StoredKey.from(status: status, data: nil)
        #expect(key == .blocked)
        #expect(throws: ChatError.keyBlocked) { try key.value() }
    }

    @Test func blockedKeyIsExplainedAndNeverForgotten() {
        #expect(!ChatError.keyBlocked.meansBadKey)
        #expect(!ChatError.keyBlocked.meansForgetKey)
        #expect(!ChatError.keyBlocked.isRetryable)
        #expect(ChatError.keyBlocked.userMessage.contains("Always Allow"))
        #expect(ChatError.keyBlocked.userMessage(in: .russian).contains("Always Allow"))
        #expect(ChatError.keyBlocked.userMessage(in: .russian).contains("ключ"))
    }

    @Test(arguments: [ChatError.missingKey, .network, .insufficientCredit, .api(status: 403, message: "x")])
    func onlyAKeyTheProviderRejectedIsForgotten(_ error: ChatError) {
        #expect(!error.meansForgetKey)
        #expect(ChatError.invalidKey.meansForgetKey)
    }

    @Test(arguments: [Provider.anthropic, .openai])
    func clientsReportABlockedKey(_ provider: Provider) async {
        let client = RoutingClient(apiKey: { _ in try StoredKey.blocked.value() })
        let request = MessagesRequest(model: provider.defaultModel, system: "", messages: [], tools: [], effort: "low", provider: provider)
        await #expect(throws: ChatError.keyBlocked) {
            for try await _ in client.stream(request) {}
        }
    }
}
