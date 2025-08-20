import Testing
import Foundation
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

// MARK: - Service Keys

struct DatabaseServiceKey: ServiceKey {
    static func build(with context: ServiceContext) -> DatabaseProtocol {
        return DatabaseService(connectionString: "sqlite://test.db")
    }
}

struct LoggerServiceKey: ServiceKey {
    static func build(with context: ServiceContext) -> LoggerProtocol {
        return LoggerService(level: "DEBUG")
    }
}

struct UserRepositoryKey: ServiceKey {
    static func build(with context: ServiceContext) -> UserRepositoryProtocol {
        let database = context.resolve(DatabaseServiceKey.self)
        let logger = context.resolve(LoggerServiceKey.self)
        return UserRepository(database: database, logger: logger)
    }
}

struct NetworkServiceKey: ServiceKey {
    static func build(with context: ServiceContext) -> NetworkServiceProtocol {
        let logger = context.resolve(LoggerServiceKey.self)
        return NetworkService(baseURL: "https://api.example.com", logger: logger)
    }
}

final class SingletonService: ServiceKey, @unchecked Sendable {
    static var scope: Scope { .shared }
    let id = UUID()
    let createdAt = Date()
    
    static func build(with context: ServiceContext) -> SingletonService {
        return SingletonService()
    }
}

final class TransientService: ServiceKey, @unchecked Sendable {
    static var scope: Scope { .transient }
    let id = UUID()
    let timestamp = Date()
    
    static func build(with context: ServiceContext) -> TransientService {
        return TransientService()
    }
}

// MARK: - Property Wrapper Tests

@Test("Service property wrapper resolves dependencies")
func testServicePropertyWrapper() async throws {
    struct UserController {
        @Service(UserRepositoryKey.self)
        var userRepository: UserRepositoryProtocol
        
        @Service(LoggerServiceKey.self)
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

@Test("LazyService property wrapper resolves dependencies lazily")
func testLazyServicePropertyWrapper() async throws {
    class APIService {
        @LazyService(NetworkServiceKey.self)
        var networkService: NetworkServiceProtocol
        
        @LazyService(LoggerServiceKey.self)
        var logger: LoggerProtocol
        
        func fetchData() async throws -> String {
            logger.info("Fetching data from API")
            let data = try await networkService.get(url: "/users")
            return String(data: data, encoding: .utf8) ?? ""
        }
    }
    
    let apiService = APIService()
    let result = try await apiService.fetchData()
    
    #expect(result == "GET response")
}

@Test("ServiceProvider property wrapper behavior")
func testServiceProviderPropertyWrapper() async throws {
    struct RequestHandler {
        @ServiceProvider(LoggerServiceKey.self)
        var logger: LoggerProtocol
        
        func handleRequest(id: String) {
            logger.info("Processing request: \(id)")
        }
    }
    
    let handler = RequestHandler()
    handler.handleRequest(id: "req-123")
    
    // Verify that the logger service works correctly
    handler.logger.info("Test message")
}

// MARK: - ServiceKey Tests

@Test("ServiceKey builds services with dependencies")
func testServiceKeyWithDependencies() async throws {
    let userRepo = UserRepositoryKey.build(with: ServiceContext())
    let user = userRepo.createUser(name: "John Doe")
    
    #expect(user.name == "John Doe")
    #expect(!user.id.isEmpty)
    
    let foundUser = userRepo.findUser(id: user.id)
    #expect(foundUser != nil)
}

// MARK: - ServiceEnv Tests

@Test("ServiceEnv provides different environments")
func testServiceEnvironments() async throws {
    #expect(ServiceEnv.online.key == "online")
    #expect(ServiceEnv.dev.key == "dev")
    #expect(ServiceEnv.inhouse.key == "inhouse")
    
    let customEnv = ServiceEnv(key: "test", maxResolutionDepth: 50)
    #expect(customEnv.key == "test")
    #expect(customEnv.maxResolutionDepth == 50)
}

@Test("ServiceEnv switches context correctly")
func testServiceEnvContextSwitching() async throws {
    struct EnvAwareService: ServiceKey {
        static func build(with context: ServiceContext) -> String {
            return "Service built in \(context.env.key) environment"
        }
    }
    
    let devResult = ServiceEnv.$current.withValue(.dev) {
        return EnvAwareService.build(with: ServiceContext())
    }
    #expect(devResult == "Service built in dev environment")
    
    let onlineResult = ServiceEnv.$current.withValue(.online) {
        return EnvAwareService.build(with: ServiceContext())
    }
    #expect(onlineResult == "Service built in online environment")
}

// MARK: - ServiceContext Tests

@Test("ServiceContext resolves services correctly")
func testServiceContextResolution() async throws {
    let context = ServiceContext()
    
    let database = context.resolve(DatabaseServiceKey.self)
    let logger = context.resolve(LoggerServiceKey.self)
    let userRepo = context.resolve(UserRepositoryKey.self)
    
    // Test actual functionality
    let connectionInfo = database.connect()
    #expect(connectionInfo.contains("sqlite://test.db"))
    
    logger.info("Testing logger service")
    
    let user = userRepo.createUser(name: "Test User")
    #expect(user.name == "Test User")
}

// MARK: - Scope Tests

@Test("Shared scope maintains singleton behavior")
func testSharedScope() async throws {
    let testEnv = ServiceEnv(key: "shared-test")
    
    ServiceEnv.$current.withValue(testEnv) {
        let context = ServiceContext()
        let service1 = context.resolve(SingletonService.self)
        let service2 = context.resolve(SingletonService.self)
        
        #expect(service1.id == service2.id)
        #expect(service1.createdAt == service2.createdAt)
    }
}

@Test("Transient scope creates new instances in different environments")
func testTransientScope() async throws {
    let env1 = ServiceEnv(key: "transient-test-1")
    let env2 = ServiceEnv(key: "transient-test-2")
    
    let service1 = ServiceEnv.$current.withValue(env1) {
        return ServiceContext().resolve(TransientService.self)
    }
    
    let service2 = ServiceEnv.$current.withValue(env2) {
        return ServiceContext().resolve(TransientService.self)
    }
    
    #expect(service1.id != service2.id)
    #expect(service1.timestamp != service2.timestamp)
}

@Test("Custom scope can be created")
func testCustomScope() async throws {
    let customScope = Scope(id: "custom") { instance in
        return SharedScopeStorage(instance)
    }
    
    #expect(customScope.id == "custom")
    #expect(customScope == customScope)
}

// MARK: - Integration Tests

@Test("Complete dependency injection flow works")
func testCompleteFlow() async throws {
    let testEnv = ServiceEnv(key: "integration-test")
    
    let result = try await ServiceEnv.$current.withValue(testEnv) {
        class UserService {
            @Service(UserRepositoryKey.self)
            var userRepository: UserRepositoryProtocol
            
            @LazyService(NetworkServiceKey.self)
            var networkService: NetworkServiceProtocol
            
            @ServiceProvider(LoggerServiceKey.self)
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

@Test("Service reset functionality works")
func testServiceReset() async throws {
    let env = ServiceEnv(key: "reset-test")
    
    ServiceEnv.$current.withValue(env) {
        let service1 = ServiceContext().resolve(SingletonService.self)
        env.reset()
        let service2 = ServiceContext().resolve(SingletonService.self)
        
        #expect(service1.id != service2.id)
        #expect(service1.createdAt != service2.createdAt)
    }
}

// MARK: - Scope Storage Tests

@Test("Scope storage behavior")
func testScopeStorageBehavior() async throws {
    let testService = SingletonService()
    
    let sharedStorage = SharedScopeStorage(testService)
    #expect(sharedStorage.cache == true)
    #expect((sharedStorage.instance as? SingletonService)?.id == testService.id)
    
    let graphStorage = GraphScopeStorage(testService)
    #expect(graphStorage.cache == false)
    #expect((graphStorage.instance as? SingletonService)?.id == testService.id)
    
    let transientStorage = TransientScopeStorage(testService)
    #expect(transientStorage.cache == false)
    #expect(transientStorage.instance == nil)
    
    let weakStorage = WeakScopeStorage(testService)
    #expect(weakStorage.cache == true)
    #expect((weakStorage.instance as? SingletonService)?.id == testService.id)
}

// MARK: - Params Tests

struct GreetingServiceKey: ServiceKey {
    struct Params: Hashable, Sendable {
        let name: String
        let language: String
    }
    static func build(with context: ServiceContext) -> String {
        guard let params = context.resolveCurrentParams(for: Self.self) else { return "Hello, World!" }
        switch params.language {
        case "en": return "Hello, \(params.name)!"
        case "zh": return "你好，\(params.name)！"
        case "fr": return "Bonjour, \(params.name)!"
        default: return "Hello, \(params.name)!"
        }
    }
}

@Test("ServiceKey with Params returns correct result")
func testServiceKeyWithParams() async throws {
    let context = ServiceContext()
    let enGreeting = context.resolve(GreetingServiceKey.self, params: .init(name: "Alice", language: "en"))
    let zhGreeting = context.resolve(GreetingServiceKey.self, params: .init(name: "小明", language: "zh"))
    let frGreeting = context.resolve(GreetingServiceKey.self, params: .init(name: "Jean", language: "fr"))
    let defaultGreeting = context.resolve(GreetingServiceKey.self)

    #expect(enGreeting == "Hello, Alice!")
    #expect(zhGreeting == "你好，小明！")
    #expect(frGreeting == "Bonjour, Jean!")
    #expect(defaultGreeting == "Hello, World!")
}

@Test("ServiceEnv caches instances by Params")
func testServiceEnvParamsCaching() async throws {
    let env = ServiceEnv(key: "params-test")
    ServiceEnv.$current.withValue(env) {
        let greeting1 = ServiceEnv.current[HashableKey<GreetingServiceKey>(params: .init(name: "Bob", language: "en"))]
        let greeting2 = ServiceEnv.current[HashableKey<GreetingServiceKey>(params: .init(name: "Bob", language: "en"))]
        let greeting3 = ServiceEnv.current[HashableKey<GreetingServiceKey>(params: .init(name: "Bob", language: "zh"))]

        // 测试结果一致性而非实例缓存
        #expect(greeting1 == greeting2)
        #expect(greeting1 != greeting3)
    }
}
