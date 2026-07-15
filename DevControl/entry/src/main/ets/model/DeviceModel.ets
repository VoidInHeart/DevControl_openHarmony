export class DeviceType {
  static readonly DOOR: number = 0;
  static readonly LIGHT: number = 1;
  static readonly SENSOR: number = 2;
  static readonly AC: number = 3;
}

export class ACMode {
  static readonly COOL: number = 0;
  static readonly HEAT: number = 1;
  static readonly FAN: number = 2;
  static readonly AUTO: number = 3;
}

export class DeviceState {
  online: boolean = true;
  isLocked: boolean = true;
  isOn: boolean = false;
  brightness: number = 0;
  temperature: number = 22;
  humidity: number = 55;
  acPower: boolean = false;
  acMode: number = ACMode.COOL;
  targetTemp: number = 26;
  targetHumidity: number = 50;
  batteryLevel: number = 100;
}

export class DeviceInfo {
  id: string = '';
  name: string = '';
  type: number = DeviceType.DOOR;
  brand: string = '';
  state: DeviceState = new DeviceState();
}

export class SceneRule {
  id: string = '';
  name: string = '';
  enabled: boolean = true;
  actions: string[] = [];
}

export class AccessLogEntry {
  time: string = '';
  deviceId: string = '';
  action: string = '';
  result: string = '';
}

export class AlertEntry {
  time: string = '';
  deviceId: string = '';
  level: string = '';
  message: string = '';
}
