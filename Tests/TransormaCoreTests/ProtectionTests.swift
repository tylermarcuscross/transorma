import Foundation
import Testing

@testable import TransormaCore

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
