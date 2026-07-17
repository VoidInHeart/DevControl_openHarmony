import { common } from '@kit.AbilityKit';
import { ControlCenterTab } from '../components/ControlCenterTab';
import { PairingPage } from '../components/PairingPage';
import { RoomTab } from '../components/RoomTab';
import { SettingsTab } from '../components/SettingsTab';
import { DeviceApplication } from '../model/DeviceApplication';
import { DeviceManager } from '../model/DeviceManager';
import { DeviceRegistry } from '../model/DeviceRegistry';

@Entry
@Component
struct Index {
  @Provide deviceManager: DeviceManager = DeviceApplication.getDeviceManager();
  @State currentTag: string = 'all';

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
        this.TopTagBar()
        if (this.currentTag === 'all') {
          ControlCenterTab()
        } else if (this.currentTag === 'settings') {
          SettingsTab()
        } else {
          RoomTab({ roomId: this.currentTag })
        }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.start_window_background'))
  }

  @Builder
  TopTagBar() {
    Scroll() {
      Row() {
        this.TagButton('all', '总控')
        ForEach(this.availableRoomIds(), (roomId: string) => {
          this.TagButton(roomId, DeviceRegistry.getRoomLabel(roomId))
        }, (roomId: string) => roomId)
        this.TagButton('settings', '设置')
      }
      .padding({ left: 12, right: 12 })
    }
    .width('100%')
    .height(58)
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .backgroundColor(Color.White)
  }

  @Builder
  TagButton(tag: string, label: string) {
    Button(label)
      .fontSize(16)
      .fontWeight(tag === this.currentTag ? FontWeight.Bold : FontWeight.Normal)
      .fontColor(tag === this.currentTag ? $r('app.color.primary') : $r('app.color.text_secondary'))
      .backgroundColor(Color.Transparent)
      .height(58)
      .borderRadius(0)
      .margin({ right: 6 })
      .onClick(() => {
        this.currentTag = tag;
      })
  }

  private availableRoomIds(): string[] {
    const allRoomIds = this.deviceManager.getRoomIds();
    const result: string[] = [];
    for (let index = 0; index < allRoomIds.length; index++) {
      if (this.deviceManager.getDevicesByRoom(allRoomIds[index]).length > 0) {
        result.push(allRoomIds[index]);
      }
    }
    return result;
  }
}
