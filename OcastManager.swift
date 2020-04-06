// Copyright (c) 2018, nangu.TV, a.s. All rights reserved.
// nangu.TV, a.s PROPRIETARY/CONFIDENTIAL. Use is subject to license terms.

import OCast
import React
import InnopiaDriver

@objc(OCastManager)
class OCastManager: RCTEventEmitter {
    public let AP_LIST_OBTAINED = "OCast:AP_LIST_OBTAINED";
    public let DEVICE_AVAILABLE = "OCast:DEVICE_AVAILABLE";
    public let DEVICE_CONNECTED = "OCast:DEVICE_CONNECTED";
    public let DEVICE_DISCONNECTED = "OCast:DEVICE_DISCONNECTED";
    public let DEVICE_LOST = "OCast:DEVICE_LOST";
    public let DEVICE_PAIRED = "OCast:DEVICE_PAIRED";
    public let ERROR_EVENT = "OCast:ERROR_EVENT";
    public let METADATA_CHANGED = "OCast:METADATA_CHANGED";
    public let PIN_NEEDED = "OCast:PIN_NEEDED";
    public let PLAYBACK_STATUS_CHANGED = "OCast:PLAYBACK_STATUS_CHANGED";

    private let CAST_FAILED = "CAST_FAILED";
    private let CONNECT_FAILED = "CONNECT_FAILED";
    fileprivate let DEVICE_ERROR = "DEVICE_ERROR";
    private let DISCONNECT_FAILED = "DISCONNECT_FAILED";
    private let METADATA_UPDATE_FAILED = "METADATA_UPDATE_FAILED";
    private let MUTE_FAILED = "MUTE_FAILED";
    private let PAIRING_ERROR = "PAIRING_ERROR";
    private let PAUSE_FAILED = "PAUSE_FAILED";
    private let PLAYBACK_STATUS_UPDATE_FAILED = "PLAYBACK_STATUS_UPDATE_FAILED";
    private let RESUME_FAILED = "RESUME_FAILED";
    private let SEEK_FAILED = "SEEK_FAILED";
    private let SETTING_TRACK_FAILED = "SETTING_TRACK_FAILED";
    private let SSL_ERROR = "SSL_ERROR";
    private let STOP_FAILED = "STOP_FAILED";
    private let VOLUME_FAILED = "VOLUME_FAILED";

    fileprivate var device: Device?
    fileprivate var devices = [Device]()

    fileprivate var applicationController: ApplicationController?
    fileprivate var mediaController: MediaController?
    fileprivate var discoveryManager: DeviceDiscovery?
    fileprivate var deviceManager: DeviceManager?
    fileprivate var privateSettings: PrivateSettings?
    fileprivate var lastState: PlayerState?

    fileprivate var applicationName: String = ""

    override init() {
        // Register Vendor and init DeviceDiscovery
        DeviceManager.registerDriver(InnopiaDriver.self, forManufacturer: "Innopia")
        self.discoveryManager = DeviceDiscovery(forTargets: [InnopiaDriver.searchTarget])

        super.init()

        self.discoveryManager?.delegate = self
    }

    @objc
    override func constantsToExport() -> [AnyHashable : Any]! {
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
            "PLAYBACK_STATE_KEY_BUFFERING": PlayerState.buffering.rawValue,
            "PLAYBACK_STATE_KEY_FAILED": PlayerState.unknown.rawValue,
            "PLAYBACK_STATE_KEY_IDLE": PlayerState.idle.rawValue,
            "PLAYBACK_STATE_KEY_PAUSED": PlayerState.paused.rawValue,
            "PLAYBACK_STATE_KEY_PLAYING": PlayerState.playing.rawValue,
            "PLAYBACK_STATUS_CHANGED": PLAYBACK_STATUS_CHANGED,
            "TRANSFER_MODE_BUFFERED": TransferMode.buffered.rawValue,
            "TRANSFER_MODE_STREAMED": TransferMode.streamed.rawValue
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
            PLAYBACK_STATUS_CHANGED
        ];
    }

    @objc
    func requiresMainQueueSetup() -> Bool {
        return true;
    }

    @objc(startScan)
    func startScan() -> Void {
        print("OCast: startScan")

        self.devices = [Device]()
        self.discoveryManager?.start()
    }

    @objc(stopScan)
    func stopScan() -> Void {
        print("OCast: stopScan")

        self.discoveryManager?.stop()
    }

    @objc(pairDevice:)
    func pairDevice(deviceId: String) -> Void {
        guard let device = self.devices.first(where: { $0.deviceID == deviceId }) else {
            print("Device not found")
            self.emitErrorEvent(error: self.PAIRING_ERROR)
            return
        }

        self.device = device
        self.initWithCert(useOldCert: false)
    }

    func initWithCert(useOldCert oldCert: Bool) -> Void {
        self.initDeviceManager(useOldCert: oldCert)

        self.initPrivateSettings(onSuccess: {
            self.privateSettings?.getInfo(onSuccess: { (versionInfo) in
                print("Version info obtained.")
                self.sendEvent(withName: self.PIN_NEEDED, body: [
                    "id": self.device?.deviceID,
                    "name": self.device?.friendlyName,
                    "ipAddress": self.device?.ipAddress,
                ])
            }, onError: { (error) in
                print("Unexpected error while getting version info: \(error as Optional).")
                self.emitErrorEvent(error: self.PAIRING_ERROR)
            })
        }, onError: {
            if (oldCert == false) {
                print("Failed to initialize private settings with new cert. Trying failover to old cert...")
                self.initWithCert(useOldCert: true)
            } else {
                print("Failed to initialize private settings with old cert. Sending PAIRING_ERROR...")
                self.emitErrorEvent(error: self.PAIRING_ERROR)
            }
        })
    }

    @objc(connectToDevice:withApplicationName:)
    func connectToDevice(deviceId: String, withApplicationName applicationName: String) -> Void {
        self.applicationName = applicationName

        guard let device = self.devices.first(where: { $0.deviceID == deviceId }) else {
            print("Device not found")
            self.emitErrorEvent(error: self.CONNECT_FAILED)
            return
        }

        self.device = device
        self.connectWithCert(useOldCert: false)
    }

    func connectWithCert(useOldCert oldCert: Bool) {
        self.initDeviceManager(useOldCert: oldCert)

        self.deviceManager?.applicationController(for: self.applicationName, onSuccess: { (applicationController) in
            applicationController.start(onSuccess: {
              self.applicationController = applicationController

              self.mediaController = self.applicationController?.mediaController
              self.mediaController?.delegate = self

              self.sendEvent(withName: self.DEVICE_CONNECTED, body: [
                  "id": self.device?.deviceID,
                  "name": self.device?.friendlyName,
              ])
          }, onError: { (error) in
              print("Unexpected error while starting the application: \(error as Optional).")
              self.emitErrorEvent(error: self.CONNECT_FAILED)
          })
        }, onError: { (error) in
            if (oldCert == false) {
                print("Failed to connect to device settings with new cert. Trying failover to old cert...")
                self.connectWithCert(useOldCert: true)
            } else {
                print("Unexpected error while creating the application controller: \(error as Optional).")
                self.emitErrorEvent(error: self.CONNECT_FAILED)
            }
        })
    }

    @objc
    func reset() -> Void {
        self.privateSettings?.reset(onSuccess: { () in
            print("Reset ok.")
        }, onError: { (error) in
            print("Unexpected error while resetting: \(error as Optional).")
        })
    }

    @objc(scanAPs:)
    func scanAPs(pinCode: NSNumber) -> Void {
        self.privateSettings?.scanAPs(pinCode: pinCode.intValue, onSuccess: { (data) in
            print("APs scan finished.")

            var aps = [[String:Any]]()

            for ap in data {
                aps.append([
                    "ssid": ap.ssid!,
                    "rssi": ap.rssi!,
                    "security": ap.security!.rawValue
                ])
            }

            let payload = [
                "pinCode": pinCode,
                "aps": aps
            ] as [String : Any]

            self.sendEvent(withName: self.AP_LIST_OBTAINED, body: payload)
        }, onError: { (error) in
            print("Unexpected error while scanning APs: \(error as Optional).")
            self.emitErrorEvent(error: self.PAIRING_ERROR)
        })
    }

    @objc
    func getAPList() -> Void {
        self.privateSettings?.getAPList(onSuccess: { (aps) in
            print("Getting APs finished successfully.")
            // TODO send event with found aps?
        }, onError: { (error) in
            print("Unexpected error while getting APs: \(error as Optional).")
        })
    }

    @objc(setAP:)
    func setAP(apConfig: [String:AnyObject]) -> Void {
        self.privateSettings?.setAP(
            pinCode: apConfig["pinCode"] as! Int,
            ssid: apConfig["ssid"] as! String,
            bssid: "",
            security: apConfig["security"] as! Int,
            password: apConfig["password"] as! String,
            onSuccess: {
                print("AP successfully set.")
                self.sendEvent(withName: self.DEVICE_PAIRED, body: [
                    "id": self.device?.deviceID,
                    "name": self.device?.friendlyName,
                    "ipAddress": self.device?.ipAddress,
                ])
            }, onError: { (error) in
                print("Unexpected error while setting the AP: \(error as Optional).")
                self.emitErrorEvent(error: self.PAIRING_ERROR)
            }
        )
    }

    @objc(setName:)
    func setName(name: String) -> Void {
        self.privateSettings?.setDevice(name: "devel-24A8", onSuccess: {
            print("Name successfully set.")
        }, onError: { (error) in
            print("Unexpected error while setting the name: \(error as Optional).")
        })
    }

    @objc
    func disconnect() -> Void {
        let deviceID = self.device?.deviceID
        let friendlyName = self.device?.friendlyName

        self.applicationController?.unmanage(stream: self.mediaController!)

        self.sendEvent(withName: self.DEVICE_DISCONNECTED, body: [
            "id": deviceID,
            "name": friendlyName,
        ]);
    }

    @objc(castMedia:)
    func castMedia(data: [String:AnyObject]) -> Void {
        let mediaPrepare = MediaPrepare(
            url: URL(string: data["url"] as! String)!,
            frequency: data["frequency"] as! UInt,
            title: data["title"] as! String,
            subtitle: data["subtitle"] as! String,
            logo: URL(string: "https://placeholder.com")!,
            mediaType: MediaType(rawValue: data["mediaType"] as! Int)!,
            transferMode: TransferMode(rawValue: data["transferMode"] as! Int)!,
            autoplay: data["autoplay"] as! Bool
        )

        let options = data["options"] as! [String:Any];

        self.mediaController?.prepare(for: mediaPrepare, withOptions: options, onSuccess: {
            print("MediaController prepared")
        }, onError: { (error) in
            print("Unexpected error while starting playback: \(error as Optional).")
            self.emitErrorEvent(error: self.CAST_FAILED);
        })
    }

    @objc(resume)
    func resume() {
        self.mediaController?.resume(onSuccess: {
            self.lastState = PlayerState.playing
            print("Playback successfully resumed")
        }, onError: { (error) in
            print("Unexpected error while resuming playback: \(error as Optional).")
            self.emitErrorEvent(error: self.RESUME_FAILED)
        })
    }

    @objc(pause)
    func pause() {
        self.mediaController?.pause(onSuccess: {
            self.lastState = PlayerState.paused
            print("Pause succesful")
        }, onError: { (error) in
            print("Unexpected error while pausing playback: \(error as Optional).")
            self.emitErrorEvent(error: self.PAUSE_FAILED)
        })
    }

    @objc(seek:)
    func seek(time: NSNumber) {
        if (lastState == PlayerState.paused) {
            print("Player paused, need to resume first ...")

            self.mediaController?.resume(onSuccess: {
                print("Playback successfully resumed")
                self.doSeek(time: time)
            }, onError: { (error) in
                print("Unexpected error while resuming playback: \(error as Optional).")
                self.emitErrorEvent(error: self.RESUME_FAILED)
            })
        } else {
            doSeek(time: time)
        }
    }

    func doSeek(time: NSNumber) {
        let positionSeconds = time.uintValue / 1000
        print("Trying to seek to position \(positionSeconds) ...")

        self.mediaController?.seek(to: positionSeconds, onSuccess: {
            print("Seek successful")
        }, onError: { (error) in
            print("Unexpected error while trying to seek: \(error as Optional).")
            self.emitErrorEvent(error: self.SEEK_FAILED)
        })
    }

    @objc(stop)
    func stop() {
        self.mediaController?.stop(onSuccess: {
            print("Playback successfully stopped")
        }, onError: { (error) in
            print("Unexpected error while trying to stop the playback: \(error as Optional).")
            self.emitErrorEvent(error: self.STOP_FAILED)
        })
    }

    @objc(volume:)
    func volume(level: NSNumber) {
      self.mediaController?.volume(to: Float(truncating: level) / 100, onSuccess: {
            print("Volume successfully set")
        }, onError: { (error) in
            print("Unexpected error while setting the volume: \(error as Optional).")
            self.emitErrorEvent(error: self.VOLUME_FAILED)
        })
    }

    @objc(mute:)
    func mute(mute: Bool) {
        self.mediaController?.mute(isMuted: mute, onSuccess: {
            print("Mute successfully set to \(mute)")
        }, onError: { (error) in
            print("Unexpected error while setting mute: \(error as Optional).")
            self.emitErrorEvent(error: self.MUTE_FAILED)
        })
    }

    // TODO not tested
    @objc(updateMetadata)
    func updateMetadata() {
        self.mediaController?.metadata(onSuccess: { (metadata) in
            print("Metadata received")
            self.emitMetadataEvent(metadata: metadata)
        }, onError: { (error) in
            print("Unexpected error while getting metadata: \(error as Optional).")
            self.emitErrorEvent(error: self.METADATA_UPDATE_FAILED)
        })
    }

    @objc(updatePlaybackStatus)
    func updatePlaybackStatus() {
        self.mediaController?.playbackStatus(onSuccess: { (playbackStatus) in
            print("Playback status received")
            self.lastState = playbackStatus.state
            self.emitPlaybackStatusEvent(playbackStatus: playbackStatus)
        }, onError: { (error) in
            print("Unexpected error while getting playback status: \(error as Optional).")
            self.emitErrorEvent(error: self.PLAYBACK_STATUS_UPDATE_FAILED)
        })
    }

    // TODO not tested
    @objc(setAudioTrack:)
    func setAudioTrack(trackId: String) {
        self.mediaController?.track(type: TrackType.audio, id: trackId, enabled: true, onSuccess: {
            print("Audio track \(trackId) successfully set")
        }, onError: { (error) in
            print("Unexpected error while setting audio track \(trackId)")
            self.emitErrorEvent(error: self.SETTING_TRACK_FAILED)
        })
    }

    func emitErrorEvent(error: String) {
        sendEvent(withName: ERROR_EVENT, body: error)
    }

    func emitMetadataEvent(metadata: Metadata) {
        var audioTracks = [[String:Any]]()
        var subtitleTracks = [[String:Any]]()

        for audioTrack in metadata.audioTracks! {
            audioTracks.append([
                "id": audioTrack.id,
                "enabled": audioTrack.enabled,
                "label": audioTrack.label,
                "language": audioTrack.language
            ])
        }

        for subtitleTrack in metadata.textTracks! {
            subtitleTracks.append([
                "id": subtitleTrack.id,
                "enabled": subtitleTrack.enabled,
                "label": subtitleTrack.enabled,
                "language": subtitleTrack.language
            ])
        }

        self.sendEvent(withName: METADATA_CHANGED, body: [
            "title": metadata.title,
            "subtitle": metadata.subtitle,
            "audioTracks": audioTracks,
            "subtitleTracks": subtitleTracks,
        ])
    }

    func emitPlaybackStatusEvent(playbackStatus: PlaybackStatus) {
        self.sendEvent(withName: PLAYBACK_STATUS_CHANGED, body: [
            "duration": playbackStatus.duration,
            "muted": playbackStatus.mute,
            "position": playbackStatus.position,
            "state": playbackStatus.state.rawValue,
            "volume": playbackStatus.volume * 100,
        ])
    }

    func initDeviceManager(useOldCert oldCert: Bool) -> Void {
        self.deviceManager = DeviceManager(with: self.device!, sslConfiguration: sslConfiguration(useOldCert: oldCert))
        self.deviceManager?.delegate = self
    }

    func initPrivateSettings(onSuccess:@escaping () -> (), onError:@escaping () -> ()) -> Void {
        self.deviceManager?.privateSettingsController(onSuccess: { (privateSettings) in
            self.privateSettings = privateSettings
            onSuccess()
        }, onError: { (error) in
            print("Unexpected error while getting the private settings controller: \(error as Optional).")
            onError()
        })
    }

    func sslConfiguration(useOldCert oldCert: Bool) -> SSLConfiguration? {
        guard let rootCertificatePath = Bundle.main.path(forResource: "orange_device_rootca_cer", ofType: ".der"),
            let rootCertificateData = try? Data(contentsOf: URL(fileURLWithPath: rootCertificatePath)),
            let serverCertificatePath = Bundle.main.path(forResource: "orange_device_firmware_ca_prod_cer", ofType: ".der"),
            let serverCertificateData = try? Data(contentsOf: URL(fileURLWithPath: serverCertificatePath)),
            let clientCertificatePath = Bundle.main.path(forResource: oldCert ? "client" : "DEM412", ofType: "p12"),
            let clientCertificateData = try? Data(contentsOf: URL(fileURLWithPath: clientCertificatePath)) else { return nil }

        let sslConfigurationClientCertificate = SSLConfigurationClientCertificate(certificate: clientCertificateData, password: oldCert ? "P9iueiUdvj8" : "7X;Pzy0lf{iZ")
        let sslConfiguration = SSLConfiguration(deviceCertificates: [rootCertificateData, serverCertificateData], clientCertificate: sslConfigurationClientCertificate)
        sslConfiguration.validatesHost = false
        sslConfiguration.validatesCertificateChain = false
        sslConfiguration.disablesSSLCertificateValidation = true

        return sslConfiguration
    }
}

extension OCastManager: DeviceDiscoveryDelegate {
    func deviceDiscovery(_ deviceDiscovery: DeviceDiscovery, didAddDevice device: Device) {
        print("OCast:DeviceDiscoveryDelegate: device added \(device.friendlyName)")
        self.devices.append(device)

        self.sendEvent(withName: DEVICE_AVAILABLE, body: [
            "id": device.deviceID,
            "name": device.friendlyName,
            "ipAddress": device.ipAddress,
        ])
    }

    func deviceDiscovery(_ deviceDiscovery: DeviceDiscovery, didRemoveDevice device: Device) {
        print("OCast:DeviceDiscoveryDelegate: device removed")
        self.devices = self.devices.filter { $0.deviceID != device.deviceID }

        self.sendEvent(withName: DEVICE_LOST, body: [
            "id": device.deviceID,
            "name": device.friendlyName,
            "ipAddress": device.ipAddress,
        ])
    }

    func deviceDiscoveryDidStop(_ deviceDiscovery: DeviceDiscovery, withError error: Error?) {
        print("OCast:DeviceDiscoveryDelegate: device discovery stopped")
    }
}

extension OCastManager: DeviceManagerDelegate {
    func deviceManager(_ deviceManager: DeviceManager, applicationDidDisconnectWithError error: NSError) {
        print("OCast:DeviceManagerDelegate: application did disconnect with error: \(error)")
        self.emitErrorEvent(error: self.DEVICE_ERROR)
    }
}

extension OCastManager: MediaControllerDelegate {
    func mediaController(_ mediaController: MediaController, didReceivePlaybackStatus playbackStatus: PlaybackStatus) {
        print("OCast:MediaControllerDelegate: onPlaybackStatus")
        self.emitPlaybackStatusEvent(playbackStatus: playbackStatus)
    }

    func mediaController(_ mediaController: MediaController, didReceiveMetadata metadata: Metadata) {
        print("OCast:MediaControllerDelegate: onMetaDataChanged")
        self.emitMetadataEvent(metadata: metadata)
    }
}
