import { describe, expect, it } from '@ohos/hypium';
import {
  DeviceType,
  LightDevice,
  parseDevice,
  parseDevices
} from '../main/ets/model/DeviceModel';

function makeLightSnapshot(): Record<string, Object> {
  const automation: Record<string, Object> = {};
  automation['enabled'] = true;
  automation['illuminanceThresholdLux'] = 90;
  automation['noPresenceDelaySeconds'] = 30;
  automation['manualOverrideUntil'] = null;

  const raw: Record<string, Object> = {};
  raw['id'] = 'light-living-01';
  raw['name'] = '客厅主灯';
  raw['roomId'] = 'living';
  raw['type'] = DeviceType.LIGHT;
  raw['online'] = true;
  raw['stateVersion'] = 7;
  raw['updatedAt'] = '2026-07-16T12:00:00+00:00';
  raw['power'] = true;
  raw['brightness'] = 75;
  raw['lastNonZeroBrightness'] = 75;
  raw['automation'] = automation;
  return raw;
}

export default function localUnitTest() {
  describe('DeviceModelContract', () => {
    it('parses discriminated light state', 0, () => {
      const parsed = parseDevice(makeLightSnapshot()) as LightDevice;
      expect(parsed.type).assertEqual(DeviceType.LIGHT);
      expect(parsed.stateVersion).assertEqual(7);
      expect(parsed.state.brightness).assertEqual(75);
      expect(parsed.state.automation.enabled).assertTrue();
    });

    it('rejects malformed snapshots', 0, () => {
      let rejected = false;
      try {
        parseDevices('not-an-array');
      } catch (error) {
        rejected = true;
      }
      expect(rejected).assertTrue();
    });
  });
}
