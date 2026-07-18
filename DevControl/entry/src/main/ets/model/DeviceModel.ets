import {
  GenericDevice,
  parseGenericDevice,
  serializeGenericDevice
} from './GenericDeviceModel';
export class DeviceType {
  static readonly LIGHT: string = 'light';
  static readonly ENVIRONMENT: string = 'environment';
  static readonly AIR_CONDITIONER: string = 'airConditioner';
  static readonly DOOR_LOCK: string = 'doorLock';
}

export class DeviceBrand {
  static readonly GENERIC: string = 'generic';
  static readonly HAIER_SIM: string = 'haierSim';
  static readonly GREE_SIM: string = 'greeSim';
  static readonly MIDEA_SIM: string = 'mideaSim';
}

export class ACMode {
  static readonly AUTO: string = 'auto';
  static readonly COOL: string = 'cool';
  static readonly HEAT: string = 'heat';
  static readonly DRY: string = 'dry';
  static readonly FAN: string = 'fan';
}

export class ConnectionState {
  static readonly DISCONNECTED: string = 'disconnected';
  static readonly CONNECTING: string = 'connecting';
  static readonly AUTHENTICATING: string = 'authenticating';
  static readonly ONLINE: string = 'online';
  static readonly RECONNECTING: string = 'reconnecting';
  static readonly CLOSED: string = 'closed';
}

export class AutomationConfig {
  enabled: boolean = false;
  illuminanceThresholdLux: number = 100;
  noPresenceDelaySeconds: number = 60;
  manualOverrideUntil: number | null = null;
}

export class LightState {
  power: boolean = false;
  brightness: number = 0;
  lastNonZeroBrightness: number = 60;
  automation: AutomationConfig = new AutomationConfig();
}

export class EnvironmentState {
  temperatureCelsius: number = 24;
  humidityPercent: number = 55;
  illuminanceLux: number = 80;
  presence: boolean = true;
  dataValid: boolean = true;
}

export class AirConditionerState {
  brand: string = DeviceBrand.HAIER_SIM;
  power: boolean = false;
  mode: string = ACMode.AUTO;
  targetTemperatureCelsius: number = 24;
  running: boolean = false;
  lastAdapterFrame: string = '';
}

export class DoorLockState {
  locked: boolean = true;
  jammed: boolean = false;
  batteryPercent: number = 100;
  autoLockEnabled: boolean = true;
  autoLockDelaySeconds: number = 10;
  autoLockAt: number | null = null;
}

export class BaseDevice {
  id: string = '';
  name: string = '';
  roomId: string = '';
  type: string = '';
  online: boolean = false;
  stateVersion: number = 0;
  updatedAt: string = '';
}

export class LightDevice extends BaseDevice {
  type: string = DeviceType.LIGHT;
  state: LightState = new LightState();
}

export class EnvironmentDevice extends BaseDevice {
  type: string = DeviceType.ENVIRONMENT;
  state: EnvironmentState = new EnvironmentState();
}

export class AirConditionerDevice extends BaseDevice {
  type: string = DeviceType.AIR_CONDITIONER;
  state: AirConditionerState = new AirConditionerState();
}

export class DoorLockDevice extends BaseDevice {
  type: string = DeviceType.DOOR_LOCK;
  state: DoorLockState = new DoorLockState();
}

export type DeviceInfo =
  LightDevice |
  EnvironmentDevice |
  AirConditionerDevice |
  DoorLockDevice |
  GenericDevice;

export class AccessLogEntry {
  time: string = '';
  deviceId: string = '';
  action: string = '';
  result: string = '';
  errorCode: string = '';
  messageIdSuffix: string = '';
}

export class AlertEntry {
  time: string = '';
  deviceId: string = '';
  level: string = '';
  message: string = '';
  code: string = '';
}

export class SceneExecutionDetail {
  deviceId: string = '';
  success: boolean = false;
  errorCode: string = '';
}

export class EnvironmentHistoryPoint {
  timestamp: number = 0;
  temperatureCelsius: number = 0;
  humidityPercent: number = 0;
  illuminanceLux: number = 0;
  presence: boolean = false;
}

export class GatewaySession {
  protocolVersion: string = '1.0';
  clientId: string = '';
  gatewayAddress: string = '';
  credential: string = '';
  dataKey: string = '';
  issuedAt: number = 0;
  expiresAt: number = 0;
}

export type CommandPayload = Record<string, Object>;

function requireString(raw: Record<string, Object>, key: string): string {
  const value = raw[key];
  if (typeof value !== 'string' || value.length === 0) {
    throw new Error('Invalid or missing string field: ' + key);
  }
  return value;
}

function optionalString(
  raw: Record<string, Object>,
  key: string,
  fallback: string = ''
): string {
  const value = raw[key];
  if (value === undefined || value === null) {
    return fallback;
  }
  if (typeof value !== 'string') {
    throw new Error('Invalid string field: ' + key);
  }
  return value;
}

function requireBoolean(raw: Record<string, Object>, key: string): boolean {
  const value = raw[key];
  if (typeof value !== 'boolean') {
    throw new Error('Invalid or missing boolean field: ' + key);
  }
  return value;
}

function requireNumber(
  raw: Record<string, Object>,
  key: string,
  minimum: number,
  maximum: number,
  integerOnly: boolean = false
): number {
  const value = raw[key];
  if (
    typeof value !== 'number' ||
    !Number.isFinite(value) ||
    value < minimum ||
    value > maximum ||
    (integerOnly && !Number.isInteger(value))
  ) {
    throw new Error('Invalid or missing number field: ' + key);
  }
  return value;
}

function requireRecord(raw: Record<string, Object>, key: string): Record<string, Object> {
  const value = raw[key];
  if (typeof value !== 'object' || value === null || Array.isArray(value)) {
    throw new Error('Invalid or missing object field: ' + key);
  }
  return value as Record<string, Object>;
}

function optionalNullableInteger(
  raw: Record<string, Object>,
  key: string
): number | null {
  const value = raw[key];
  if (value === null || value === undefined) {
    return null;
  }
  if (typeof value !== 'number' || !Number.isInteger(value) || value < 0) {
    throw new Error('Invalid nullable integer field: ' + key);
  }
  return value;
}

function copyBase(device: BaseDevice, raw: Record<string, Object>): void {
  device.id = requireString(raw, 'id');
  device.name = requireString(raw, 'name');
  device.roomId = requireString(raw, 'roomId');
  device.online = requireBoolean(raw, 'online');
  device.stateVersion = requireNumber(raw, 'stateVersion', 0, Number.MAX_SAFE_INTEGER, true);
  device.updatedAt = requireString(raw, 'updatedAt');
}

export function parseDevice(raw: Record<string, Object>): DeviceInfo {
  const type = requireString(raw, 'type');
  if (type === DeviceType.LIGHT) {
    const device = new LightDevice();
    copyBase(device, raw);
    device.state.power = requireBoolean(raw, 'power');
    device.state.brightness = requireNumber(raw, 'brightness', 0, 100, true);
    device.state.lastNonZeroBrightness =
      requireNumber(raw, 'lastNonZeroBrightness', 1, 100, true);
    const automation = requireRecord(raw, 'automation');
    device.state.automation.enabled = requireBoolean(automation, 'enabled');
    device.state.automation.illuminanceThresholdLux =
      requireNumber(automation, 'illuminanceThresholdLux', 10, 500, true);
    device.state.automation.noPresenceDelaySeconds =
      requireNumber(automation, 'noPresenceDelaySeconds', 5, 600, true);
    device.state.automation.manualOverrideUntil =
      optionalNullableInteger(automation, 'manualOverrideUntil');
    return device;
  }
  if (type === DeviceType.ENVIRONMENT) {
    const device = new EnvironmentDevice();
    copyBase(device, raw);
    device.state.temperatureCelsius =
      requireNumber(raw, 'temperatureCelsius', -50, 80);
    device.state.humidityPercent =
      requireNumber(raw, 'humidityPercent', 0, 100);
    device.state.illuminanceLux =
      requireNumber(raw, 'illuminanceLux', 0, 100000);
    device.state.presence = requireBoolean(raw, 'presence');
    device.state.dataValid = requireBoolean(raw, 'dataValid');
    return device;
  }
  if (type === DeviceType.AIR_CONDITIONER) {
    const device = new AirConditionerDevice();
    copyBase(device, raw);
    device.state.brand = requireString(raw, 'brand');
    if (
      device.state.brand !== DeviceBrand.GENERIC &&
      device.state.brand !== DeviceBrand.HAIER_SIM &&
      device.state.brand !== DeviceBrand.GREE_SIM &&
      device.state.brand !== DeviceBrand.MIDEA_SIM
    ) {
      throw new Error('Unsupported air-conditioner brand: ' + device.state.brand);
    }
    device.state.power = requireBoolean(raw, 'power');
    device.state.mode = requireString(raw, 'mode');
    if (
      device.state.mode !== ACMode.AUTO &&
      device.state.mode !== ACMode.COOL &&
      device.state.mode !== ACMode.HEAT &&
      device.state.mode !== ACMode.DRY &&
      device.state.mode !== ACMode.FAN
    ) {
      throw new Error('Unsupported air-conditioner mode: ' + device.state.mode);
    }
    device.state.targetTemperatureCelsius =
      requireNumber(raw, 'targetTemperatureCelsius', 16, 30, true);
    device.state.running = requireBoolean(raw, 'running');
    device.state.lastAdapterFrame = optionalString(raw, 'lastAdapterFrame');
    return device;
  }
  if (type === DeviceType.DOOR_LOCK) {
    const device = new DoorLockDevice();
    copyBase(device, raw);
    device.state.locked = requireBoolean(raw, 'locked');
    device.state.jammed = requireBoolean(raw, 'jammed');
    device.state.batteryPercent =
      requireNumber(raw, 'batteryPercent', 0, 100, true);
    device.state.autoLockEnabled = requireBoolean(raw, 'autoLockEnabled');
    device.state.autoLockDelaySeconds =
      requireNumber(raw, 'autoLockDelaySeconds', 5, 60, true);
    device.state.autoLockAt = optionalNullableInteger(raw, 'autoLockAt');
    return device;
  }
  return parseGenericDevice(raw);
}

export function parseDevices(value: Object): DeviceInfo[] {
  if (!Array.isArray(value)) {
    throw new Error('Device snapshot must be an array');
  }
  const rawDevices = value as object[];
  const result: DeviceInfo[] = [];
  for (let index = 0; index < rawDevices.length; index++) {
    const item = rawDevices[index];
    if (typeof item !== 'object' || item === null || Array.isArray(item)) {
      throw new Error('Device snapshot contains a non-object entry');
    }
    const raw = item as Record<string, Object>;
    try {
      result.push(parseDevice(raw));
    } catch (error) {
      const deviceType = raw['type'];
      if (
        deviceType === DeviceType.LIGHT ||
        deviceType === DeviceType.ENVIRONMENT ||
        deviceType === DeviceType.AIR_CONDITIONER ||
        deviceType === DeviceType.DOOR_LOCK
      ) {
        const message = error instanceof Error ?
          error.message :
          'Known device parsing failed';
        throw new Error(message);
      }
    }
  }
  return result;
}

export function serializeDevice(device: DeviceInfo): Record<string, Object> {
  if (
    device.type !== DeviceType.LIGHT &&
    device.type !== DeviceType.ENVIRONMENT &&
    device.type !== DeviceType.AIR_CONDITIONER &&
    device.type !== DeviceType.DOOR_LOCK
  ) {
    return serializeGenericDevice(device as GenericDevice);
  }
  const raw: Record<string, Object> = {
    'id': device.id,
    'name': device.name,
    'roomId': device.roomId,
    'type': device.type,
    'online': device.online,
    'stateVersion': device.stateVersion,
    'updatedAt': device.updatedAt
  };
  if (device.type === DeviceType.LIGHT) {
    const light = device as LightDevice;
    raw['power'] = light.state.power;
    raw['brightness'] = light.state.brightness;
    raw['lastNonZeroBrightness'] = light.state.lastNonZeroBrightness;
    const automation: Record<string, Object> = {
      'enabled': light.state.automation.enabled,
      'illuminanceThresholdLux': light.state.automation.illuminanceThresholdLux,
      'noPresenceDelaySeconds': light.state.automation.noPresenceDelaySeconds
    };
    if (light.state.automation.manualOverrideUntil !== null) {
      automation['manualOverrideUntil'] = light.state.automation.manualOverrideUntil;
    }
    raw['automation'] = automation;
  } else if (device.type === DeviceType.ENVIRONMENT) {
    const environment = device as EnvironmentDevice;
    raw['temperatureCelsius'] = environment.state.temperatureCelsius;
    raw['humidityPercent'] = environment.state.humidityPercent;
    raw['illuminanceLux'] = environment.state.illuminanceLux;
    raw['presence'] = environment.state.presence;
    raw['dataValid'] = environment.state.dataValid;
  } else if (device.type === DeviceType.AIR_CONDITIONER) {
    const ac = device as AirConditionerDevice;
    raw['brand'] = ac.state.brand;
    raw['power'] = ac.state.power;
    raw['mode'] = ac.state.mode;
    raw['targetTemperatureCelsius'] = ac.state.targetTemperatureCelsius;
    raw['running'] = ac.state.running;
    raw['lastAdapterFrame'] = ac.state.lastAdapterFrame;
  } else {
    const door = device as DoorLockDevice;
    raw['locked'] = door.state.locked;
    raw['jammed'] = door.state.jammed;
    raw['batteryPercent'] = door.state.batteryPercent;
    raw['autoLockEnabled'] = door.state.autoLockEnabled;
    raw['autoLockDelaySeconds'] = door.state.autoLockDelaySeconds;
    if (door.state.autoLockAt !== null) {
      raw['autoLockAt'] = door.state.autoLockAt;
    }
  }
  return raw;
}
