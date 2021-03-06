//
// Copyright (c) Vatsal Manot
//

import FoundationX
import Merge
import Swallow

public final class AnyRepository<Interface: ProgramInterface, Session: RequestSession>: Repository where Interface.Request == Session.Request {
    public typealias Cache = NoCache<Session.Request, Session.Request.Response>
    
    private let getInterface: () -> Interface
    private let getSession: () -> Session
    
    public let objectWillChange: AnyObjectWillChangePublisher
    
    public var interface: Interface {
        getInterface()
    }
    
    public var session: Session {
        getSession()
    }
    
    public init<Repository: API.Repository>(
        _ repository: Repository
    ) where Repository.Interface == Interface, Repository.Session == Session {
        self.objectWillChange = .init(from: repository)
        self.getInterface = { repository.interface }
        self.getSession = { repository.session }
    }
}
