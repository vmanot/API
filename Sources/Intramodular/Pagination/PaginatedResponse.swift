//
// Copyright (c) Vatsal Manot
//

import Compute
import Swallow
import Swift

public protocol PaginatedResponse {
    associatedtype PaginatedListRepresentation: PaginatedListType
    
    func convert() throws -> Partial<PaginatedListRepresentation>
}
