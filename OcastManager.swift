// Copyright (c) 2018, nangu.TV, a.s. All rights reserved.
// nangu.TV, a.s PROPRIETARY/CONFIDENTIAL. Use is subject to license terms.

import InnopiaDriver
import OCast
import OCastPrivate
import React

@objc(OCastManager)
class OCastManager: RCTEventEmitter, DeviceCenterDelegate {
    public let AP_LIST_OBTAINED = "OCast:AP_LIST_OBTAINED"
    public let DEVICE_AVAILABLE = "OCast:DEVICE_AVAILABLE"
    public let DEVICE_CONNECTED = "OCast:DEVICE_CONNECTED"
    public let DEVICE_DISCONNECTED = "OCast:DEVICE_DISCONNECTED"
    public let DEVICE_LOST = "OCast:DEVICE_LOST"
    public let DEVICE_PAIRED = "OCast:DEVICE_PAIRED"
    public let ERROR_EVENT = "OCast:ERROR_EVENT"
    public let METADATA_CHANGED = "OCast:METADATA_CHANGED"
    public let PIN_NEEDED = "OCast:PIN_NEEDED"
    public let PLAYBACK_STATUS_CHANGED = "OCast:PLAYBACK_STATUS_CHANGED"

    private let CAST_FAILED = "CAST_FAILED"
    private let CONNECT_FAILED = "CONNECT_FAILED"
    fileprivate let DEVICE_ERROR = "DEVICE_ERROR"
    private let DISCONNECT_FAILED = "DISCONNECT_FAILED"
    private let METADATA_UPDATE_FAILED = "METADATA_UPDATE_FAILED"
    private let MUTE_FAILED = "MUTE_FAILED"
    private let PAIRING_ERROR = "PAIRING_ERROR"
    private let PAUSE_FAILED = "PAUSE_FAILED"
    private let PLAYBACK_STATUS_UPDATE_FAILED = "PLAYBACK_STATUS_UPDATE_FAILED"
    private let RESUME_FAILED = "RESUME_FAILED"
    private let SEEK_FAILED = "SEEK_FAILED"
    private let SETTING_TRACK_FAILED = "SETTING_TRACK_FAILED"
    private let SSL_ERROR = "SSL_ERROR"
    private let STOP_FAILED = "STOP_FAILED"
    private let VOLUME_FAILED = "VOLUME_FAILED"

    fileprivate var device: Device?
    fileprivate var devices = [Device]()
    let deviceCenter = DeviceCenter()

    fileprivate var lastState: MediaPlaybackState?

    fileprivate var applicationName: String = ""

    override init() {
        super.init()
        deviceCenter.delegate = self
        deviceCenter.discoveryInterval = 5
        // Register Vendor and init DeviceDiscovery
        deviceCenter.registerDevice(InnopiaDevice.self, forManufacturer: "Innopia")
    }

    @objc override static func requiresMainQueueSetup() -> Bool {
        return false
    }

    @objc
    override func constantsToExport() -> [AnyHashable: Any]! {
        return [
            "AP_LIST_OBTAINED": AP_LIST_OBTAINED,
            "DEVICE_AVAILABLE": DEVICE_AVAILABLE,
            "DEVICE_CONNECTED": DEVICE_CONNECTED,
            "DEVICE_DISCONNECTED": DEVICE_DISCONNECTED,
            "DEVICE_LOST": DEVICE_LOST,
            "DEVICE_PAIRED": DEVICE_PAIRED,
            "ERROR_EVENT": ERROR_EVENT,
            "MEDIA_TYPE_AUDIO": MediaType.audio.rawValue,
            "MEDIA_TYPE_IMAGE": MediaType.image.rawValue,
            "MEDIA_TYPE_VIDEO": MediaType.video.rawValue,
            "METADATA_CHANGED": METADATA_CHANGED,
            "PIN_NEEDED": PIN_NEEDED,
            "PLAYBACK_STATE_KEY_BUFFERING": MediaPlaybackState.buffering.rawValue,
            "PLAYBACK_STATE_KEY_FAILED": MediaPlaybackState.unknown.rawValue,
            "PLAYBACK_STATE_KEY_IDLE": MediaPlaybackState.idle.rawValue,
            "PLAYBACK_STATE_KEY_PAUSED": MediaPlaybackState.paused.rawValue,
            "PLAYBACK_STATE_KEY_PLAYING": MediaPlaybackState.playing.rawValue,
            "PLAYBACK_STATUS_CHANGED": PLAYBACK_STATUS_CHANGED,
            "TRANSFER_MODE_BUFFERED": MediaTransferMode.buffered.rawValue,
            "TRANSFER_MODE_STREAMED": MediaTransferMode.streamed.rawValue,
        ]
    }

    @objc
    override func supportedEvents() -> [String]! {
        return [
            AP_LIST_OBTAINED,
            DEVICE_AVAILABLE,
            DEVICE_CONNECTED,
            DEVICE_DISCONNECTED,
            DEVICE_LOST,
            DEVICE_PAIRED,
            ERROR_EVENT,
            METADATA_CHANGED,
            PIN_NEEDED,
            PLAYBACK_STATUS_CHANGED,
        ]
    }

    @objc
    func requiresMainQueueSetup() -> Bool {
        return true
    }

    private func transformDeviceForJS(device: Device?) -> [String: String?] {
        return ["id": device?.upnpID, "name": device?.friendlyName, "ipAddress": device?.host]
    }

    func center(_: DeviceCenter, didAdd devices: [Device]) {
        if devices.count > 0 {
            for device in devices {
                let deviceTransformed = transformDeviceForJS(device: device)
                print("Ocast:didAdd device \(deviceTransformed.description)")
                sendEvent(withName: DEVICE_AVAILABLE, body: deviceTransformed)
            }
        } else {
            print("Ocast:didAdd no devices to be added")
        }

        self.devices.append(contentsOf: devices)
    }

    func center(_ center: DeviceCenter, didRemove devices: [Device]) {
        if devices.count > 0 {
            for removedDevice in devices {
                let deviceTransformed = transformDeviceForJS(device: removedDevice)
                print("Ocast:didRemove device \(deviceTransformed.description)")
                dump(removedDevice) // print device key value pairs
                sendEvent(withName: DEVICE_LOST, body: deviceTransformed)
            }
        } else {
            print("Ocast:didRemove no devices to be removed")
        }

        self.devices = center.devices
    }

    func centerDidStop(_: DeviceCenter, withError error: Error?) {
        if let error = error {
            print("OCast:centerDidStop: device discovery stopped with error: \(error.localizedDescription)")
        } else {
            print("OCast:centerDidStop: without error")
        }
    }

    @objc func applicationDidEnterBackground() {
        print("OCast:applicationDidEnterBackground and pauseDiscovery")
        deviceCenter.discoveryInterval = 30
        deviceCenter.pauseDiscovery()
    }

    @objc func applicationWillEnterForeground() {
        print("OCast:applicationWillEnterForeground and startScan")
        deviceCenter.discoveryInterval = 5
        startScan()
    }

    @objc(startScan)
    func startScan() {
        for device in devices {
            print("Ocast:startScan devices: \(device.friendlyName)")
        }
        if !deviceCenter.discoveryIsRunning {
            print("OCast:startScan")
            deviceCenter.resumeDiscovery()
        } else {
            print("OCast:startScan discoveryIsRunning already")
        }
    }

    @objc(stopScan)
    func stopScan() {
        for device in devices {
            print("Ocast:stopScan devices: \(device.friendlyName)")
        }
        if deviceCenter.discoveryIsRunning {
            print("OCast:stopScan")
            deviceCenter.pauseDiscovery() // had to pause, stop removed the device
        }
    }

    @objc(pairDevice:)
    func pairDevice(deviceId: String) {
        print("Ocast:device tryin to pair")
        if let device = devices.first(where: { $0.upnpID == deviceId }) {
            print("Ocast:device to be paired \(transformDeviceForJS(device: device).description)")
            self.device = device
            initDevice(useOldCert: false, successCallback: sendPinNeeded)
        } else {
            print("Ocast:Device with deviceId \(deviceId) not found")
            emitErrorEvent(error: PAIRING_ERROR)
            return
        }
    }

    @objc(connectToDevice:withApplicationName:)
    func connectToDevice(deviceId: String, withApplicationName applicationName: String) {
        print("Ocast:trying to connect to device with deviceId \(deviceId) and applicationName \(applicationName)")
        if let device = devices.first(where: { $0.upnpID == deviceId }) {
            dump(device)
            print("Ocast:Device \(device.friendlyName) in connectToDevice found")
            self.device = device
            self.applicationName = applicationName
            initDevice(useOldCert: false, successCallback: startApplication)
        } else {
            print("Ocast:Device in connectToDevice not found")
            emitErrorEvent(error: CONNECT_FAILED)
        }
    }

    private func startApplication() {
        if device != nil {
            print("Ocast:trying to start application for \(device!.friendlyName)")
            device!.startApplication(completion: { error in
                if let error = error { // TODO: why error here
                    print("Ocast:Unexpected error while starting the application: \(error.localizedDescription).")
                    self.emitErrorEvent(error: self.CONNECT_FAILED)
                } else {
                    let deviceTransformed = self.transformDeviceForJS(device: self.device!)
                    self.sendEvent(withName: self.DEVICE_CONNECTED, body: deviceTransformed)
                }
            })
        } else {
            print("Ocast:trying to start application for unavailable device")
        }
    }

    @objc
    func reset() {
        device?.privateSettings?.reset(completion: { error in
            if let error = error {
                print("Ocast:Unexpected error while resetting: \(error.localizedDescription).")
            } else {
                print("Ocast:Reset ok.")
            }
        })
    }

    @objc(scanAPs:)
    func scanAPs(pinCode: NSNumber) {
        device?.privateSettings?.scanAccessPoints(withPINCode: pinCode.intValue, completion: { result, error in
            if let result = result {
                print("Ocast:Access points scan finished.")

                var aps = [[String: Any]]()

                for ap in result {
                    aps.append([
                        "ssid": ap.ssid,
                        "rssi": ap.rssi,
                        "security": ap.security.rawValue,
                    ])
                }

                let payload = [
                    "pinCode": pinCode,
                    "aps": aps,
                ] as [String: Any]

                self.sendEvent(withName: self.AP_LIST_OBTAINED, body: payload)
            } else if let error = error {
                print("Ocast:Unexpected error while scanning APs: \(error.localizedDescription).")
                self.emitErrorEvent(error: self.PAIRING_ERROR)
            } else {
                print("Ocast:Could not find any access points.")
                self.emitErrorEvent(error: self.PAIRING_ERROR)
            }
        })
    }

    @objc
    func getAPList() {
        device?.privateSettings?.accessPoints(completion: { result, error in
            if let result = result {
                print("Ocast:Getting \(result.count) APs finished successfully.")
            } else if let error = error {
                print("Ocast:Unexpected error while getting APs: \(error.localizedDescription).")
            }
        })
    }

    @objc(setAP:)
    func setAP(apConfig: [String: AnyObject]) { // todo add correct type
        let accessPointParams = SetAccessPointCommandParams(
            ssid: apConfig["ssid"] as! String,
            password: apConfig["password"] as! String,
            bssid: "",
            security: WifiSecurity(rawValue: apConfig["security"] as! Int), // todo check if correct type
            pinCode: apConfig["pinCode"] as! Int
        )
        device?.privateSettings?.setAccessPoint(accessPointParams, completion: { error in
            if let error = error {
                print("Ocast:Unexpected error while setting the AP: \(error.localizedDescription).")
                self.emitErrorEvent(error: self.PAIRING_ERROR)
            } else {
                print("Ocast:AP successfully set.")
                let deviceTransformed = self.transformDeviceForJS(device: self.device!)
                self.sendEvent(withName: self.DEVICE_PAIRED, body: deviceTransformed)
            }
        })
    }

    @objc(setName:)
    func setName(name _: String) {
        device?.privateSettings?.setDeviceName("devel-24A8", completion: { error in
            if let error = error {
                print("Ocast:Unexpected error while setting the name: \(error.localizedDescription).")
            } else {
                print("Ocast:Name successfully set.")
            }
        })
    }

    @objc
    func disconnect() {
        device?.disconnect(completion: { error in
            if error != nil {
                print("Ocast:failed to disconnect")
            } else {
                let deviceTransformed = self.transformDeviceForJS(device: self.device!)
                self.sendEvent(withName: self.DEVICE_DISCONNECTED, body: deviceTransformed)
            }
        })
    }

    @objc(castMedia:)
    func castMedia(data: [String: AnyObject]) { // todo add correct types
        let mediaPrepare = PrepareMediaCommandParams(
            url: data["url"] as! String,
            frequency: data["frequency"] as! UInt,
            title: data["title"] as! String,
            subtitle: data["subtitle"] as! String,
            logo: "https://placeholder.com",
            mediaType: MediaType(rawValue: data["mediaType"] as! String)!,
            transferMode: MediaTransferMode(rawValue: data["transferMode"] as! String)!,
            autoPlay: data["autoplay"] as! Bool
        )

        let options = data["options"] as! [String: Any]

        ensureConnected { [weak self] connected in
            if connected {
                self?.device?.prepareMedia(mediaPrepare, withOptions: options, completion: { error in
                    if let error = error {
                        print("Ocast:Unexpected error while starting playback: \(error.localizedDescription).")
                        self?.emitErrorEvent(error: self!.CAST_FAILED)
                    } else {
                        print("Ocast:MediaController prepared")
                    }
                })
            }
        }
    }

    @objc(resume)
    func resume() {
        ensureConnected { [weak self] connected in
            if connected {
                if self?.lastState == MediaPlaybackState.paused {
                    self?.device?.resumeMedia(completion: { error in
                        if let error = error {
                            print("Ocast:Unexpected error while resuming playback: \(error.localizedDescription).")
                            self?.emitErrorEvent(error: self!.RESUME_FAILED)
                        } else {
                            self?.lastState = MediaPlaybackState.playing
                            print("Ocast:Playback successfully resumed")
                        }
                    })
                }
            }
        }
    }

    @objc(pause)
    func pause() {
        ensureConnected { [weak self] connected in
            if connected {
                if self?.lastState == MediaPlaybackState.playing {
                    self?.device?.pauseMedia(completion: { error in
                        if let error = error {
                            print("Ocast:Unexpected error while pausing playback: \(error.localizedDescription).")
                            self?.emitErrorEvent(error: self!.PAUSE_FAILED)
                        } else {
                            self?.lastState = MediaPlaybackState.paused
                            print("Ocast:Pause succesful")
                        }
                    })
                }
            }
        }
    }

    @objc(seek:)
    func seek(time: NSNumber) {
        if lastState == MediaPlaybackState.paused {
            print("Ocast:Player paused, need to resume first ...")

            device?.resumeMedia(completion: { error in
                if let error = error {
                    print("Ocast:Unexpected error while resuming playback: \(error.localizedDescription).")
                    self.emitErrorEvent(error: self.RESUME_FAILED)
                } else {
                    print("Ocast:Playback successfully resumed")
                    self.doSeek(time: time)
                }
            })
        } else {
            doSeek(time: time)
        }
    }

    func doSeek(time: NSNumber?) {
        guard let time = time else { return }

        ensureConnected { [weak self] connected in
            guard let `self` = self else { return }
            if connected {
                let positionSeconds = time.uintValue / 1000
                print("Ocast:Trying to seek to position \(positionSeconds) ...")

                self.device?.seekMedia(to: Double(positionSeconds), completion: { error in
                    if let error = error {
                        print("Ocast:Unexpected error while trying to seek: \(error.localizedDescription).")
                        self.emitErrorEvent(error: self.SEEK_FAILED)
                    } else {
                        print("Ocast:Seek successful")
                    }
                })
            }
        }
    }

    @objc(stop)
    func stop() {
        ensureConnected { [weak self] connected in
            if connected {
                self?.device?.stopMedia(completion: { error in
                    if let error = error {
                        print("Ocast:Unexpected error while trying to stop the playback: \(error.localizedDescription).")
                        self?.emitErrorEvent(error: self!.STOP_FAILED)
                    } else {
                        print("Ocast:Playback successfully stopped")
                    }
                })
            }
        }
    }

    @objc(volume:)
    func volume(level: NSNumber) {
        ensureConnected { [weak self] connected in
            guard let `self` = self else { return }
            if connected {
                let volume = Double(truncating: level) / 100
                self.device?.setMediaVolume(volume, completion: { error in
                    if let error = error {
                        print("Ocast:Unexpected error while setting the volume: \(error.localizedDescription).")
                        self.emitErrorEvent(error: self.VOLUME_FAILED)
                    } else {
                        print("Ocast:Volume successfully set")
                    }
                })
            }
        }
    }

    @objc(mute:)
    func mute(mute: Bool) {
        device?.muteMedia(mute, completion: { error in
            if let error = error {
                print("Ocast:Unexpected error while setting mute: \(error.localizedDescription).")
                self.emitErrorEvent(error: self.MUTE_FAILED)
            } else {
                print("Ocast:Mute successfully set to \(mute)")
            }
        })
    }

    // TODO: not tested
    @objc(updateMetadata)
    func updateMetadata() {
        ensureConnected { [weak self] connected in
            if connected {
                self?.device?.mediaMetadata(completion: { metadata, error in
                    if let error = error {
                        print("Ocast:Unexpected error while getting metadata: \(error.localizedDescription).")
                        self?.emitErrorEvent(error: self!.METADATA_UPDATE_FAILED)
                    } else if let metadata = metadata {
                        print("Ocast:Metadata received")
                        self?.emitMetadataEvent(metadata: metadata)
                    }
                })
            }
        }
    }

    @objc(updatePlaybackStatus)
    func updatePlaybackStatus() {
        ensureConnected { [weak self] connected in
            if connected {
                self?.device?.mediaPlaybackStatus(completion: { playbackStatus, error in
                    if let error = error {
                        print("Ocast:Unexpected error while getting playback status: \(error.localizedDescription).")
                        self?.emitErrorEvent(error: self!.PLAYBACK_STATUS_UPDATE_FAILED)
                    } else if let playbackStatus = playbackStatus {
                        print("Ocast:Playback status received")
                        self?.lastState = playbackStatus.state
                        self?.emitPlaybackStatusEvent(playbackStatus: playbackStatus)
                    }
                })
            }
        }
    }

    // TODO: not tested
    @objc(setAudioTrack:)
    func setAudioTrack(trackId: String) {
        let mediaTrackParams = SetMediaTrackCommandParams(
            trackId: trackId,
            type: MediaTrackType.audio,
            enabled: true
        )
        device?.setMediaTrack(mediaTrackParams, completion: { error in
            if let error = error {
                print("Ocast:Unexpected error \(error.localizedDescription) while setting audio track \(trackId)")
                self.emitErrorEvent(error: self.SETTING_TRACK_FAILED)
            } else {
                print("Ocast:Audio track \(trackId) successfully set")
            }
        })
    }

    func emitErrorEvent(error: String) {
        sendEvent(withName: ERROR_EVENT, body: error)
    }

    func emitMetadataEvent(metadata: MediaMetadata) {
        var audioTracks = [[String: Any]]()
        var subtitleTracks = [[String: Any]]()

        for audioTrack in metadata.audioTracks {
            audioTracks.append([
                "id": audioTrack.trackId,
                "enabled": audioTrack.enabled,
                "label": audioTrack.label,
                "language": audioTrack.language,
            ])
        }

        for subtitleTrack in metadata.subtitleTracks {
            subtitleTracks.append([
                "id": subtitleTrack.trackId,
                "enabled": subtitleTrack.enabled,
                "label": subtitleTrack.enabled,
                "language": subtitleTrack.language,
            ])
        }

        sendEvent(withName: METADATA_CHANGED, body: [
            "title": metadata.title,
            "subtitle": metadata.subtitle,
            "audioTracks": audioTracks,
            "subtitleTracks": subtitleTracks,
        ])
    }

    func emitPlaybackStatusEvent(playbackStatus: MediaPlaybackStatus) {
        sendEvent(withName: PLAYBACK_STATUS_CHANGED, body: [
            "duration": playbackStatus.duration,
            "muted": playbackStatus.muted,
            "position": playbackStatus.position,
            "state": playbackStatus.state.rawValue,
            "volume": playbackStatus.volume * 100,
        ])
    }

    private func sendPinNeeded() {
        device?.privateSettings?.versionInfo(completion: { versionInfo, error in
            if versionInfo != nil {
                print("Ocast:Version info obtained.")
                let deviceTransformed = self.transformDeviceForJS(device: self.device)
                self.sendEvent(withName: self.PIN_NEEDED, body: deviceTransformed)
            } else if let error = error {
                print("Ocast:Unexpected error while getting version info: \(error.localizedDescription).")
                self.emitErrorEvent(error: self.PAIRING_ERROR)
            } else {
                print("Ocast:Unable to get version info.")
                self.emitErrorEvent(error: self.PAIRING_ERROR)
            }
        })
    }

    private func ensureConnected(completion: @escaping (Bool) -> Void) {
        if device!.state != .connected {
            print("Ocast:ensureConnected \(device!.friendlyName) was not connected, trying to reinit the device")
            initDevice(useOldCert: false, successCallback: startApplication)
        } else {
            print("Ocast:ensureConnected \(device!.friendlyName) is connected")
            completion(true)
        }
    }

    func initDevice(useOldCert oldCert: Bool, successCallback: @escaping () -> Void) {
        device?.connect(sslConfiguration(useOldCert: oldCert), completion: { error in
            if let error = error {
                if oldCert == false {
                    print("Ocast:Failed to initialize device with new cert. Trying failover to old cert...")
                    self.initDevice(useOldCert: true, successCallback: successCallback)
                } else {
                    print("Ocast:device init failed with \(error.localizedDescription)")
                }
            } else {
                print("Ocast:device init for \(self.device!.friendlyName) success")
                successCallback()
            }
        })
    }

    func sslConfiguration(useOldCert oldCert: Bool) -> SSLConfiguration? {
        guard let rootCertificatePath = Bundle.main.path(forResource: "orange_device_rootca_cer", ofType: ".der"),
            let rootCertificateData = try? Data(contentsOf: URL(fileURLWithPath: rootCertificatePath)),
            let serverCertificatePath = Bundle.main.path(forResource: "orange_device_firmware_ca_prod_cer", ofType: ".der"),
            let serverCertificateData = try? Data(contentsOf: URL(fileURLWithPath: serverCertificatePath)),
            let clientCertificatePath = Bundle.main.path(forResource: oldCert ? "client" : "DEM412", ofType: "p12"),
            let clientCertificateData = try? URL(fileURLWithPath: clientCertificatePath) else { return nil }

        print("Ocast:sslConfiguration: rootCertificateData \(rootCertificateData.description), serverCertificatePath: \(serverCertificatePath.description), serverCertificateData: \(serverCertificateData.description), clientCertificatePath: \(clientCertificatePath.description), clientCertificateData: \(clientCertificateData.description)")

        let sslConfigurationClientCertificate = SSLConfigurationClientCertificate(certificate: clientCertificateData, password: oldCert ? "P9iueiUdvj8" : "7X;Pzy0lf{iZ")
        let sslConfiguration = SSLConfiguration(deviceCertificates: [rootCertificateData, serverCertificateData], clientCertificate: sslConfigurationClientCertificate)
        sslConfiguration.validatesHost = false
        sslConfiguration.validatesCertificateChain = false
        sslConfiguration.disablesSSLCertificateValidation = true
        print("Ocast:sslConfiguration: \(sslConfiguration.description)")
        return sslConfiguration
    }
}

// TODO: not sure if I need this at all
extension OCastManager: WebSocketDelegate { // DeviceDiscoveryDelegate was the closest thing but is no longer public
    func websocket(_: WebSocketProtocol, didReceiveMessage message: String) {
        print("OCast:WebSocketDelegate: application didReceiveMessage url: \(message)")
    }

    func websocket(_: WebSocketProtocol, didConnectTo url: URL?) {
        print("OCast:WebSocketDelegate: application didConnectTo url: \(url!)")
    }

    func websocket(_: WebSocketProtocol, didDisconnectWith error: Error?) {
        if error != nil {
            print("OCast:WebSocketDelegate: application did disconnect with error: \(error!)")
            emitErrorEvent(error: DEVICE_ERROR)
        }
    }
}
