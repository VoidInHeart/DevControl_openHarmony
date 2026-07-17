import { describe, expect, it } from '@ohos/hypium';
import { DeviceRegistry } from '../main/ets/model/DeviceRegistry';
import { DeviceType, LightDevice } from '../main/ets/model/DeviceModel';

function makeLight(roomId: string, isOn: boolean): LightDevice {
  const device = new LightDevice();
  device.id = 'light-' + roomId;
  device.name = '测试灯';
  device.roomId = roomId;
  device.online = true;
  device.state.power = isOn;
  device.state.brightness = 60;
  return device;
}

export default function deviceRegistryTest() {
  describe('DeviceRegistry', () => {
    it('exposes capabilities for each registered device family', 0, () => {
      expect(DeviceRegistry.supportsAction(DeviceType.LIGHT, 'setBrightness')).assertTrue();
      expect(DeviceRegistry.supportsAction(DeviceType.ENVIRONMENT, 'setPower')).assertFalse();
      expect(DeviceRegistry.supportsAction('unknown', 'setPower')).assertFalse();
    });

    it('groups rooms and creates a reusable device presentation', 0, () => {
      const rooms = DeviceRegistry.getRoomIds([
        makeLight('living', true),
        makeLight('bedroom', false),
        makeLight('living', true)
      ]);
      expect(rooms.length).assertEqual(2);
      expect(DeviceRegistry.getRoomLabel(rooms[0])).assertEqual('客厅');
      const presentation = DeviceRegistry.present(makeLight('living', true));
      expect(presentation.title).assertEqual('测试灯');
      expect(presentation.summary).assertEqual('已开启 · 60%');
    });
  });
}
