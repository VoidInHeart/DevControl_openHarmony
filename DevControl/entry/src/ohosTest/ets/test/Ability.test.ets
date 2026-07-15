import abilityDelegatorRegistry from '@ohos.app.ability.abilityDelegatorRegistry';
import { describe, beforeAll, beforeEach, afterEach, afterAll, it, expect } from '@ohos/hypium';
import { GatewaySessionStore } from '../../../main/ets/infrastructure/GatewaySessionStore';
import { PairingResult } from '../../../main/ets/model/GatewayModels';

export default function abilityTest() {
  describe('ActsAbilityTest', () => {
    // Defines a test suite. Two parameters are supported: test suite name and test suite function.
    beforeAll(() => {
      // Presets an action, which is performed only once before all test cases of the test suite start.
      // This API supports only one parameter: preset action function.
    })
    beforeEach(() => {
      // Presets an action, which is performed before each unit test case starts.
      // The number of execution times is the same as the number of test cases defined by **it**.
      // This API supports only one parameter: preset action function.
    })
    afterEach(() => {
      // Presets a clear action, which is performed after each unit test case ends.
      // The number of execution times is the same as the number of test cases defined by **it**.
      // This API supports only one parameter: clear action function.
    })
    afterAll(() => {
      // Presets a clear action, which is performed after all test cases of the test suite end.
      // This API supports only one parameter: clear action function.
    })
    it('persistsGatewaySessionWithHuks', 0, async () => {
      const ability = await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility();
      const store = new GatewaySessionStore(ability.context);
      const pairing = new PairingResult();
      pairing.clientId = 'instrument-test-client';
      pairing.credential = 'instrument-test-credential-0000000000000001';
      pairing.dataKey = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=';
      pairing.expiresAt = Date.now() + 60_000;

      await store.clear();
      try {
        await store.save('https://127.0.0.1:9443', pairing);
        const restored = await store.restore();
        expect(restored === null).assertFalse();
        expect(restored?.endpoint).assertEqual('https://127.0.0.1:9443');
        expect(restored?.clientId).assertEqual(pairing.clientId);
        expect(restored?.credential).assertEqual(pairing.credential);
        expect(restored?.dataKey).assertEqual(pairing.dataKey);
        expect(restored?.expiresAt).assertEqual(pairing.expiresAt);
      } finally {
        await store.clear();
      }
    })
  })
}
