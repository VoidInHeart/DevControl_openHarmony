export class ConnectionState {
  static readonly DISCONNECTED: string = 'disconnected';
  static readonly CONNECTING: string = 'connecting';
  static readonly AUTHENTICATING: string = 'authenticating';
  static readonly ONLINE: string = 'online';
  static readonly RECONNECTING: string = 'reconnecting';
  static readonly CLOSED: string = 'closed';
}

export class GatewayConnectionConfig {
  httpsEndpoint: string = '';
  wssEndpoint: string = '';
  caPath: string = '';
  connectTimeoutMs: number = 10000;
}

export class PairingResult {
  clientId: string = '';
  credential: string = '';
  dataKey: string = '';
  expiresAt: number = 0;
}

export type GatewayMessageHandler = (rawMessage: string) => void;
export type TransportStateHandler = (state: string, message: string) => void;

export interface GatewayTransport {
  configure(config: GatewayConnectionConfig): void;
  checkHealth(): Promise<boolean>;
  pair(pairingCode: string, clientId: string): Promise<PairingResult>;
  fetchDeviceSnapshot(): Promise<string>;
  connect(): Promise<void>;
  sendCommand(rawCommand: string): Promise<void>;
  reconnect(): Promise<void>;
  subscribe(handler: GatewayMessageHandler): () => void;
  subscribeState(handler: TransportStateHandler): () => void;
  close(): Promise<void>;
}
