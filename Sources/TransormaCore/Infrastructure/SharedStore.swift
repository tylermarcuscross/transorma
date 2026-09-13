import Darwin
import Foundation

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
    private static let claimLifetime: TimeInterval = 180
    private static let retentionInterval: TimeInterval = 7 * 86_400
    private static let maximumJobs = 200
    private static let maximumRecentRequests = 2000
    private static let maximumAttempts = 3
    public static let groupIdentifier = "group.me.tylercross.transorma"

    public static func appGroup() throws -> SharedStore {
        guard let directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier)
        else {
            throw MailError.storageUnavailable
        }
        return try SharedStore(directory: directory.appendingPathComponent("Protection", isDirectory: true))
    }

    public init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }

    public func snapshot() throws -> StoreSnapshot { try transaction(write: false) { $0 } }

    public func setSettings(_ settings: ProtectionSettings) throws {
        try transaction { state in
            applySettings(settings, to: &state)
        }
    }

    /// Updates the latest persisted settings while holding both the thread and process locks.
    public func updateSettings(_ change: (inout ProtectionSettings) -> Void) throws {
        try transaction { state in
            var settings = state.settings
            change(&settings)
            applySettings(settings, to: &state)
        }
    }

    public func heartbeat(now: Date = .now) throws {
        try transaction { state in state.lastMailActivity = now }
    }

    /// Persist before returning a Trash action. A full or inaccessible store keeps the message.
    @discardableResult public func enqueue(_ job: UnsubscribeJob) throws -> Bool {
        try transaction { state in
            guard state.settings.permits(job) else { throw MailError.paused }
            prune(&state, now: job.createdAt)
            if state.recentRequests[job.id] != nil
                || state.jobs.contains(where: { $0.id == job.id && $0.status != .cancelled })
            {
                return false
            }
            state.jobs.removeAll { $0.id == job.id }
            guard state.jobs.count < Self.maximumJobs, state.recentRequests.count < Self.maximumRecentRequests else {
                throw MailError.queueFull
            }
            state.jobs.append(job)
            return true
        }
    }

    public func claim(now: Date = .now) throws -> UnsubscribeJob? {
        try transaction { state in
            prune(&state, now: now)
            // A killed process may have sent a POST. Never silently replay that work.
            for index in state.jobs.indices
            where state.jobs[index].status == .processing
                && now.timeIntervalSince(state.jobs[index].updatedAt) > Self.claimLifetime
            {
                state.jobs[index].status = .uncertain
                state.jobs[index].url = nil
                state.jobs[index].detail = "Processing was interrupted; the remote outcome is unknown."
            }
            guard state.settings.enabled, !state.jobs.contains(where: { $0.status == .processing }),
                let index = state.jobs.firstIndex(where: {
                    $0.status == .pending && $0.nextAttempt <= now && state.settings.permits($0)
                })
            else { return nil }
            state.jobs[index].status = .processing
            state.jobs[index].attempts += 1
            state.jobs[index].updatedAt = now
            state.recentRequests[state.jobs[index].id] = now
            return state.jobs[index]
        }
    }

    /// A worker must still own its persisted attempt immediately before each network write.
    public func authorize(_ job: UnsubscribeJob, now: Date = .now) throws -> ProtectionSettings {
        try transaction(write: false) { state in
            guard let current = state.jobs.first(where: { $0.id == job.id }),
                current.status == .processing, current.attempts == job.attempts,
                now.timeIntervalSince(current.updatedAt) <= Self.claimLifetime
            else { throw MailError.staleClaim }
            guard state.settings.permits(current) else { throw MailError.paused }
            return state.settings
        }
    }

    public func finish(_ job: UnsubscribeJob, status: JobStatus, detail: String, retry: Bool = false, now: Date = .now)
        throws
    {
        try transaction { state in
            guard let index = state.jobs.firstIndex(where: { $0.id == job.id }),
                state.jobs[index].status == .processing, state.jobs[index].attempts == job.attempts
            else { return }
            state.jobs[index].updatedAt = now
            state.jobs[index].detail = detail
            if retry && job.attempts < Self.maximumAttempts && state.settings.permits(state.jobs[index]) {
                state.jobs[index].status = .pending
                state.jobs[index].nextAttempt = now.addingTimeInterval(pow(2, Double(job.attempts)) * 60)
            } else {
                state.jobs[index].status = status
                state.jobs[index].url = nil  // Unsubscribe tokens are retained only while work is pending.
            }
        }
    }

    public func clearHistory() throws {
        try transaction { state in
            state.jobs.removeAll { $0.status != .pending && $0.status != .processing }
        }
    }

    private func applySettings(_ settings: ProtectionSettings, to state: inout StoreSnapshot) {
        state.settings = settings
        for index in state.jobs.indices where state.jobs[index].status == .pending {
            guard !settings.permits(state.jobs[index]) else { continue }
            state.jobs[index].status = .cancelled
            state.jobs[index].url = nil
            state.jobs[index].detail = "Cancelled by protection settings."
        }
    }

    private func prune(_ state: inout StoreSnapshot, now: Date) {
        state.jobs.removeAll {
            now.timeIntervalSince($0.createdAt) > Self.retentionInterval && $0.status != .processing
        }
        state.recentRequests = state.recentRequests.filter { now.timeIntervalSince($0.value) <= Self.retentionInterval }
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
            guard data.count <= 4_000_000, let stored = try? JSONDecoder().decode(StoreSnapshot.self, from: data),
                stored.version == 1
            else { throw MailError.corruptStore }
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
