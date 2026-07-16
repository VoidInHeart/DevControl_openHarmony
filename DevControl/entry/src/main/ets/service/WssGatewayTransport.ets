import { BusinessError } from '@kit.BasicServicesKit';
import { http, webSocket } from '@kit.NetworkKit';
import native from 'libentry.so';
import {
  CommandPayload,
  ConnectionState,
  DeviceInfo,
  EnvironmentHistoryPoint,
  GatewaySession,
  parseDevices
} from '../model/DeviceModel';
import { GatewayTransport, GatewayTransportListener } from './GatewayTransport';

class SealedParts {
  nonce: string = '';
  ciphertext: string = '';
  authTag: string = '';
}

class CommandHeader {
  protocolVersion: string = '1.0';
  messageId: string = '';
  deviceId: string = '';
  timestamp: number = 0;
  type: string = 'command.request';
  action: string = '';
  expectedStateVersion: number | null = null;
}

class CommandEnvelope extends CommandHeader {
  nonce: string = '';
  ciphertext: string = '';
  authTag: string = '';
}

export class WssGatewayTransport implements GatewayTransport {
  private session: GatewaySession | null = null;
  private caPath: string = '';
  private socket: webSocket.WebSocket | null = null;
  private listener: GatewayTransportListener | null = null;
  private closedByUser: boolean = false;
  private reconnectAttempt: number = 0;
  private reconnectTimer: number = -1;
  private heartbeatTimer: number = -1;
  private lastMessageAt: number = 0;

  configure(session: GatewaySession): void {
    this.session = session;
  }

  setCertificateAuthorityPath(path: string): void {
    this.caPath = path;
  }

  async checkHealth(address: string): Promise<boolean> {
    const response = await this.request(address + '/api/v1/health', http.RequestMethod.GET, null, '');
    return response['status'] === 'ok' && response['protocolVersion'] === '1.0';
  }

  async pair(address: string, pairingCode: string, clientId: string): Promise<GatewaySession> {
    const body: Record<string, Object> = {
      'protocolVersion': '1.0',
      'pairingCode': pairingCode,
      'clientId': clientId
    };
    const response = await this.request(
      address + '/api/v1/pair',
      http.RequestMethod.POST,
      body,
      ''
    );
    const session = new GatewaySession();
    session.protocolVersion = response['protocolVersion'] as string;
    session.clientId = response['clientId'] as string;
    session.gatewayAddress = address;
    session.credential = response['credential'] as string;
    session.dataKey = response['dataKey'] as string;
    session.issuedAt = response['issuedAt'] as number;
    return session;
  }

  async fetchDeviceSnapshot(): Promise<DeviceInfo[]> {
    const session = this.requireSession();
    const response = await this.request(
      session.gatewayAddress + '/api/v1/devices',
      http.RequestMethod.GET,
      null,
      session.credential
    );
    return parseDevices(response['devices']);
  }

  async fetchLogs(limit: number): Promise<Record<string, Object>[]> {
    const session = this.requireSession();
    const response = await this.request(
      session.gatewayAddress + '/api/v1/logs?limit=' + limit.toString(),
      http.RequestMethod.GET,
      null,
      session.credential
    );
    return response['items'] as Record<string, Object>[];
  }

  async fetchAlerts(limit: number): Promise<Record<string, Object>[]> {
    const session = this.requireSession();
    const response = await this.request(
      session.gatewayAddress + '/api/v1/logs?limit=' + limit.toString(),
      http.RequestMethod.GET,
      null,
      session.credential
    );
    return response['alerts'] as Record<string, Object>[];
  }

  async fetchEnvironmentHistory(fromTimestamp: number): Promise<EnvironmentHistoryPoint[]> {
    const session = this.requireSession();
    const response = await this.request(
      session.gatewayAddress + '/api/v1/history/environment?from=' +
        fromTimestamp.toString() + '&limit=43200',
      http.RequestMethod.GET,
      null,
      session.credential
    );
    const raw = response['items'] as Record<string, Object>[];
    const result: EnvironmentHistoryPoint[] = [];
    for (let index = 0; index < raw.length; index++) {
      const point = new EnvironmentHistoryPoint();
      point.timestamp = raw[index]['timestamp'] as number;
      point.temperatureCelsius = raw[index]['temperatureCelsius'] as number;
      point.humidityPercent = raw[index]['humidityPercent'] as number;
      point.illuminanceLux = raw[index]['illuminanceLux'] as number;
      point.presence = raw[index]['presence'] as boolean;
      result.push(point);
    }
    return result;
  }

  async connect(listener: GatewayTransportListener): Promise<void> {
    const session = this.requireSession();
    this.listener = listener;
    this.closedByUser = false;
    this.clearReconnectTimer();
    listener.onConnectionStateChanged(ConnectionState.CONNECTING);
    const socket = webSocket.createWebSocket();
    this.socket = socket;
    socket.on('message', (error: BusinessError, data: string | ArrayBuffer): void => {
      if (error) {
        this.notifyError('INTERNAL_ERROR', error.message);
        return;
      }
      this.lastMessageAt = Date.now();
      if (typeof data === 'string') {
        try {
          const message = JSON.parse(data) as Record<string, Object>;
          if (this.listener !== null) {
            this.listener.onGatewayMessage(message);
          }
        } catch (parseError) {
          this.notifyError('INVALID_COMMAND', '网关消息格式无效');
        }
      }
    });
    socket.on('close', (error: BusinessError): void => {
      if (error) {
        this.notifyError('INTERNAL_ERROR', error.message);
      }
      this.stopHeartbeatMonitor();
      if (!this.closedByUser) {
        this.scheduleReconnect();
      }
    });
    socket.on('error', (error: BusinessError): void => {
      this.notifyError('INTERNAL_ERROR', error.message);
    });
    const wsAddress = session.gatewayAddress.replace('https://', 'wss://') + '/ws/v1/events';
    const options: webSocket.WebSocketRequestOptions = {
      header: {
        'Authorization': 'Bearer ' + session.credential
      },
      skipServerCertVerification: false
    };
    if (this.caPath.length > 0) {
      options.caPath = this.caPath;
    }
    try {
      await socket.connect(wsAddress, options);
      this.reconnectAttempt = 0;
      this.lastMessageAt = Date.now();
      listener.onConnectionStateChanged(ConnectionState.ONLINE);
      this.startHeartbeatMonitor();
    } catch (error) {
      this.scheduleReconnect();
      const message = error instanceof Error ? error.message : JSON.stringify(error);
      throw new Error(message);
    }
  }

  async sendCommand(
    deviceId: string,
    action: string,
    expectedStateVersion: number | null,
    payload: CommandPayload
  ): Promise<string> {
    const session = this.requireSession();
    if (this.socket === null) {
      throw new Error('WebSocket is not connected');
    }
    const header = new CommandHeader();
    header.messageId = native.generateMessageId();
    header.deviceId = deviceId;
    header.timestamp = Date.now();
    header.action = action;
    header.expectedStateVersion = expectedStateVersion;
    const aadJson = JSON.stringify(header);
    const sealedRaw = JSON.parse(
      native.sealCommand(session.dataKey, JSON.stringify(payload), aadJson)
    ) as Record<string, Object>;
    const sealed = new SealedParts();
    sealed.nonce = sealedRaw['nonce'] as string;
    sealed.ciphertext = sealedRaw['ciphertext'] as string;
    sealed.authTag = sealedRaw['authTag'] as string;
    const envelope = new CommandEnvelope();
    envelope.messageId = header.messageId;
    envelope.deviceId = header.deviceId;
    envelope.timestamp = header.timestamp;
    envelope.action = header.action;
    envelope.expectedStateVersion = header.expectedStateVersion;
    envelope.nonce = sealed.nonce;
    envelope.ciphertext = sealed.ciphertext;
    envelope.authTag = sealed.authTag;
    const sent = await this.socket.send(JSON.stringify(envelope));
    if (!sent) {
      throw new Error('WebSocket send failed');
    }
    return header.messageId;
  }

  async reconnect(): Promise<void> {
    if (this.listener === null) {
      throw new Error('Transport listener is not configured');
    }
    await this.closeSocketOnly();
    await this.connect(this.listener);
  }

  async close(): Promise<void> {
    this.closedByUser = true;
    this.clearReconnectTimer();
    this.stopHeartbeatMonitor();
    await this.closeSocketOnly();
    if (this.listener !== null) {
      this.listener.onConnectionStateChanged(ConnectionState.CLOSED);
    }
  }

  private requireSession(): GatewaySession {
    if (this.session === null) {
      throw new Error('Gateway session is not configured');
    }
    return this.session;
  }

  private async request(
    url: string,
    method: http.RequestMethod,
    body: Record<string, Object> | null,
    credential: string
  ): Promise<Record<string, Object>> {
    const request = http.createHttp();
    const headers: Record<string, string> = {
      'Content-Type': 'application/json'
    };
    if (credential.length > 0) {
      headers['Authorization'] = 'Bearer ' + credential;
    }
    try {
      const options: http.HttpRequestOptions = {
        method: method,
        header: headers,
        extraData: body === null ? '' : JSON.stringify(body),
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 5000,
        readTimeout: 5000
      };
      if (this.caPath.length > 0) {
        options.caPath = this.caPath;
      }
      const response = await request.request(url, options);
      const text = response.result as string;
      const parsed = JSON.parse(text) as Record<string, Object>;
      if (response.responseCode < 200 || response.responseCode >= 300) {
        const error = parsed['error'] as Record<string, Object>;
        const code = error !== undefined ? error['code'] as string : 'INTERNAL_ERROR';
        const message = error !== undefined ? error['message'] as string : '网关请求失败';
        throw new Error(code + ':' + message);
      }
      return parsed;
    } finally {
      request.destroy();
    }
  }

  private scheduleReconnect(): void {
    if (this.closedByUser || this.listener === null || this.reconnectTimer !== -1) {
      return;
    }
    this.listener.onConnectionStateChanged(ConnectionState.RECONNECTING);
    const delays: number[] = [1000, 2000, 4000, 8000, 10000];
    const index = Math.min(this.reconnectAttempt, delays.length - 1);
    const delay = delays[index];
    this.reconnectAttempt++;
    this.reconnectTimer = setTimeout(() => {
      this.reconnectTimer = -1;
      if (this.listener !== null) {
        this.connect(this.listener).catch((error: Error) => {
          this.notifyError('INTERNAL_ERROR', error.message);
          this.scheduleReconnect();
        });
      }
    }, delay) as number;
  }

  private startHeartbeatMonitor(): void {
    this.stopHeartbeatMonitor();
    this.heartbeatTimer = setInterval(() => {
      if (Date.now() - this.lastMessageAt > 45000) {
        this.notifyError('COMMAND_TIMEOUT', '网关心跳超时');
        this.closeSocketOnly().finally(() => {
          this.scheduleReconnect();
        });
      }
    }, 5000) as number;
  }

  private stopHeartbeatMonitor(): void {
    if (this.heartbeatTimer !== -1) {
      clearInterval(this.heartbeatTimer);
      this.heartbeatTimer = -1;
    }
  }

  private clearReconnectTimer(): void {
    if (this.reconnectTimer !== -1) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = -1;
    }
  }

  private async closeSocketOnly(): Promise<void> {
    const current = this.socket;
    this.socket = null;
    if (current !== null) {
      try {
        await current.close({ code: 1000, reason: 'client close' });
      } catch (error) {
      }
    }
  }

  private notifyError(code: string, message: string): void {
    if (this.listener !== null) {
      this.listener.onTransportError(code, native.redactDiagnostic(message));
    }
  }
}
