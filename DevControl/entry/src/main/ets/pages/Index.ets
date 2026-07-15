import { DeviceManager } from '../model/DeviceManager';
import { Constants } from '../common/Constants';
import { ControlCenterTab } from '../components/ControlCenterTab';
import { LightingTab } from '../components/LightingTab';
import { TemperatureTab } from '../components/TemperatureTab';
import { DoorLockTab } from '../components/DoorLockTab';
import { Context } from '@kit.AbilityKit';

@Entry
@Component
struct Index {
  @Provide deviceManager: DeviceManager = new DeviceManager();
  @State currentTab: number = 0;

  aboutToAppear(): void {
    const context = this.getUIContext().getHostContext() as Context;
    this.deviceManager.init(context);
    this.deviceManager.startTick(Constants.TICK_INTERVAL_MS);
  }

  aboutToDisappear(): void {
    this.deviceManager.close();
  }

  build() {
    Column() {
      Tabs({ index: this.currentTab }) {
        TabContent() {
          ControlCenterTab()
        }
        .tabBar('Control')

        TabContent() {
          LightingTab()
        }
        .tabBar('Lighting')

        TabContent() {
          TemperatureTab()
        }
        .tabBar('Climate')

        TabContent() {
          DoorLockTab()
        }
        .tabBar('Door')
      }
      .width('100%')
      .layoutWeight(1)
      .barMode(BarMode.Fixed)
      .onChange((index: number) => {
        this.currentTab = index;
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.start_window_background'))
  }
}
