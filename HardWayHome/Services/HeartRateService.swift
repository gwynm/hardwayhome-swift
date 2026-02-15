import Foundation
@preconcurrency import CoreBluetooth
import os

private let log = Logger(subsystem: "com.gwynmorfey.hardwayhome.native", category: "heartrate")

/// BLE connection state.
enum HrConnectionState: Sendable {
    case disconnected
    case scanning
    case connecting
    case connected
}

/// A discovered BLE heart rate device.
struct HrDevice: Identifiable, Sendable {
    let id: String  // CBPeripheral identifier UUID string
    let name: String?
}

/// Manages CoreBluetooth for heart rate monitor connectivity.
/// Writes pulse readings directly to the database when a workout is active.
///
/// All CoreBluetooth delegate callbacks arrive on the main queue (queue: nil),
/// matching this class's @MainActor isolation.
@MainActor
@Observable
final class HeartRateService: NSObject {

    private(set) var connectionState: HrConnectionState = .disconnected
    private(set) var currentBpm: Int? = nil
    private(set) var discoveredDevices: [HrDevice] = []

    private var centralManager: CBCentralManager?
    private var connectedPeripheral: CBPeripheral?
    private var activeWorkoutId: Int64? = nil
    private var reconnectTimer: Timer?
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 30
    private var lastDeviceUUID: UUID?
    private let db: AppDatabase

    // Standard Bluetooth Heart Rate Service UUIDs
    private let hrServiceUUID = CBUUID(string: "180D")
    private let hrMeasurementCharUUID = CBUUID(string: "2A37")

    // KV keys
    private static let kvLastDeviceID = "ble_last_device_id"
    private static let kvLastDeviceName = "ble_last_device_name"

    init(db: AppDatabase = .shared) {
        self.db = db
        super.init()
    }

    // MARK: - Public API

    func initialize() {
        if centralManager == nil {
            centralManager = CBCentralManager(
                delegate: self,
                queue: .main,
                options: [CBCentralManagerOptionRestoreIdentifierKey: "hardwayhome-ble"])
        }
    }

    func startScan() {
        discoveredDevices = []
        connectionState = .scanning
        centralManager?.scanForPeripherals(
            withServices: [hrServiceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    func stopScan() {
        centralManager?.stopScan()
        if connectionState == .scanning {
            connectionState = connectedPeripheral != nil ? .connected : .disconnected
        }
    }

    func connect(to deviceId: String) {
        stopScan()
        guard let uuid = UUID(uuidString: deviceId),
              let peripheral = centralManager?.retrievePeripherals(withIdentifiers: [uuid]).first else {
            return
        }
        connectionState = .connecting
        connectedPeripheral = peripheral
        peripheral.delegate = self
        centralManager?.connect(peripheral, options: nil)
    }

    func disconnect() {
        cancelReconnect()
        if let peripheral = connectedPeripheral {
            centralManager?.cancelPeripheralConnection(peripheral)
        }
        connectedPeripheral = nil
        currentBpm = nil
        connectionState = .disconnected
    }

    func reconnectToLastDevice() {
        guard let idString = try? db.kvGet(Self.kvLastDeviceID),
              let uuid = UUID(uuidString: idString) else { return }
        lastDeviceUUID = uuid
        guard let peripheral = centralManager?.retrievePeripherals(withIdentifiers: [uuid]).first else { return }
        connectionState = .connecting
        connectedPeripheral = peripheral
        peripheral.delegate = self
        centralManager?.connect(peripheral, options: nil)
    }

    var lastDevice: HrDevice? {
        guard let id = try? db.kvGet(Self.kvLastDeviceID) else { return nil }
        let name = try? db.kvGet(Self.kvLastDeviceName)
        return HrDevice(id: id, name: name)
    }

    var setActiveWorkoutId: Int64? {
        get { activeWorkoutId }
        set { activeWorkoutId = newValue }
    }

    // MARK: - Reconnection

    private func scheduleReconnect(for peripheral: CBPeripheral) {
        cancelReconnect()
        reconnectAttempts = 0
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.attemptReconnect(for: peripheral)
            }
        }
    }

    private func attemptReconnect(for peripheral: CBPeripheral) {
        guard connectionState != .connected else {
            cancelReconnect()
            return
        }
        reconnectAttempts += 1
        if reconnectAttempts > maxReconnectAttempts {
            cancelReconnect()
            return
        }
        connectionState = .connecting
        centralManager?.connect(peripheral, options: nil)
    }

    private func cancelReconnect() {
        reconnectTimer?.invalidate()
        reconnectTimer = nil
    }

    // MARK: - HR parsing

    private func parseHeartRate(_ data: Data) -> Int? {
        guard data.count >= 2 else { return nil }
        let flags = data[0]
        let is16Bit = (flags & 0x01) != 0
        if is16Bit, data.count >= 3 {
            return Int(data[1]) | (Int(data[2]) << 8)
        }
        return Int(data[1])
    }
}

// MARK: - CBCentralManagerDelegate
// Callbacks arrive on .main queue, matching @MainActor isolation.

extension HeartRateService: CBCentralManagerDelegate {

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let state = central.state
        Task { @MainActor in
            if state == .poweredOn {
                // Auto-reconnect to last known HR monitor when BLE becomes ready
                self.reconnectToLastDevice()
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any],
                                    rssi RSSI: NSNumber) {
        let deviceId = peripheral.identifier.uuidString
        let deviceName = peripheral.name
            ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
        MainActor.assumeIsolated {
            let device = HrDevice(id: deviceId, name: deviceName)
            if !discoveredDevices.contains(where: { $0.id == device.id }) {
                discoveredDevices.append(device)
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didConnect peripheral: CBPeripheral) {
        MainActor.assumeIsolated {
            connectionState = .connected
            cancelReconnect()
            try? db.kvSet(Self.kvLastDeviceID, value: peripheral.identifier.uuidString)
            try? db.kvSet(Self.kvLastDeviceName, value: peripheral.name ?? "HR Monitor")
            peripheral.discoverServices([hrServiceUUID])
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didDisconnectPeripheral peripheral: CBPeripheral,
                                    error: Error?) {
        MainActor.assumeIsolated {
            connectedPeripheral = nil
            currentBpm = nil
            connectionState = .disconnected
            if activeWorkoutId != nil {
                scheduleReconnect(for: peripheral)
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didFailToConnect peripheral: CBPeripheral,
                                    error: Error?) {
        MainActor.assumeIsolated {
            connectionState = .disconnected
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    willRestoreState dict: [String: Any]) {
        // Extract sendable values before crossing isolation boundary
        let peripheralUUID = (dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral])?.first?.identifier
        let wasConnected = (dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral])?.first?.state == .connected
        Task { @MainActor in
            guard let uuid = peripheralUUID,
                  let peripheral = centralManager?.retrievePeripherals(withIdentifiers: [uuid]).first else { return }
            connectedPeripheral = peripheral
            peripheral.delegate = self
            if wasConnected {
                connectionState = .connected
                peripheral.discoverServices([hrServiceUUID])
            }
        }
    }
}

// MARK: - CBPeripheralDelegate

extension HeartRateService: CBPeripheralDelegate {

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didDiscoverServices error: Error?) {
        MainActor.assumeIsolated {
            guard let services = peripheral.services else { return }
            for service in services where service.uuid == hrServiceUUID {
                peripheral.discoverCharacteristics([hrMeasurementCharUUID], for: service)
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didDiscoverCharacteristicsFor service: CBService,
                                error: Error?) {
        MainActor.assumeIsolated {
            guard let chars = service.characteristics else { return }
            for char in chars where char.uuid == hrMeasurementCharUUID {
                peripheral.setNotifyValue(true, for: char)
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didUpdateValueFor characteristic: CBCharacteristic,
                                error: Error?) {
        guard let data = characteristic.value else { return }
        MainActor.assumeIsolated {
            if let bpm = parseHeartRate(data) {
                currentBpm = bpm
                if let workoutId = activeWorkoutId {
                    do {
                        try db.insertPulse(workoutId: workoutId, bpm: bpm)
                    } catch {
                        log.error("Failed to insert pulse: \(error)")
                    }
                }
            }
        }
    }
}
