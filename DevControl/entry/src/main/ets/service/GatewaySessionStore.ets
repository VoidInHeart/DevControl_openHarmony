import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { huks } from '@kit.UniversalKeystoreKit';
import native from 'libentry.so';
import { GatewaySession } from '../model/DeviceModel';

const KEY_ALIAS = 'devcontrol.gateway.session.wrap.v1';
const PREFERENCES_NAME = 'devcontrol_gateway_session';
const SESSION_BLOB_KEY = 'encryptedSession';
const SESSION_VERSION = 1;
const SESSION_AAD = 'DevControl/GatewaySession/v1';
const GCM_TAG_LENGTH = 16;
const HUKS_ITEM_NOT_EXIST = 12000011;

class StoredSessionBlob {
  version: number = SESSION_VERSION;
  iv: string = '';
  ciphertext: string = '';
  authTag: string = '';
}

export class GatewaySessionStore {
  private context: common.UIAbilityContext;
  private base64: util.Base64Helper = new util.Base64Helper();
  private encoder: util.TextEncoder = util.TextEncoder.create();
  private decoder: util.TextDecoder = util.TextDecoder.create('utf-8');

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  async save(session: GatewaySession): Promise<void> {
    await this.ensureWrappingKey();
    const iv = await this.secureRandom(12);
    const plaintext = this.encoder.encodeInto(JSON.stringify(session));
    const ciphertext = await this.crypt(
      huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT,
      iv,
      plaintext,
      null
    );
    if (ciphertext.length <= GCM_TAG_LENGTH) {
      throw new Error('HUKS encrypted output is too short');
    }
    const encryptedData = ciphertext.slice(0, ciphertext.length - GCM_TAG_LENGTH);
    const authTag = ciphertext.slice(ciphertext.length - GCM_TAG_LENGTH);
    const blob = new StoredSessionBlob();
    blob.iv = this.base64.encodeToStringSync(iv, util.Type.BASIC_URL_SAFE);
    blob.ciphertext =
      this.base64.encodeToStringSync(encryptedData, util.Type.BASIC_URL_SAFE);
    blob.authTag =
      this.base64.encodeToStringSync(authTag, util.Type.BASIC_URL_SAFE);
    const store = await preferences.getPreferences(this.context, PREFERENCES_NAME);
    await store.put(SESSION_BLOB_KEY, JSON.stringify(blob));
    await store.flush();
  }

  async restore(): Promise<GatewaySession | null> {
    const exists = await this.keyItemExists();
    if (!exists) {
      return null;
    }
    const store = await preferences.getPreferences(this.context, PREFERENCES_NAME);
    const blobText = await store.get(SESSION_BLOB_KEY, '') as string;
    if (blobText.length === 0) {
      return null;
    }
    const rawBlob = JSON.parse(blobText) as Record<string, Object>;
    const version = rawBlob['version'];
    const ivText = rawBlob['iv'];
    const ciphertextText = rawBlob['ciphertext'];
    const authTagText = rawBlob['authTag'];
    if (
      version !== SESSION_VERSION ||
      typeof ivText !== 'string' ||
      typeof ciphertextText !== 'string' ||
      typeof authTagText !== 'string' ||
      ivText.length === 0 ||
      ciphertextText.length === 0 ||
      authTagText.length === 0
    ) {
      throw new Error('Stored gateway session envelope is invalid');
    }
    const iv = this.base64.decodeSync(ivText, util.Type.BASIC_URL_SAFE);
    const encryptedData =
      this.base64.decodeSync(ciphertextText, util.Type.BASIC_URL_SAFE);
    const authTag = this.base64.decodeSync(authTagText, util.Type.BASIC_URL_SAFE);
    if (iv.length !== 12 || authTag.length !== GCM_TAG_LENGTH) {
      throw new Error('Stored gateway session nonce or tag is invalid');
    }
    const plaintext = await this.crypt(
      huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT,
      iv,
      encryptedData,
      authTag
    );
    const parsed = JSON.parse(this.decoder.decodeToString(plaintext)) as Record<string, Object>;
    const session = new GatewaySession();
    session.protocolVersion = parsed['protocolVersion'] as string;
    session.clientId = parsed['clientId'] as string;
    session.gatewayAddress = parsed['gatewayAddress'] as string;
    session.credential = parsed['credential'] as string;
    session.dataKey = parsed['dataKey'] as string;
    session.issuedAt = parsed['issuedAt'] as number;
    const expiresAt = parsed['expiresAt'];
    if (
      session.protocolVersion !== '1.0' ||
      session.gatewayAddress.indexOf('https://') !== 0 ||
      session.credential.length === 0 ||
      session.dataKey.length === 0 ||
      typeof expiresAt !== 'number' ||
      expiresAt <= session.issuedAt
    ) {
      throw new Error('Stored gateway session is invalid');
    }
    session.expiresAt = expiresAt as number;
    if (session.expiresAt <= Date.now()) {
      await this.clear();
      throw new Error('AUTH_FAILED:Stored gateway session has expired');
    }
    return session;
  }

  async clear(): Promise<void> {
    const store = await preferences.getPreferences(this.context, PREFERENCES_NAME);
    await store.clear();
    await store.flush();
  }

  private async ensureWrappingKey(): Promise<void> {
    const exists = await this.keyItemExists();
    if (exists) {
      return;
    }
    const properties: huks.HuksParam[] = [
      {
        tag: huks.HuksTag.HUKS_TAG_ALGORITHM,
        value: huks.HuksKeyAlg.HUKS_ALG_AES
      },
      {
        tag: huks.HuksTag.HUKS_TAG_KEY_SIZE,
        value: huks.HuksKeySize.HUKS_AES_KEY_SIZE_256
      },
      {
        tag: huks.HuksTag.HUKS_TAG_PURPOSE,
        value: huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT |
          huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT
      },
      {
        tag: huks.HuksTag.HUKS_TAG_BLOCK_MODE,
        value: huks.HuksCipherMode.HUKS_MODE_GCM
      },
      {
        tag: huks.HuksTag.HUKS_TAG_PADDING,
        value: huks.HuksKeyPadding.HUKS_PADDING_NONE
      }
    ];
    await huks.generateKeyItem(KEY_ALIAS, { properties: properties });
  }

  private async keyItemExists(): Promise<boolean> {
    try {
      return await huks.isKeyItemExist(KEY_ALIAS, {});
    } catch (error) {
      const businessError = error as BusinessError;
      if (businessError.code === HUKS_ITEM_NOT_EXIST) {
        return false;
      }
      const message = error instanceof Error ? error.message : JSON.stringify(error);
      throw new Error(message);
    }
  }

  private async secureRandom(length: number): Promise<Uint8Array> {
    if (length !== 12) {
      throw new Error('Only 96-bit HUKS IVs are supported');
    }
    return this.base64.decodeSync(native.generateNonce(), util.Type.BASIC_URL_SAFE);
  }

  private async crypt(
    purpose: huks.HuksKeyPurpose,
    iv: Uint8Array,
    input: Uint8Array,
    authTag: Uint8Array | null
  ): Promise<Uint8Array> {
    const properties: huks.HuksParam[] = [
      {
        tag: huks.HuksTag.HUKS_TAG_ALGORITHM,
        value: huks.HuksKeyAlg.HUKS_ALG_AES
      },
      {
        tag: huks.HuksTag.HUKS_TAG_PURPOSE,
        value: purpose
      },
      {
        tag: huks.HuksTag.HUKS_TAG_BLOCK_MODE,
        value: huks.HuksCipherMode.HUKS_MODE_GCM
      },
      {
        tag: huks.HuksTag.HUKS_TAG_PADDING,
        value: huks.HuksKeyPadding.HUKS_PADDING_NONE
      },
      {
        tag: huks.HuksTag.HUKS_TAG_NONCE,
        value: iv
      },
      {
        tag: huks.HuksTag.HUKS_TAG_ASSOCIATED_DATA,
        value: this.encoder.encodeInto(SESSION_AAD)
      }
    ];
    if (purpose === huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT) {
      if (authTag === null || authTag.length !== GCM_TAG_LENGTH) {
        throw new Error('HUKS AES-GCM authentication tag is invalid');
      }
      properties.push({
        tag: huks.HuksTag.HUKS_TAG_AE_TAG,
        value: authTag
      });
    }
    const handle = await huks.initSession(KEY_ALIAS, { properties: properties });
    try {
      const result = await huks.finishSession(handle.handle, {
        properties: properties,
        inData: input
      });
      if (result.outData === undefined) {
        throw new Error('HUKS returned no output');
      }
      return result.outData;
    } catch (error) {
      const message = error instanceof Error ? error.message : JSON.stringify(error);
      try {
        await huks.abortSession(handle.handle, {});
      } catch (abortError) {
        // finishSession may already have consumed the handle. Cleanup is
        // best-effort and must never replace the original HUKS failure.
      }
      throw new Error(message);
    }
  }
}
