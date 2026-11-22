//
//  AudioRouteMonitorImpl.swift
//  finpro
//

import AVFoundation

nonisolated final class AudioRouteMonitorImpl: AudioRouteMonitor, @unchecked Sendable {
    private nonisolated final class Observer: @unchecked Sendable {
        let token: NSObjectProtocol
        init(_ token: NSObjectProtocol) { self.token = token }
        func cancel() { NotificationCenter.default.removeObserver(token) }
    }

    private let queue = DispatchQueue(label: "audio.route-monitor", qos: .utility)
    private let lock = NSLock()
    private var cachedRoute: AudioOutputRoute = .speaker
    private var routeSubscribers: [UUID: AsyncStream<AudioOutputRoute>.Continuation] = [:]
    private var routeObserver: NSObjectProtocol?

    init() {
        routeObserver = NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: nil) { [weak self] _ in
            self?.refreshRoute()
        }
        refreshRoute()
    }

    deinit {
        if let routeObserver { NotificationCenter.default.removeObserver(routeObserver) }
    }

    var currentRoute: AudioOutputRoute {
        lock.withLock { cachedRoute }
    }
    var isEarphoneConnected: Bool { currentRoute == .wired || currentRoute == .bluetooth }

    func routeChanges() -> AsyncStream<AudioOutputRoute> {
        let id = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let current = lock.withLock { () -> AudioOutputRoute in
                routeSubscribers[id] = continuation
                return cachedRoute
            }
            continuation.yield(current)
            refreshRoute()
            continuation.onTermination = { [weak self] _ in
                self?.lock.withLock { _ = self?.routeSubscribers.removeValue(forKey: id) }
            }
        }
    }

    func interruptions() -> AsyncStream<Void> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let observer = Observer(NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: nil) { notification in
                let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                if type == AVAudioSession.InterruptionType.began.rawValue { continuation.yield(()) }
            })
            continuation.onTermination = { _ in observer.cancel() }
        }
    }

    private func refreshRoute() {
        queue.async { [weak self] in
            guard let self else { return }
            let route = Self.readSystemRoute()
            let targets = self.lock.withLock { () -> [AsyncStream<AudioOutputRoute>.Continuation] in
                guard route != self.cachedRoute else { return [] }
                self.cachedRoute = route
                return Array(self.routeSubscribers.values)
            }
            targets.forEach { $0.yield(route) }
        }
    }

    private static func readSystemRoute() -> AudioOutputRoute {
        let ports = AVAudioSession.sharedInstance().currentRoute.outputs.map(\.portType)
        if ports.contains(.builtInSpeaker) || ports.contains(.builtInReceiver) { return .speaker }
        if ports.contains(.bluetoothA2DP) || ports.contains(.bluetoothHFP) || ports.contains(.bluetoothLE) { return .bluetooth }
        if ports.contains(.headphones) || ports.contains(.usbAudio) { return .wired }
        return .other
    }
}
