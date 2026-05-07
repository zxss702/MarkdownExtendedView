import Foundation
import Synchronization

final class RWLock: @unchecked Sendable {
    private let mutex = Mutex<Void>(())

    func read<T>(_ block: () -> T) -> T {
        mutex.withLock { _ in block() }
    }

    func readWrite<T>(_ block: () -> T) -> T {
        mutex.withLock { _ in block() }
    }
}

@propertyWrapper
struct RWLocked<T> {
    init(wrappedValue: T) {
        value = wrappedValue
    }

    var wrappedValue: T {
        get {
            lock.read {
                value
            }
        }
        set {
            lock.readWrite {
                value = newValue
            }
        }
    }

    @discardableResult
    mutating func readWrite(_ block: (inout T) -> Void) -> (oldValue: T, newValue: T) {
        lock.readWrite {
            let old = value
            block(&value)
            return (old, value)
        }
    }

    private var value: T
    private let lock = RWLock()
}

