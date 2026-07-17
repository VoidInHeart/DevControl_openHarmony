import { router } from '@kit.ArkUI';
import { DeviceInfo } from '../model/DeviceModel';
import { DeviceManager } from '../model/DeviceManager';
import { DeviceRegistry } from '../model/DeviceRegistry';

@Component
export struct ControlCenterTab {
  @Consume deviceManager: DeviceManager;
  @State selectedRoomId: string = 'all';

  build() {
    Scroll() {
      Column() {
        this.HomeHeader()
        this.RoomFilter()
        this.DeviceSection()
      }
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#EAF5FF')
    .scrollBar(BarState.Auto)
  }

  @Builder
  HomeHeader() {
    Column() {
      Row() {
        Column() {
          Text(this.selectedRoomId === 'all' ? '我的全屋' :
            DeviceRegistry.getRoomLabel(this.selectedRoomId))
            .fontSize(28)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
          Text(this.headerSubtitle())
            .fontSize(13)
            .fontColor('#CDEBFF')
            .margin({ top: 6 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Text('☰')
          .fontSize(30)
          .fontColor(Color.White)
      }
      .width('100%')
      this.MetricRow()
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 28, bottom: 22 })
    .backgroundColor('#197FC7')
  }

  @Builder
  MetricRow() {
    Row() {
      this.MetricCard('🌡', this.averageTemperature(), '温度')
      this.MetricCard('💧', this.averageHumidity(), '湿度')
      this.MetricCard('💡', this.lightsOnCount().toString(), '亮灯')
      this.MetricCard('🔒', this.unlockedDoorCount().toString(), '未锁')
    }
    .width('100%')
    .margin({ top: 22 })
    .justifyContent(FlexAlign.SpaceBetween)
  }

  @Builder
  MetricCard(icon: string, value: string, label: string) {
    Column() {
      Text(icon)
        .fontSize(22)
      Text(value)
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor(Color.White)
        .margin({ top: 4 })
      Text(label)
        .fontSize(11)
        .fontColor('#CDEBFF')
        .margin({ top: 2 })
    }
    .width('23%')
    .padding({ top: 10, bottom: 10 })
    .borderRadius(16)
    .backgroundColor('#287FBA')
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  RoomFilter() {
    Flex({ wrap: FlexWrap.Wrap }) {
      this.RoomButton('all', '全屋')
      ForEach(this.deviceManager.getRoomIds(), (roomId: string) => {
        this.RoomButton(roomId, DeviceRegistry.getRoomLabel(roomId))
      }, (roomId: string) => roomId)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 16, bottom: 8 })
  }

  @Builder
  RoomButton(roomId: string, label: string) {
    Button(label)
      .fontSize(14)
      .fontWeight(roomId === this.selectedRoomId ? FontWeight.Bold : FontWeight.Normal)
      .fontColor(roomId === this.selectedRoomId ? Color.White : $r('app.color.text_primary'))
      .backgroundColor(roomId === this.selectedRoomId ? '#197FC7' : Color.White)
      .borderRadius(18)
      .margin({ right: 8, bottom: 8 })
      .padding({ left: 14, right: 14 })
      .onClick(() => {
        this.selectedRoomId = roomId;
      })
  }

  @Builder
  DeviceSection() {
    Column() {
      Row() {
        Text(this.selectedRoomId === 'all' ? '全屋设备' :
          DeviceRegistry.getRoomLabel(this.selectedRoomId) + '设备')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Blank()
        Text(this.filteredDevices().length.toString() + ' 台设备')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
      .margin({ bottom: 12 })

      if (this.filteredDevices().length === 0) {
        Text('当前房间暂无已同步设备')
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding(32)
      } else {
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
          ForEach(this.filteredDevices(), (device: DeviceInfo) => {
            this.DeviceCard(device)
          }, (device: DeviceInfo) => device.id + ':' + device.stateVersion.toString())
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, bottom: 28 })
  }

  @Builder
  DeviceCard(device: DeviceInfo) {
    Column() {
      Row() {
        Text(this.deviceIcon(device))
          .fontSize(34)
        Blank()
        Text('›')
          .fontSize(30)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
      Text(device.name)
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .margin({ top: 20 })
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(this.deviceSummary(device))
        .fontSize(13)
        .fontColor(device.online ? $r('app.color.text_secondary') : $r('app.color.status_offline'))
        .width('100%')
        .margin({ top: 6 })
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(DeviceRegistry.getRoomLabel(device.roomId))
        .fontSize(11)
        .fontColor('#6C9CC0')
        .width('100%')
        .margin({ top: 8 })
    }
    .width('48.5%')
    .height(166)
    .padding(16)
    .margin({ bottom: 12 })
    .borderRadius(20)
    .backgroundColor(Color.White)
    .onClick(() => {
      this.openDevice(device.id);
    })
  }

  private filteredDevices(): DeviceInfo[] {
    if (this.selectedRoomId === 'all') {
      return this.deviceManager.devices;
    }
    return this.deviceManager.getDevicesByRoom(this.selectedRoomId);
  }

  private deviceIcon(device: DeviceInfo): string {
    return DeviceRegistry.present(device).icon;
  }

  private deviceSummary(device: DeviceInfo): string {
    return DeviceRegistry.present(device).summary;
  }

  private openDevice(deviceId: string): void {
    router.pushUrl({
      url: 'pages/DeviceDetail',
      params: { deviceId: deviceId }
    });
  }

  private headerSubtitle(): string {
    const online = this.deviceManager.getOnlineCount();
    return online.toString() + ' 台设备在线 · ' + this.deviceManager.getConnectionLabel();
  }

  private averageTemperature(): string {
    const sensors = this.deviceManager.getEnvironmentDevices();
    if (sensors.length === 0) {
      return '--';
    }
    let total = 0;
    for (let index = 0; index < sensors.length; index++) {
      total += sensors[index].state.temperatureCelsius;
    }
    return (total / sensors.length).toFixed(1) + '°';
  }

  private averageHumidity(): string {
    const sensors = this.deviceManager.getEnvironmentDevices();
    if (sensors.length === 0) {
      return '--';
    }
    let total = 0;
    for (let index = 0; index < sensors.length; index++) {
      total += sensors[index].state.humidityPercent;
    }
    return (total / sensors.length).toFixed(0) + '%';
  }

  private lightsOnCount(): number {
    let count = 0;
    const lights = this.deviceManager.getLights();
    for (let index = 0; index < lights.length; index++) {
      if (lights[index].state.power) {
        count++;
      }
    }
    return count;
  }

  private unlockedDoorCount(): number {
    let count = 0;
    const doors = this.deviceManager.getDoorLocks();
    for (let index = 0; index < doors.length; index++) {
      if (!doors[index].state.locked) {
        count++;
      }
    }
    return count;
  }
}
