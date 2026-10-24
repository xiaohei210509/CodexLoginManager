import Foundation

final class CodexDownload: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let limit: Int64
    private let feed: Bool
    private let progress: @Sendable (Double) -> Void
    private let lock = NSLock()
    private var task: URLSessionDownloadTask?
    private var continuation: CheckedContinuation<Int, Error>?
    private var saved = false
    private var failure: Error?
    private var cancelled = false
    private var lastProgress = -1.0

    init(destination: URL, limit: Int64, feed: Bool = false, progress: @escaping @Sendable (Double) -> Void = { _ in }) {
        self.destination = destination
        self.limit = limit
        self.feed = feed
        self.progress = progress
    }

    func download(_ url: URL) async throws -> Int {
        guard CodexUpdate.allowedURL(url, feed: feed) else { throw CodexUpdateFailure.invalidDownload }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 1200
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                self.continuation = continuation
                let task = session.downloadTask(with: url)
                self.task = task
                let cancelled = self.cancelled
                lock.unlock()
                task.resume()
                if cancelled { task.cancel() }
            }
        } onCancel: {
            self.lock.lock()
            self.cancelled = true
            let task = self.task
            self.lock.unlock()
            task?.cancel()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(request.url.map { CodexUpdate.allowedURL($0, feed: feed) } == true ? request : nil)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesWritten > limit || totalBytesExpectedToWrite > limit {
            lock.lock()
            failure = CodexUpdateFailure.invalidDownload
            lock.unlock()
            downloadTask.cancel()
        } else {
            let value = min(1, Double(totalBytesWritten) / Double(limit))
            if value - lastProgress >= 0.005 || value == 1 {
                lastProgress = value
                progress(value)
            }
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            guard let response = downloadTask.response as? HTTPURLResponse, let url = response.url,
                  CodexUpdate.allowedURL(url, feed: feed), [200, 204].contains(response.statusCode),
                  response.statusCode != 204 || feed else { throw CodexUpdateFailure.invalidDownload }
            let size = try location.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= limit else { throw CodexUpdateFailure.invalidDownload }
            try FileManager.default.copyItem(at: location, to: destination)
            lock.lock()
            saved = true
            lock.unlock()
        } catch {
            lock.lock()
            failure = error
            lock.unlock()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        let failure = self.failure ?? error ?? (saved ? nil : CodexUpdateFailure.invalidDownload)
        lock.unlock()
        if let failure { continuation?.resume(throwing: failure) }
        else { continuation?.resume(returning: (task.response as? HTTPURLResponse)?.statusCode ?? 0) }
    }
}
