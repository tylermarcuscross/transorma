import Foundation
import Darwin

public struct StoreSnapshot: Codable, Sendable {
    public var version = 1
    public var settings = ProtectionSettings()
    public var jobs: [UnsubscribeJob] = []
    public var recentRequests: [String: Date] = [:]
    public var lastMailActivity: Date?
    public init() {}
}

/// Small, bounded state file shared by the app and extension. flock + atomic replacement
/// make read/modify/write and queue claims exclusive across both processes.
public final class SharedStore: @unchecked Sendable {
    private let directory: URL
    private let lock = NSLock()
    public static let groupIdentifier = "group.me.tylercross.transorma"

    public static func appGroup() throws -> SharedStore {
        guard let directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier) else {
            throw MailError.storageUnavailable
        }
        return try SharedStore(directory: directory.appendingPathComponent("Protection", isDirectory: true))
    }

    public init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }

    public func snapshot() throws -> StoreSnapshot { try transaction(write: false) { $0 } }

    public func setSettings(_ settings: ProtectionSettings) throws {
        try transaction { state in
            state.settings = settings
            for index in state.jobs.indices where state.jobs[index].status == .pending {
                if !settings.enabled || settings.allows(state.jobs[index].sender) {
                    state.jobs[index].status = .cancelled
                    state.jobs[index].url = nil
                    state.jobs[index].detail = "Cancelled by protection settings."
                }
            }
        }
    }

    public func heartbeat(now: Date = .now) throws {
        try transaction { state in state.lastMailActivity = now }
    }

    /// Persist before returning a Trash action. A full or inaccessible store keeps the message.
    @discardableResult public func enqueue(_ job: UnsubscribeJob) throws -> Bool {
        try transaction { state in
            guard state.settings.enabled, !state.settings.allows(job.sender) else { throw MailError.paused }
            prune(&state, now: job.createdAt)
            if state.recentRequests[job.id] != nil || state.jobs.contains(where: { $0.id == job.id && $0.status != .cancelled }) { return false }
            state.jobs.removeAll { $0.id == job.id }
            guard state.jobs.count < 200, state.recentRequests.count < 2000 else { throw MailError.queueFull }
            state.jobs.append(job)
            return true
        }
    }

    public func claim(now: Date = .now) throws -> UnsubscribeJob? {
        try transaction { state in
            prune(&state, now: now)
            // A killed process may have sent a POST. Never silently replay that work.
            for index in state.jobs.indices where state.jobs[index].status == .processing && now.timeIntervalSince(state.jobs[index].updatedAt) > 180 {
                state.jobs[index].status = .uncertain
                state.jobs[index].url = nil
                state.jobs[index].detail = "Processing was interrupted; the remote outcome is unknown."
            }
            guard state.settings.enabled, !state.jobs.contains(where: { $0.status == .processing }),
                  let index = state.jobs.firstIndex(where: { $0.status == .pending && $0.nextAttempt <= now && !state.settings.allows($0.sender) }) else { return nil }
            state.jobs[index].status = .processing
            state.jobs[index].attempts += 1
            state.jobs[index].updatedAt = now
            state.recentRequests[state.jobs[index].id] = now
            return state.jobs[index]
        }
    }

    public func finish(_ job: UnsubscribeJob, status: JobStatus, detail: String, retry: Bool = false, now: Date = .now) throws {
        try transaction { state in
            guard let index = state.jobs.firstIndex(where: { $0.id == job.id }), state.jobs[index].status == .processing else { return }
            state.jobs[index].updatedAt = now
            state.jobs[index].detail = detail
            if retry && job.attempts < 3 && state.settings.enabled && !state.settings.allows(job.sender) {
                state.jobs[index].status = .pending
                state.jobs[index].nextAttempt = now.addingTimeInterval(pow(2, Double(job.attempts)) * 60)
            } else {
                state.jobs[index].status = status
                state.jobs[index].url = nil // Unsubscribe tokens are retained only while work is pending.
            }
        }
    }

    public func clearHistory() throws {
        try transaction { state in
            state.jobs.removeAll { $0.status != .pending && $0.status != .processing }
        }
    }

    private func prune(_ state: inout StoreSnapshot, now: Date) {
        state.jobs.removeAll { now.timeIntervalSince($0.createdAt) > 7 * 86_400 && $0.status != .processing }
        state.recentRequests = state.recentRequests.filter { now.timeIntervalSince($0.value) <= 7 * 86_400 }
    }

    private func transaction<T>(write: Bool = true, _ body: (inout StoreSnapshot) throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        let fd = open(directory.appendingPathComponent("state.lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw MailError.storageUnavailable }
        defer { close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw MailError.storageUnavailable }
        defer { flock(fd, LOCK_UN) }
        let file = directory.appendingPathComponent("state.json")
        var state = StoreSnapshot()
        if FileManager.default.fileExists(atPath: file.path) {
            let data = try Data(contentsOf: file)
            guard data.count <= 4_000_000, let stored = try? JSONDecoder().decode(StoreSnapshot.self, from: data), stored.version == 1 else { throw MailError.corruptStore }
            state = stored
        }
        let result = try body(&state)
        if write {
            try JSONEncoder().encode(state).write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        }
        return result
    }
}
