import { router } from '@kit.ArkUI';
import { RoomTab } from '../components/RoomTab';
import { DeviceApplication } from '../model/DeviceApplication';
import { DeviceManager } from '../model/DeviceManager';
import { DeviceRegistry } from '../model/DeviceRegistry';

@Entry
@Component
struct RoomDevices {
  @Provide deviceManager: DeviceManager = DeviceApplication.getDeviceManager();
  @State roomId: string = '';

  aboutToAppear(): void {
    const params = router.getParams() as Record<string, Object>;
    const roomId = params['roomId'];
    if (typeof roomId === 'string') {
      this.roomId = roomId;
    }
  }

  build() {
    Column() {
      this.NavigationHeader()
      RoomTab({ roomId: this.roomId, showTitle: false })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#EAF5FF')
  }

  @Builder
  NavigationHeader() {
    Row() {
      Text('‹')
        .fontSize(40)
        .fontColor($r('app.color.text_primary'))
        .width(44)
        .height(48)
        .textAlign(TextAlign.Center)
        .onClick(() => {
          router.back();
        })
      Text(DeviceRegistry.getRoomLabel(this.roomId))
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
    }
    .width('100%')
    .height(64)
    .padding({ left: 8, right: 20 })
    .backgroundColor(Color.White)
  }
}
