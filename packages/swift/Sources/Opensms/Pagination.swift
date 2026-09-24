import Foundation

/// Parameters of a cursor list method. ``OpensmsClient/paginate(_:_:)`` feeds
/// each page's `nextCursor` back through ``cursor``.
public protocol CursorParams {
    var cursor: String? { get set }
}

/// Plain `{ limit, cursor }` list parameters, used by most list methods.
public struct ListParams: CursorParams, Equatable {
    public var limit: Int?
    public var cursor: String?

    public init(limit: Int? = nil, cursor: String? = nil) {
        self.limit = limit
        self.cursor = cursor
    }

    var query: [(String, String?)] { [("limit", limit.q), ("cursor", cursor)] }
}

/// Auto-pagination over any cursor list method. Pull based: a page is only
/// fetched when the consumer asks for an item beyond the current buffer, so
/// breaking out of the loop never triggers another request.
func paginate<P: CursorParams, T>(
    _ list: @escaping (P) async throws -> Page<T>,
    _ params: P
) -> AsyncThrowingStream<T, Error> {
    let state = PagerState<P, T>(list: list, params: params)
    return AsyncThrowingStream(unfolding: { try await state.next() })
}

/// Iteration state for ``paginate(_:_:)``.
final class PagerState<P: CursorParams, T: Decodable> {
    private let list: (P) async throws -> Page<T>
    private var params: P
    private var buffer: [T] = []
    private var index = 0
    private var finished = false

    init(list: @escaping (P) async throws -> Page<T>, params: P) {
        self.list = list
        self.params = params
    }

    func next() async throws -> T? {
        while index >= buffer.count {
            if finished { return nil }
            let page = try await list(params)
            buffer = page.items
            index = 0
            if let cursor = page.nextCursor, !cursor.isEmpty {
                params.cursor = cursor
            } else {
                finished = true
            }
        }
        defer { index += 1 }
        return buffer[index]
    }
}
