# Circular Dependencies

Service automatically detects circular dependencies at runtime and provides clear error messages to help you identify and fix dependency cycles.

> Localization: **English**  |  **[简体中文](<doc:CircularDependencies.zh-Hans>)**

## What is a Circular Dependency?

A circular dependency occurs when services depend on each other in a cycle. For example:

- Service A depends on Service B
- Service B depends on Service C
- Service C depends on Service A

This creates a cycle: A → B → C → A

## How Service Detects Cycles

When resolving services, Service tracks the current resolution chain. If a service attempts to resolve itself (directly or indirectly), a circular dependency is detected and the program terminates with a descriptive error.

### Example of Circular Dependency

```swift
// Service A depends on B
ServiceEnv.current.register(AService.self) {
    let b = ServiceEnv.current.resolve(BService.self)  // Resolves B
    return AService(b: b)
}

// Service B depends on C
ServiceEnv.current.register(BService.self) {
    let c = ServiceEnv.current.resolve(CService.self)  // Resolves C
    return BService(c: c)
}

// Service C depends on A (creates cycle!)
ServiceEnv.current.register(CService.self) {
    let a = ServiceEnv.current.resolve(AService.self)  // Cycle detected!
    return CService(a: a)
}

// When resolving AService, the cycle is detected:
let service = ServiceEnv.current.resolve(AService.self)
// Fatal error: Circular dependency detected
```

## Error Messages

When a circular dependency is detected, you'll see a clear error message showing the full dependency chain:

```
Circular dependency detected for service 'AService'.
Dependency chain: AService -> BService -> CService -> AService
Check your service registration to break the cycle.
```

## Resolution Depth Limit

To prevent stack overflow from excessively deep dependency chains, Service enforces a maximum resolution depth of 100. If exceeded:

```
Maximum resolution depth (100) exceeded.
Current chain: ServiceA -> ServiceB -> ... -> ServiceN
This may indicate a circular dependency or overly deep dependency graph.
```

## Breaking Circular Dependencies

Here are common strategies to break circular dependencies:

### 1. Restructure Your Services

Extract shared logic into a new service that both can depend on:

```swift
// Before: A and B depend on each other
// After: Extract shared logic to C

struct SharedService {
    func sharedMethod() { /* ... */ }
}

struct AService {
    let shared: SharedService
    let b: BService
}

struct BService {
    let shared: SharedService
    let a: AService  // Still depends on A, but no cycle
}
```

### 2. Use Lazy Resolution

Defer resolution until the service is actually needed:

```swift
struct AService {
    private let bFactory: () -> BService
    
    init(bFactory: @escaping () -> BService) {
        self.bFactory = bFactory
    }
    
    func doSomething() {
        let b = bFactory()  // Resolve only when needed
        // Use b...
    }
}

// Register with factory
ServiceEnv.current.register(AService.self) {
    AService(bFactory: {
        ServiceEnv.current.resolve(BService.self)
    })
}
```

### 3. Use Property Injection

Inject dependencies after construction instead of in the factory:

```swift
struct AService {
    var bService: BService?
}

struct BService {
    var aService: AService?
}

// Register services
let a = AService()
let b = BService()

ServiceEnv.current.register(a)
ServiceEnv.current.register(b)

// Inject dependencies after registration
a.bService = b
b.aService = a
```

### 4. Introduce a Mediator

Create a mediator service that coordinates between the two services:

```swift
struct CoordinatorService {
    let a: AService
    let b: BService
    
    func coordinate() {
        // Coordinate between A and B
    }
}

// A and B no longer depend on each other
struct AService {
    // No dependency on B
}

struct BService {
    // No dependency on A
}
```

## Real-World Example

Here's a real-world scenario and how to fix it:

### Problem: UserService and AuthService Circular Dependency

```swift
// UserService needs AuthService to check permissions
struct UserService {
    let auth: AuthService
    
    func updateProfile(userId: String, profile: Profile) {
        guard auth.hasPermission(userId, .updateProfile) else { return }
        // Update profile...
    }
}

// AuthService needs UserService to get user data
struct AuthService {
    let user: UserService
    
    func hasPermission(_ userId: String, _ permission: Permission) -> Bool {
        let user = user.getUser(id: userId)  // Circular dependency!
        return user.permissions.contains(permission)
    }
}
```

### Solution: Extract Permission Service

```swift
// Extract permission logic to a separate service
struct PermissionService {
    func hasPermission(_ userId: String, _ permission: Permission) -> Bool {
        // Check permissions without needing UserService
        // ...
    }
}

// Both services depend on PermissionService instead
struct UserService {
    let permissions: PermissionService
    
    func updateProfile(userId: String, profile: Profile) {
        guard permissions.hasPermission(userId, .updateProfile) else { return }
        // Update profile...
    }
}

struct AuthService {
    let permissions: PermissionService
    
    func authenticate(credentials: Credentials) -> AuthResult {
        // Use permissions service...
    }
}
```

## Testing for Circular Dependencies

Service's automatic detection makes it easy to catch circular dependencies during development. If you suspect a circular dependency, try resolving the service:

```swift
func testNoCircularDependency() {
    // If there's a cycle, this will fail with a clear error
    let service = ServiceEnv.current.resolve(AService.self)
    XCTAssertNotNil(service)
}
```

## Best Practices

1. **Design services with clear dependencies**: Avoid bidirectional dependencies when possible.

2. **Use dependency injection**: Let Service manage dependencies rather than services creating their own.

3. **Keep services focused**: Each service should have a single, well-defined responsibility.

4. **Test early**: Service's cycle detection will catch issues at runtime, but it's better to design services to avoid cycles from the start.

## Next Steps

- Learn about <doc:ServiceAssembly> for organizing service registrations
- Explore <doc:RealWorldExamples> for more patterns
- Read <doc:UnderstandingService> for a deeper understanding of Service's resolution mechanism
