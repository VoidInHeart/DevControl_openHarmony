import { describe, expect, it } from '@ohos/hypium';
import { DeviceRegistry } from '../main/ets/model/DeviceRegistry';
import { DeviceType, DoorLockDevice, LightDevice } from '../main/ets/model/DeviceModel';
import {
  DeviceCategory,
  DeviceControl,
  DeviceControlKind,
  GenericDevice
} from '../main/ets/model/GenericDeviceModel';

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
function makeCurtain(): GenericDevice {
  const device = new GenericDevice();
  device.id = 'curtain-living-01';
  device.name = '测试窗帘';
  device.roomId = 'living';
  device.type = 'curtain';
  device.online = true;
  device.stateVersion = 1;
  const category = new DeviceCategory();
  category.id = 'curtains';
  category.title = '窗帘';
  category.icon = '🪟';
  device.category = category;
  device.state['positionPercent'] = 30;
  const control = new DeviceControl();
  control.id = 'position';
  control.kind = DeviceControlKind.SLIDER;
  control.label = '开合度';
  control.action = 'setPosition';
  control.stateKey = 'positionPercent';
  control.payloadKey = 'positionPercent';
  control.minimum = 0;
  control.maximum = 100;
  control.step = 1;
  control.unit = '%';
  control.primary = true;
  device.controls = [control];
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
      expect(features.length).assertEqual(3);
      expect(DeviceRegistry.getDevicesByFeature([light, doorLock], 'lighting').length)
        .assertEqual(1);
      expect(DeviceRegistry.getDevicesByFeature([light, doorLock], 'locks').length)
        .assertEqual(1);
      expect(DeviceRegistry.getDevicesByFeature([light, doorLock], 'curtains').length)
        .assertEqual(0);
      expect(DeviceRegistry.getRoomDevices([light, doorLock], 'living').length).assertEqual(1);
    });
    it('discovers generic categories, actions and presentations', 0, () => {
      const curtain = makeCurtain();
      expect(DeviceRegistry.supportsDeviceAction(curtain, 'setPosition')).assertTrue();
      expect(DeviceRegistry.getDevicesByFeature([curtain], 'curtains').length)
        .assertEqual(1);
      expect(DeviceRegistry.getRoomDevices([curtain], 'living').length)
        .assertEqual(1);
      expect(DeviceRegistry.present(curtain).summary).assertEqual('开合度 · 30%');

      curtain.category.id = 'shades';
      curtain.category.title = '遮阳';
      expect(DeviceRegistry.getHomeFeatures([curtain]).length).assertEqual(4);
      const feature = DeviceRegistry.getFeature('shades', [curtain]);
      expect(feature === null ? '' : feature.title).assertEqual('遮阳');
    });
  });
}
