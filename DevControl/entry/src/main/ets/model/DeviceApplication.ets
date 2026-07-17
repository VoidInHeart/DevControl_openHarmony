import { DeviceManager } from './DeviceManager';

/**
 * Keeps one observable device session alive while ArkUI moves between pages.
 */
export class DeviceApplication {
  private static readonly deviceManager: DeviceManager = new DeviceManager();

  static getDeviceManager(): DeviceManager {
    return DeviceApplication.deviceManager;
  }
}
