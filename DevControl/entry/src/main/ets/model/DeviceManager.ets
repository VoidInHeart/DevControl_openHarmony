import { common } from '@kit.AbilityKit';
import native from 'libentry.so';
import {
  AccessLogEntry,
  ACFanSpeed,
  ACMode,
  AirConditionerDevice,
  AlertEntry,
  CommandPayload,
  ConnectionState,
  DeviceInfo,
  DeviceType,
  DoorLockDevice,
  EnvironmentDevice,
  EnvironmentHistoryPoint,
  GatewaySession,
  LightDevice,
  parseDevice,
  SceneDeviceAction,
  SceneExecutionDetail
} from './DeviceModel';
import { GatewayTransport, GatewayTransportListener } from '../service/GatewayTransport';
import { DemoCertificateStore } from '../service/DemoCertificateStore';
import { DeviceSnapshotStore } from '../service/DeviceSnapshotStore';
import { GatewaySessionStore } from '../service/GatewaySessionStore';
import { PairingPreferenceStore } from '../service/PairingPreferenceStore';
import { WssGatewayTransport } from '../service/WssGatewayTransport';
import {
  DeviceRemovalResult,
  DeviceRegistrationRequest,
  DeviceRegistrationResult
} from '../service/DeviceRegistration';
import { DeviceRegistry } from './DeviceRegistry';
import {
  DeviceControl,
  DeviceControlKind,
  GenericDevice
} from './GenericDeviceModel';

@Observed
export class DeviceManager implements GatewayTransportListener {
  devices: DeviceInfo[] = [];
  deviceStateRevision: number = 0;
  accessLogs: AccessLogEntry[] = [];
  alerts: AlertEntry[] = [];
  environmentHistory: EnvironmentHistoryPoint[] = [];
  sceneResults: SceneExecutionDetail[] = [];
  connectionState: string = ConnectionState.DISCONNECTED;
  pairingRequired: boolean = true;
  initialized: boolean = false;
  pairingBusy: boolean = false;
  gatewayAddress: string = '';
  lastGatewayAddress: string = '';
  lastError: string = '';
  lastErrorCode: string = '';
  lastSyncAt: number = 0;
  lastHeartbeatAt: number = 0;
  pendingDeviceIds: string[] = [];

  private transport: GatewayTransport;
  private sessionStore: GatewaySessionStore | null = null;
  private snapshotStore: DeviceSnapshotStore | null = null;
  private pairingPreferenceStore: PairingPreferenceStore | null = null;
  private session: GatewaySession | null = null;
  private pendingByMessage: Map<string, string> = new Map<string, string>();
  private actionByMessage: Map<string, string> = new Map<string, string>();
  private timeoutByMessage: Map<string, number> = new Map<string, number>();

  constructor(transport: GatewayTransport = new WssGatewayTransport()) {
    this.transport = transport;
  }

  async initialize(context: common.UIAbilityContext): Promise<void> {
    if (this.initialized) {
      return;
    }
    this.initialized = true;
    this.sessionStore = new GatewaySessionStore(context);
    this.snapshotStore = new DeviceSnapshotStore(context);
    this.pairingPreferenceStore = new PairingPreferenceStore(context);
    try {
      const rememberedAddress = await this.pairingPreferenceStore.restoreGatewayAddress();
      if (rememberedAddress.length > 0) {
        this.lastGatewayAddress = rememberedAddress;
        this.gatewayAddress = rememberedAddress;
      }
    } catch (preferenceError) {
    }
    try {
      const caPath = await DemoCertificateStore.prepare(context);
      this.transport.setCertificateAuthorityPath(caPath);
      const cached = await this.snapshotStore.restore();
      if (cached !== null) {
        this.devices = cached.devices;
        this.bumpDeviceStateRevision();
        this.lastSyncAt = cached.lastSyncAt;
      }
      const restored = await this.sessionStore.restore();
      if (restored === null) {
        this.pairingRequired = true;
        this.connectionState = ConnectionState.DISCONNECTED;
        return;
      }
      this.session = restored;
      this.gatewayAddress = restored.gatewayAddress;
      this.lastGatewayAddress = restored.gatewayAddress;
      this.pairingRequired = false;
      this.transport.configure(restored);
      await this.connectAndSync();
    } catch (error) {
      this.connectionState = ConnectionState.DISCONNECTED;
      this.setErrorFromException(error);
      if (this.session === null || this.lastErrorCode === 'AUTH_FAILED') {
        this.pairingRequired = true;
        this.setError('AUTH_FAILED', '安全会话恢复失败，请重新配对');
      } else {
        this.pairingRequired = true;
      }
    }
  }

  async pairGateway(address: string, pairingCode: string): Promise<boolean> {
    const normalized = address.trim().replace(/\/+$/, '');
    if (normalized.indexOf('https://') !== 0) {
      this.setError('INVALID_COMMAND', '网关地址必须以 https:// 开头');
      return false;
    }
    this.gatewayAddress = normalized;
    this.lastGatewayAddress = normalized;
    if (this.pairingPreferenceStore !== null) {
      try {
        await this.pairingPreferenceStore.saveGatewayAddress(normalized);
      } catch (preferenceError) {
      }
    }
    if (!/^\d{6}$/.test(pairingCode.trim())) {
      this.setError('INVALID_COMMAND', '配对码必须是6位数字');
      return false;
    }
    if (this.sessionStore === null) {
      this.setError('INTERNAL_ERROR', '会话存储尚未初始化');
      return false;
    }
    this.pairingBusy = true;
    this.lastError = '';
    this.connectionState = ConnectionState.AUTHENTICATING;
    try {
      const healthy = await this.transport.checkHealth(normalized);
      if (!healthy) {
        throw new Error('网关协议版本不兼容');
      }
      const clientId = 'harmony-' + native.generateMessageId();
      const newSession = await this.transport.pair(normalized, pairingCode.trim(), clientId);
      await this.sessionStore.save(newSession);
      this.session = newSession;
      this.gatewayAddress = newSession.gatewayAddress;
      this.lastGatewayAddress = newSession.gatewayAddress;
      this.transport.configure(newSession);
      this.pairingRequired = false;
      await this.connectAndSync();
      return true;
    } catch (error) {
      this.connectionState = ConnectionState.DISCONNECTED;
      this.pairingRequired = true;
      this.setErrorFromException(error);
      return false;
    } finally {
      this.pairingBusy = false;
    }
  }

  async reconnect(): Promise<void> {
    if (this.session === null) {
      this.pairingRequired = true;
      return;
    }
    try {
      await this.transport.reconnect();
      await this.refreshAll();
    } catch (error) {
      this.setErrorFromException(error);
    }
  }

  async forgetGateway(): Promise<void> {
    await this.transport.close();
    if (this.sessionStore !== null) {
      await this.sessionStore.clear();
    }
    if (this.snapshotStore !== null) {
      await this.snapshotStore.clear();
    }
    this.session = null;
    this.devices = [];
    this.bumpDeviceStateRevision();
    this.accessLogs = [];
    this.alerts = [];
    this.environmentHistory = [];
    this.sceneResults = [];
    this.pendingDeviceIds = [];
    this.pairingRequired = true;
    this.gatewayAddress = this.lastGatewayAddress;
    this.connectionState = ConnectionState.DISCONNECTED;
    this.lastError = '';
  }

  async shutdown(): Promise<void> {
    await this.transport.close();
    this.clearAllCommandTimeouts();
  }

  onConnectionStateChanged(state: string): void {
    this.connectionState = state;
    if (state === ConnectionState.ONLINE) {
      this.pairingRequired = false;
      this.lastHeartbeatAt = Date.now();
      this.refreshAll().catch((error: Error) => {
        this.setErrorFromException(error);
      });
    } else if (state === ConnectionState.DISCONNECTED) {
      this.pairingRequired = true;
      this.clearAllCommandTimeouts();
    }
  }

  onGatewayMessage(message: Record<string, Object>): void {
    const type = message['type'] as string;
    this.lastHeartbeatAt = Date.now();
    if (type === 'heartbeat') {
      return;
    }
    if (type === 'state.changed') {
      const rawDevice = message['device'] as Record<string, Object>;
      if (rawDevice !== undefined && rawDevice !== null) {
        try {
          this.applyDevice(parseDevice(rawDevice));
        } catch (error) {
          this.setError('INVALID_COMMAND', '网关设备状态字段校验失败');
        }
      }
      return;
    }
    if (type === 'device.removed') {
      const deviceId = message['deviceId'];
      if (typeof deviceId === 'string') {
        this.devices = this.devices.filter((device: DeviceInfo) => device.id !== deviceId);
        this.bumpDeviceStateRevision();
      }
      return;
    }
    if (type === 'command.result') {
      this.handleCommandResult(message);
      return;
    }
    if (type === 'alert.raised') {
      this.handleAlert(message);
    }
  }

  onTransportError(code: string, message: string): void {
    if (code === 'AUTH_FAILED') {
      this.invalidateSession(message);
      return;
    }
    this.setError(code, message);
  }

  async refreshAll(): Promise<boolean> {
    if (this.session === null) {
      return false;
    }
    try {
      const snapshot = await this.transport.fetchDeviceSnapshot();
      this.devices = snapshot;
      this.bumpDeviceStateRevision();
      this.lastSyncAt = Date.now();
      if (this.snapshotStore !== null) {
        try {
          await this.snapshotStore.save(this.devices, this.lastSyncAt);
        } catch (cacheError) {
        }
      }
      this.lastError = '';
      await this.refreshLogs();
      await this.refreshEnvironmentHistory();
      return true;
    } catch (error) {
      this.setErrorFromException(error);
      if (this.lastErrorCode === 'AUTH_FAILED') {
        this.invalidateSession(this.lastError);
      }
      return false;
    }
  }

  /**
   * The gateway verifies the signed QR proof, registers the device and probes
   * every requested capability. The App then verifies the authenticated
   * snapshot before presenting registration as successful.
   */
  async registerDevice(request: DeviceRegistrationRequest): Promise<DeviceRegistrationResult> {
    const result = new DeviceRegistrationResult();
    if (!this.isOnline()) {
      result.message = '网关离线，无法验证并注册设备';
      return result;
    }
    try {
      const receipt = await this.transport.registerDevice(request);
      if (!receipt.accepted) {
        result.message = '网关未接受该设备的认证信息';
        return result;
      }
      if (!receipt.online) {
        result.message = '设备已认证，但未通过网关在线探测';
        return result;
      }
      const snapshotSynchronized = await this.refreshAll();
      if (!snapshotSynchronized) {
        result.message = '网关注册成功，但设备快照同步失败';
        return result;
      }
      const device = this.getDeviceById(request.deviceId);
      if (device === null || !device.online) {
        result.message = '网关尚未同步到在线设备，请稍后重试';
        return result;
      }
      if (device.name !== request.deviceName) {
        result.message = '网关返回的设备名称与二维码不一致';
        return result;
      }
      if (device.roomId !== request.roomId) {
        result.message = '网关返回的所属房间与所选房间不一致';
        return result;
      }
      if (device.type !== request.deviceType) {
        result.message = '网关返回的设备类型与二维码不一致';
        return result;
      }
      if (!this.matchesRegistrationCategory(device, request.categoryId)) {
        result.message = '网关返回的设备分类与二维码不一致';
        return result;
      }
      if (!this.matchesRegistrationCapabilities(device, request.capabilities)) {
        result.message = '设备未通过全部能力接口校验';
        return result;
      }
      result.registered = true;
      result.online = true;
      result.message = '设备已注册并通过网关在线校验';
      return result;
    } catch (error) {
      const registrationFailure = this.registrationFailureMessage(error);
      if (registrationFailure.length > 0) {
        this.setError('DEVICE_PROOF_INVALID', registrationFailure);
        result.message = registrationFailure;
        return result;
      }
      this.setErrorFromException(error);
      result.message = this.lastError.length > 0 ? this.lastError : '设备注册失败';
      return result;
    }
  }

  async deleteDevice(deviceId: string): Promise<DeviceRemovalResult> {
    const result = new DeviceRemovalResult();
    const device = this.getDeviceById(deviceId);
    if (device === null) {
      result.message = '设备不存在或已被移除';
      return result;
    }
    if (!device.removable) {
      result.message = '该内置设备不支持移除';
      return result;
    }
    if (!this.isOnline()) {
      result.message = '网关离线，无法移除设备';
      return result;
    }
    try {
      const receipt = await this.transport.deleteDevice(deviceId);
      if (!receipt.deleted) {
        result.message = '网关未移除该设备';
        return result;
      }
      const snapshotSynchronized = await this.refreshAll();
      if (!snapshotSynchronized) {
        result.message = '网关已移除设备，但设备快照同步失败';
        return result;
      }
      if (this.getDeviceById(deviceId) !== null) {
        result.message = '网关快照中仍存在该设备';
        return result;
      }
      result.deleted = true;
      result.message = '设备已移除';
      return result;
    } catch (error) {
      this.setErrorFromException(error);
      result.message = this.lastError.length > 0 ? this.lastError : '设备移除失败';
      return result;
    }
  }

  async refreshLogs(): Promise<void> {
    try {
      const raw = await this.transport.fetchLogs(50);
      const result: AccessLogEntry[] = [];
      for (let index = 0; index < raw.length; index++) {
        const item = new AccessLogEntry();
        item.time = this.formatTime(raw[index]['timestamp'] as number);
        item.deviceId = raw[index]['deviceId'] as string;
        item.action = raw[index]['action'] as string;
        item.result = raw[index]['result'] as string;
        const errorCode = raw[index]['errorCode'];
        item.errorCode = typeof errorCode === 'string' ? errorCode : '';
        const messageIdSuffix = raw[index]['messageIdSuffix'];
        item.messageIdSuffix =
          typeof messageIdSuffix === 'string' ? messageIdSuffix : '';
        result.push(item);
      }
      this.accessLogs = result;
      const rawAlerts = await this.transport.fetchAlerts(20);
      const alerts: AlertEntry[] = [];
      for (let index = 0; index < rawAlerts.length; index++) {
        const alert = new AlertEntry();
        alert.time = this.formatTime(rawAlerts[index]['timestamp'] as number);
        alert.deviceId = rawAlerts[index]['deviceId'] as string;
        alert.level = rawAlerts[index]['severity'] as string;
        alert.code = rawAlerts[index]['code'] as string;
        alert.message = rawAlerts[index]['description'] as string;
        alerts.push(alert);
      }
      this.alerts = alerts;
    } catch (error) {
    }
  }

  async refreshEnvironmentHistory(): Promise<void> {
    try {
      this.environmentHistory = await this.transport.fetchEnvironmentHistory(
        Date.now() - 24 * 60 * 60 * 1000
      );
    } catch (error) {
    }
  }

  getDevicesByType(type: string): DeviceInfo[] {
    const result: DeviceInfo[] = [];
    for (let index = 0; index < this.devices.length; index++) {
      if (this.devices[index].type === type) {
        result.push(this.devices[index]);
      }
    }
    return result;
  }

  getDevicesByRoom(roomId: string): DeviceInfo[] {
    return DeviceRegistry.getRoomDevices(this.devices, roomId);
  }

  getRoomIds(): string[] {
    return DeviceRegistry.getRoomIds(this.devices);
  }

  getLights(): LightDevice[] {
    return this.getDevicesByType(DeviceType.LIGHT) as LightDevice[];
  }

  getEnvironmentDevices(): EnvironmentDevice[] {
    return this.getDevicesByType(DeviceType.ENVIRONMENT) as EnvironmentDevice[];
  }

  getAirConditioners(): AirConditionerDevice[] {
    return this.getDevicesByType(DeviceType.AIR_CONDITIONER) as AirConditionerDevice[];
  }

  getDoorLocks(): DoorLockDevice[] {
    return this.getDevicesByType(DeviceType.DOOR_LOCK) as DoorLockDevice[];
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
      if (this.devices[index].online) {
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

  isDevicePending(deviceId: string): boolean {
    return this.pendingDeviceIds.indexOf(deviceId) >= 0;
  }

  getConnectionLabel(): string {
    if (this.connectionState === ConnectionState.CONNECTING) {
      return '连接中';
    }
    if (this.connectionState === ConnectionState.AUTHENTICATING) {
      return '认证中';
    }
    if (this.connectionState === ConnectionState.ONLINE) {
      return '在线';
    }
    if (this.connectionState === ConnectionState.RECONNECTING) {
      return '重连中';
    }
    if (this.connectionState === ConnectionState.CLOSED) {
      return '已关闭';
    }
    return '离线';
  }

  async setLightPower(device: LightDevice, power: boolean): Promise<void> {
    const payload: CommandPayload = {};
    payload['power'] = power;
    await this.submit(device, 'setPower', payload);
  }

  async setLightBrightness(device: LightDevice, brightness: number): Promise<void> {
    const payload: CommandPayload = {};
    payload['brightness'] = Math.round(brightness);
    await this.submit(device, 'setBrightness', payload);
  }

  async setLightAutomation(
    device: LightDevice,
    enabled: boolean,
    threshold: number,
    delaySeconds: number
  ): Promise<void> {
    const payload: CommandPayload = {};
    payload['enabled'] = enabled;
    payload['illuminanceThresholdLux'] = Math.round(threshold);
    payload['noPresenceDelaySeconds'] = Math.round(delaySeconds);
    await this.submit(device, 'setAutomationConfig', payload);
  }

  async setAcPower(device: AirConditionerDevice, power: boolean): Promise<void> {
    const payload: CommandPayload = {};
    payload['power'] = power;
    await this.submit(device, 'setPower', payload);
  }

  async setAcMode(device: AirConditionerDevice, mode: string): Promise<void> {
    const payload: CommandPayload = {};
    payload['mode'] = mode;
    await this.submit(device, 'setMode', payload);
  }

  async setAcDehumidify(device: AirConditionerDevice, enabled: boolean): Promise<void> {
    const payload: CommandPayload = {};
    payload['enabled'] = enabled;
    await this.submit(device, 'setDehumidify', payload);
  }

  async setAcTemperature(device: AirConditionerDevice, temperature: number): Promise<void> {
    const payload: CommandPayload = {};
    payload['temperatureCelsius'] = Math.round(temperature);
    await this.submit(device, 'setTemperature', payload);
  }

  async setAcFanSpeed(device: AirConditionerDevice, fanSpeed: string): Promise<void> {
    const payload: CommandPayload = {};
    payload['fanSpeed'] = fanSpeed;
    await this.submit(device, 'setFanSpeed', payload);
  }

  async setAcBrand(device: AirConditionerDevice, brand: string): Promise<void> {
    const payload: CommandPayload = {};
    payload['brand'] = brand;
    await this.submit(device, 'setBrand', payload);
  }

  async setDoorLocked(device: DoorLockDevice, locked: boolean): Promise<void> {
    await this.submit(device, locked ? 'lock' : 'unlock', {});
  }

  async setDoorAutoLock(
    device: DoorLockDevice,
    enabled: boolean,
    delaySeconds: number
  ): Promise<void> {
    const payload: CommandPayload = {};
    payload['enabled'] = enabled;
    payload['delaySeconds'] = Math.round(delaySeconds);
    await this.submit(device, 'setAutoLockConfig', payload);
  }

  async executeDeviceAction(
    device: DeviceInfo,
    action: string,
    payload: CommandPayload
  ): Promise<void> {
    await this.submit(device, action, payload);
  }

  async executeAwayScene(): Promise<void> {
    await this.submitRaw('scene-away', 'executeAway', null, {});
  }

  async executeHomeScene(): Promise<void> {
    await this.submitRaw('scene-home', 'executeHome', null, {});
  }

  async executeConfiguredScene(actions: SceneDeviceAction[]): Promise<void> {
    this.sceneResults = [];
    for (let index = 0; index < actions.length; index++) {
      const sceneAction = actions[index];
      if (sceneAction.operation === 'keep') {
        continue;
      }
      const device = this.getDeviceById(sceneAction.deviceId);
      if (device === null || device.type === DeviceType.ENVIRONMENT) {
        continue;
      }
      const power = sceneAction.operation === 'on';
      if (device.type === DeviceType.LIGHT) {
        await this.setLightPower(device as LightDevice, power);
      } else if (device.type === DeviceType.AIR_CONDITIONER) {
        await this.setAcPower(device as AirConditionerDevice, power);
      } else if (device.type === DeviceType.DOOR_LOCK) {
        if (!power) {
          await this.setDoorLocked(device as DoorLockDevice, true);
        }
      } else {
        await this.executeGenericSceneOperation(device as GenericDevice, power);
      }
    }
  }

  async applySmartTemplate(templateId: string): Promise<void> {
    if (templateId === 'away') {
      await this.executeAwayScene();
      return;
    }
    if (templateId === 'home') {
      await this.executeHomeScene();
      return;
    }
    if (templateId === 'motionLight') {
      await this.enableMotionLighting(100, 60);
      return;
    }
    if (templateId === 'cooling') {
      await this.configureAllAirConditioners(true, ACMode.COOL, 24, ACFanSpeed.AUTO);
      return;
    }
    if (templateId === 'heating') {
      await this.configureAllAirConditioners(true, ACMode.HEAT, 26, ACFanSpeed.LOW);
      return;
    }
    if (templateId === 'humidityDry') {
      await this.configureAllAirConditioners(true, ACMode.DRY, 24, ACFanSpeed.MEDIUM);
    }
  }

  async applyCustomAutomation(condition: string, action: string): Promise<void> {
    if (action === 'livingLight') {
      await this.enableMotionLighting(condition === 'motionDark' ? 100 : 180, 60);
      return;
    }
    if (action === 'dryMode') {
      await this.configureAllAirConditioners(true, ACMode.DRY, 24, ACFanSpeed.MEDIUM);
      return;
    }
    if (action === 'awayScene') {
      await this.executeAwayScene();
    }
  }

  private matchesRegistrationCategory(device: DeviceInfo, categoryId: string): boolean {
    if (device.type === DeviceType.LIGHT) {
      return categoryId === 'lighting';
    }
    if (
      device.type === DeviceType.ENVIRONMENT ||
      device.type === DeviceType.AIR_CONDITIONER
    ) {
      return categoryId === 'environment';
    }
    if (device.type === DeviceType.DOOR_LOCK) {
      return categoryId === 'locks';
    }
    return (device as GenericDevice).category.id === categoryId;
  }

  private matchesRegistrationCapabilities(device: DeviceInfo, capabilities: string[]): boolean {
    for (let index = 0; index < capabilities.length; index++) {
      if (!DeviceRegistry.supportsDeviceAction(device, capabilities[index])) {
        return false;
      }
    }
    return true;
  }

  private async connectAndSync(): Promise<void> {
    await this.transport.connect(this);
    await this.refreshAll();
  }

  private async enableMotionLighting(threshold: number, delaySeconds: number): Promise<void> {
    const lights = this.getLights();
    for (let index = 0; index < lights.length; index++) {
      await this.setLightAutomation(lights[index], true, threshold, delaySeconds);
    }
  }

  private async configureAllAirConditioners(
    power: boolean,
    mode: string,
    temperature: number,
    fanSpeed: string
  ): Promise<void> {
    const airConditioners = this.getAirConditioners();
    for (let index = 0; index < airConditioners.length; index++) {
      await this.setAcPower(airConditioners[index], power);
      await this.setAcMode(airConditioners[index], mode);
      await this.setAcTemperature(airConditioners[index], temperature);
      await this.setAcFanSpeed(airConditioners[index], fanSpeed);
    }
  }

  private async executeGenericSceneOperation(
    device: GenericDevice,
    power: boolean
  ): Promise<void> {
    let toggle: DeviceControl | null = null;
    let namedButton: DeviceControl | null = null;
    let slider: DeviceControl | null = null;
    const buttonAction = power ? 'open' : 'close';
    for (let index = 0; index < device.controls.length; index++) {
      const control = device.controls[index];
      if (control.kind === DeviceControlKind.TOGGLE && (toggle === null || control.primary)) {
        toggle = control;
      } else if (
        control.kind === DeviceControlKind.BUTTON &&
        control.action === buttonAction
      ) {
        namedButton = control;
      } else if (control.kind === DeviceControlKind.SLIDER && (slider === null || control.primary)) {
        slider = control;
      }
    }
    if (toggle !== null) {
      const payload: CommandPayload = {};
      payload[toggle.payloadKey] = power;
      await this.executeDeviceAction(device, toggle.action, payload);
      return;
    }
    if (namedButton !== null) {
      await this.executeDeviceAction(device, namedButton.action, {});
      return;
    }
    if (slider !== null) {
      const payload: CommandPayload = {};
      payload[slider.payloadKey] = power ? slider.maximum : slider.minimum;
      await this.executeDeviceAction(device, slider.action, payload);
    }
  }

  private async submit(
    device: DeviceInfo,
    action: string,
    payload: CommandPayload
  ): Promise<void> {
    if (!DeviceRegistry.supportsDeviceAction(device, action)) {
      this.setError('INVALID_COMMAND', '该设备不支持此控制操作');
      return;
    }
    await this.submitRaw(device.id, action, device.stateVersion, payload);
  }

  private async submitRaw(
    deviceId: string,
    action: string,
    expectedStateVersion: number | null,
    payload: CommandPayload
  ): Promise<void> {
    if (!this.isOnline()) {
      this.setError('DEVICE_OFFLINE', '网关离线，控制操作已禁用');
      return;
    }
    if (this.isDevicePending(deviceId)) {
      return;
    }
    this.pendingDeviceIds = [...this.pendingDeviceIds, deviceId];
    try {
      const messageId = await this.transport.sendCommand(
        deviceId,
        action,
        expectedStateVersion,
        payload
      );
      this.pendingByMessage.set(messageId, deviceId);
      this.actionByMessage.set(messageId, action);
      const timer = setTimeout(() => {
        if (this.pendingByMessage.has(messageId)) {
          this.finishPending(messageId);
          this.setError('COMMAND_TIMEOUT', '命令响应超过5秒');
        }
      }, 5000) as number;
      this.timeoutByMessage.set(messageId, timer);
    } catch (error) {
      this.removePendingDevice(deviceId);
      this.setErrorFromException(error);
      if (this.lastErrorCode === 'AUTH_FAILED') {
        this.invalidateSession(this.lastError);
      }
    }
  }

  private applyDevice(incoming: DeviceInfo): void {
    const result: DeviceInfo[] = [];
    let found = false;
    for (let index = 0; index < this.devices.length; index++) {
      const current = this.devices[index];
      if (current.id === incoming.id) {
        found = true;
        result.push(incoming.stateVersion > current.stateVersion ? incoming : current);
      } else {
        result.push(current);
      }
    }
    if (!found) {
      result.push(incoming);
    }
    this.devices = result;
    this.bumpDeviceStateRevision();
    this.lastSyncAt = Date.now();
  }

  private handleCommandResult(message: Record<string, Object>): void {
    const messageId = message['messageId'] as string;
    const deviceId = message['deviceId'] as string;
    const action = message['action'] as string;
    const success = message['success'] as boolean;
    this.finishPending(messageId);
    if (this.isSceneCommand(deviceId)) {
      this.sceneResults = this.parseSceneResults(message['details']);
    }
    const log = new AccessLogEntry();
    log.time = this.formatTime(Date.now());
    log.deviceId = deviceId;
    log.action = action;
    log.result = success ? 'success' : 'failed';
    if (!success) {
      const error = message['error'] as Record<string, Object>;
      if (error !== undefined && error !== null) {
        log.errorCode = error['code'] as string;
        this.setError(log.errorCode, this.errorMessage(log.errorCode, error['message'] as string));
        if (log.errorCode === 'STATE_CONFLICT') {
          this.refreshAll().catch((refreshError: Error) => {
            this.setErrorFromException(refreshError);
          });
        }
        if (log.errorCode === 'AUTH_FAILED') {
          this.invalidateSession(this.lastError);
        }
      }
    } else {
      this.lastError = '';
      this.lastErrorCode = '';
    }
    this.accessLogs = [log, ...this.accessLogs].slice(0, 50);
    if (success) {
      this.refreshAll().catch((error: Error) => {
        this.setErrorFromException(error);
      });
    }
  }

  private handleAlert(message: Record<string, Object>): void {
    const alert = new AlertEntry();
    alert.time = this.formatTime(message['timestamp'] as number);
    alert.deviceId = message['deviceId'] as string;
    alert.level = message['severity'] as string;
    alert.code = message['code'] as string;
    alert.message = message['description'] as string;
    this.alerts = [alert, ...this.alerts].slice(0, 20);
  }

  private parseSceneResults(value: Object): SceneExecutionDetail[] {
    if (!Array.isArray(value)) {
      return [];
    }
    const raw = value as object[];
    const result: SceneExecutionDetail[] = [];
    for (let index = 0; index < raw.length; index++) {
      const item = raw[index] as Record<string, Object>;
      if (
        typeof item['deviceId'] !== 'string' ||
        typeof item['success'] !== 'boolean'
      ) {
        continue;
      }
      const detail = new SceneExecutionDetail();
      detail.deviceId = item['deviceId'] as string;
      detail.success = item['success'] as boolean;
      const errorCode = item['errorCode'];
      detail.errorCode = typeof errorCode === 'string' ? errorCode : '';
      result.push(detail);
    }
    return result;
  }

  private isSceneCommand(deviceId: string): boolean {
    return deviceId === 'scene-away' || deviceId === 'scene-home';
  }

  private finishPending(messageId: string): void {
    const timer = this.timeoutByMessage.get(messageId);
    if (timer !== undefined) {
      clearTimeout(timer);
      this.timeoutByMessage.delete(messageId);
    }
    const deviceId = this.pendingByMessage.get(messageId);
    if (deviceId !== undefined) {
      this.removePendingDevice(deviceId);
    }
    this.pendingByMessage.delete(messageId);
    this.actionByMessage.delete(messageId);
  }

  private removePendingDevice(deviceId: string): void {
    this.pendingDeviceIds = this.pendingDeviceIds.filter((value: string) => value !== deviceId);
  }

  private clearAllCommandTimeouts(): void {
    this.timeoutByMessage.forEach((timer: number) => clearTimeout(timer));
    this.timeoutByMessage.clear();
    this.pendingByMessage.clear();
    this.actionByMessage.clear();
    this.pendingDeviceIds = [];
  }

  private bumpDeviceStateRevision(): void {
    this.deviceStateRevision += 1;
  }

  private invalidateSession(message: string): void {
    this.session = null;
    this.pairingRequired = true;
    this.gatewayAddress = this.lastGatewayAddress;
    this.connectionState = ConnectionState.DISCONNECTED;
    this.clearAllCommandTimeouts();
    this.setError('AUTH_FAILED', message);
    if (this.sessionStore !== null) {
      this.sessionStore.clear().catch((clearError: Error) => {
      });
    }
    this.transport.close().catch((closeError: Error) => {
    });
  }

  private setErrorFromException(error: Object): void {
    const text = error instanceof Error ? error.message : JSON.stringify(error);
    const separator = text.indexOf(':');
    if (separator > 0) {
      const code = text.substring(0, separator);
      const message = text.substring(separator + 1);
      this.setError(code, this.errorMessage(code, message));
    } else {
      this.setError('INTERNAL_ERROR', text);
    }
  }

  private registrationFailureMessage(error: Object): string {
    const text = error instanceof Error ? error.message : JSON.stringify(error);
    const separator = text.indexOf(':');
    if (separator <= 0) {
      return '';
    }
    const code = text.substring(0, separator);
    const detail = text.substring(separator + 1);
    const isDeviceProof = code === 'DEVICE_PROOF_INVALID' ||
      (code === 'AUTH_FAILED' && detail.indexOf('设备认证证明') >= 0);
    if (isDeviceProof) {
      return '设备二维码未通过当前网关证书认证，请检查二维码所属网关';
    }
    return '';
  }

  private setError(code: string, message: string): void {
    this.lastErrorCode = code;
    this.lastError = native.redactDiagnostic(message);
  }

  private errorMessage(code: string, fallback: string): string {
    if (code === 'AUTH_FAILED') {
      if (fallback.indexOf('网关已重启') >= 0) {
        return '网关已重启，安全会话已失效，请重新配对';
      }
      return '会话已失效，请重新配对';
    }
    if (code === 'DEVICE_PROOF_INVALID') {
      return '设备二维码未通过当前网关证书认证，请检查二维码所属网关';
    }
    if (code === 'DEVICE_OFFLINE') {
      return '目标设备离线';
    }
    if (code === 'INVALID_COMMAND') {
      return '控制参数无效';
    }
    if (code === 'COMMAND_TIMEOUT') {
      return '命令执行超时';
    }
    if (code === 'STATE_CONFLICT') {
      return '设备状态已更新，已重新同步';
    }
    if (code === 'REPLAY_DETECTED') {
      return '命令安全校验失败';
    }
    if (code === 'RATE_LIMITED') {
      return '操作过于频繁，请稍后再试';
    }
    return fallback.length > 0 ? fallback : '网关内部错误';
  }

  private formatTime(timestamp: number): string {
    const date = new Date(timestamp);
    return date.getHours().toString().padStart(2, '0') + ':' +
      date.getMinutes().toString().padStart(2, '0') + ':' +
      date.getSeconds().toString().padStart(2, '0');
  }
}
