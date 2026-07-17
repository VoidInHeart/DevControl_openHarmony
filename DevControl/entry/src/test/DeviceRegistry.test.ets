import { describe, expect, it } from '@ohos/hypium';
import { DeviceRegistry } from '../main/ets/model/DeviceRegistry';
import { DeviceType, DoorLockDevice, LightDevice } from '../main/ets/model/DeviceModel';

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

function makeDoorLock(roomId: string): DoorLockDevice {
  const device = new DoorLockDevice();
  device.id = 'lock-' + roomId;
  device.name = '测试门锁';
  device.roomId = roomId;
  device.online = true;
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

    it('keeps locks in the all-home feature while excluding them from rooms', 0, () => {
      const light = makeLight('living', true);
      const doorLock = makeDoorLock('living');
      const features = DeviceRegistry.getHomeFeatures();
      expect(features.length).assertEqual(4);
      expect(DeviceRegistry.getDevicesByFeature([light, doorLock], 'lighting').length)
        .assertEqual(1);
      expect(DeviceRegistry.getDevicesByFeature([light, doorLock], 'locks').length)
        .assertEqual(1);
      expect(DeviceRegistry.getDevicesByFeature([light, doorLock], 'curtains').length)
        .assertEqual(0);
      expect(DeviceRegistry.getRoomDevices([light, doorLock], 'living').length).assertEqual(1);
    });
  });
}
