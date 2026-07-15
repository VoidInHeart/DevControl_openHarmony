import { http, webSocket } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import {
  GatewayConnectionConfig,
  GatewayMessageHandler,
  GatewayTransport,
  PairingResult,
  TransportStateHandler
} from '../model/GatewayModels';

class PairRequest {
  pairingCode: string = '';
  clientId: string = '';
}

export class WssGatewayTransport implements GatewayTransport {
  private config: GatewayConnectionConfig = new GatewayConnectionConfig();
  private socket: webSocket.WebSocket | null = null;
  private credential: string = '';
  private messageHandlers: GatewayMessageHandler[] = [];
  private stateHandlers: TransportStateHandler[] = [];
  private closing: boolean = false;

  configure(config: GatewayConnectionConfig): void {
    this.config = config;
  }

  async checkHealth(): Promise<boolean> {
    const raw = await this.request('/api/v1/health', http.RequestMethod.GET, '', false);
    const parsed = JSON.parse(raw) as Record<string, Object>;
    return parsed['status'] === 'ok' && parsed['protocolVersion'] === '1.0';
  }

  async pair(pairingCode: string, clientId: string): Promise<PairingResult> {
    const request = new PairRequest();
    request.pairingCode = pairingCode;
    request.clientId = clientId;
    const raw = await this.request('/api/v1/pair', http.RequestMethod.POST, JSON.stringify(request), false);
    const parsed = JSON.parse(raw) as Record<string, Object>;
    const result = new PairingResult();
    result.clientId = parsed['clientId'] as string;
    result.credential = parsed['credential'] as string;
    result.dataKey = parsed['dataKey'] as string;
    result.expiresAt = parsed['expiresAt'] as number;
    this.credential = result.credential;
    return result;
  }

  async fetchDeviceSnapshot(): Promise<string> {
    return await this.request('/api/v1/devices', http.RequestMethod.GET, '', true);
  }

  async connect(): Promise<void> {
    if (this.credential.length === 0) {
      throw new Error('No paired gateway credential is available');
    }
    await this.closeSocketOnly();
    this.closing = false;
    const socket = webSocket.createWebSocket();
    this.socket = socket;
    this.registerSocketEvents(socket);

    const headers: Record<string, string> = {
      'Authorization': 'Bearer ' + this.credential,
      'X-Protocol-Version': '1.0'
    };
    const options: webSocket.WebSocketRequestOptions = {
      header: headers,
      skipServerCertVerification: false
    };
    if (this.config.caPath.length > 0) {
      options.caPath = this.config.caPath;
    }
    this.emitState('connecting', '正在建立安全连接');
    try {
      const connected = await socket.connect(this.config.wssEndpoint, options);
      if (!connected) {
        this.socket = null;
        throw new Error('WebSocket connection was rejected');
      }
    } catch (error) {
      this.socket = null;
      throw new Error(this.errorMessage(error));
    }
    this.emitState('online', '网关连接正常');
  }

  async sendCommand(rawCommand: string): Promise<void> {
    const socket = this.socket;
    if (socket === null) {
      throw new Error('Gateway is offline');
    }
    try {
      const sent = await socket.send(rawCommand);
      if (!sent) {
        throw new Error('Command could not be sent');
      }
    } catch (error) {
      throw new Error(this.errorMessage(error));
    }
  }

  async reconnect(): Promise<void> {
    this.emitState('reconnecting', '正在重新连接网关');
    await this.connect();
  }

  subscribe(handler: GatewayMessageHandler): () => void {
    this.messageHandlers.push(handler);
    return () => {
      const index = this.messageHandlers.indexOf(handler);
      if (index >= 0) {
        this.messageHandlers.splice(index, 1);
      }
    };
  }

  subscribeState(handler: TransportStateHandler): () => void {
    this.stateHandlers.push(handler);
    return () => {
      const index = this.stateHandlers.indexOf(handler);
      if (index >= 0) {
        this.stateHandlers.splice(index, 1);
      }
    };
  }

  async close(): Promise<void> {
    this.closing = true;
    await this.closeSocketOnly();
    this.emitState('closed', '连接已关闭');
  }

  private async closeSocketOnly(): Promise<void> {
    const socket = this.socket;
    this.socket = null;
    if (socket !== null) {
      try {
        await socket.close({ code: 1000, reason: 'client close' });
      } catch (_) {
      }
    }
  }

  private registerSocketEvents(socket: webSocket.WebSocket): void {
    socket.on('message', (error: BusinessError, data: string | ArrayBuffer) => {
      if (error) {
        this.emitState('disconnected', '接收网关消息失败');
        return;
      }
      if (typeof data === 'string') {
        for (let index = 0; index < this.messageHandlers.length; index++) {
          this.messageHandlers[index](data);
        }
      }
    });
    socket.on('close', (error: BusinessError) => {
      this.socket = null;
      if (!this.closing) {
        const reason = error ? error.message : '连接中断';
        this.emitState('disconnected', reason);
      }
    });
    socket.on('error', (error: BusinessError) => {
      this.emitState('disconnected', error.message);
    });
  }

  private emitState(state: string, message: string): void {
    for (let index = 0; index < this.stateHandlers.length; index++) {
      this.stateHandlers[index](state, message);
    }
  }

  private async request(path: string, method: http.RequestMethod,
    body: string, authenticated: boolean): Promise<string> {
    const request = http.createHttp();
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
      'X-Protocol-Version': '1.0'
    };
    if (authenticated) {
      if (this.credential.length === 0) {
        request.destroy();
        throw new Error('No paired gateway credential is available');
      }
      headers['Authorization'] = 'Bearer ' + this.credential;
    }
    const options: http.HttpRequestOptions = {
      method: method,
      header: headers,
      extraData: body,
      expectDataType: http.HttpDataType.STRING,
      usingCache: false,
      connectTimeout: this.config.connectTimeoutMs,
      readTimeout: this.config.connectTimeoutMs
    };
    if (this.config.caPath.length > 0) {
      options.caPath = this.config.caPath;
    }
    try {
      const response = await request.request(this.config.httpsEndpoint + path, options);
      if (response.responseCode < 200 || response.responseCode >= 300) {
        throw new Error('Gateway returned HTTP ' + response.responseCode.toString());
      }
      if (typeof response.result !== 'string') {
        return JSON.stringify(response.result);
      }
      return response.result;
    } catch (error) {
      throw new Error(this.errorMessage(error));
    } finally {
      request.destroy();
    }
  }

  private errorMessage(error: Object): string {
    const typed = error as Error;
    return typed.message === undefined || typed.message.length === 0 ? 'Gateway request failed' : typed.message;
  }
}
