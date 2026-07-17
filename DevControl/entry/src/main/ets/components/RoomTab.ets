import { DeviceInfo } from '../model/DeviceModel';
import { DeviceManager } from '../model/DeviceManager';
import { DeviceRegistry } from '../model/DeviceRegistry';
import { DeviceListItem } from './DeviceListItem';

@Component
export struct RoomTab {
  @Consume deviceManager: DeviceManager;
  @Prop roomId: string = '';
  @Prop showTitle: boolean = true;

  build() {
    Scroll() {
      Column() {
        if (this.showTitle) {
          Text(DeviceRegistry.getRoomLabel(this.roomId))
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
            .margin({ bottom: 4 })
          Text(this.roomDevices().length.toString() + ' 台房间设备')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
            .margin({ bottom: 16 })
        }
        if (this.roomDevices().length === 0) {
          this.EmptyState()
        } else {
          ForEach(this.roomDevices(), (device: DeviceInfo) => {
            DeviceListItem({ device: device })
          }, (device: DeviceInfo) => device.id + ':' + device.stateVersion.toString())
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 20, bottom: 28 })
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Auto)
  }

  @Builder
  EmptyState() {
    Column() {
      Text('⌂')
        .fontSize(44)
      Text('这个房间还没有可展示的设备')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .margin({ top: 12 })
      Text('门锁仅在全屋总控的功能入口中展示。')
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .margin({ top: 8 })
    }
    .width('100%')
    .padding(32)
    .borderRadius(20)
    .backgroundColor(Color.White)
    .alignItems(HorizontalAlign.Center)
  }

  private roomDevices(): DeviceInfo[] {
    return this.deviceManager.getDevicesByRoom(this.roomId);
  }
}
