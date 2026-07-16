import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import {
  DeviceInfo,
  parseDevices,
  serializeDevice
} from '../model/DeviceModel';

const PREFERENCES_NAME = 'devcontrol_device_snapshot';
const DEVICES_KEY = 'devices';
const LAST_SYNC_KEY = 'lastSyncAt';

export class CachedDeviceSnapshot {
  devices: DeviceInfo[] = [];
  lastSyncAt: number = 0;
}

export class DeviceSnapshotStore {
  private context: common.UIAbilityContext;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  async save(devices: DeviceInfo[], lastSyncAt: number): Promise<void> {
    const raw: Record<string, Object>[] = [];
    for (let index = 0; index < devices.length; index++) {
      raw.push(serializeDevice(devices[index]));
    }
    const store = await preferences.getPreferences(this.context, PREFERENCES_NAME);
    await store.put(DEVICES_KEY, JSON.stringify(raw));
    await store.put(LAST_SYNC_KEY, lastSyncAt);
    await store.flush();
  }

  async restore(): Promise<CachedDeviceSnapshot | null> {
    const store = await preferences.getPreferences(this.context, PREFERENCES_NAME);
    const text = await store.get(DEVICES_KEY, '') as string;
    const lastSyncAt = await store.get(LAST_SYNC_KEY, 0) as number;
    if (text.length === 0 || lastSyncAt <= 0) {
      return null;
    }
    const parsed = JSON.parse(text) as Object;
    const snapshot = new CachedDeviceSnapshot();
    snapshot.devices = parseDevices(parsed);
    snapshot.lastSyncAt = lastSyncAt;
    return snapshot;
  }

  async clear(): Promise<void> {
    const store = await preferences.getPreferences(this.context, PREFERENCES_NAME);
    await store.clear();
    await store.flush();
  }
}
