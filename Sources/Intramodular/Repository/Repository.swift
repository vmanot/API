//
// Copyright (c) Vatsal Manot
//

import Merge
import Swallow
import Task

/// A data repository.
///
/// The combination of a program interface and a compatible request session.
@dynamicMemberLookup
public protocol Repository: ObservableObject {
    associatedtype Interface: ProgramInterface
    associatedtype Session: RequestSession where Session.Request == Interface.Request
    
    typealias Schema = Interface.Schema
    
    var interface: Interface { get }
    var session: Session { get }
}

// MARK: - Implementation -

extension Repository {
    public subscript<Endpoint: API.Endpoint>(
        dynamicMember keyPath: KeyPath<Interface, Endpoint>
    ) -> RunEndpointFunction<Endpoint> where Endpoint.Root == Interface, Endpoint.Options == Void {
        .init {
            self.run(keyPath, with: $0)
        }
    }
}

// MARK: - Extensions -

extension Repository {
    public func task<E: Endpoint>(
        for endpoint: E
    ) -> AnyParametrizedTask<
        (input: E.Input, options: E.Options),
        E.Output, Interface.Error
    > where E.Root == Interface {
        return ParametrizedPassthroughTask(body: { (task: ParametrizedPassthroughTask) in
            guard let (input, options) = task.input else {
                task.send(.error(.missingInput()))
                
                return .empty()
            }
            
            let endpoint = endpoint
            
            do {
                let request = try endpoint.buildRequest(
                    from: input,
                    context: .init(root: self.interface, options: options)
                )
                
                return self
                    .session
                    .task(with: request)
                    .successPublisher
                    .sinkResult({ [weak task] result in
                        switch result {
                            case .success(let value): do {
                                do {
                                    task?.send(.success(try endpoint.decodeOutput(from: value, context: .init(root: self.interface, input: input, request: request))))
                                } catch {
                                    task?.send(.error(.init(runtimeError: error)))
                                }
                            }
                            case .failure(let error): do {
                                task?.send(.error(.init(runtimeError: error)))
                            }
                        }
                    })
            } catch {
                task.send(.error(.init(runtimeError: error)))
                
                return AnyCancellable.empty()
            }
        })
        .eraseToAnyTask()
    }
}

extension Repository {
    public func run<E: Endpoint>(
        _ endpoint: E,
        with input: E.Input,
        options: E.Options
    ) -> AnyTask<E.Output, Interface.Error> where E.Root == Interface {
        let result = task(for: endpoint)
        
        do {
            try result.receive((input: input, options: options))
        } catch {
            return .failure(.init(runtimeError: error))
        }
        
        result.start()
        
        session.cancellables.insert(result)
        
        return result.eraseToAnyTask()
    }
    
    public func run<E: Endpoint>(
        _ endpoint: KeyPath<Interface, E>,
        with input: E.Input
    ) -> AnyTask<E.Output, Interface.Error> where E.Root == Interface, E.Options == Void {
        run(interface[keyPath: endpoint], with: input, options: ())
    }
    
    public func run<E: Endpoint>(
        _ endpoint: KeyPath<Interface.Endpoints.Type, E>,
        with input: E.Input
    ) -> AnyTask<E.Output, Interface.Error> where E.Root == Interface, E.Options == Void {
        run(Interface.Endpoints.self[keyPath: endpoint], with: input, options: ())
    }
}

// MARK: - Auxiliary Implementation -

private enum _DefaultRepositoryError: Error {
    case missingInput
    case invalidInput
    case invalidOutput
}

private extension ProgramInterfaceError {
    static func missingInput() -> Self {
        .init(runtimeError: _DefaultRepositoryError.missingInput)
    }
    
    static func invalidInput() -> Self {
        .init(runtimeError: _DefaultRepositoryError.invalidInput)
    }
    
    static func invalidOutput() -> Self {
        .init(runtimeError: _DefaultRepositoryError.invalidOutput)
    }
}

public struct RunEndpointFunction<Endpoint: API.Endpoint>  {
    let run: (Endpoint.Input) -> AnyTask<Endpoint.Output, Endpoint.Root.Error>
    
    public func callAsFunction(_ input: (Endpoint.Input)) -> AnyTask<Endpoint.Output, Endpoint.Root.Error> {
        run(input)
    }
    
    public func callAsFunction() -> AnyTask<Endpoint.Output, Endpoint.Root.Error> where Endpoint.Input: ExpressibleByNilLiteral {
        run(nil)
    }
}
