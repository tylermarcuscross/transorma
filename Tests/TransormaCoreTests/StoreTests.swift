import Foundation
import Testing

@testable import TransormaCore

@Test func settingsMutationsAcrossStoreInstancesPreserveOtherChanges() async throws {
    let storage = try TestStore()
    defer { storage.remove() }
    try storage.store.updateSettings { $0.enabled = true }
    try await withThrowingTaskGroup(of: Void.self) { tasks in
        for index in 0..<20 {
            tasks.addTask {
                let store = try SharedStore(directory: storage.directory)
                try store.updateSettings { $0.allowedSenders.append("sender\(index)@example.com") }
            }
        }
        try await tasks.waitForAll()
    }
    let settings = try storage.store.snapshot().settings
    #expect(settings.enabled)
    #expect(Set(settings.allowedSenders).count == 20)
}

@Test func independentStoreInstancesCannotClaimSameJob() throws {
    let storage = try TestStore()
    defer { storage.remove() }
    let a = storage.store
    let b = try SharedStore(directory: storage.directory)
    var settings = ProtectionSettings()
    settings.enabled = true
    try a.setSettings(settings)
    let url = try #require(URL(string: "https://store.example.com/u"))
    try a.enqueue(UnsubscribeJob(sender: "offers@store.example.com", kind: .oneClick, url: url))
    let claimed = try #require(try a.claim())
    #expect(try b.claim() == nil)
    #expect(throws: MailError.staleClaim) {
        try a.authorize(claimed, now: claimed.updatedAt.addingTimeInterval(181))
    }
    #expect(try b.claim(now: claimed.updatedAt.addingTimeInterval(181)) == nil)
    #expect(try b.snapshot().jobs.first?.status == .uncertain)
    #expect(try b.snapshot().jobs.first?.url == nil)
}

@Test func clearingHistoryDoesNotRepeatCompletedRequests() throws {
    let storage = try TestStore()
    defer { storage.remove() }
    let store = storage.store
    var settings = ProtectionSettings()
    settings.enabled = true
    try store.setSettings(settings)
    let job = UnsubscribeJob(
        sender: "offers@store.example.com", kind: .oneClick,
        url: try #require(URL(string: "https://store.example.com/u")))
    try store.enqueue(job)
    let claimed = try #require(try store.claim())
    try store.finish(claimed, status: .accepted, detail: "Accepted")
    try store.clearHistory()
    #expect(try store.snapshot().jobs.isEmpty)
    #expect(try store.enqueue(job) == false)
    #expect(try store.claim() == nil)
}

@Test func disablingIntelligenceCancelsOnlyWebJobsAndRejectsLateEnqueues() throws {
    let storage = try TestStore()
    defer { storage.remove() }
    let store = storage.store
    var settings = ProtectionSettings()
    settings.enabled = true
    try store.setSettings(settings)
    let web = UnsubscribeJob(
        sender: "offers@store.example.com", kind: .web,
        url: try #require(URL(string: "https://store.example.com/web")))
    let oneClick = UnsubscribeJob(
        sender: "offers@store.example.com", kind: .oneClick,
        url: try #require(URL(string: "https://store.example.com/one-click")))
    try store.enqueue(web)
    try store.enqueue(oneClick)
    settings.useIntelligence = false
    try store.setSettings(settings)

    let jobs = try store.snapshot().jobs
    #expect(jobs.first(where: { $0.id == web.id })?.status == .cancelled)
    #expect(jobs.first(where: { $0.id == web.id })?.url == nil)
    #expect(jobs.first(where: { $0.id == oneClick.id })?.status == .pending)
    #expect(throws: MailError.paused) { try store.enqueue(web) }
    #expect(try store.claim()?.id == oneClick.id)
}

@Test func staleAttemptCannotAuthorizeOrCompleteANewerRetry() throws {
    let storage = try TestStore()
    defer { storage.remove() }
    let store = storage.store
    var settings = ProtectionSettings()
    settings.enabled = true
    try store.setSettings(settings)
    let now = Date.now
    let job = UnsubscribeJob(
        sender: "offers@store.example.com", kind: .oneClick,
        url: try #require(URL(string: "https://store.example.com/u")), now: now)
    try store.enqueue(job)
    let first = try #require(try store.claim(now: now))
    try store.finish(first, status: .failed, detail: "Try again", retry: true, now: now)
    let retryTime = now.addingTimeInterval(121)
    let second = try #require(try store.claim(now: retryTime))

    #expect(second.attempts == 2)
    #expect(throws: MailError.staleClaim) { try store.authorize(first, now: retryTime) }
    #expect(try store.authorize(second, now: retryTime).enabled)
    try store.finish(first, status: .accepted, detail: "Late first result", now: retryTime)
    #expect(try store.snapshot().jobs.first?.status == .processing)
    try store.finish(second, status: .accepted, detail: "Second result", now: retryTime)
    #expect(try store.snapshot().jobs.first?.detail == "Second result")
}

@Test func webRetryIsNotScheduledAfterIntelligenceIsDisabled() throws {
    let storage = try TestStore()
    defer { storage.remove() }
    let store = storage.store
    var settings = ProtectionSettings()
    settings.enabled = true
    try store.setSettings(settings)
    let job = UnsubscribeJob(
        sender: "offers@store.example.com", kind: .web,
        url: try #require(URL(string: "https://store.example.com/u")))
    try store.enqueue(job)
    let claimed = try #require(try store.claim())
    settings.useIntelligence = false
    try store.setSettings(settings)
    #expect(throws: MailError.paused) { try store.authorize(claimed) }
    try store.finish(claimed, status: .failed, detail: "No retry", retry: true)
    #expect(try store.snapshot().jobs.first?.status == .failed)
    #expect(try store.snapshot().jobs.first?.url == nil)
}
