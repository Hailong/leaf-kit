enum LeafToken: CustomStringConvertible, Equatable  {
    case raw(ByteBuffer)
    
    case tag(name: String)
    case tagBodyIndicator
    
    case parametersStart
    case parameterDelimiter
    case parametersEnd
    
    case variable(name: String)
    
    var description: String {
        switch self {
        case .raw(var byteBuffer):
            let string = byteBuffer.readString(length: byteBuffer.readableBytes) ?? ""
            return "raw(\(string.debugDescription))"
        case .tag(let name):
            return "tag(name: \(name.debugDescription))"
        case .tagBodyIndicator:
            return "tagBodyIndicator"
        case .parametersStart:
            return "parametersStart"
        case .parametersEnd:
            return "parametersEnd"
        case .parameterDelimiter:
            return "parameterDelimiter"
        case .variable(let name):
            return "varaible(name: \(name.debugDescription))"
        }
    }
}

struct LeafLexer {
    private var buffer: ByteBuffer
    
    init(string: String) {
        var buffer = ByteBufferAllocator().buffer(capacity: 0)
        buffer.write(string: string)
        self.init(template: buffer)
    }
    
    enum State {
        case normal
        case tag
        case parameters
    }
    
    var state: State
    
    init(template buffer: ByteBuffer) {
        self.buffer = buffer
        self.state = .normal
    }
    
    mutating func lex() throws -> [LeafToken] {
        var tokens: [LeafToken] = []
        while let next = try self.next() {
            tokens.append(next)
        }
        return tokens
    }
    
    mutating func next() throws -> LeafToken? {
        guard let next = self.peek() else {
            // empty
            return nil
        }
        
        switch state {
        case .normal:
            switch next {
            case .octothorpe:
                self.buffer.moveReaderIndex(forwardBy: 1)
                guard let length = self.countMatching(check: { $0.isAllowedInVariable }) else {
                    return nil
                }
                guard let name = self.buffer.readString(length: length) else {
                    return nil
                }
                self.state = .tag
                return .tag(name: name)
            default:
                guard let length = self.countMatching(check: { $0 != .octothorpe }) else {
                    return nil
                }
                return self.buffer.readSlice(length: length)
                    .map { .raw($0) }
            }
        case .tag:
            switch next {
            case .leftParenthesis:
                self.buffer.moveReaderIndex(forwardBy: 1)
                self.state = .parameters
                return .parametersStart
            case .colon:
                self.buffer.moveReaderIndex(forwardBy: 1)
                self.state = .normal
                return .tagBodyIndicator
            default:
                self.state = .normal
                return try self.next()
            }
        case .parameters:
            switch next {
            case .rightParenthesis:
                // tag, to check for closing body
                self.state = .tag
                self.buffer.moveReaderIndex(forwardBy: 1)
                return .parametersEnd
            case .comma:
                self.buffer.moveReaderIndex(forwardBy: 1)
                return .parameterDelimiter
            default:
                guard let length = self.countMatching(check: { $0.isAllowedInVariable }) else {
                    return nil
                }
                guard let name = self.buffer.readString(length: length) else {
                    return nil
                }
                return .variable(name: name)
            }
        }
    }
    
    // MARK: byte buffer methods
    
    mutating func pop(if byte: UInt8) -> Bool {
        if self.peek() == byte {
            self.pop()
            return true
        } else {
            return false
        }
    }
    
    func peek() -> UInt8? {
        return self.buffer.getInteger(at: self.buffer.readerIndex)
    }
    
    mutating func pop() {
        self.buffer.moveReaderIndex(forwardBy: 1)
    }
    
    func countMatching(check isMatch: (UInt8) -> (Bool)) -> Int? {
        if self.buffer.readableBytes == 0 {
            return nil
        }
        
        var copy = self.buffer
        while let curr = copy.readInteger(as: UInt8.self) {
            if !isMatch(curr) {
                return (copy.readerIndex - self.buffer.readerIndex) - 1
            }
        }
        return copy.readerIndex - self.buffer.readerIndex
    }
}
