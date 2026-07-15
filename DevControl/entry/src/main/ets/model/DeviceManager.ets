import { DeviceInfo, DeviceState, DeviceType, AccessLogEntry, AlertEntry, SceneRule, ACMode } from './DeviceModel';
import { ConnectionState, GatewayConnectionConfig } from './GatewayModels';
import { WssGatewayTransport } from '../infrastructure/WssGatewayTransport';
import { Constants } from '../common/Constants';
import native from 'libentry.so';

@Observed
export class DeviceManager {
  devices: DeviceInfo[] = [];
  accessLogs: AccessLogEntry[] = [];
  alerts: AlertEntry[] = [];
  scenes: SceneRule[] = [];
  connectionState: string = ConnectionState.DISCONNECTED;
  connectionMessage: string = '尚未连接网关';
  gatewayEndpoint: string = Constants.DEFAULT_GATEWAY_ENDPOINT;
  lastMessageAt: number = 0;
  usingCachedSnapshot: boolean = false;
  private tickInterval: number = -1;
  private reconnecting: boolean = false;
  private reconnectAttempt: number = 0;
  private reconnectTimer: number = -1;
  private sessionDataKey: string = '';
  private transport: WssGatewayTransport = new WssGatewayTransport();
  private pendingCommands: Map<string, string> = new Map<string, string>();

  init(): void {
    this.initScenes();
    this.transport.subscribe((rawMessage: string) => {
      this.handleGatewayMessage(rawMessage);
    });
    this.transport.subscribeState((state: string, message: string) => {
      this.connectionState = state;
      this.connectionMessage = message;
      if (state !== ConnectionState.ONLINE && this.devices.length > 0) {
        this.usingCachedSnapshot = true;
      }
      if (state === ConnectionState.DISCONNECTED) {
        this.beginReconnect();
      }
    });
  }

  async pairAndConnect(endpoint: string, pairingCode: string): Promise<boolean> {
    const normalized = this.normalizeEndpoint(endpoint);
    if (normalized.length === 0 || pairingCode.trim().length !== 6) {
      this.connectionMessage = '请输入有效的 HTTPS 地址和 6 位配对码';
      return false;
    }
    this.gatewayEndpoint = normalized;
    this.connectionState = ConnectionState.CONNECTING;
    this.connectionMessage = '正在检查网关';
    const config = new GatewayConnectionConfig();
    config.httpsEndpoint = normalized;
    config.wssEndpoint = this.toWebSocketEndpoint(normalized);
    config.connectTimeoutMs = 10000;
    this.transport.configure(config);

    try {
      const healthy = await this.transport.checkHealth();
      if (!healthy) {
        throw new Error('网关协议版本不兼容');
      }
      this.connectionState = ConnectionState.AUTHENTICATING;
      this.connectionMessage = '正在安全配对';
      const clientId = 'oh-' + native.createMessageId();
      const pairing = await this.transport.pair(pairingCode.trim(), clientId);
      this.sessionDataKey = pairing.dataKey;
      const snapshot = await this.transport.fetchDeviceSnapshot();
      this.applySnapshot(snapshot);
      await this.transport.connect();
      this.connectionState = ConnectionState.ONLINE;
      this.connectionMessage = '网关在线';
      this.lastMessageAt = Date.now();
      this.usingCachedSnapshot = false;
      this.reconnectAttempt = 0;
      return true;
    } catch (error) {
      this.connectionState = ConnectionState.DISCONNECTED;
      this.connectionMessage = this.errorText(error);
      this.usingCachedSnapshot = this.devices.length > 0;
      return false;
    }
  }

  sendCommand(deviceId: string, command: string, param: string): void {
    this.dispatchCommand(deviceId, command, param);
  }

  getDevicesByType(type: number): DeviceInfo[] {
    const result: DeviceInfo[] = [];
    for (let index = 0; index < this.devices.length; index++) {
      if (this.devices[index].type === type) {
        result.push(this.devices[index]);
      }
    }
    return result;
  }

  getDeviceById(id: string): DeviceInfo | null {
    for (let index = 0; index < this.devices.length; index++) {
      if (this.devices[index].id === id) {
        return this.devices[index];
      }
    }
    return null;
  }

  getOnlineCount(): number {
    let count = 0;
    for (let index = 0; index < this.devices.length; index++) {
      if (this.devices[index].state.online) {
        count++;
      }
    }
    return count;
  }

  getOfflineCount(): number {
    return this.devices.length - this.getOnlineCount();
  }

  isOnline(): boolean {
    return this.connectionState === ConnectionState.ONLINE;
  }

  startTick(intervalMs: number): void {
    this.stopTick();
    this.tickInterval = setInterval(() => {
      this.monitorConnection();
    }, intervalMs) as number;
  }

  stopTick(): void {
    if (this.tickInterval !== -1) {
      clearInterval(this.tickInterval);
      this.tickInterval = -1;
    }
  }

  close(): void {
    this.stopTick();
    if (this.reconnectTimer !== -1) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = -1;
    }
    this.transport.close();
    this.sessionDataKey = '';
  }

  addAccessLog(deviceId: string, action: string, result: string, reason: string = ''): void {
    const entry = new AccessLogEntry();
    entry.time = this.currentTimeText();
    entry.deviceId = deviceId;
    entry.action = action;
    entry.result = result;
    entry.reason = reason;
    this.accessLogs.unshift(entry);
    if (this.accessLogs.length > 50) {
      this.accessLogs.pop();
    }
    this.accessLogs = this.accessLogs.slice();
  }

  addAlert(deviceId: string, level: string, message: string): void {
    const entry = new AlertEntry();
    entry.time = this.currentTimeText();
    entry.deviceId = deviceId;
    entry.level = level;
    entry.message = message;
    this.alerts.unshift(entry);
    if (this.alerts.length > 20) {
      this.alerts.pop();
    }
    this.alerts = this.alerts.slice();
  }

  executeScene(sceneId: string): void {
    if (sceneId === 'scene_away') {
      this.dispatchCommand('gateway', 'executeAway', '');
    }
  }

  configureLightingAutomation(enabled: boolean, illuminanceThreshold: number, noPresenceDelaySeconds: number): void {
    const lights = this.getDevicesByType(DeviceType.LIGHT);
    const parameter = (enabled ? '1' : '0') + ',' + illuminanceThreshold.toFixed(0) + ',' +
      noPresenceDelaySeconds.toFixed(0);
    for (let index = 0; index < lights.length; index++) {
      this.dispatchCommand(lights[index].id, 'setAutomation', parameter);
    }
  }

  clearAlerts(): void {
    this.alerts = [];
  }

  clearAccessLogs(): void {
    this.accessLogs = [];
  }

  private async dispatchCommand(deviceId: string, action: string, param: string): Promise<void> {
    if (!this.isOnline()) {
      this.addAccessLog(deviceId, action, 'failed', '网关离线');
      this.connectionMessage = '网关离线，控制命令未发送';
      return;
    }
    const device = this.getDeviceById(deviceId);
    const expectedVersion = device === null ? -1 : device.stateVersion;
    const payload = this.buildPayload(action, param);
    try {
      if (this.sessionDataKey.length === 0) {
        throw new Error('安全会话密钥不可用，请重新配对');
      }
      const envelope = native.buildSecureCommandEnvelope(
        deviceId, action, payload, this.sessionDataKey, expectedVersion);
      const parsed = JSON.parse(envelope) as Record<string, Object>;
      const messageId = parsed['messageId'] as string;
      this.pendingCommands.set(messageId, deviceId);
      if (device !== null) {
        device.pendingAction = action;
        device.lastError = '';
        this.devices = this.devices.slice();
      }
      await this.transport.sendCommand(envelope);
      setTimeout(() => {
        this.handleCommandTimeout(messageId, deviceId, action);
      }, Constants.COMMAND_TIMEOUT_MS);
    } catch (error) {
      const reason = this.errorText(error);
      this.addAccessLog(deviceId, action, 'failed', reason);
      if (device !== null) {
        device.pendingAction = '';
        device.lastError = reason;
        this.devices = this.devices.slice();
      }
    }
  }

  private handleGatewayMessage(raw: string): void {
    const validationError = native.validateGatewayMessage(raw, Constants.MESSAGE_CLOCK_SKEW_MS);
    if (validationError.length > 0) {
      this.addAlert('gateway', 'warning', '已丢弃无效网关消息：' + validationError);
      return;
    }
    this.lastMessageAt = Date.now();
    const message = JSON.parse(raw) as Record<string, Object>;
    const type = message['type'] as string;
    if (type === 'heartbeat') {
      return;
    }
    if (type === 'snapshot') {
      this.applySnapshot(raw);
      return;
    }
    if (type === 'state.changed') {
      this.applyStateChanged(message);
      return;
    }
    if (type === 'command.result') {
      this.applyCommandResult(message);
      return;
    }
    if (type === 'alert.raised') {
      const deviceId = message['deviceId'] as string;
      const severity = message['severity'] as string;
      const description = message['description'] as string;
      this.addAlert(deviceId, severity, description);
    }
  }

  private applySnapshot(raw: string): void {
    const root = JSON.parse(raw) as Record<string, Object>;
    const rawDevices = root['devices'] as object[];
    const devices: DeviceInfo[] = [];
    for (let index = 0; index < rawDevices.length; index++) {
      devices.push(this.parseDevice(rawDevices[index] as Record<string, Object>));
    }
    this.devices = devices;
    this.usingCachedSnapshot = false;
  }

  private applyStateChanged(message: Record<string, Object>): void {
    const rawDevice = message['device'] as Record<string, Object>;
    const updated = this.parseDevice(rawDevice);
    let found = false;
    for (let index = 0; index < this.devices.length; index++) {
      if (this.devices[index].id === updated.id) {
        if (updated.stateVersion >= this.devices[index].stateVersion) {
          updated.pendingAction = '';
          this.devices[index] = updated;
        }
        found = true;
        break;
      }
    }
    if (!found) {
      this.devices.push(updated);
    }
    this.devices = this.devices.slice();
  }

  private applyCommandResult(message: Record<string, Object>): void {
    const messageId = message['messageId'] as string;
    const deviceId = message['deviceId'] as string;
    const success = message['success'] as boolean;
    const action = message['action'] as string;
    const errorMessage = message['errorMessage'] as string;
    this.pendingCommands.delete(messageId);
    const device = this.getDeviceById(deviceId);
    if (device !== null) {
      device.pendingAction = '';
      device.lastError = success ? '' : errorMessage;
      this.devices = this.devices.slice();
    }
    this.addAccessLog(deviceId, action, success ? 'success' : 'failed', success ? '' : errorMessage);
  }

  private parseDevice(raw: Record<string, Object>): DeviceInfo {
    const device = new DeviceInfo();
    device.id = raw['id'] as string;
    device.name = raw['name'] as string;
    device.roomId = raw['roomId'] as string;
    device.type = this.parseDeviceType(raw['type'] as string);
    device.brand = raw['brand'] as string;
    device.stateVersion = raw['stateVersion'] as number;
    device.updatedAt = raw['updatedAt'] as number;
    device.state = this.parseDeviceState(raw['state'] as Record<string, Object>, device.type);
    device.state.online = raw['online'] as boolean;
    return device;
  }

  private parseDeviceState(raw: Record<string, Object>, type: number): DeviceState {
    const state = new DeviceState();
    if (type === DeviceType.DOOR) {
      state.status = raw['status'] as string;
      state.isLocked = state.status === 'locked';
      state.batteryLevel = raw['batteryPercent'] as number;
      state.autoLockAt = this.numberOrZero(raw['autoLockAt']);
    } else if (type === DeviceType.LIGHT) {
      state.isOn = raw['power'] as boolean;
      state.brightness = raw['brightness'] as number;
      state.automationEnabled = raw['automationEnabled'] as boolean;
      state.manualOverrideUntil = this.numberOrZero(raw['manualOverrideUntil']);
    } else if (type === DeviceType.SENSOR) {
      state.temperature = raw['temperatureCelsius'] as number;
      state.humidity = raw['humidityPercent'] as number;
      state.presence = raw['presence'] as boolean;
      state.illuminanceLux = raw['illuminanceLux'] as number;
    } else if (type === DeviceType.AC) {
      state.acPower = raw['power'] as boolean;
      state.acMode = this.parseAcMode(raw['mode'] as string);
      state.targetTemp = raw['targetTemperatureCelsius'] as number;
      state.running = raw['running'] as boolean;
    }
    return state;
  }

  private parseDeviceType(type: string): number {
    if (type === 'light') {
      return DeviceType.LIGHT;
    }
    if (type === 'environment') {
      return DeviceType.SENSOR;
    }
    if (type === 'airConditioner') {
      return DeviceType.AC;
    }
    return DeviceType.DOOR;
  }

  private parseAcMode(mode: string): number {
    if (mode === 'heat') {
      return ACMode.HEAT;
    }
    if (mode === 'fan') {
      return ACMode.FAN;
    }
    if (mode === 'auto') {
      return ACMode.AUTO;
    }
    if (mode === 'dry') {
      return ACMode.DRY;
    }
    return ACMode.COOL;
  }

  private buildPayload(action: string, param: string): string {
    if (action === 'setBrightness') {
      return '{"brightness":' + this.safeNumber(param, 0).toString() + '}';
    }
    if (action === 'setTargetTemp') {
      return '{"temperatureCelsius":' + this.safeNumber(param, 26).toString() + '}';
    }
    if (action === 'setACMode') {
      return '{"mode":"' + this.modeName(this.safeNumber(param, 0)) + '"}';
    }
    if (action === 'setAutomation') {
      const parts = param.split(',');
      if (parts.length === 3) {
        return '{"enabled":' + (parts[0] === '1' ? 'true' : 'false') +
          ',"illuminanceThresholdLux":' + this.safeNumber(parts[1], 100).toString() +
          ',"noPresenceDelaySeconds":' + this.safeNumber(parts[2], 60).toString() + '}';
      }
    }
    return '{}';
  }

  private safeNumber(value: string, fallback: number): number {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : fallback;
  }

  private modeName(mode: number): string {
    if (mode === ACMode.HEAT) {
      return 'heat';
    }
    if (mode === ACMode.FAN) {
      return 'fan';
    }
    if (mode === ACMode.AUTO) {
      return 'auto';
    }
    if (mode === ACMode.DRY) {
      return 'dry';
    }
    return 'cool';
  }

  private numberOrZero(value: Object): number {
    if (value === undefined || value === null) {
      return 0;
    }
    return value as number;
  }

  private handleCommandTimeout(messageId: string, deviceId: string, action: string): void {
    if (!this.pendingCommands.has(messageId)) {
      return;
    }
    this.pendingCommands.delete(messageId);
    const device = this.getDeviceById(deviceId);
    if (device !== null) {
      device.pendingAction = '';
      device.lastError = 'COMMAND_TIMEOUT';
      this.devices = this.devices.slice();
    }
    this.addAccessLog(deviceId, action, 'failed', 'COMMAND_TIMEOUT');
  }

  private monitorConnection(): void {
    if (!this.isOnline() || this.reconnecting || this.lastMessageAt === 0) {
      return;
    }
    if (Date.now() - this.lastMessageAt <= Constants.HEARTBEAT_TIMEOUT_MS) {
      return;
    }
    this.connectionState = ConnectionState.DISCONNECTED;
    this.connectionMessage = '心跳超时，准备重连';
    this.usingCachedSnapshot = this.devices.length > 0;
    this.beginReconnect();
  }

  private beginReconnect(): void {
    if (this.reconnecting || this.reconnectTimer !== -1 || this.sessionDataKey.length === 0 ||
      this.connectionState === ConnectionState.CLOSED) {
      return;
    }
    const delays: number[] = [1000, 2000, 4000, 8000, 10000];
    const delayIndex = Math.min(this.reconnectAttempt, delays.length - 1);
    const delay = delays[delayIndex];
    this.reconnectAttempt++;
    this.connectionState = ConnectionState.RECONNECTING;
    this.connectionMessage = (delay / 1000).toFixed(0) + ' 秒后重连';
    this.reconnectTimer = setTimeout(() => {
      this.reconnectTimer = -1;
      this.performReconnect();
    }, delay) as number;
  }

  private performReconnect(): void {
    this.reconnecting = true;
    this.transport.reconnect().then(() => {
      return this.transport.fetchDeviceSnapshot();
    }).then((snapshot: string) => {
      this.applySnapshot(snapshot);
      this.reconnecting = false;
      this.reconnectAttempt = 0;
      this.connectionState = ConnectionState.ONLINE;
      this.connectionMessage = '网关已恢复连接';
      this.lastMessageAt = Date.now();
      this.usingCachedSnapshot = false;
    }).catch((error: Error) => {
      this.reconnecting = false;
      this.connectionState = ConnectionState.DISCONNECTED;
      this.connectionMessage = this.errorText(error);
      this.beginReconnect();
    });
  }

  private initScenes(): void {
    const awayScene = new SceneRule();
    awayScene.id = 'scene_away';
    awayScene.name = '离家模式';
    awayScene.enabled = true;
    awayScene.actions = [];
    this.scenes = [awayScene];
  }

  private normalizeEndpoint(endpoint: string): string {
    let normalized = endpoint.trim();
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    if (!normalized.startsWith('https://')) {
      return '';
    }
    return normalized;
  }

  private toWebSocketEndpoint(endpoint: string): string {
    return 'wss://' + endpoint.substring('https://'.length) + '/ws/v1/events';
  }

  private currentTimeText(): string {
    const now = new Date();
    return now.getHours().toString().padStart(2, '0') + ':' +
      now.getMinutes().toString().padStart(2, '0') + ':' +
      now.getSeconds().toString().padStart(2, '0');
  }

  private errorText(error: Object): string {
    const typed = error as Error;
    if (typed.message !== undefined && typed.message.length > 0) {
      return typed.message;
    }
    return '网关操作失败';
  }
}
