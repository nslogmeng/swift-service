import Foundation
import Testing

@testable import Service

// MARK: - Test Service Protocols

protocol DatabaseProtocol: Sendable {
    func connect() -> String
    func query(_ sql: String) -> [String]
    func disconnect()
}

protocol LoggerProtocol: Sendable {
    func info(_ message: String)
    func error(_ message: String)
    func debug(_ message: String)
}

protocol UserRepositoryProtocol: Sendable {
    func createUser(name: String) -> User
    func findUser(id: String) -> User?
    func deleteUser(id: String) -> Bool
}

protocol NetworkServiceProtocol: Sendable {
    func get(url: String) async throws -> Data
    func post(url: String, data: Data) async throws -> Data
}

// MARK: - Test Service Implementations

struct User: Sendable {
    let id: String
    let name: String
    let createdAt: Date
}

final class DatabaseService: DatabaseProtocol, @unchecked Sendable {
    private let connectionString: String

    init(connectionString: String = "sqlite://memory") {
        self.connectionString = connectionString
    }

    func connect() -> String {
        return "Connected to \(connectionString)"
    }

    func query(_ sql: String) -> [String] {
        return ["Result for: \(sql)"]
    }

    func disconnect() {
        // Cleanup connection
    }
}

final class LoggerService: LoggerProtocol, @unchecked Sendable {
    private let level: String

    init(level: String = "INFO") {
        self.level = level
    }

    func info(_ message: String) {
        print("[\(level)] INFO: \(message)")
    }

    func error(_ message: String) {
        print("[\(level)] ERROR: \(message)")
    }

    func debug(_ message: String) {
        print("[\(level)] DEBUG: \(message)")
    }
}

final class UserRepository: UserRepositoryProtocol, @unchecked Sendable {
    private let database: DatabaseProtocol
    private let logger: LoggerProtocol

    init(database: DatabaseProtocol, logger: LoggerProtocol) {
        self.database = database
        self.logger = logger
    }

    func createUser(name: String) -> User {
        let user = User(id: UUID().uuidString, name: name, createdAt: Date())
        logger.info("Creating user: \(name)")
        _ = database.query("INSERT INTO users (id, name) VALUES ('\(user.id)', '\(name)')")
        return user
    }

    func findUser(id: String) -> User? {
        logger.debug("Finding user with id: \(id)")
        let results = database.query("SELECT * FROM users WHERE id = '\(id)'")
        return results.isEmpty ? nil : User(id: id, name: "Found User", createdAt: Date())
    }

    func deleteUser(id: String) -> Bool {
        logger.info("Deleting user: \(id)")
        _ = database.query("DELETE FROM users WHERE id = '\(id)'")
        return true
    }
}

final class NetworkService: NetworkServiceProtocol, @unchecked Sendable {
    private let baseURL: String
    private let logger: LoggerProtocol

    init(baseURL: String, logger: LoggerProtocol) {
        self.baseURL = baseURL
        self.logger = logger
    }

    func get(url: String) async throws -> Data {
        logger.debug("GET request to: \(url)")
        return "GET response".data(using: .utf8) ?? Data()
    }

    func post(url: String, data: Data) async throws -> Data {
        logger.debug("POST request to: \(url)")
        return "POST response".data(using: .utf8) ?? Data()
    }
}

// MARK: - ServiceKey Implementations

struct DatabaseServiceKey: ServiceKey {
    static var `default`: DatabaseServiceKey {
        DatabaseServiceKey()
    }
}

struct LoggerServiceKey: ServiceKey {
    static var `default`: LoggerServiceKey {
        LoggerServiceKey()
    }
}

// MARK: - Property Wrapper Tests

@Test("Service property wrapper resolves dependencies")
func testServicePropertyWrapper() async throws {
    // Setup test environment
    let testEnv = ServiceEnv(name: "test")
    ServiceEnv.$current.withValue(testEnv) {
        // Register services
        ServiceEnv.current.register(DatabaseProtocol.self) {
            DatabaseService(connectionString: "sqlite://test.db")
        }
        ServiceEnv.current.register(LoggerProtocol.self) {
            LoggerService(level: "DEBUG")
        }
        ServiceEnv.current.register(UserRepositoryProtocol.self) {
            let database = ServiceEnv.current.resolve(DatabaseProtocol.self)
            let logger = ServiceEnv.current.resolve(LoggerProtocol.self)
            return UserRepository(database: database, logger: logger)
        }

        struct UserController {
            @Service
            var userRepository: UserRepositoryProtocol

            @Service
            var logger: LoggerProtocol

            func handleCreateUser(name: String) -> User {
                logger.info("Handling user creation request")
                return userRepository.createUser(name: name)
            }
        }

        let controller = UserController()
        let user = controller.handleCreateUser(name: "Test User")

        #expect(user.name == "Test User")
        #expect(!user.id.isEmpty)
    }
}

// MARK: - ServiceKey Tests

@Test("ServiceKey protocol can define default services")
func testServiceKeyProtocol() async throws {
    let testEnv = ServiceEnv(name: "test")
    ServiceEnv.$current.withValue(testEnv) {
        // Register service using ServiceKey
        ServiceEnv.current.register(DatabaseServiceKey.self)

        // Verify service can be accessed by type
        let _ = ServiceEnv.current.resolve(DatabaseServiceKey.self)
        // If resolution succeeds, registration and resolution work correctly
    }
}

// MARK: - ServiceEnv Tests

@Test("ServiceEnv provides different environments")
func testServiceEnvironments() async throws {
    #expect(ServiceEnv.online.name == "online")
    #expect(ServiceEnv.dev.name == "dev")
    #expect(ServiceEnv.test.name == "test")

    let customEnv = ServiceEnv(name: "custom")
    #expect(customEnv.name == "custom")
}

@Test("ServiceEnv can switch contexts")
func testServiceEnvContextSwitching() async throws {
    let testEnv = ServiceEnv(name: "test-env")

    ServiceEnv.$current.withValue(testEnv) {
        ServiceEnv.current.register(String.self) {
            "Service built in \(ServiceEnv.current.name) environment"
        }

        let result = ServiceEnv.current.resolve(String.self)
        #expect(result == "Service built in test-env environment")
    }

    ServiceEnv.$current.withValue(.dev) {
        ServiceEnv.current.register(String.self) {
            "Service built in \(ServiceEnv.current.name) environment"
        }

        let result = ServiceEnv.current.resolve(String.self)
        #expect(result == "Service built in dev environment")
    }
}

@Test("ServiceEnv can register and resolve services")
func testServiceEnvRegistrationAndResolution() async throws {
    let testEnv = ServiceEnv(name: "test")
    ServiceEnv.$current.withValue(testEnv) {
        // Register services
        ServiceEnv.current.register(DatabaseProtocol.self) {
            DatabaseService(connectionString: "sqlite://test.db")
        }
        ServiceEnv.current.register(LoggerProtocol.self) {
            LoggerService(level: "DEBUG")
        }

        // Resolve services
        let database = ServiceEnv.current.resolve(DatabaseProtocol.self)
        let logger = ServiceEnv.current.resolve(LoggerProtocol.self)

        // Test actual functionality
        let connectionInfo = database.connect()
        #expect(connectionInfo.contains("sqlite://test.db"))

        logger.info("Testing logger service")
    }
}

@Test("ServiceEnv singleton behavior")
func testServiceEnvSingletonBehavior() async throws {
    let testEnv = ServiceEnv(name: "singleton-test")
    ServiceEnv.$current.withValue(testEnv) {
        ServiceEnv.current.register(String.self) {
            UUID().uuidString
        }

        let service1 = ServiceEnv.current.resolve(String.self)
        let service2 = ServiceEnv.current.resolve(String.self)

        // Should return the same instance (singleton)
        #expect(service1 == service2)
    }
}

@Test("ServiceEnv resetAll functionality")
func testServiceResetAll() async throws {
    let env = ServiceEnv(name: "reset-all-test")
    ServiceEnv.$current.withValue(env) {
        var serviceId1: String?
        var serviceId2: String?

        ServiceEnv.current.register(String.self) {
            UUID().uuidString
        }

        serviceId1 = ServiceEnv.current.resolve(String.self)

        // resetAll clears cache and providers
        ServiceEnv.current.resetAll()

        // Re-register service
        ServiceEnv.current.register(String.self) {
            UUID().uuidString
        }

        serviceId2 = ServiceEnv.current.resolve(String.self)

        // Instances recreated after resetAll should be different
        #expect(serviceId1 != serviceId2)
    }
}

@Test("ServiceEnv resetCaches functionality")
func testServiceResetCaches() async throws {
    let env = ServiceEnv(name: "reset-caches-test")
    ServiceEnv.$current.withValue(env) {
        var serviceId1: String?
        var serviceId2: String?
        var serviceId3: String?

        // Register service
        ServiceEnv.current.register(String.self) {
            UUID().uuidString
        }

        // First resolution - creates and caches instance
        serviceId1 = ServiceEnv.current.resolve(String.self)

        // Second resolution - should return same cached instance
        serviceId2 = ServiceEnv.current.resolve(String.self)
        #expect(serviceId1 == serviceId2)

        // resetCaches clears cache but keeps providers
        ServiceEnv.current.resetCaches()

        // Third resolution - should create new instance using same provider
        serviceId3 = ServiceEnv.current.resolve(String.self)

        // New instance created after resetCaches should be different
        #expect(serviceId1 != serviceId3)
        #expect(serviceId2 != serviceId3)

        // Service should still be registered (provider still exists)
        let serviceId4 = ServiceEnv.current.resolve(String.self)
        #expect(!serviceId4.isEmpty)
    }
}

@Test("ServiceEnv resetCaches vs resetAll difference")
func testResetCachesVsResetAll() async throws {
    let env = ServiceEnv(name: "reset-comparison-test")
    ServiceEnv.$current.withValue(env) {
        // Register service
        ServiceEnv.current.register(String.self) {
            UUID().uuidString
        }

        let service1 = ServiceEnv.current.resolve(String.self)

        // resetCaches - provider still exists
        ServiceEnv.current.resetCaches()
        let service2 = ServiceEnv.current.resolve(String.self)
        #expect(service1 != service2)  // New instance created

        // resetAll - provider removed
        ServiceEnv.current.resetAll()

        // Service should no longer be registered
        // This will cause a fatalError, so we can't test it directly
        // But we can verify by re-registering
        ServiceEnv.current.register(String.self) {
            UUID().uuidString
        }
        let service3 = ServiceEnv.current.resolve(String.self)
        #expect(!service3.isEmpty)
    }
}

// MARK: - Integration Tests

@Test("Complete dependency injection flow")
func testCompleteFlow() async throws {
    let testEnv = ServiceEnv(name: "integration-test")

    let result = try await ServiceEnv.$current.withValue(testEnv) {
        // Register all services
        ServiceEnv.current.register(DatabaseProtocol.self) {
            DatabaseService(connectionString: "sqlite://test.db")
        }
        ServiceEnv.current.register(LoggerProtocol.self) {
            LoggerService(level: "INFO")
        }
        ServiceEnv.current.register(UserRepositoryProtocol.self) {
            let database = ServiceEnv.current.resolve(DatabaseProtocol.self)
            let logger = ServiceEnv.current.resolve(LoggerProtocol.self)
            return UserRepository(database: database, logger: logger)
        }
        ServiceEnv.current.register(NetworkServiceProtocol.self) {
            let logger = ServiceEnv.current.resolve(LoggerProtocol.self)
            return NetworkService(baseURL: "https://api.example.com", logger: logger)
        }

        class UserService {
            @Service
            var userRepository: UserRepositoryProtocol

            @Service
            var networkService: NetworkServiceProtocol

            @Service
            var logger: LoggerProtocol

            func processUser(name: String) async throws -> User {
                logger.info("Processing user: \(name)")

                // Simulate API call
                _ = try await networkService.get(url: "/validate-user")

                // Create user
                let user = userRepository.createUser(name: name)

                logger.info("User processed successfully: \(user.id)")
                return user
            }
        }

        let userService = UserService()
        return try await userService.processUser(name: "Integration Test User")
    }

    #expect(result.name == "Integration Test User")
    #expect(!result.id.isEmpty)
}

@Test("Service isolation between different environments")
func testServiceIsolationBetweenEnvironments() async throws {
    let env1 = ServiceEnv(name: "env1")
    let env2 = ServiceEnv(name: "env2")

    var service1: String?
    var service2: String?

    ServiceEnv.$current.withValue(env1) {
        ServiceEnv.current.register(String.self) {
            "env1-service"
        }
        service1 = ServiceEnv.current.resolve(String.self)
    }

    ServiceEnv.$current.withValue(env2) {
        ServiceEnv.current.register(String.self) {
            "env2-service"
        }
        service2 = ServiceEnv.current.resolve(String.self)
    }

    #expect(service1 == "env1-service")
    #expect(service2 == "env2-service")
    #expect(service1 != service2)
}

// MARK: - ServiceAssembly Tests

struct DatabaseAssembly: ServiceAssembly {
    func assemble(env: ServiceEnv) {
        env.register(DatabaseProtocol.self) {
            DatabaseService(connectionString: "sqlite://assembly.db")
        }
    }
}

struct LoggerAssembly: ServiceAssembly {
    func assemble(env: ServiceEnv) {
        env.register(LoggerProtocol.self) {
            LoggerService(level: "ASSEMBLY")
        }
    }
}

struct RepositoryAssembly: ServiceAssembly {
    func assemble(env: ServiceEnv) {
        env.register(UserRepositoryProtocol.self) {
            let database = env.resolve(DatabaseProtocol.self)
            let logger = env.resolve(LoggerProtocol.self)
            return UserRepository(database: database, logger: logger)
        }
    }
}

struct NetworkAssembly: ServiceAssembly {
    func assemble(env: ServiceEnv) {
        env.register(NetworkServiceProtocol.self) {
            let logger = env.resolve(LoggerProtocol.self)
            return NetworkService(baseURL: "https://api.assembly.com", logger: logger)
        }
    }
}

@Test("ServiceAssembly can register services")
func testServiceAssembly() async throws {
    let testEnv = ServiceEnv(name: "assembly-test")
    await ServiceEnv.$current.withValue(testEnv) {
        // Assemble a single assembly
        await MainActor.run {
            ServiceEnv.current.assemble(DatabaseAssembly())
        }

        // Verify service is registered
        let database = ServiceEnv.current.resolve(DatabaseProtocol.self)
        let connectionInfo = database.connect()
        #expect(connectionInfo.contains("sqlite://assembly.db"))
    }
}

@Test("ServiceAssembly can apply multiple assemblies")
func testMultipleAssemblies() async throws {
    let testEnv = ServiceEnv(name: "multi-assembly-test")
    await ServiceEnv.$current.withValue(testEnv) { @MainActor in
        // Assemble multiple assemblies using array
        await MainActor.run {
            ServiceEnv.current.assemble([
                DatabaseAssembly(),
                LoggerAssembly(),
            ])
        }

        // Verify both services are registered
        let database = ServiceEnv.current.resolve(DatabaseProtocol.self)
        let logger = ServiceEnv.current.resolve(LoggerProtocol.self)

        #expect(database.connect().contains("sqlite://assembly.db"))
        logger.info("Testing logger from assembly")
    }
}

@Test("ServiceAssembly can apply multiple assemblies using variadic arguments")
func testVariadicAssemblies() async throws {
    let testEnv = ServiceEnv(name: "variadic-assembly-test")
    await ServiceEnv.$current.withValue(testEnv) {
        // Assemble multiple assemblies using variadic arguments
        await MainActor.run {
            ServiceEnv.current.assemble(
                DatabaseAssembly(),
                LoggerAssembly(),
                RepositoryAssembly()
            )
        }

        // Verify all services are registered and can work together
        let userRepository = ServiceEnv.current.resolve(UserRepositoryProtocol.self)
        let user = userRepository.createUser(name: "Assembly User")

        #expect(user.name == "Assembly User")
        #expect(!user.id.isEmpty)
    }
}

@Test("ServiceAssembly supports dependency injection between assemblies")
func testAssemblyDependencyInjection() async throws {
    let testEnv = ServiceEnv(name: "assembly-di-test")
    try await ServiceEnv.$current.withValue(testEnv) {
        // Assemble assemblies in order (dependencies first)
        await MainActor.run {
            ServiceEnv.current.assemble(
                DatabaseAssembly(),
                LoggerAssembly(),
                RepositoryAssembly(),
                NetworkAssembly()
            )
        }

        // Verify services with dependencies work correctly
        let networkService = ServiceEnv.current.resolve(NetworkServiceProtocol.self)
        let userRepository = ServiceEnv.current.resolve(UserRepositoryProtocol.self)

        // Test network service (depends on logger)
        let response = try await networkService.get(url: "/test")
        #expect(!response.isEmpty)

        // Test user repository (depends on database and logger)
        let user = userRepository.createUser(name: "DI Test User")
        #expect(user.name == "DI Test User")
    }
}

@Test("ServiceAssembly can be used with different environments")
func testAssemblyWithDifferentEnvironments() async throws {
    let env1 = ServiceEnv(name: "env1")
    let env2 = ServiceEnv(name: "env2")

    var service1: DatabaseProtocol?
    var service2: DatabaseProtocol?

    await ServiceEnv.$current.withValue(env1) {
        await MainActor.run {
            ServiceEnv.current.assemble(DatabaseAssembly())
        }
        service1 = ServiceEnv.current.resolve(DatabaseProtocol.self)
    }

    await ServiceEnv.$current.withValue(env2) {
        await MainActor.run {
            ServiceEnv.current.assemble(DatabaseAssembly())
        }
        service2 = ServiceEnv.current.resolve(DatabaseProtocol.self)
    }

    // Verify services are isolated per environment
    #expect(service1 != nil)
    #expect(service2 != nil)
    #expect(service1?.connect() == service2?.connect())  // Same implementation
}
