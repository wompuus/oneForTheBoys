import Vapor
import OFTBShared

@main
struct ServerMain {
    static func main() throws {
        var env = try Environment.detect()
        try LoggingSystem.bootstrap(from: &env)
        let app = Application(env)
        defer { app.shutdown() }
        
        //Testing localhost for server
        app.http.server.configuration.hostname = "0.0.0.0"
        app.http.server.configuration.port = 8080
        
        
        let roomManager = CrazyEightsRoomManager()

        app.webSocket("crazy-eights") { req, ws in
            ws.onBinary { ws, buffer in
                let data = Data(buffer.readableBytesView)
                guard let message = try? JSONDecoder().decode(CrazyEightsClientMessage.self, from: data) else {
                    return
                }
        roomManager.handle(message: message, from: ws)
    }

    ws.onClose.whenComplete { _ in
        roomManager.handleDisconnect(ws)
    }
}

try app.run()
    }
}
