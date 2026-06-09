import Foundation

/// Generic GET-with-retry helper. Ported from `lib/services/_http.dart`
/// `fetchWithRetry`: one retry (default) on a transient transport failure
/// (timeout / network error), with a fixed `retryDelay` between attempts, then
/// rethrows. Custom `headers` + per-request `timeout` are applied to every
/// attempt. Used only by `OpenFoodFactsService`.
///
/// Mirrors the Dart loop `for attempt in 0...retryCount`: do the GET; on a
/// transient error rethrow only on the last attempt, else wait `retryDelay`
/// and retry. A non-2xx HTTP status is NOT a transient failure here — it is
/// returned to the caller (parity with the Dart, which returns the response and
/// lets the service branch on `statusCode`).
func fetchWithRetry(
    _ url: URL,
    session: URLSession = .shared,
    timeout: TimeInterval = 8,
    retryDelay: TimeInterval = 0.5,
    retryCount: Int = 1,
    headers: [String: String] = [:]
) async throws -> (Data, HTTPURLResponse) {
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.timeoutInterval = timeout
    for (field, value) in headers {
        request.setValue(value, forHTTPHeaderField: field)
    }

    var attempt = 0
    while true {
        do {
            let (data, response) = try await session.data(for: request)
            let http = response as? HTTPURLResponse
                ?? HTTPURLResponse(url: url, statusCode: 0, httpVersion: nil, headerFields: nil)!
            return (data, http)
        } catch is CancellationError {
            // Cancellation is never retried — propagate immediately.
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            // Transient transport failure (timeout / connection): retry until the
            // budget is exhausted, then rethrow (mirrors the Dart rethrow-on-last).
            if attempt >= retryCount { throw error }
            attempt += 1
            try await Task.sleep(for: .seconds(retryDelay))
        }
    }
}
