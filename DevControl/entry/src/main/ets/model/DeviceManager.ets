import { DeviceInfo, DeviceState, DeviceType, AccessLogEntry, AlertEntry, SceneRule } from './DeviceModel';
import native from 'libentry.so';

export class DeviceManager {
  devices: DeviceInfo[] = [];
  accessLogs: AccessLogEntry[] = [];
  alerts: AlertEntry[] = [];
  scenes: SceneRule[] = [];
  tlsConnected: boolean = false;
  private tickInterval: number = -1;

  init(): void {
    native.initDevices();
    this.refreshDeviceList();
    this.initScenes();
  }

  refreshDeviceList(): void {
    const jsonStr: string = native.listDevicesAsJson();
    const parsed: object[] = JSON.parse(jsonStr) as object[];
    const result: DeviceInfo[] = [];
    for (let i = 0; i < parsed.length; i++) {
      const raw: Record<string, Object> = parsed[i] as Record<string, Object>;
      const device = new DeviceInfo();
      device.id = raw['id'] as string;
      device.name = raw['name'] as string;
      device.type = raw['type'] as number;
      device.brand = raw['brand'] as string;
      const rawState = raw['state'] as Record<string, Object>;
      if (rawState !== undefined && rawState !== null) {
        device.state = this.parseDeviceState(rawState);
      }
      result.push(device);
    }
    this.devices = result;
  }

  private parseDeviceState(raw: Record<string, Object>): DeviceState {
    const state = new DeviceState();
    state.online = raw['online'] as boolean;
    state.isLocked = raw['isLocked'] as boolean;
    state.isOn = raw['isOn'] as boolean;
    state.brightness = raw['brightness'] as number;
    state.temperature = raw['temperature'] as number;
    state.humidity = raw['humidity'] as number;
    state.acPower = raw['acPower'] as boolean;
    state.acMode = raw['acMode'] as number;
    state.targetTemp = raw['targetTemp'] as number;
    state.targetHumidity = raw['targetHumidity'] as number;
    if (raw['batteryLevel'] !== undefined && raw['batteryLevel'] !== null) {
      state.batteryLevel = raw['batteryLevel'] as number;
    }
    return state;
  }

  sendCommand(deviceId: string, command: string, param: string): string {
    const result: string = native.simulateDevice(deviceId, command, param);
    this.addAccessLog(deviceId, command, result);
    this.refreshDeviceList();
    return result;
  }

  getDevicesByType(type: number): DeviceInfo[] {
    const result: DeviceInfo[] = [];
    for (let i = 0; i < this.devices.length; i++) {
      if (this.devices[i].type === type) {
        result.push(this.devices[i]);
      }
    }
    return result;
  }

  getDeviceById(id: string): DeviceInfo | null {
    for (let i = 0; i < this.devices.length; i++) {
      if (this.devices[i].id === id) {
        return this.devices[i];
      }
    }
    return null;
  }

  getOnlineCount(): number {
    let count = 0;
    for (let i = 0; i < this.devices.length; i++) {
      if (this.devices[i].state.online) {
        count++;
      }
    }
    return count;
  }

  getOfflineCount(): number {
    return this.devices.length - this.getOnlineCount();
  }

  tick(): void {
    native.tick();
    this.refreshDeviceList();
  }

  startTick(intervalMs: number): void {
    this.stopTick();
    this.tickInterval = setInterval(() => {
      this.tick();
    }, intervalMs) as number;
  }

  stopTick(): void {
    if (this.tickInterval !== -1) {
      clearInterval(this.tickInterval as number);
      this.tickInterval = -1;
    }
  }

  connectTLS(host: string, port: number): boolean {
    this.tlsConnected = native.tlsConnect(host, port);
    return this.tlsConnected;
  }

  sendTLS(data: string): string {
    return native.tlsSend(data);
  }

  closeTLS(): void {
    native.tlsClose();
    this.tlsConnected = false;
  }

  encryptData(data: string, key: string): string {
    return native.encryptData(data, key);
  }

  decryptData(data: string, key: string): string {
    return native.decryptData(data, key);
  }

  signData(data: string, key: string): string {
    return native.hmacSign(data, key);
  }

  addAccessLog(deviceId: string, action: string, result: string): void {
    const entry = new AccessLogEntry();
    const now = new Date();
    entry.time = now.getHours().toString().padStart(2, '0') + ':' +
      now.getMinutes().toString().padStart(2, '0') + ':' +
      now.getSeconds().toString().padStart(2, '0');
    entry.deviceId = deviceId;
    entry.action = action;
    entry.result = result.indexOf('"ok"') >= 0 ? 'success' : 'failed';
    this.accessLogs.unshift(entry);
    if (this.accessLogs.length > 50) {
      this.accessLogs.pop();
    }
  }

  addAlert(deviceId: string, level: string, message: string): void {
    const entry = new AlertEntry();
    const now = new Date();
    entry.time = now.getHours().toString().padStart(2, '0') + ':' +
      now.getMinutes().toString().padStart(2, '0') + ':' +
      now.getSeconds().toString().padStart(2, '0');
    entry.deviceId = deviceId;
    entry.level = level;
    entry.message = message;
    this.alerts.unshift(entry);
    if (this.alerts.length > 20) {
      this.alerts.pop();
    }
  }

  private initScenes(): void {
    const homeScene = new SceneRule();
    homeScene.id = 'scene_home';
    homeScene.name = 'Home';
    homeScene.enabled = true;
    homeScene.actions = ['light_001:turnOn', 'light_002:turnOn', 'door_001:unlock'];

    const awayScene = new SceneRule();
    awayScene.id = 'scene_away';
    awayScene.name = 'Away';
    awayScene.enabled = true;
    awayScene.actions = ['light_001:turnOff', 'light_002:turnOff', 'light_003:turnOff', 'door_001:lock', 'door_002:lock'];

    const sleepScene = new SceneRule();
    sleepScene.id = 'scene_sleep';
    sleepScene.name = 'Sleep';
    sleepScene.enabled = true;
    sleepScene.actions = ['light_001:turnOff', 'light_002:turnOff', 'light_003:turnOff', 'door_001:lock', 'ac_001:acPowerOn'];

    this.scenes = [homeScene, awayScene, sleepScene];
  }

  executeScene(sceneId: string): void {
    for (let i = 0; i < this.scenes.length; i++) {
      if (this.scenes[i].id === sceneId && this.scenes[i].enabled) {
        const actions = this.scenes[i].actions;
        for (let j = 0; j < actions.length; j++) {
          const parts = actions[j].split(':');
          if (parts.length >= 2) {
            this.sendCommand(parts[0], parts[1], '');
          }
        }
        break;
      }
    }
  }

  clearAlerts(): void {
    this.alerts = [];
  }

  clearAccessLogs(): void {
    this.accessLogs = [];
  }
}
