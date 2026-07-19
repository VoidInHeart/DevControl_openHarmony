import {
  AirConditionerDevice,
  DeviceInfo,
  DeviceType,
  DoorLockDevice,
  EnvironmentDevice,
  LightDevice
} from './DeviceModel';
import {
  DeviceControl,
  DeviceControlKind,
  GenericDevice
} from './GenericDeviceModel';

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

/**
 * A home feature is a product-level grouping. It is intentionally separate
 * from rooms: locks belong in the full-home feature list but not in rooms.
 */
export class DeviceFeature {
  id: string = '';
  title: string = '';
  icon: string = '';
  deviceTypes: string[] = [];
  homeOnly: boolean = false;

  constructor(
    id: string,
    title: string,
    icon: string,
    deviceTypes: string[],
    homeOnly: boolean = false
  ) {
    this.id = id;
    this.title = title;
    this.icon = icon;
    this.deviceTypes = deviceTypes;
    this.homeOnly = homeOnly;
  }

  containsType(type: string): boolean {
    return this.deviceTypes.indexOf(type) >= 0;
  }
}

export class DeviceRegistry {
  private static readonly capabilities: DeviceCapability[] = [
    new DeviceCapability(DeviceType.LIGHT, '灯光', '○', [
      'setPower', 'setBrightness', 'setAutomationConfig'
    ]),
    new DeviceCapability(DeviceType.ENVIRONMENT, '环境', '≈', []),
    new DeviceCapability(DeviceType.AIR_CONDITIONER, '空调', '❄', [
      'setPower', 'setMode', 'setTemperature', 'setFanSpeed', 'setDehumidify', 'setBrand'
    ]),
    new DeviceCapability(DeviceType.DOOR_LOCK, '门锁', '🔒', [
      'lock', 'unlock', 'setAutoLockConfig'
    ])
  ];

  private static readonly homeFeatures: DeviceFeature[] = [
    new DeviceFeature('lighting', '灯光', '○', [DeviceType.LIGHT]),
    new DeviceFeature('environment', '环境', '≈', [
      DeviceType.ENVIRONMENT, DeviceType.AIR_CONDITIONER
    ]),
    new DeviceFeature('locks', '门锁', '🔒', [DeviceType.DOOR_LOCK], true)
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

  static supportsDeviceAction(device: DeviceInfo, action: string): boolean {
    const capability = DeviceRegistry.getCapability(device.type);
    if (capability !== null) {
      return capability.supports(action);
    }
    const generic = device as GenericDevice;
    for (let index = 0; index < generic.controls.length; index++) {
      if (generic.controls[index].action === action) {
        return true;
      }
    }
    return false;
  }

  static getHomeFeatures(devices: DeviceInfo[] = []): DeviceFeature[] {
    const result: DeviceFeature[] = [];
    for (let index = 0; index < DeviceRegistry.homeFeatures.length; index++) {
      result.push(DeviceRegistry.homeFeatures[index]);
    }
    for (let index = 0; index < devices.length; index++) {
      if (DeviceRegistry.getCapability(devices[index].type) !== null) {
        continue;
      }
      const category = (devices[index] as GenericDevice).category;
      let exists = false;
      for (let featureIndex = 0; featureIndex < result.length; featureIndex++) {
        if (result[featureIndex].id === category.id) {
          exists = true;
          break;
        }
      }
      if (!exists) {
        result.push(new DeviceFeature(
          category.id,
          category.title,
          category.icon,
          [],
          category.homeOnly
        ));
      }
    }
    return result;
  }

  static getFeature(
    featureId: string,
    devices: DeviceInfo[] = []
  ): DeviceFeature | null {
    const features = DeviceRegistry.getHomeFeatures(devices);
    for (let index = 0; index < features.length; index++) {
      const feature = features[index];
      if (feature.id === featureId) {
        return feature;
      }
    }
    return null;
  }

  static getDevicesByFeature(devices: DeviceInfo[], featureId: string): DeviceInfo[] {
    const feature = DeviceRegistry.getFeature(featureId, devices);
    if (feature === null) {
      return [];
    }
    const result: DeviceInfo[] = [];
    for (let index = 0; index < devices.length; index++) {
      const device = devices[index];
      let belongs = feature.containsType(device.type);
      if (DeviceRegistry.getCapability(device.type) === null) {
        belongs = (device as GenericDevice).category.id === featureId;
      }
      if (belongs) {
        result.push(device);
      }
    }
    return result;
  }

  static getRoomDevices(devices: DeviceInfo[], roomId: string): DeviceInfo[] {
    const result: DeviceInfo[] = [];
    for (let index = 0; index < devices.length; index++) {
      const device = devices[index];
      const feature = DeviceRegistry.featureForType(device.type);
      const genericHomeOnly = DeviceRegistry.getCapability(device.type) === null &&
        (device as GenericDevice).category.homeOnly;
      if (
        device.roomId === roomId &&
        !genericHomeOnly &&
        (feature === null || !feature.homeOnly)
      ) {
        result.push(device);
      }
    }
    return result;
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
      return '次卧';
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

  private static featureForType(type: string): DeviceFeature | null {
    for (let index = 0; index < DeviceRegistry.homeFeatures.length; index++) {
      const feature = DeviceRegistry.homeFeatures[index];
      if (feature.containsType(type)) {
        return feature;
      }
    }
    return null;
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
    if (capability === null) {
      const generic = device as GenericDevice;
      result.icon = generic.category.icon;
      let primary: DeviceControl | null = null;
      for (let index = 0; index < generic.controls.length; index++) {
        if (generic.controls[index].primary) {
          primary = generic.controls[index];
          break;
        }
      }
      result.summary = primary === null ? '\u8bbe\u5907\u5728\u7ebf' :
        primary.label + ' \u00b7 ' +
        DeviceRegistry.formatGenericValue(generic, primary);
      return result;
    }
    if (device.type === DeviceType.LIGHT) {
      const light = device as LightDevice;
      result.icon = light.state.power ? '●' : '○';
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
      result.icon = airConditioner.state.power ? '❄' : '○';
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

  private static formatGenericValue(
    device: GenericDevice,
    control: DeviceControl
  ): string {
    const value = device.state[control.stateKey];
    if (typeof value === 'boolean') {
      return value ? '\u5df2\u5f00\u542f' : '\u5df2\u5173\u95ed';
    }
    if (typeof value === 'number') {
      return value.toFixed(0) + control.unit;
    }
    if (typeof value === 'string') {
      if (control.kind === DeviceControlKind.ENUM) {
        for (let index = 0; index < control.options.length; index++) {
          if (control.options[index].value === value) {
            return control.options[index].label;
          }
        }
      }
      return value + control.unit;
    }
    return '--';
  }
}
