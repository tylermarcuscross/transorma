import Foundation
import Testing

@testable import TransormaCore

@Test func aDownloadBurstWaitsForAssessmentSlots() async throws {
    let storage = try TestStore()
    defer { storage.remove() }
    try storage.store.updateSettings { $0.enabled = true }
    let fixture = try SignedFixture()
    let gate = AsyncGate()
    let engine = ProtectionEngine(
        store: storage.store, verifier: DKIMVerifier(resolver: fixture.dns),
        intelligence: FakeIntelligence(beforeClassification: { await gate.wait() }))

    try await withThrowingTaskGroup(of: UnsubscribeJob?.self) { tasks in
        for _ in 0..<10 { tasks.addTask { await engine.prepare(raw: fixture.raw) } }
        await gate.waitUntilWaiting(count: 2)
        do { try await waitForAssessments(engine, count: 8) } catch {
            await gate.open()
            tasks.cancelAll()
            throw error
        }
        await gate.open()
        var prepared = 0
        for try await job in tasks { if job != nil { prepared += 1 } }
        #expect(prepared == 10)
    }
    #expect(await engine.pendingAssessmentCount == 0)
    #expect(try storage.store.snapshot().jobs.isEmpty)
}

@Test(arguments: ["cancel", "deadline", "pause"])
func queuedAssessmentsRespectCancellationDeadlineAndConsent(reason: String) async throws {
    let storage = try TestStore()
    defer { storage.remove() }
    try storage.store.updateSettings { $0.enabled = true }
    let fixture = try SignedFixture()
    let gate = AsyncGate()
    let engine = ProtectionEngine(
        store: storage.store, verifier: DKIMVerifier(resolver: fixture.dns),
        intelligence: FakeIntelligence(beforeClassification: { await gate.wait() }))

    try await withThrowingTaskGroup(of: Void.self) { tasks in
        for _ in 0..<2 { tasks.addTask { _ = await engine.prepare(raw: fixture.raw) } }
        await gate.waitUntilWaiting(count: 2)
        let deadline = ContinuousClock.now.advanced(by: reason == "deadline" ? .seconds(1) : .seconds(20))
        let queued = Task { await engine.prepare(raw: fixture.raw, deadline: deadline) }
        do { try await waitForAssessments(engine, count: 1) } catch {
            queued.cancel()
            await gate.open()
            tasks.cancelAll()
            throw error
        }
        switch reason {
        case "cancel": queued.cancel()
        case "pause":
            try storage.store.updateSettings { $0.enabled = false }
            await gate.open()
        default: break
        }
        // Cancellation and expiry must release a queued caller even while both
        // active model requests remain suspended and ignore cancellation.
        #expect(await queued.value == nil)
        #expect(await engine.pendingAssessmentCount == 0)
        await gate.open()
    }
    #expect(try storage.store.snapshot().jobs.isEmpty)
}

@Test(arguments: [false, true])
func assessmentWaitingIsBoundedByCountAndBytes(largeMessages: Bool) async throws {
    let storage = try TestStore()
    defer { storage.remove() }
    try storage.store.updateSettings { $0.enabled = true }
    let fixture = try SignedFixture()
    let gate = AsyncGate()
    let engine = ProtectionEngine(
        store: storage.store, verifier: DKIMVerifier(resolver: fixture.dns),
        intelligence: FakeIntelligence(beforeClassification: { await gate.wait() }))
    try await withThrowingTaskGroup(of: Void.self) { active in
        for _ in 0..<2 { active.addTask { _ = await engine.prepare(raw: fixture.raw) } }
        await gate.waitUntilWaiting(count: 2)
        let raw = largeMessages ? Data(repeating: 0, count: 2_000_000) : fixture.raw
        let count = largeMessages ? 4 : 32
        let queued = (0..<count).map { _ in Task { await engine.prepare(raw: raw) } }
        do { try await waitForAssessments(engine, count: count) } catch {
            for task in queued { task.cancel() }
            await gate.open()
            active.cancelAll()
            throw error
        }
        #expect(await engine.prepare(raw: raw) == nil)
        for task in queued { task.cancel() }
        for task in queued { #expect(await task.value == nil) }
        #expect(await engine.pendingAssessmentCount == 0)
        await gate.open()
    }
}

private func waitForAssessments(_ engine: ProtectionEngine, count: Int) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while await engine.pendingAssessmentCount != count {
        try #require(ContinuousClock.now < deadline, "Assessment queue did not reach the expected size.")
        await Task.yield()
    }
}

@Test func preparationRequiresConsentAndNeverEnqueues() async throws {
    let storage = try TestStore()
    defer { storage.remove() }
    let store = storage.store
    let fixture = try SignedFixture()
    let engine = ProtectionEngine(
        store: store, verifier: DKIMVerifier(resolver: fixture.dns), intelligence: FakeIntelligence())
    #expect(await engine.prepare(raw: fixture.raw) == nil)

    var settings = ProtectionSettings()
    settings.enabled = true
    try store.setSettings(settings)
    let prepared = await engine.prepare(raw: fixture.raw)
    let job = try #require(prepared)
    #expect(try store.snapshot().jobs.isEmpty)
    #expect(try store.enqueue(job))
    #expect(try store.enqueue(job) == false)
    #expect(try store.snapshot().jobs.count == 1)
}

@Test func marketingPolicyPreservesTransactionsAndCorrespondence() {
    #expect(
        !MarketingPolicy.isCandidate(
            subject: "Your order confirmation", text: "Save today and shop now", hasUnsubscribe: true))
    #expect(!MarketingPolicy.isCandidate(subject: "Newsletter", text: "Our latest news", hasUnsubscribe: true))
    #expect(!MarketingPolicy.isCandidate(subject: "Re: sale", text: "Save today and shop now", hasUnsubscribe: true))
}

@Test func keepListAndAIRejectionPreventPreparation() async throws {
    let storage = try TestStore()
    defer { storage.remove() }
    let store = storage.store
    let fixture = try SignedFixture()
    var settings = ProtectionSettings()
    settings.enabled = true
    settings.allowedSenders = ["example.com"]
    try store.setSettings(settings)
    let engine = ProtectionEngine(
        store: store, verifier: DKIMVerifier(resolver: fixture.dns), intelligence: FakeIntelligence())
    #expect(await engine.prepare(raw: fixture.raw) == nil)
    settings.allowedSenders = []
    try store.setSettings(settings)
    let cautious = ProtectionEngine(
        store: store, verifier: DKIMVerifier(resolver: fixture.dns), intelligence: FakeIntelligence(marketing: false))
    #expect(await cautious.prepare(raw: fixture.raw) == nil)
    #expect(try store.snapshot().jobs.isEmpty)
}

@Test func unavailableModelStillAllowsStandardUnsubscribe() async throws {
    let storage = try TestStore()
    defer { storage.remove() }
    let store = storage.store
    var settings = ProtectionSettings()
    settings.enabled = true
    try store.setSettings(settings)
    let fixture = try SignedFixture()
    let engine = ProtectionEngine(
        store: store, verifier: DKIMVerifier(resolver: fixture.dns), intelligence: FakeIntelligence(available: false))
    #expect(await engine.prepare(raw: fixture.raw)?.kind == .oneClick)
    #expect(try store.snapshot().jobs.isEmpty)
}

@Test func cancelledPreparationCannotProduceWorkAfterInferenceResumes() async throws {
    let storage = try TestStore()
    defer { storage.remove() }
    let store = storage.store
    var settings = ProtectionSettings()
    settings.enabled = true
    try store.setSettings(settings)
    let fixture = try SignedFixture()
    let gate = AsyncGate()
    let engine = ProtectionEngine(
        store: store, verifier: DKIMVerifier(resolver: fixture.dns),
        intelligence: FakeIntelligence(beforeClassification: { await gate.wait() }))
    let task = Task { await engine.prepare(raw: fixture.raw) }
    await gate.waitUntilWaiting()
    task.cancel()
    await gate.open()
    #expect(await task.value == nil)
    #expect(try store.snapshot().jobs.isEmpty)
}
