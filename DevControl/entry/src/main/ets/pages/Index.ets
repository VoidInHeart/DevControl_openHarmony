import { common } from '@kit.AbilityKit';
import { DeviceManager } from '../model/DeviceManager';
import { ControlCenterTab } from '../components/ControlCenterTab';
import { LightingTab } from '../components/LightingTab';
import { TemperatureTab } from '../components/TemperatureTab';
import { DoorLockTab } from '../components/DoorLockTab';
import { PairingPage } from '../components/PairingPage';
import { SettingsTab } from '../components/SettingsTab';

@Entry
@Component
struct Index {
  @Provide deviceManager: DeviceManager = new DeviceManager();
  @State currentTab: number = 0;

  aboutToAppear(): void {
    const context = getContext(this) as common.UIAbilityContext;
    this.deviceManager.initialize(context);
  }

  onPageShow(): void {
    if (
      this.deviceManager.initialized &&
      !this.deviceManager.pairingRequired &&
      !this.deviceManager.isOnline()
    ) {
      this.deviceManager.reconnect();
    }
  }

  build() {
    Column() {
      if (this.deviceManager.pairingRequired) {
        PairingPage()
      } else {
        Tabs({ index: this.currentTab }) {
          TabContent() {
            ControlCenterTab()
          }
          .tabBar('总控')

          TabContent() {
            LightingTab()
          }
          .tabBar('照明')

          TabContent() {
            TemperatureTab()
          }
          .tabBar('环境')

          TabContent() {
            DoorLockTab()
          }
          .tabBar('门锁')

          TabContent() {
            SettingsTab()
          }
          .tabBar('设置')
        }
        .width('100%')
        .layoutWeight(1)
        .barMode(BarMode.Fixed)
        .onChange((index: number) => {
          this.currentTab = index;
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.start_window_background'))
  }
}
