const IDENTIFIER_PATTERN: RegExp = /^[A-Za-z][A-Za-z0-9._-]{0,63}$/;
const DEVICE_ID_PATTERN: RegExp = /^[A-Za-z0-9][A-Za-z0-9._:-]{2,63}$/;
const COMPACT_JWS_PATTERN: RegExp = /^[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}$/;
const DEVICE_NAME_PATTERN: RegExp = /^[^\u0000-\u001F\u007F]{1,64}$/;
const MAX_QR_PAYLOAD_LENGTH: number = 8192;

/**
 * The registration manifest is intentionally a declaration, not a device
 * model. The gateway owns the final device state and validates the signed
 * proof before it makes a device visible in a snapshot.
 */
export class DeviceRegistrationRequest {
  schema: string = 'devcontrol.device-registration';
  protocolVersion: string = '1.0';
  deviceId: string = '';
  deviceName: string = '';
  deviceType: string = '';
  categoryId: string = '';
  // This is selected in the App during registration. It is intentionally not
  // part of the QR payload or the signed device identity certificate.
  roomId: string = '';
  capabilities: string[] = [];
  gatewayProofFormat: string = 'jws';
  gatewayProof: string = '';
}

export class DeviceRegistrationReceipt {
  deviceId: string = '';
  accepted: boolean = false;
  online: boolean = false;
}

export class DeviceRegistrationResult {
  registered: boolean = false;
  online: boolean = false;
  message: string = '';
}

export class DeviceRemovalReceipt {
  deviceId: string = '';
  deleted: boolean = false;
}

export class DeviceRemovalResult {
  deleted: boolean = false;
  message: string = '';
}

/**
 * Parses the only QR payload format accepted by the App.
 *
 * Raw JSON is accepted for compact QR generation. A URI-wrapped form is also
 * supported for scanners that require an app scheme:
 * devcontrol://register?payload=<URL-encoded JSON>
 */
export class DeviceRegistrationQr {
  static parse(rawValue: string): DeviceRegistrationRequest {
    if (rawValue.length === 0 || rawValue.length > MAX_QR_PAYLOAD_LENGTH) {
      throw new Error('二维码注册信息长度无效');
    }
    const payload = DeviceRegistrationQr.extractPayload(rawValue);
    let parsed: Object;
    try {
      parsed = JSON.parse(payload) as Object;
    } catch (error) {
      throw new Error('二维码不是有效的设备注册信息');
    }
    if (typeof parsed !== 'object' || parsed === null || Array.isArray(parsed)) {
      throw new Error('二维码注册信息必须是对象');
    }
    return DeviceRegistrationQr.parseManifest(parsed as Record<string, Object>);
  }

  private static extractPayload(rawValue: string): string {
    const prefix = 'devcontrol://register?payload=';
    if (!rawValue.startsWith(prefix)) {
      return rawValue;
    }
    const encoded = rawValue.substring(prefix.length);
    if (encoded.length === 0) {
      throw new Error('二维码缺少注册信息');
    }
    try {
      return decodeURIComponent(encoded);
    } catch (error) {
      throw new Error('二维码注册信息编码无效');
    }
  }

  private static parseManifest(raw: Record<string, Object>): DeviceRegistrationRequest {
    const schema = DeviceRegistrationQr.requireString(raw, 'schema', 64);
    if (schema !== 'devcontrol.device-registration') {
      throw new Error('不支持的二维码注册格式');
    }
    const request = new DeviceRegistrationRequest();
    request.schema = schema;
    request.protocolVersion = DeviceRegistrationQr.requireString(raw, 'protocolVersion', 16);
    if (request.protocolVersion !== '1.0') {
      throw new Error('不支持的二维码协议版本');
    }
    request.deviceId = DeviceRegistrationQr.requireString(raw, 'deviceId', 64);
    if (!DEVICE_ID_PATTERN.test(request.deviceId)) {
      throw new Error('设备序列号格式无效');
    }
    request.deviceName = DeviceRegistrationQr.requireDeviceName(raw);
    request.deviceType = DeviceRegistrationQr.requireIdentifier(raw, 'deviceType');
    request.categoryId = DeviceRegistrationQr.requireIdentifier(raw, 'categoryId');
    request.capabilities = DeviceRegistrationQr.requireIdentifiers(raw, 'capabilities', 1, 32);
    request.gatewayProofFormat = DeviceRegistrationQr.requireString(raw, 'gatewayProofFormat', 16);
    if (request.gatewayProofFormat !== 'jws') {
      throw new Error('不支持的网关认证格式');
    }
    request.gatewayProof = DeviceRegistrationQr.requireString(raw, 'gatewayProof', 4096);
    if (!COMPACT_JWS_PATTERN.test(request.gatewayProof)) {
      throw new Error('网关认证信息格式无效');
    }
    return request;
  }

  private static requireString(
    raw: Record<string, Object>,
    key: string,
    maximumLength: number
  ): string {
    const value = raw[key];
    if (typeof value !== 'string' || value.length === 0 || value.length > maximumLength) {
      throw new Error('二维码字段无效: ' + key);
    }
    return value;
  }

  private static requireIdentifier(raw: Record<string, Object>, key: string): string {
    const value = DeviceRegistrationQr.requireString(raw, key, 64);
    if (!IDENTIFIER_PATTERN.test(value)) {
      throw new Error('二维码标识符无效: ' + key);
    }
    return value;
  }

  private static requireDeviceName(raw: Record<string, Object>): string {
    const value = DeviceRegistrationQr.requireString(raw, 'deviceName', 64);
    if (!DEVICE_NAME_PATTERN.test(value) || value.trim().length === 0) {
      throw new Error('设备名称必须为 1 到 64 个非控制字符，且不能仅包含空白字符');
    }
    return value;
  }

  private static requireIdentifiers(
    raw: Record<string, Object>,
    key: string,
    minimumLength: number,
    maximumLength: number
  ): string[] {
    const value = raw[key];
    if (!Array.isArray(value) || value.length < minimumLength || value.length > maximumLength) {
      throw new Error('二维码能力列表无效');
    }
    const capabilityValues = value as Object[];
    const result: string[] = [];
    for (let index = 0; index < capabilityValues.length; index++) {
      const item: Object = capabilityValues[index];
      if (typeof item !== 'string' || !IDENTIFIER_PATTERN.test(item) || result.indexOf(item) >= 0) {
        throw new Error('二维码能力标识符无效');
      }
      result.push(item);
    }
    return result;
  }
}
