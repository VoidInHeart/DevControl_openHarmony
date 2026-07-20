import { describe, expect, it } from '@ohos/hypium';
import {
  DeviceType,
  LightDevice,
  parseDevice,
  parseDevices,
  serializeDevice
} from '../main/ets/model/DeviceModel';
import { GenericDevice } from '../main/ets/model/GenericDeviceModel';
import { describeHttpBusinessError } from '../main/ets/service/NetworkErrorMessage';

function makeLightSnapshot(): Record<string, Object> {
  const automation: Record<string, Object> = {};
  automation['enabled'] = true;
  automation['illuminanceThresholdLux'] = 90;
  automation['noPresenceDelaySeconds'] = 30;

  const raw: Record<string, Object> = {};
  raw['id'] = 'light-living-01';
  raw['name'] = '客厅主灯';
  raw['roomId'] = 'living';
  raw['type'] = DeviceType.LIGHT;
  raw['online'] = true;
  raw['removable'] = true;
  raw['stateVersion'] = 7;
  raw['updatedAt'] = '2026-07-16T12:00:00+00:00';
  raw['power'] = true;
  raw['brightness'] = 75;
  raw['lastNonZeroBrightness'] = 75;
  raw['automation'] = automation;
  return raw;
}
function makeCurtainSnapshot(): Record<string, Object> {
  const category: Record<string, Object> = {
    'id': 'curtains',
    'title': '窗帘',
    'icon': '🪟',
    'homeOnly': false
  };
  const state: Record<string, Object> = {
    'positionPercent': 30,
    'targetPositionPercent': 60,
    'movement': 'opening'
  };
  const slider: Record<string, Object> = {
    'id': 'position',
    'kind': 'slider',
    'label': '开合度',
    'action': 'setPosition',
    'stateKey': 'positionPercent',
    'payloadKey': 'positionPercent',
    'minimum': 0,
    'maximum': 100,
    'step': 1,
    'unit': '%',
    'primary': true
  };
  return {
    'id': 'curtain-living-01',
    'name': '客厅智能窗帘',
    'roomId': 'living',
    'type': 'curtain',
    'online': true,
    'stateVersion': 3,
    'updatedAt': '2026-07-18T00:00:00+00:00',
    'category': category,
    'state': state,
    'controls': [slider]
  };
}

export default function localUnitTest() {
  describe('DeviceModelContract', () => {
    it('parses discriminated light state', 0, () => {
      const parsed = parseDevice(makeLightSnapshot()) as LightDevice;
      expect(parsed.type).assertEqual(DeviceType.LIGHT);
      expect(parsed.stateVersion).assertEqual(7);
      expect(parsed.state.brightness).assertEqual(75);
      expect(parsed.state.automation.enabled).assertTrue();
      expect(parsed.removable).assertTrue();
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
    it('parses, validates and serializes generic capability devices', 0, () => {
      const parsed = parseDevice(makeCurtainSnapshot()) as GenericDevice;
      expect(parsed.type).assertEqual('curtain');
      expect(parsed.controls.length).assertEqual(1);
      expect(parsed.state['positionPercent'] as number).assertEqual(30);

      const serialized = serializeDevice(parsed);
      const state = serialized['state'] as Record<string, Object>;
      expect(state['targetPositionPercent'] as number).assertEqual(60);
    });

    it('isolates malformed optional generic devices in a snapshot', 0, () => {
      const malformed: Record<string, Object> = {
        'id': 'broken-device',
        'name': '损坏设备',
        'roomId': 'living',
        'type': 'futureDevice'
      };
      const parsed = parseDevices([makeCurtainSnapshot(), malformed]);
      expect(parsed.length).assertEqual(1);
      expect(parsed[0].type).assertEqual('curtain');
    });

    it('rejects unsafe state keys and invalid slider ranges', 0, () => {
      const invalidState = makeCurtainSnapshot();
      const state = invalidState['state'] as Record<string, Object>;
      state['unsafe key'] = 1;
      expect(parseDevices([invalidState]).length).assertEqual(0);

      const invalidSlider = makeCurtainSnapshot();
      const controls = invalidSlider['controls'] as Record<string, Object>[];
      controls[0]['step'] = 0;
      expect(parseDevices([invalidSlider]).length).assertEqual(0);
    });

    it('turns NetworkKit failures into actionable pairing messages', 0, () => {
      expect(describeHttpBusinessError(2300028)).assertContain('无法连接网关');
      expect(describeHttpBusinessError(2300060)).assertContain('证书校验失败');
      expect(describeHttpBusinessError(2300006)).assertContain('无法解析网关地址');
      expect(describeHttpBusinessError(2300001)).assertContain('2300001');
    });
  });
}
