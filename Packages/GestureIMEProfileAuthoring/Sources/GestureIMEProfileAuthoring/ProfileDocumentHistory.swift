import Foundation

public struct ProfileDocumentHistory: Sendable {
    public private(set) var document: ProfileDocument
    public let capacity: Int

    private var undoStack: [ProfileDocument]
    private var redoStack: [ProfileDocument]

    public init(
        document: ProfileDocument,
        capacity: Int = 100
    ) {
        self.document = document
        self.capacity = max(1, capacity)
        self.undoStack = []
        self.redoStack = []
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    public mutating func mutate(
        _ mutation: (inout ProfileDocument) throws -> Void
    ) throws {
        var next = document
        try mutation(&next)
        guard next != document else { return }

        Self.push(&undoStack, document, capacity: capacity)
        document = next
        redoStack.removeAll(keepingCapacity: true)
    }

    @discardableResult
    public mutating func undo() -> Bool {
        guard let previous = undoStack.popLast() else { return false }
        Self.push(&redoStack, document, capacity: capacity)
        document = previous
        return true
    }

    @discardableResult
    public mutating func redo() -> Bool {
        guard let next = redoStack.popLast() else { return false }
        push(&undoStack, document)
        document = next
        return true
    }

    public mutating func reset(to document: ProfileDocument) {
        self.document = document
        undoStack.removeAll(keepingCapacity: false)
        redoStack.removeAll(keepingCapacity: false)
    }

    private static func push(
        _ stack: inout [ProfileDocument],
        _ value: ProfileDocument,
        capacity: Int
    ) {
        stack.append(value)
        if stack.count > capacity {
            stack.removeFirst(stack.count - capacity)
        }
    }
}
