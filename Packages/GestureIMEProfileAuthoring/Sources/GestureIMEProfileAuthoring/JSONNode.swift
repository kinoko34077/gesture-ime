import Foundation

public enum JSONNode: Equatable, Sendable {
    case object([String: JSONNode])
    case array([JSONNode])
    case string(String)
    case integer(Int64)
    case decimal(Double)
    case bool(Bool)
    case null

    public init(foundation value: Any) throws {
        if value is NSNull {
            self = .null
        } else if let value = value as? Bool {
            self = .bool(value)
        } else if let value = value as? String {
            self = .string(value)
        } else if let value = value as? NSNumber {
            let type = String(cString: value.objCType)
            if type == "f" || type == "d" {
                self = .decimal(value.doubleValue)
            } else {
                self = .integer(value.int64Value)
            }
        } else if let value = value as? [Any] {
            self = .array(try value.map(JSONNode.init(foundation:)))
        } else if let value = value as? [String: Any] {
            self = .object(try value.mapValues(JSONNode.init(foundation:)))
        } else {
            throw ProfileAuthoringError.invalidJSON("Unsupported JSON value: \(type(of: value))")
        }
    }

    public var foundationValue: Any {
        switch self {
        case .object(let object):
            return object.mapValues(\.foundationValue)
        case .array(let array):
            return array.map(\.foundationValue)
        case .string(let value):
            return value
        case .integer(let value):
            return NSNumber(value: value)
        case .decimal(let value):
            return NSNumber(value: value)
        case .bool(let value):
            return NSNumber(value: value)
        case .null:
            return NSNull()
        }
    }

    public var objectValue: [String: JSONNode]? {
        guard case .object(let value) = self else { return nil }
        return value
    }

    public var arrayValue: [JSONNode]? {
        guard case .array(let value) = self else { return nil }
        return value
    }

    public var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    public var intValue: Int? {
        switch self {
        case .integer(let value):
            return Int(exactly: value)
        case .decimal(let value) where value.rounded() == value:
            return Int(exactly: Int64(value))
        default:
            return nil
        }
    }

    public var doubleValue: Double? {
        switch self {
        case .integer(let value): return Double(value)
        case .decimal(let value): return value
        default: return nil
        }
    }
}

public enum ProfileAuthoringError: Error, Equatable, LocalizedError {
    case invalidJSON(String)
    case missingField(String)
    case missingReference(String)
    case invalidPath(String)
    case validationFailed(code: String?, detail: String?)
    case profileNotFound(String)
    case duplicateProfile(String)

    public var errorDescription: String? {
        switch self {
        case .invalidJSON(let detail): return "Invalid JSON: \(detail)"
        case .missingField(let field): return "Missing field: \(field)"
        case .missingReference(let reference): return "Missing reference: \(reference)"
        case .invalidPath(let detail): return "Invalid gesture path: \(detail)"
        case .validationFailed(let code, let detail):
            return [code, detail].compactMap { $0 }.joined(separator: ": ")
        case .profileNotFound(let id): return "Profile not found: \(id)"
        case .duplicateProfile(let id): return "Profile already exists: \(id)"
        }
    }
}
