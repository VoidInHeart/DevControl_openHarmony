import {
  CommandPayload,
  DeviceInfo,
  EnvironmentHistoryPoint,
  GatewaySession
} from '../model/DeviceModel';
import {
  DeviceRemovalReceipt,
  DeviceRegistrationReceipt,
  DeviceRegistrationRequest
} from './DeviceRegistration';

export interface GatewayTransportListener {
  onConnectionStateChanged(state: string): void;
  onGatewayMessage(message: Record<string, Object>): void;
  onTransportError(code: string, message: string): void;
}

export interface GatewayTransport {
  setCertificateAuthorityPath(path: string): void;
  configure(session: GatewaySession): void;
  checkHealth(address: string): Promise<boolean>;
  pair(address: string, pairingCode: string, clientId: string): Promise<GatewaySession>;
  fetchDeviceSnapshot(): Promise<DeviceInfo[]>;
  fetchLogs(limit: number): Promise<Record<string, Object>[]>;
  fetchAlerts(limit: number): Promise<Record<string, Object>[]>;
  fetchEnvironmentHistory(fromTimestamp: number): Promise<EnvironmentHistoryPoint[]>;
  registerDevice(request: DeviceRegistrationRequest): Promise<DeviceRegistrationReceipt>;
  deleteDevice(deviceId: string): Promise<DeviceRemovalReceipt>;
  connect(listener: GatewayTransportListener): Promise<void>;
  sendCommand(
    deviceId: string,
    action: string,
    expectedStateVersion: number | null,
    payload: CommandPayload
  ): Promise<string>;
  reconnect(): Promise<void>;
  close(): Promise<void>;
}
