import {
  AirConditionerDevice,
  DeviceInfo,
  DeviceType,
  DoorLockDevice,
  EnvironmentDevice,
  LightDevice
} from './DeviceModel';

/**
 * A device capability describes the UI and command affordances that a device
 * family exposes. New device families are registered here instead of being
 * scattered through overview and room pages.
 */
export class DeviceCapability {
  type: string = '';
  title: string = '';
  icon: string = '';
  actions: string[] = [];

  constructor(type: string, title: string, icon: string, actions: string[]) {
    this.type = type;
    this.title = title;
    this.icon = icon;
    this.actions = actions;
  }

  supports(action: string): boolean {
    return this.actions.indexOf(action) >= 0;
  }
}

export class DevicePresentation {
  icon: string = '';
  title: string = '';
  summary: string = '';
  online: boolean = false;
}

export class DeviceRegistry {
  private static readonly capabilities: DeviceCapability[] = [
    new DeviceCapability(DeviceType.LIGHT, '灯光', '💡', [
      'setPower', 'setBrightness', 'setAutomationConfig'
    ]),
    new DeviceCapability(DeviceType.ENVIRONMENT, '环境', '🌿', []),
    new DeviceCapability(DeviceType.AIR_CONDITIONER, '空调', '❄️', [
      'setPower', 'setMode', 'setTemperature', 'setBrand'
    ]),
    new DeviceCapability(DeviceType.DOOR_LOCK, '门锁', '🔒', [
      'lock', 'unlock', 'setAutoLockConfig'
    ])
  ];

  static getCapability(type: string): DeviceCapability | null {
    for (let index = 0; index < DeviceRegistry.capabilities.length; index++) {
      const capability = DeviceRegistry.capabilities[index];
      if (capability.type === type) {
        return capability;
      }
    }
    return null;
  }

  static supportsAction(type: string, action: string): boolean {
    const capability = DeviceRegistry.getCapability(type);
    return capability !== null && capability.supports(action);
  }

  static getRoomIds(devices: DeviceInfo[]): string[] {
    const result: string[] = [];
    for (let index = 0; index < devices.length; index++) {
      const roomId = devices[index].roomId;
      if (roomId.length > 0 && result.indexOf(roomId) < 0) {
        result.push(roomId);
      }
    }
    return result;
  }

  static getRoomLabel(roomId: string): string {
    if (roomId === 'living') {
      return '客厅';
    }
    if (roomId === 'bedroom') {
      return '卧室';
    }
    if (roomId === 'masterBedroom') {
      return '主卧';
    }
    if (roomId === 'bathroom') {
      return '浴室';
    }
    if (roomId === 'kitchen') {
      return '厨房';
    }
    return roomId;
  }

  static present(device: DeviceInfo): DevicePresentation {
    const result = new DevicePresentation();
    const capability = DeviceRegistry.getCapability(device.type);
    result.icon = capability === null ? '◈' : capability.icon;
    result.title = device.name;
    result.online = device.online;
    if (!device.online) {
      result.summary = '设备离线';
      return result;
    }
    if (device.type === DeviceType.LIGHT) {
      const light = device as LightDevice;
      result.icon = light.state.power ? '💡' : '○';
      result.summary = light.state.power ?
        '已开启 · ' + light.state.brightness.toFixed(0) + '%' : '已关闭';
      return result;
    }
    if (device.type === DeviceType.ENVIRONMENT) {
      const environment = device as EnvironmentDevice;
      result.summary = environment.state.temperatureCelsius.toFixed(1) + '°C · ' +
        environment.state.humidityPercent.toFixed(0) + '%';
      return result;
    }
    if (device.type === DeviceType.AIR_CONDITIONER) {
      const airConditioner = device as AirConditionerDevice;
      result.icon = airConditioner.state.power ? '❄️' : '○';
      result.summary = airConditioner.state.power ?
        airConditioner.state.mode + ' · ' +
        airConditioner.state.targetTemperatureCelsius.toFixed(0) + '°C' : '已关闭';
      return result;
    }
    const doorLock = device as DoorLockDevice;
    result.icon = doorLock.state.locked ? '🔒' : '🔓';
    result.summary = doorLock.state.jammed ? '锁体异常' :
      (doorLock.state.locked ? '已上锁' : '已解锁');
    return result;
  }
}
