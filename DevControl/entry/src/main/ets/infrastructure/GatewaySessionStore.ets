import { Context } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { huks } from '@kit.UniversalKeystoreKit';
import { PairingResult } from '../model/GatewayModels';

const KEY_ALIAS: string = 'devcontrol.gateway.session.kek.v1';
const PREFERENCES_NAME: string = 'devcontrol_secure_session';
const ENVELOPE_KEY: string = 'gateway_session_envelope';
const SCHEMA_VERSION: number = 1;
const GCM_TAG_BYTES: number = 16;
const GCM_IV_BYTES: number = 12;
const ASSOCIATED_DATA: string = 'devcontrol.gateway.session.v1';

class SessionPlaintext {
  endpoint: string = '';
  clientId: string = '';
  credential: string = '';
  dataKey: string = '';
  expiresAt: number = 0;
}

class StoredEnvelope {
  schemaVersion: number = SCHEMA_VERSION;
  iv: string = '';
  sealed: string = '';
}

export class RestoredGatewaySession {
  endpoint: string = '';
  clientId: string = '';
  credential: string = '';
  dataKey: string = '';
  expiresAt: number = 0;
}

export class GatewaySessionStore {
  private context: Context;
  private base64: util.Base64Helper = new util.Base64Helper();
  private encoder: util.TextEncoder = util.TextEncoder.create('utf-8');
  private decoder: util.TextDecoder = util.TextDecoder.create('utf-8');

  constructor(context: Context) {
    this.context = context;
  }

  async save(endpoint: string, pairing: PairingResult): Promise<void> {
    await this.ensureWrappingKey();
    const plaintext = new SessionPlaintext();
    plaintext.endpoint = endpoint;
    plaintext.clientId = pairing.clientId;
    plaintext.credential = pairing.credential;
    plaintext.dataKey = pairing.dataKey;
    plaintext.expiresAt = pairing.expiresAt;

    const iv = this.randomIv();
    const encoded = this.encoder.encodeInto(JSON.stringify(plaintext));
    let sealed: Uint8Array;
    try {
      sealed = await this.encrypt(encoded, iv);
    } finally {
      encoded.fill(0);
    }
    const envelope = new StoredEnvelope();
    envelope.iv = this.base64.encodeToStringSync(iv);
    envelope.sealed = this.base64.encodeToStringSync(sealed);

    try {
      const store = await preferences.getPreferences(this.context, PREFERENCES_NAME);
      await store.put(ENVELOPE_KEY, JSON.stringify(envelope));
      await store.flush();
    } catch (error) {
      const typed = error as BusinessError;
      throw new Error(`Secure session persistence failed (${typed.code}: ${typed.message})`);
    }
  }

  async restore(): Promise<RestoredGatewaySession | null> {
    let raw: string = '';
    try {
      const store = await preferences.getPreferences(this.context, PREFERENCES_NAME);
      const rawValue = await store.get(ENVELOPE_KEY, '');
      raw = rawValue as string;
    } catch (_) {
      return null;
    }
    if (raw.length === 0) {
      return null;
    }

    let iv: Uint8Array;
    let sealed: Uint8Array;
    try {
      const parsedEnvelope = JSON.parse(raw) as Record<string, Object>;
      const schemaVersion = parsedEnvelope['schemaVersion'] as number;
      const ivText = parsedEnvelope['iv'] as string;
      const sealedText = parsedEnvelope['sealed'] as string;
      if (schemaVersion !== SCHEMA_VERSION || ivText.length === 0 || sealedText.length === 0) {
        throw new Error('Unsupported secure session envelope');
      }
      iv = this.base64.decodeSync(ivText);
      sealed = this.base64.decodeSync(sealedText);
      if (iv.length !== GCM_IV_BYTES || sealed.length <= GCM_TAG_BYTES) {
        throw new Error('Invalid secure session envelope');
      }
    } catch (_) {
      await this.clear();
      return null;
    }

    try {
      if (!await this.keyExists()) {
        await this.clear();
        return null;
      }
    } catch (_) {
      return null;
    }

    let plaintext: Uint8Array;
    try {
      plaintext = await this.decrypt(sealed, iv);
    } catch (_) {
      return null;
    }

    try {
      const decoded = this.decoder.decodeToString(plaintext);
      plaintext.fill(0);
      const parsedSession = JSON.parse(decoded) as Record<string, Object>;
      const restored = new RestoredGatewaySession();
      restored.endpoint = parsedSession['endpoint'] as string;
      restored.clientId = parsedSession['clientId'] as string;
      restored.credential = parsedSession['credential'] as string;
      restored.dataKey = parsedSession['dataKey'] as string;
      restored.expiresAt = parsedSession['expiresAt'] as number;
      if (!this.isValid(restored)) {
        await this.clear();
        return null;
      }
      return restored;
    } catch (_) {
      await this.clear();
      return null;
    }
  }

  async clear(): Promise<void> {
    try {
      const store = await preferences.getPreferences(this.context, PREFERENCES_NAME);
      await store.delete(ENVELOPE_KEY);
      await store.flush();
    } catch (_) {
    }
  }

  private async ensureWrappingKey(): Promise<void> {
    try {
      if (await this.keyExists()) {
        return;
      }
      const properties: huks.HuksParam[] = this.publicProperties(
        huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT | huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT);
      properties.push({
        tag: huks.HuksTag.HUKS_TAG_NO_AUTH_REQUIRED,
        value: true
      });
      await huks.generateKeyItem(KEY_ALIAS, { properties: properties });
    } catch (error) {
      const typed = error as BusinessError;
      throw new Error(`Secure session key is unavailable (${typed.code}: ${typed.message})`);
    }
  }

  private async keyExists(): Promise<boolean> {
    try {
      return await huks.isKeyItemExist(KEY_ALIAS, { properties: [] });
    } catch (error) {
      const typed = error as BusinessError;
      if (typed.code === huks.HuksExceptionErrCode.HUKS_ERR_CODE_ITEM_NOT_EXIST) {
        return false;
      }
      throw new Error(`HUKS key lookup failed (${typed.code}: ${typed.message})`);
    }
  }

  private async encrypt(plaintext: Uint8Array, iv: Uint8Array): Promise<Uint8Array> {
    const properties = this.operationProperties(huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT, iv,
      new Uint8Array(GCM_TAG_BYTES));
    return await this.finishOperation(properties, plaintext);
  }

  private async decrypt(sealed: Uint8Array, iv: Uint8Array): Promise<Uint8Array> {
    const ciphertext = sealed.slice(0, sealed.length - GCM_TAG_BYTES);
    const tag = sealed.slice(sealed.length - GCM_TAG_BYTES);
    const properties = this.operationProperties(huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT, iv, tag);
    return await this.finishOperation(properties, ciphertext);
  }

  private async finishOperation(properties: huks.HuksParam[], input: Uint8Array): Promise<Uint8Array> {
    let handle: number = -1;
    try {
      const session = await huks.initSession(KEY_ALIAS, { properties: properties });
      handle = session.handle;
      const result = await huks.finishSession(handle, { properties: properties, inData: input });
      handle = -1;
      if (result.outData === undefined || result.outData.length === 0) {
        throw new Error('HUKS returned no output');
      }
      return result.outData;
    } catch (_) {
      if (handle >= 0) {
        try {
          await huks.abortSession(handle, { properties: [] });
        } catch (_) {
        }
      }
      throw new Error('Secure session operation failed');
    }
  }

  private publicProperties(purpose: number): huks.HuksParam[] {
    return [
      { tag: huks.HuksTag.HUKS_TAG_ALGORITHM, value: huks.HuksKeyAlg.HUKS_ALG_AES },
      { tag: huks.HuksTag.HUKS_TAG_KEY_SIZE, value: huks.HuksKeySize.HUKS_AES_KEY_SIZE_256 },
      { tag: huks.HuksTag.HUKS_TAG_PURPOSE, value: purpose },
      { tag: huks.HuksTag.HUKS_TAG_DIGEST, value: huks.HuksKeyDigest.HUKS_DIGEST_NONE },
      { tag: huks.HuksTag.HUKS_TAG_PADDING, value: huks.HuksKeyPadding.HUKS_PADDING_NONE },
      { tag: huks.HuksTag.HUKS_TAG_BLOCK_MODE, value: huks.HuksCipherMode.HUKS_MODE_GCM }
    ];
  }

  private operationProperties(purpose: number, iv: Uint8Array, tag: Uint8Array): huks.HuksParam[] {
    const properties = this.publicProperties(purpose);
    properties.push({
      tag: huks.HuksTag.HUKS_TAG_ASSOCIATED_DATA,
      value: this.encoder.encodeInto(ASSOCIATED_DATA)
    });
    properties.push({ tag: huks.HuksTag.HUKS_TAG_NONCE, value: iv });
    properties.push({ tag: huks.HuksTag.HUKS_TAG_AE_TAG, value: tag });
    properties.push({ tag: huks.HuksTag.HUKS_TAG_IV, value: iv });
    return properties;
  }

  private randomIv(): Uint8Array {
    try {
      return cryptoFramework.createRandom().generateRandomSync(GCM_IV_BYTES).data;
    } catch (_) {
      throw new Error('Secure random generation failed');
    }
  }

  private isValid(session: RestoredGatewaySession): boolean {
    return session.endpoint.startsWith('https://') && session.clientId.length > 0 &&
      session.credential.length >= 32 && session.dataKey.length > 0 && session.expiresAt > Date.now();
  }
}
