import { router } from '@kit.ArkUI';
import { DoorLockTab } from '../components/DoorLockTab';
import { LightingTab } from '../components/LightingTab';
import { TemperatureTab } from '../components/TemperatureTab';
import { GenericDeviceControl } from '../components/GenericDeviceControl';
import { DeviceInfo, DeviceType } from '../model/DeviceModel';
import { DeviceApplication } from '../model/DeviceApplication';
import { DeviceManager } from '../model/DeviceManager';
import { DeviceRegistry } from '../model/DeviceRegistry';

@Entry
@Component
struct DeviceDetail {
  @Provide deviceManager: DeviceManager = DeviceApplication.getDeviceManager();
  @State deviceId: string = '';

  aboutToAppear(): void {
    const params = router.getParams() as Record<string, Object>;
    const deviceId = params['deviceId'];
    if (typeof deviceId === 'string') {
      this.deviceId = deviceId;
    }
  }

  build() {
    Column() {
      this.NavigationHeader()
      if (this.currentDevice() === null) {
        this.EmptyState()
      } else if ((this.currentDevice() as DeviceInfo).type === DeviceType.LIGHT) {
        LightingTab({ deviceId: this.deviceId, showTitle: false })
      } else if ((this.currentDevice() as DeviceInfo).type === DeviceType.ENVIRONMENT ||
        (this.currentDevice() as DeviceInfo).type === DeviceType.AIR_CONDITIONER) {
        TemperatureTab({ deviceId: this.deviceId, showTitle: false })
      } else if ((this.currentDevice() as DeviceInfo).type === DeviceType.DOOR_LOCK) {
        DoorLockTab({ deviceId: this.deviceId, showTitle: false })
      } else {
        GenericDeviceControl({ deviceId: this.deviceId })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#DCEAF2')
  }

  @Builder
  NavigationHeader() {
    Row() {
      Text('‹')
        .fontSize(40)
        .fontColor('#14263A')
        .width(44)
        .height(48)
        .textAlign(TextAlign.Center)
        .onClick(() => {
          router.back();
        })
      Column() {
        Text(this.currentTitle())
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#14263A')
        Text(this.currentRoom())
          .fontSize(12)
          .fontColor('#748294')
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .height(64)
    .padding({ left: 8, right: 20 })
    .backgroundColor('#DCEAF2')
  }

  @Builder
  EmptyState() {
    Column() {
      Text('设备不可用')
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
      Text('设备可能已被移除，或尚未同步到本地。')
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .margin({ top: 8 })
    }
    .width('100%')
    .layoutWeight(1)
    .padding(24)
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
  }

  private currentDevice(): DeviceInfo | null {
    return this.deviceManager.getDeviceById(this.deviceId);
  }

  private currentTitle(): string {
    const device = this.currentDevice();
    return device === null ? '设备详情' : device.name;
  }

  private currentRoom(): string {
    const device = this.currentDevice();
    return device === null ? '' : DeviceRegistry.getRoomLabel(device.roomId);
  }
}
