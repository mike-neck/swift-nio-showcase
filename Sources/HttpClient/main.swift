import NIO
import NIOHTTP1
import NIOOpenSSL
import NIOConcurrencyHelpers


class HttpHandler: ChannelInboundHandler {

    typealias InboundIn = HTTPClientResponsePart

    let promise: EventLoopPromise<Void>
    var closed: Bool

    init(_ promise: EventLoopPromise<Void>) {
        self.promise = promise
        closed = false
    }

    func channelRead(ctx: ChannelHandlerContext, data: NIOAny) {
        let httpClientResponsePart = unwrapInboundIn(data)
        switch httpClientResponsePart {
        case .head(let header):
            print("\(header.version.description) \(header.status.code) \(header.status.reasonPhrase)")
            for (name, value) in header.headers {
                print("\(name): \(value)")
            }
        case .body(let byteBuffer):
            var buffer = byteBuffer
            if let body = buffer.readString(length: byteBuffer.readableBytes) {
                print(body)
            }
        case .end(_):
            closeIfNotClosed(ctx: ctx) {
                $0.succeed(result: ())
            }
        }
    }

    private func closeIfNotClosed(ctx: ChannelHandlerContext, _ withPromise: (EventLoopPromise<Void>) -> ()) {
        let c = UnsafeMutableRawPointer(&closed)
        let ptr: OpaquePointer = OpaquePointer(c)
        if !Bool.atomic_load(ptr) {
            withPromise(promise)
            ctx.channel.close(promise: nil)
            _ = Bool.atomic_compare_and_exchange(ptr, false, true)
        }
    }

    func channelInactive(ctx: ChannelHandlerContext) {
        closeIfNotClosed(ctx: ctx) {
            $0.fail(error: ChannelError.alreadyClosed)
        }
    }

    func errorCaught(ctx: ChannelHandlerContext, error: Error) {
        print("Error: \(error)")
        closeIfNotClosed(ctx: ctx) {
            $0.fail(error: error)
        }
    }
}

struct HttpUrl {
    private let scehme: Scheme
    let host: String
    let port: Int?
    let path: String?
    let query: String?

    static func http(host: String, port: Int? = nil, path: String? = nil, query: String? = nil) -> HttpUrl {
        return HttpUrl(scehme: .http, host: host, port: port, path: path, query: query)
    }

    static func https(host: String, port: Int? = nil, path: String? = nil, query: String? = nil) -> HttpUrl {
        return HttpUrl(scehme: .https, host: host, port: port, path: path, query: query)
    }

    var headerHost: String {
        get {
            if let p = port {
                return "\(host):\(p)"
            } else {
                return host
            }
        }
    }

    var portNumber: Int {
        get {
            if let p = port {
                return p
            } else {
                return scehme.port
            }
        }
    }

    private var portPart: String {
        get {
            if let p = port {
                return ":\(p)"
            } else {
                return ""
            }
        }
    }

    private var pathPart: String {
        get {
            if let p = path {
                return "/\(p)"
            } else {
                return ""
            }
        }
    }

    private var queryPart: String {
        get {
            if let q = query {
                return "?\(q)"
            } else {
                return ""
            }
        }
    }

    var uri: String {
        get {
            return "\(scehme)://\(host)\(portPart)\(pathPart)\(queryPart)"
        }
    }

    private enum Scheme {
        case http
        case https

        var port: Int {
            get {
                switch self {
                case .http: return 80
                case .https: return 443
                }
            }
        }
    }
}


let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
let promise: EventLoopPromise<Void> = eventLoopGroup.next().newPromise()

let url = HttpUrl.https(host: "api.github.com", port: nil, path: "search/repositories", query: "q=netty&sort=stars&order=desc&per_page=5")

print("request to", url.uri)

let tlsConfiguration = TLSConfiguration.forClient()
let sslContext = try! SSLContext(configuration: tlsConfiguration)

let bootstrap = ClientBootstrap(group: eventLoopGroup)
        .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
        .channelOption(ChannelOptions.socket(IPPROTO_TCP, TCP_NODELAY), value: 1)
        .channelInitializer { channel in
            let openSslHandler = try! OpenSSLClientHandler(context: sslContext, serverHostname: url.host)
            return channel.pipeline.add(handler: openSslHandler).then {
                channel.pipeline.addHTTPClientHandlers()
            }.then {
                channel.pipeline.add(handler: HttpHandler(promise))
            }
        }

bootstrap.connect(host: url.host, port: url.portNumber).then { (channel: Channel) -> EventLoopFuture<Void> in
    var request = HTTPRequestHead(version: HTTPVersion(major: 1, minor: 1), method: HTTPMethod.GET, uri: url.uri)
    request.headers = HTTPHeaders([
        ("Host", url.host),
        ("User-Agent", "swift-nio"),
        ("Accept-Encoding", "identity"),
        ("Accept", "application/json"),
//        ("Connection", "close"),
    ])
    channel.write(HTTPClientRequestPart.head(request), promise: nil)
    return channel.writeAndFlush(HTTPClientRequestPart.end(nil))
}.cascadeFailure(promise: promise)

defer {
    try! eventLoopGroup.syncShutdownGracefully()
}
defer {
    try! promise.futureResult.wait()
}
