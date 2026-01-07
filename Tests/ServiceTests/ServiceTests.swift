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
            let database = ServiceEnv.current[DatabaseProtocol.self]
            let logger = ServiceEnv.current[LoggerProtocol.self]
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
        let _ = ServiceEnv.current[DatabaseServiceKey.self]
        // If resolution succeeds, registration and resolution work correctly
    }
}

// MARK: - ServiceEnv Tests

@Test("ServiceEnv provides different environments")
func testServiceEnvironments() async throws {
    #expect(ServiceEnv.online.name == "online")
    #expect(ServiceEnv.dev.name == "dev")
    #expect(ServiceEnv.inhouse.name == "inhouse")
    
    let customEnv = ServiceEnv(name: "test")
    #expect(customEnv.name == "test")
}

@Test("ServiceEnv can switch contexts")
func testServiceEnvContextSwitching() async throws {
    let testEnv = ServiceEnv(name: "test-env")
    
    ServiceEnv.$current.withValue(testEnv) {
        ServiceEnv.current.register(String.self) {
            "Service built in \(ServiceEnv.current.name) environment"
        }
        
        let result = ServiceEnv.current[String.self]
        #expect(result == "Service built in test-env environment")
    }
    
    ServiceEnv.$current.withValue(.dev) {
        ServiceEnv.current.register(String.self) {
            "Service built in \(ServiceEnv.current.name) environment"
        }
        
        let result = ServiceEnv.current[String.self]
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
        let database = ServiceEnv.current[DatabaseProtocol.self]
        let logger = ServiceEnv.current[LoggerProtocol.self]
        
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
        
        let service1 = ServiceEnv.current[String.self]
        let service2 = ServiceEnv.current[String.self]
        
        // Should return the same instance (singleton)
        #expect(service1 == service2)
    }
}

@Test("ServiceEnv reset functionality")
func testServiceReset() async throws {
    let env = ServiceEnv(name: "reset-test")
    ServiceEnv.$current.withValue(env) {
        var serviceId1: String?
        var serviceId2: String?
        
        ServiceEnv.current.register(String.self) {
            UUID().uuidString
        }
        
        serviceId1 = ServiceEnv.current[String.self]
        
        // reset clears cache and providers
        ServiceEnv.current.reset()
        
        // Re-register service
        ServiceEnv.current.register(String.self) {
            UUID().uuidString
        }
        
        serviceId2 = ServiceEnv.current[String.self]
        
        // Instances recreated after reset should be different
        #expect(serviceId1 != serviceId2)
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
            let database = ServiceEnv.current[DatabaseProtocol.self]
            let logger = ServiceEnv.current[LoggerProtocol.self]
            return UserRepository(database: database, logger: logger)
        }
        ServiceEnv.current.register(NetworkServiceProtocol.self) {
            let logger = ServiceEnv.current[LoggerProtocol.self]
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
        service1 = ServiceEnv.current[String.self]
    }
    
    ServiceEnv.$current.withValue(env2) {
        ServiceEnv.current.register(String.self) {
            "env2-service"
        }
        service2 = ServiceEnv.current[String.self]
    }
    
    #expect(service1 == "env1-service")
    #expect(service2 == "env2-service")
    #expect(service1 != service2)
}

