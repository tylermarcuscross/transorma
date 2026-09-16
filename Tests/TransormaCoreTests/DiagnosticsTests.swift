import Foundation
import Testing

@testable import TransormaCore

@Test func oldStateAndJobsDecodeWithoutDiagnostics() throws {
    var state = StoreSnapshot()
    state.settings.enabled = true
    state.jobs = [
        UnsubscribeJob(sender: "offers@example.com", kind: .oneClick, url: URL(string: "https://example.com/u")!)
    ]
    var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
    json.removeValue(forKey: "diagnostics")
    var jobs = try #require(json["jobs"] as? [[String: Any]])
    jobs[0].removeValue(forKey: "traceID")
    json["jobs"] = jobs
    let decoded = try JSONDecoder().decode(StoreSnapshot.self, from: JSONSerialization.data(withJSONObject: json))
    #expect(decoded.settings.enabled)
    #expect(decoded.jobs.count == 1)
    #expect(decoded.jobs[0].traceID == nil)
    #expect(decoded.diagnostics == nil)
}

@Test func diagnosticsStayBoundedAndExpireWithoutRemovingJobs() throws {
    let storage = try TestStore()
    defer { storage.remove() }
    let now = Date.now
    for index in 0..<310 {
        try storage.store.recordDiagnostic(
            DiagnosticEntry(
                id: UUID(), traceID: UUID(), date: now, event: .received,
                elapsedMilliseconds: index, senderDomain: "example.com"))
    }
    let state = try storage.store.snapshot()
    #expect(state.diagnostics?.entries.count == 300)
    #expect(state.diagnostics?.callbackCount == 310)
    #expect(state.lastMailActivity == now)
    try storage.store.recordDiagnostic(
        DiagnosticEntry(
            id: UUID(), traceID: UUID(), date: now.addingTimeInterval(-8 * 86_400), event: .paused,
            elapsedMilliseconds: 0, senderDomain: nil))
    #expect(try storage.store.snapshot().diagnostics?.entries.contains { $0.event == .paused } == false)
}

@Test func unreadableDiagnosticDataDoesNotHideConsentOrQueuedWork() throws {
    var state = StoreSnapshot()
    state.settings.enabled = true
    state.jobs = [
        UnsubscribeJob(sender: "offers@example.com", kind: .oneClick, url: URL(string: "https://example.com/u")!)
    ]
    var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
    json["diagnostics"] = ["entries": "a newer or malformed diagnostic format"]
    let decoded = try JSONDecoder().decode(StoreSnapshot.self, from: JSONSerialization.data(withJSONObject: json))
    #expect(decoded.settings.enabled)
    #expect(decoded.jobs.count == 1)
    #expect(decoded.diagnostics == nil)
}

@Test func diagnosticWritesAcrossInstancesDoNotLoseCallbacksOrSettings() async throws {
    let storage = try TestStore()
    defer { storage.remove() }
    try storage.store.updateSettings { $0.enabled = true }
    try await withThrowingTaskGroup(of: Void.self) { tasks in
        for _ in 0..<20 {
            tasks.addTask {
                let writer = try SharedStore(directory: storage.directory)
                try writer.recordDiagnostic(
                    DiagnosticEntry(
                        id: UUID(), traceID: UUID(), date: .now, event: .received,
                        elapsedMilliseconds: 0, senderDomain: nil))
            }
        }
        try await tasks.waitForAll()
    }
    let state = try storage.store.snapshot()
    #expect(state.settings.enabled)
    #expect(state.diagnostics?.callbackCount == 20)
    #expect(state.diagnostics?.entries.count == 20)
}

@Test(arguments: [false, true])
func tracesExplainPreservationWithoutSavingMessageContents(marketing: Bool) async throws {
    let storage = try TestStore()
    defer { storage.remove() }
    try storage.store.updateSettings { $0.enabled = true }
    let fixture = try SignedFixture(subject: "Unlock $200 at the club", body: "Join today. PRIVACY POLICY")
    let trace = MessageTrace(store: storage.store)
    let job = await ProtectionEngine(
        store: storage.store, verifier: DKIMVerifier(resolver: fixture.dns),
        intelligence: FakeIntelligence(marketing: marketing)
    ).prepare(raw: fixture.raw, trace: trace)
    let state = try storage.store.snapshot()
    let entries = try #require(state.diagnostics?.entries)
    #expect(
        entries.map(\.event) == [
            .assessing, .verifyingSignature, .classifying, marketing ? .preparingOneClick : .modelRejected,
        ])
    #expect(entries.allSatisfy { $0.traceID == trace.id })
    #expect(job?.traceID == (marketing ? trace.id : nil))
    #expect(state.lastMailActivity == nil)
    #expect(state.jobs.isEmpty)
    let encoded = String(decoding: try JSONEncoder().encode(state.diagnostics), as: UTF8.self)
    #expect(!encoded.contains("$200"))
    #expect(!encoded.contains("PRIVACY"))
    #expect(!encoded.contains("https://"))
    #expect(!encoded.contains("@"))
}

@Test func failedDiagnosticStorageDoesNotChangeTheAssessment() async throws {
    let storage = try TestStore()
    let broken = try TestStore()
    defer {
        storage.remove()
        broken.remove()
    }
    try storage.store.updateSettings { $0.enabled = true }
    try Data("invalid".utf8).write(to: broken.directory.appendingPathComponent("state.json"))
    let fixture = try SignedFixture()
    let engine = ProtectionEngine(
        store: storage.store, verifier: DKIMVerifier(resolver: fixture.dns), intelligence: FakeIntelligence())
    #expect(await engine.prepare(raw: fixture.raw, trace: MessageTrace(store: broken.store)) != nil)
}

@Test(arguments: [
    ("From: sender@example.com\nSubject: TEST\n\nHello.\n", ProcessingEvent.noUnsubscribe),
    ("From: sender@example.com\r\n\nHello.", .malformedMessage),
    ("From: first@example.com, second@example.com\n\nHello.", .invalidSender),
    ("Subject: TEST\n\nHello.", .invalidSender),
])
func parsingDiagnosticsDistinguishPreservationReasons(raw: String, expected: ProcessingEvent) async throws {
    let storage = try TestStore()
    defer { storage.remove() }
    try storage.store.updateSettings { $0.enabled = true }
    let trace = MessageTrace(store: storage.store)
    let job = await ProtectionEngine(store: storage.store, intelligence: FakeIntelligence())
        .prepare(raw: Data(raw.utf8), trace: trace)
    #expect(job == nil)
    let state = try storage.store.snapshot()
    #expect(state.diagnostics?.entries.map(\.event) == [.assessing, expected])
    #expect(state.jobs.isEmpty)
}

@Test func deadlineIsRecordedOnceAndCannotClaimTrash() throws {
    let storage = try TestStore()
    defer { storage.remove() }
    let trace = MessageTrace(store: storage.store)
    let gate = MessageDecisionGate(store: storage.store, trace: trace) { #expect(!$0) }
    #expect(gate.resolve(nil, timedOut: true))
    #expect(!gate.resolve(nil, timedOut: true))
    #expect(try storage.store.snapshot().diagnostics?.entries.map(\.event) == [.deadlineExpired])
}
