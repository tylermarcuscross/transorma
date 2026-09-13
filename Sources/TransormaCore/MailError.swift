public enum MailError: Error, Sendable, Equatable {
    case malformedMessage, unsupportedSignature, invalidSignature, dnsFailure
    case unsafeURL, networkFailure, oversizedResponse, unsupportedPage, unavailable
    case storageUnavailable, corruptStore, queueFull, paused, staleClaim
}
