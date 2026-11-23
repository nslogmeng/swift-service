//
//  Copyright © 2025 Service Contributors. All rights reserved.
//

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Android)
import Android
#endif

/// The resolution chains that the current thread is running.
///
/// A resolution chain is one top-level `resolve` call and the resolutions that its factories start.
/// Resolution is synchronous, so a chain runs on one thread from its first step to its last.
/// The chain is bound to that thread for that time.
///
/// The chain is thread-local, not task-local, for two reasons:
/// - A task that a factory starts inherits task-local values and keeps them after the chain has ended.
///   It is not a part of the chain.
/// - A cache slot lock is held by a thread. The chains of a thread tell whether the thread holds it.
///
/// A thread usually runs one chain. A nested run loop inside a factory can run another task on the
/// same thread. A resolution in that task starts a chain of its own, which interrupts the first chain
/// until it ends.
enum ServiceContext {
    /// Identifies a registration: its storage and the service type.
    ///
    /// A chain can resolve from more than one environment, so the type alone is not enough.
    /// The key retains the storage, because the identity of a storage is its address, and a released
    /// storage could pass its address on to a new one.
    struct Key: Hashable {
        let storage: ServiceStorage
        let type: any Any.Type

        static func == (lhs: Key, rhs: Key) -> Bool {
            lhs.storage === rhs.storage && ObjectIdentifier(lhs.type) == ObjectIdentifier(rhs.type)
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(ObjectIdentifier(storage))
            hasher.combine(ObjectIdentifier(type))
        }
    }

    /// The state of one chain. Only the thread that runs the chain uses it, so it has no lock.
    final class Chain {
        /// The registrations that are being resolved, outermost first.
        private var steps: [Key] = []

        /// The graph-scoped instances of the chain. They are released when the chain ends.
        private var graphCache: [Key: AnyCacheBox] = [:]

        /// The chain that this chain interrupts on its thread. `nil` if the thread ran no chain when
        /// this chain started.
        private let interrupted: Chain?

        /// Identifies the task that runs the chain. `nil` outside a task.
        fileprivate let task: Int?

        fileprivate init(interrupting interrupted: Chain?, task: Int?) {
            self.interrupted = interrupted
            self.task = task
        }

        fileprivate var depth: Int {
            steps.count
        }

        /// The steps of the chains that this chain interrupts, followed by its own steps.
        fileprivate var stepsOnThread: [Key] {
            (interrupted?.stepsOnThread ?? []) + steps
        }

        /// Whether this chain is resolving the registration.
        fileprivate func isResolving(_ key: Key) -> Bool {
            steps.contains(key)
        }

        /// Whether this chain, or a chain that it interrupts, is resolving the registration.
        fileprivate func isResolvingOnThread(_ key: Key) -> Bool {
            isResolving(key) || (interrupted?.isResolvingOnThread(key) ?? false)
        }

        fileprivate func push(_ key: Key) {
            steps.append(key)
        }

        fileprivate func pop() {
            steps.removeLast()
        }

        /// Returns the graph-scoped instance for `key`, or creates and caches one.
        func graphInstance<Service>(for key: Key, factory: () throws -> Service) rethrows -> Service {
            if let cached = graphCache[key] as? CacheBox<Service> {
                return cached.value
            }
            let instance = try factory()
            graphCache[key] = CacheBox(instance)
            return instance
        }
    }

    /// Whether a chain of the current thread is resolving the type from `storage`.
    ///
    /// If the registration has a cache slot, the thread then holds the lock of that slot.
    static func isResolving(_ type: any Any.Type, in storage: ServiceStorage) -> Bool {
        guard let chain = currentChain else {
            return false
        }
        return chain.isResolvingOnThread(Key(storage: storage, type: type))
    }

    /// Runs `resolve` as one step of a chain of the current thread.
    ///
    /// The step belongs to the chain that the thread is running, if the same task runs the step.
    /// Otherwise the step starts a chain, and that chain ends when the step returns.
    ///
    /// - Parameters:
    ///   - type: Only the static type `Service` is used. The value can be the metatype of a subclass.
    ///   - storage: The storage that holds the registration.
    ///   - locksSlot: Whether the step holds the lock of a cache slot while `resolve` runs.
    ///   - resolve: Creates the instance. Its argument is the chain of the step.
    /// - Throws: `circularDependency` if the chain is already resolving the registration. With
    ///   `locksSlot`, also if a chain that it interrupts is: this thread then holds the lock already.
    ///   `maxDepthExceeded` if the chain has reached `ServiceEnv.maxResolutionDepth`.
    ///   A `ServiceError` from `resolve` unchanged, and any other error as `factoryFailed`.
    static func withResolutionTracking<Service>(
        _: Service.Type,
        in storage: ServiceStorage,
        locksSlot: Bool,
        resolve: (Chain) throws -> Service
    ) throws(ServiceError) -> Service {
        let key = Key(storage: storage, type: Service.self)
        let bound = currentChain
        let task = currentTask
        let chain: Chain
        if let bound, bound.task == task {
            chain = bound
        } else {
            chain = Chain(interrupting: bound, task: task)
        }

        if locksSlot ? chain.isResolvingOnThread(key) : chain.isResolving(key) {
            let names = (chain.stepsOnThread + [key]).map { String(describing: $0.type) }
            throw ServiceError.circularDependency(serviceType: String(describing: key.type), chain: names)
        }

        let maxDepth = ServiceEnv.maxResolutionDepth
        if chain.depth >= maxDepth {
            let names = chain.stepsOnThread.map { String(describing: $0.type) }
            throw ServiceError.maxDepthExceeded(depth: maxDepth, chain: names)
        }

        chain.push(key)
        if chain !== bound {
            currentChain = chain
        }
        defer {
            // A chain that ends here is unbound before it is released. Releasing it releases its
            // graph-scoped instances, and a `deinit` of those can resolve.
            if chain !== bound {
                currentChain = bound
            }
            chain.pop()
        }

        do {
            return try resolve(chain)
        } catch let error as ServiceError {
            throw error
        } catch {
            throw ServiceError.factoryFailed(serviceType: String(describing: key.type), underlyingError: error)
        }
    }

    /// Identifies the current task. `nil` outside a task.
    ///
    /// The value is the hash of the task, because an `UnsafeCurrentTask` must not leave the closure.
    private static var currentTask: Int? {
        unsafe withUnsafeCurrentTask { unsafe $0?.hashValue }
    }
}

// MARK: - Thread-Local Storage

extension ServiceContext {
    /// The innermost chain that the current thread is running. `nil` if the thread is not resolving.
    ///
    /// The thread-local storage does not retain the chain. `withResolutionTracking` keeps a chain alive
    /// from its first step to its last, and unbinds it before it releases it.
    private static var currentChain: Chain? {
        get {
            guard let pointer = unsafe threadLocalPointer else {
                return nil
            }
            return unsafe Unmanaged<Chain>.fromOpaque(pointer).takeUnretainedValue()
        }
        set {
            unsafe threadLocalPointer = newValue.map { unsafe Unmanaged.passUnretained($0).toOpaque() }
        }
    }
}

#if canImport(WASILibc)

// WebAssembly runs on one thread, so a global variable is thread-local. `Locked` relies on the same
// property. A WebAssembly target with threads is not supported.
nonisolated(unsafe) private var threadLocalPointer: UnsafeMutableRawPointer?

#elseif os(Windows)

#error("Service has no thread-local storage for Windows. The implementation for other platforms uses pthread.")

#else

private let threadLocalKey: pthread_key_t = {
    var key = pthread_key_t()
    let status = unsafe pthread_key_create(&key, nil)
    precondition(status == 0, "pthread_key_create failed with status \(status)")
    return key
}()

private var threadLocalPointer: UnsafeMutableRawPointer? {
    get {
        unsafe pthread_getspecific(threadLocalKey)
    }
    set {
        let status = unsafe pthread_setspecific(threadLocalKey, newValue)
        precondition(status == 0, "pthread_setspecific failed with status \(status)")
    }
}

#endif
