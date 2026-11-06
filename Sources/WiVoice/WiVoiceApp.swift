import SwiftUI
import ScreenCaptureKit
import Network
import AVFoundation
import CryptoKit
import Darwin
import CoreGraphics

@main
struct WiVoiceApp: App {
    var body: some Scene {
        WindowGroup { MainView().frame(minWidth: 480, minHeight: 360) }
    }
}

@MainActor
final class AudioBroadcaster: ObservableObject {
    @Published var running = false
    @Published var status = "Ready"
    @Published var address = ""
    @Published private var audioPackets = 0
    private var stream: SCStream?
    private var server: AudioWebSocketServer?
    private let output = AudioOutput()

    func start() async {
        guard !running else { return }
        do {
            status = "Requesting system audio access…"
            guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
                throw CaptureError.permissionDenied
            }
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first else { throw CaptureError.noDisplay }
            let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
            let config = SCStreamConfiguration()
            config.capturesAudio = true
            config.sampleRate = 48_000
            config.channelCount = 2
            config.excludesCurrentProcessAudio = true
            config.width = 2
            config.height = 2
            let stream = SCStream(filter: filter, configuration: config, delegate: nil)
            try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: DispatchQueue(label: "wi.voice.audio"))
            try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: DispatchQueue(label: "wi.voice.video"))
            self.stream = stream
            let server = try AudioWebSocketServer(port: 8765)
            self.server = server
            audioPackets = 0
            output.onAudio = { [weak self, weak server] data in
                server?.broadcast(data)
                Task { @MainActor in
                    guard let self else { return }
                    self.audioPackets += 1
                    if self.audioPackets == 1 { self.status = "Audio is flowing to the receiver" }
                }
            }
            try await stream.startCapture()
            let host = Self.localAddress() ?? "Mac IP"
            address = "http://\(host):8765"
            running = true
            status = "Waiting for Mac system audio…"
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard let self, self.running, self.audioPackets == 0 else { return }
                self.status = "No audio from macOS. It has no output device; install a virtual audio device or restore Hackintosh audio."
            }
        } catch {
            if error is CaptureError {
                status = "macOS blocked capture. Enable WiVoice in System Settings → Privacy & Security → Screen Recording, then quit and reopen WiVoice."
            } else {
                status = "Could not start: \(error.localizedDescription)"
            }
            server?.stop(); server = nil
        }
    }

    func stop() async {
        if let stream { try? await stream.stopCapture() }
        stream = nil; server?.stop(); server = nil
        running = false; address = ""; status = "Stopped"
    }

    private static func localAddress() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let list = ifaddr else { return nil }
        defer { freeifaddrs(list) }
        var ptr: UnsafeMutablePointer<ifaddrs>? = list
        while let item = ptr {
            if let sa = item.pointee.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET), String(cString: item.pointee.ifa_name) != "lo0" {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 { return String(cString: host) }
            }
            ptr = item.pointee.ifa_next
        }
        return nil
    }

    enum CaptureError: LocalizedError {
        case noDisplay, permissionDenied
        var errorDescription: String? {
            switch self {
            case .noDisplay: return "No display was found."
            case .permissionDenied: return "Screen & System Audio Recording access was denied."
            }
        }
    }
}

struct MainView: View {
    @StateObject private var broadcaster = AudioBroadcaster()
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform.circle.fill").font(.system(size: 56)).foregroundStyle(.tint)
            Text("WiVoice").font(.largeTitle.bold())
            Text("Send your Mac’s system audio to another device on the same Wi-Fi network.").multilineTextAlignment(.center).foregroundStyle(.secondary)
            if broadcaster.running {
                VStack(spacing: 8) {
                    Text("On your iPad or phone, open this address").foregroundStyle(.secondary)
                    Text(broadcaster.address).font(.system(.title3, design: .monospaced)).textSelection(.enabled)
                    Text("Keep this app open while listening.").font(.caption).foregroundStyle(.secondary)
                }.padding()
                Button("Stop streaming") { Task { await broadcaster.stop() } }.buttonStyle(.bordered)
            } else {
                Button("Start streaming") { Task { await broadcaster.start() } }.buttonStyle(.borderedProminent).controlSize(.large)
            }
            Text(broadcaster.status).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Text("Both devices must be on the same local network. Streaming is unencrypted.").font(.caption2).foregroundStyle(.tertiary).multilineTextAlignment(.center)
        }.padding(28)
    }
}

private final class AudioOutput: NSObject, SCStreamOutput {
    var onAudio: ((Data) -> Void)?
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, CMSampleBufferIsValid(sampleBuffer) else { return }
        // ScreenCaptureKit supplies audio as an AudioBufferList. Its channel data
        // isn't guaranteed to be one interleaved byte block, so normalize it here.
        try? sampleBuffer.withAudioBufferList { audioBufferList, _ in
            guard let description = sampleBuffer.formatDescription?.audioStreamBasicDescription,
                  let format = AVAudioFormat(standardFormatWithSampleRate: description.mSampleRate,
                                             channels: description.mChannelsPerFrame),
                  let pcm = AVAudioPCMBuffer(pcmFormat: format,
                                             bufferListNoCopy: audioBufferList.unsafePointer),
                  let channels = pcm.floatChannelData else { return }

            let frameCount = Int(pcm.frameLength)
            guard frameCount > 0 else { return }
            let channelCount = Int(pcm.format.channelCount)
            var interleaved = [Float](repeating: 0, count: frameCount * 2)
            for frame in 0..<frameCount {
                let left = channels[0][frame]
                let right = channelCount > 1 ? channels[1][frame] : left
                interleaved[frame * 2] = left
                interleaved[frame * 2 + 1] = right
            }
            let data = interleaved.withUnsafeBytes { Data($0) }
            onAudio?(data)
        }
    }
}

private final class AudioWebSocketServer {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "wi.voice.server")
    private var clients: [NWConnection] = []
    init(port: UInt16) throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        listener.start(queue: queue)
    }
    func broadcast(_ data: Data) {
        queue.async { [weak self] in
            guard let self else { return }
            let frame = Self.frame(data)
            for client in self.clients { client.send(content: frame, completion: .contentProcessed { _ in }) }
        }
    }
    func stop() { listener.cancel(); queue.async { self.clients.forEach { $0.cancel() }; self.clients.removeAll() } }
    private func accept(_ connection: NWConnection) {
        clients.append(connection)
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            if case .failed = state, let connection { self?.clients.removeAll { $0 === connection } }
            if case .cancelled = state, let connection { self?.clients.removeAll { $0 === connection } }
        }
        connection.start(queue: queue)
        readHandshake(connection, buffer: Data())
    }
    private func readHandshake(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, _, error in
            guard let self, error == nil, let data else { connection.cancel(); return }
            var request = buffer; request.append(data)
            guard request.count < 16_384 else { connection.cancel(); return }
            guard let text = String(data: request, encoding: .utf8), text.contains("\r\n\r\n") else { self.readHandshake(connection, buffer: request); return }
            guard text.lowercased().contains("upgrade: websocket") else {
                let body = Bundle.module.url(forResource: "receiver", withExtension: "html").flatMap { try? Data(contentsOf: $0) } ?? Data("WiVoice receiver missing".utf8)
                var response = Data("HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n".utf8)
                response.append(body)
                connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
                return
            }
            guard let keyLine = text.components(separatedBy: "\r\n").first(where: { $0.lowercased().hasPrefix("sec-websocket-key:") }),
                  let key = keyLine.split(separator: ":", maxSplits: 1).last?.trimmingCharacters(in: .whitespaces) else { connection.cancel(); return }
            let digest = Insecure.SHA1.hash(data: Data((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").utf8))
            let accept = Data(digest).base64EncodedString()
            let response = "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: \(accept)\r\n\r\n"
            connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in })
            self.readClient(connection)
        }
    }
    private func readClient(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 2, maximumLength: 2048) { [weak self] _, _, complete, error in
            if error != nil || complete { connection.cancel(); return }
            self?.readClient(connection)
        }
    }
    private static func frame(_ data: Data) -> Data {
        var out = Data([0x82]); let n = data.count
        if n < 126 { out.append(UInt8(n)) }
        else if n <= 65535 { out.append(126); out.append(UInt8((n >> 8) & 255)); out.append(UInt8(n & 255)) }
        else { out.append(127); for shift in stride(from: 56, through: 0, by: -8) { out.append(UInt8((UInt64(n) >> UInt64(shift)) & 255)) } }
        out.append(data); return out
    }
}
