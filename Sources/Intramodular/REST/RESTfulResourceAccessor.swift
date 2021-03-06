//
// Copyright (c) Vatsal Manot
//

import Dispatch
import Merge
import Swallow

/// An accessor for a REST resource.
@propertyWrapper
public final class RESTfulResourceAccessor<
    Value,
    Container: Repository,
    GetEndpoint: Endpoint,
    SetEndpoint: Endpoint
>: ResourceAccessor where GetEndpoint.Root == Container.Interface, SetEndpoint.Root == Container.Interface {
    public typealias Resource = RESTfulResource<Value, Container, GetEndpoint, SetEndpoint>
    public typealias Root = Container.Interface
    
    fileprivate weak var repository: Container?
    
    fileprivate let cancellables = Cancellables()
    fileprivate let base: Resource
    fileprivate var repositorySubscription: AnyCancellable?
    
    public var projectedValue: AnyRepositoryResource<Container, Value> {
        .init(base, repository: repository)
    }
    
    public var wrappedValue: Value? {
        get {
            base.latestValue
        } set {
            base.latestValue = newValue
        }
    }
    
    init(
        get: Resource.EndpointCoordinator<GetEndpoint>,
        getDependencies: [Resource.EndpointDependency] = [],
        set: Resource.EndpointCoordinator<SetEndpoint>,
        setDependencies: [Resource.EndpointDependency] = []
    ) {
        self.base = .init(
            get: get,
            dependenciesForGet: getDependencies,
            set: set,
            dependenciesForSet: setDependencies
        )
    }
    
    @inlinable
    public static subscript<EnclosingSelf: Repository>(
        _enclosingInstance object: EnclosingSelf,
        wrapped wrappedKeyPath: ReferenceWritableKeyPath<EnclosingSelf, Value?>,
        storage storageKeyPath: ReferenceWritableKeyPath<EnclosingSelf, RESTfulResourceAccessor>
    ) -> Value? where EnclosingSelf.Interface == Root {
        get {
            object[keyPath: storageKeyPath].receiveEnclosingInstance(object, storageKeyPath: storageKeyPath)
            
            return object[keyPath: storageKeyPath].wrappedValue
        } set {
            object[keyPath: storageKeyPath].receiveEnclosingInstance(object, storageKeyPath: storageKeyPath)
            
            object[keyPath: storageKeyPath].wrappedValue = newValue
        }
    }
    
    @usableFromInline
    func receiveEnclosingInstance<EnclosingSelf: Repository>(
        _ object:  EnclosingSelf,
        storageKeyPath: ReferenceWritableKeyPath<EnclosingSelf, RESTfulResourceAccessor>
    ) where EnclosingSelf.Interface == Root {
        let isFirstRun = repository == nil
        
        guard let repository = object as? Container else {
            assertionFailure()
            
            return
        }
        
        self.repository = repository
        self.base._repository = repository
        
        if isFirstRun {
            if let repositoryObjectWillChange = repository.objectWillChange as? _opaque_VoidSender {
                self.base.objectWillChange
                    .receiveOnMainQueue()
                    .publish(to: repositoryObjectWillChange)
                    .subscribe(in: cancellables)
            }
            
            self.base._lastRootID = repository.interface.id
            
            repositorySubscription = repository.objectWillChange.receive(on: DispatchQueue.main).sinkResult { [weak self, weak repository] _ in
                guard let self = self, let repository = repository else {
                    return
                }
                
                if self.base.needsGetCall {
                    self.base.fetch()
                }
                
                self.base._lastRootID = repository.interface.id
            }
        }
    }
}

// MARK: - Initializers -

extension RESTfulResourceAccessor {
    public convenience init(
        wrappedValue: Value? = nil,
        get: KeyPath<Root, GetEndpoint>,
        _ getValueKeyPath: KeyPath<GetEndpoint.Output, Value>
    ) where GetEndpoint.Input: Initiable, SetEndpoint == NeverEndpoint<Root> {
        self.init(
            get: .init(
                endpoint: get,
                input: { _ in .init() },
                output: { $0[keyPath: getValueKeyPath] }
            ),
            set: .init()
        )
    }
    
    public convenience init(
        wrappedValue: Value? = nil,
        get: KeyPath<Root, GetEndpoint>
    ) where GetEndpoint.Input: ExpressibleByNilLiteral, GetEndpoint.Output == Value, SetEndpoint == NeverEndpoint<Root> {
        self.init(
            get: .init(
                endpoint: get,
                input: { _ in .init(nilLiteral: ()) },
                output: { $0 }
            ),
            set: .init()
        )
    }
    
    public convenience init(
        wrappedValue: Value? = nil,
        get: KeyPath<Root, GetEndpoint>
    ) where GetEndpoint.Input: Initiable, GetEndpoint.Output == Value, SetEndpoint == NeverEndpoint<Root> {
        self.init(
            get: .init(
                endpoint: get,
                input: { _ in .init() },
                output: { $0 }
            ),
            set: .init()
        )
    }
    
    public convenience init(
        wrappedValue: Value? = nil,
        get: KeyPath<Root, GetEndpoint>
    ) where GetEndpoint.Input == Void, GetEndpoint.Output == Value, SetEndpoint == NeverEndpoint<Root> {
        self.init(
            get: .init(
                endpoint: get,
                input: { _ in () },
                output: { $0 }
            ),
            set: .init()
        )
    }
    
    public convenience init(
        wrappedValue: Value? = nil,
        get: KeyPath<Root, GetEndpoint>,
        from getInput: GetEndpoint.Input
    ) where GetEndpoint.Output == Value, SetEndpoint == NeverEndpoint<Root> {
        self.init(
            get: .init(
                endpoint: get,
                input: { _ in getInput },
                output: { $0 }
            ),
            set: .init()
        )
    }
    
    public convenience init(
        wrappedValue: Value? = nil,
        get: KeyPath<Root, GetEndpoint>,
        from getInput: @escaping (Container) throws -> GetEndpoint.Input
    ) where GetEndpoint.Output == Value, SetEndpoint == NeverEndpoint<Root> {
        self.init(
            get: .init(
                endpoint: get,
                input: { try getInput($0) },
                output: { $0 }
            ),
            set: .init()
        )
    }
}

// MARK: - API -

extension Repository where Interface: RESTfulInterface {
    public typealias Resource<Value, GetEndpoint: Endpoint, SetEndpoint: Endpoint> = RESTfulResourceAccessor<
        Value,
        Self,
        GetEndpoint,
        SetEndpoint
    > where GetEndpoint.Root == Interface, SetEndpoint.Root == Interface
}

// MARK: - Auxiliary Implementation -

extension RESTfulResourceAccessor {
    @usableFromInline
    final class ResourceDependency<R: ResourceAccessor>: Resource.EndpointDependency {
        let location: KeyPath<Container, R>
        
        init(location: KeyPath<Container, R>) {
            self.location = location
        }
        
        override func isAvailable(in repository: Container) -> Bool {
            repository[keyPath: location].wrappedValue != nil
        }
    }
}
