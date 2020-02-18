//  For Vapor 4
//  MultiplexServer.swift
//
//	Naive & brutish extension for a multiplexed server structure in Vapor 4-beta
//
//  Based heavily on native Vapor4 Application.Server and ServeCommand as of 2/18/20.
//
//  in use:
//
//	-- DURING CONFIGURATION --
//  config(app)
//	~~~~~~
//
//  a.commands.use(MultiplexServeCommand(), as: "multiserve")
//
//  for i in 0..<8 {
//		a.server.configuration.port = 8080+i  // Assumes prior set base configuration
//		a.servers.configs.append(a.server.configuration)
//	}
//
//	-- RUN BUILT APP --
//	vapor Run multiserve
//
// -- Result - 8 identical HTTPServer responders listening on ports 8080-8087,
//   utilizing the same configured routing tree/middleware.



import Vapor

extension Application {
	public var servers: MultiplexServers {
		get {
			if let existing = self.storage[MultiplexServerKey.self] {
				return existing
			} else {
				let servers = MultiplexServers(self)
				self.storage[MultiplexServerKey.self] = servers
				return servers
			}
		}
		set {
			self.storage[MultiplexServerKey.self] = newValue
		}
	}
	
	public struct MultiplexServers {
		var application: Application
		var servers: [MultiplexServer] = []
		var configs: [HTTPServer.Configuration] = []
	
		var running: Bool {
			servers.count > 0
		}
		
		public init(_ application: Application) {
			self.application = application
		}
		
		struct CommandKey: StorageKey {
			typealias Value = MultiplexServeCommand
		}

	   public var command: MultiplexServeCommand {
		   if let existing = self.application.storage.get(CommandKey.self) {
			   return existing
		   } else {
			   let new = MultiplexServeCommand()
			   self.application.storage.set(CommandKey.self, to: new) {
				   $0.shutdown()
			   }
			   return new
		   }
	   }
		
		public mutating func start() throws -> [MultiplexServer] {
			for config in configs  {
				let server = HTTPServer(
					application: self.application,
					responder: self.application.responder.current,
					configuration: config,
					on: self.application.eventLoopGroup
				)
				try server.start()
				self.application.logger.notice("HTTP responding at \(config.hostname) on port \(config.port)")
				servers.append(MultiplexServer(server))
			}
			return servers
        }
	}
	
	struct MultiplexServerKey: StorageKey {
		typealias Value = MultiplexServers
	}

    public struct MultiplexServer {
        let server: HTTPServer

		init(_ server: HTTPServer) {
			self.server = server
		}
		
		public func shutdown() {
            self.server.shutdown()
        }
    }
}

public final class MultiplexServeCommand: Command {
    public struct Signature: CommandSignature {
        public init() { }
    }

    /// See `Command`.
    public let signature = Signature()

    /// See `Command`.
    public var help: String {
        return "Begins MultiplexServer the app over multiple ports."
    }

    private var signalSources: [DispatchSourceSignal]
    private var didShutdown: Bool
	private var running: Application.Running?
	private var servers: [Application.MultiplexServer]?

    /// Create a new `MultiplexServeCommand`.
    public init() {
        self.signalSources = []
        self.didShutdown = false
    }

    /// See `Command`.
    public func run(using context: CommandContext, signature: Signature) throws {
		let servers = try context.application.servers.start()
		self.servers = servers
		
		// allow the server to be stopped or waited for
        let promise = context.application.eventLoopGroup.next().makePromise(of: Void.self)
        context.application.running = .start(using: promise)
        self.running = context.application.running

        // setup signal sources for shutdown
        let signalQueue = DispatchQueue(label: "codes.vapor.server.shutdown")
        func makeSignalSource(_ code: Int32) {
            let source = DispatchSource.makeSignalSource(signal: code, queue: signalQueue)
            source.setEventHandler {
                print() // clear ^C
                promise.succeed(())
            }
            source.resume()
            self.signalSources.append(source)
            signal(code, SIG_IGN)
        }
        makeSignalSource(SIGTERM)
        makeSignalSource(SIGINT)
    }

    func shutdown() {
        self.didShutdown = true
        self.running?.stop()
        if let servers = servers {
			for server in servers {
				server.shutdown()
			}
        }
        self.signalSources.forEach { $0.cancel() } // clear refs
        self.signalSources = []
    }
    
    deinit {
        assert(self.didShutdown, "MultiplexServeCommand did not shutdown before deinit")
    }
}
