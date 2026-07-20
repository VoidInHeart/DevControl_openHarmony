import abilityDelegatorRegistry from '@ohos.app.ability.abilityDelegatorRegistry';
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { describe, expect, it } from '@ohos/hypium';
import { GatewaySession } from '../../../main/ets/model/DeviceModel';
import { GatewaySessionStore } from '../../../main/ets/service/GatewaySessionStore';

const PREFERENCES_NAME = 'devcontrol_gateway_session';
const SESSION_BLOB_KEY = 'encryptedSession';

function testSession(): GatewaySession {
  const session = new GatewaySession();
  session.protocolVersion = '1.0';
  session.clientId = 'huks-instrument-test-client';
  session.gatewayAddress = 'https://127.0.0.1:8443';
  session.credential = 'test-credential';
  session.dataKey = 'test-data-key';
  session.issuedAt = 1700000000000;
  session.expiresAt = Date.now() + 60000;
  return session;
}

export default function gatewaySessionStoreTest() {
  describe('GatewaySessionStoreTest', () => {
    it('restoresValidSessionAndRejectsTamperedAuthTag', 0, async () => {
      const context = (await abilityDelegatorRegistry.getAbilityDelegator()
        .getCurrentTopAbility()).context as common.UIAbilityContext;
      const preferencesStore = await preferences.getPreferences(
        context,
        PREFERENCES_NAME
      );
      const previousBlob = await preferencesStore.get(SESSION_BLOB_KEY, '') as string;
      const sessionStore = new GatewaySessionStore(context);
      try {
        const expected = testSession();
        await sessionStore.save(expected);
        const restored = await sessionStore.restore();
        expect(restored !== null).assertTrue();
        expect(restored?.clientId).assertEqual(expected.clientId);
        expect(restored?.credential).assertEqual(expected.credential);
        expect(restored?.dataKey).assertEqual(expected.dataKey);
        expect(restored?.expiresAt).assertEqual(expected.expiresAt);

        const blobText = await preferencesStore.get(SESSION_BLOB_KEY, '') as string;
        const blob = JSON.parse(blobText) as Record<string, Object>;
        const authTag = blob['authTag'] as string;
        blob['authTag'] = (authTag.startsWith('A') ? 'B' : 'A') + authTag.substring(1);
        await preferencesStore.put(SESSION_BLOB_KEY, JSON.stringify(blob));
        await preferencesStore.flush();

        let rejected = false;
        try {
          await sessionStore.restore();
        } catch (error) {
          rejected = true;
        }
        expect(rejected).assertTrue();
      } finally {
        if (previousBlob.length > 0) {
          await preferencesStore.put(SESSION_BLOB_KEY, previousBlob);
        } else {
          await preferencesStore.delete(SESSION_BLOB_KEY);
        }
        await preferencesStore.flush();
      }
    });
  });
}
