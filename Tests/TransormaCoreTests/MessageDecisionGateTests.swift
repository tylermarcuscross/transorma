import Foundation
import Synchronization
import Testing

@testable import TransormaCore

@Test func anExpiredDecisionCannotEnqueueALateCandidate() throws {
    let storage = try TestStore()
    defer { storage.remove() }
    try storage.store.updateSettings { $0.enabled = true }
    let decisions = Mutex<[Bool]>([])
    let gate = MessageDecisionGate(store: storage.store, deadline: .now.advanced(by: .seconds(-1))) { decision in
        decisions.withLock { $0.append(decision) }
    }
    let job = UnsubscribeJob(
        sender: "offers@store.example.com", kind: .oneClick,
        url: try #require(URL(string: "https://store.example.com/u")))

    #expect(gate.resolve(job))
    #expect(!gate.resolve(job))
    #expect(decisions.withLock { $0 } == [false])
    #expect(try storage.store.snapshot().jobs.isEmpty)
}

@Test func timeoutCompletionPreventsALaterCommit() throws {
    let storage = try TestStore()
    defer { storage.remove() }
    try storage.store.updateSettings { $0.enabled = true }
    let decisions = Mutex<[Bool]>([])
    let gate = MessageDecisionGate(store: storage.store) { decision in decisions.withLock { $0.append(decision) } }
    let job = UnsubscribeJob(
        sender: "offers@store.example.com", kind: .oneClick,
        url: try #require(URL(string: "https://store.example.com/u")))

    #expect(gate.resolve(nil))
    #expect(!gate.resolve(job))
    #expect(decisions.withLock { $0 } == [false])
    #expect(try storage.store.snapshot().jobs.isEmpty)
}

@Test func theTrashCallbackSeesPersistedWorkAndCanReenterTheGate() throws {
    let storage = try TestStore()
    defer { storage.remove() }
    try storage.store.updateSettings { $0.enabled = true }
    let decisions = Mutex<[Bool]>([])
    let gateReference = Mutex<MessageDecisionGate?>(nil)
    let gate = MessageDecisionGate(store: storage.store) { decision in
        #expect((try? storage.store.snapshot().jobs.count) == 1)
        #expect(gateReference.withLock { $0 }?.resolve(nil) == false)
        decisions.withLock { $0.append(decision) }
    }
    gateReference.withLock { $0 = gate }
    let job = UnsubscribeJob(
        sender: "offers@store.example.com", kind: .oneClick,
        url: try #require(URL(string: "https://store.example.com/u")))

    #expect(gate.resolve(job))
    #expect(decisions.withLock { $0 } == [true])
}

@Test func concurrentDecisionResolversHaveOneConsistentOutcome() async throws {
    let storage = try TestStore()
    defer { storage.remove() }
    try storage.store.updateSettings { $0.enabled = true }
    let decisions = Mutex<[Bool]>([])
    let gate = MessageDecisionGate(store: storage.store) { decision in decisions.withLock { $0.append(decision) } }
    let job = UnsubscribeJob(
        sender: "offers@store.example.com", kind: .oneClick,
        url: try #require(URL(string: "https://store.example.com/u")))
    let winners = await withTaskGroup(of: Bool.self) { tasks in
        for index in 0..<40 {
            tasks.addTask { gate.resolve(index.isMultiple(of: 2) ? job : nil) }
        }
        return await tasks.reduce(0) { $0 + ($1 ? 1 : 0) }
    }

    #expect(winners == 1)
    let callbacks = decisions.withLock { $0 }
    #expect(callbacks.count == 1)
    #expect(try storage.store.snapshot().jobs.count == (callbacks.first == true ? 1 : 0))
}

@Test(arguments: ["disabled", "corrupt"])
func commitFailurePreservesMailAndCompletesOnlyOnce(failure: String) throws {
    let storage = try TestStore()
    defer { storage.remove() }
    if failure == "corrupt" {
        try Data("invalid state".utf8).write(to: storage.directory.appendingPathComponent("state.json"))
    }
    let decisions = Mutex<[Bool]>([])
    let gate = MessageDecisionGate(store: storage.store) { decision in decisions.withLock { $0.append(decision) } }
    let job = UnsubscribeJob(
        sender: "offers@store.example.com", kind: .oneClick,
        url: try #require(URL(string: "https://store.example.com/u")))

    #expect(gate.resolve(job))
    #expect(!gate.resolve(nil))
    #expect(decisions.withLock { $0 } == [false])
}

@Test func cancelledAssessmentCannotCommitThroughAnOpenGate() async throws {
    let storage = try TestStore()
    defer { storage.remove() }
    try storage.store.updateSettings { $0.enabled = true }
    let decisions = Mutex<[Bool]>([])
    let gate = MessageDecisionGate(store: storage.store) { decision in decisions.withLock { $0.append(decision) } }
    let job = UnsubscribeJob(
        sender: "offers@store.example.com", kind: .oneClick,
        url: try #require(URL(string: "https://store.example.com/u")))
    let suspension = AsyncGate()
    let task = Task {
        await suspension.wait()
        return gate.resolve(job)
    }
    await suspension.waitUntilWaiting()
    task.cancel()
    await suspension.open()

    #expect(await task.value)
    #expect(decisions.withLock { $0 } == [false])
    #expect(try storage.store.snapshot().jobs.isEmpty)
}

@Test func duplicateRequestsCanTrashMailWithoutRepeatingTheJob() throws {
    let storage = try TestStore()
    defer { storage.remove() }
    try storage.store.updateSettings { $0.enabled = true }
    let job = UnsubscribeJob(
        sender: "offers@store.example.com", kind: .oneClick,
        url: try #require(URL(string: "https://store.example.com/u")))
    try storage.store.enqueue(job)
    let decisions = Mutex<[Bool]>([])
    let gate = MessageDecisionGate(store: storage.store) { decision in decisions.withLock { $0.append(decision) } }

    #expect(gate.resolve(job))
    #expect(decisions.withLock { $0 } == [true])
    #expect(try storage.store.snapshot().jobs.count == 1)
}
