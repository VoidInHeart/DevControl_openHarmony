import { DeviceInfo, DeviceType } from '../model/DeviceModel';
import { DeviceManager } from '../model/DeviceManager';

@Component
export struct ControlCenterTab {
  @Consume deviceManager: DeviceManager;

  build() {
    Scroll() {
      Column() {
        this.StatsSection()
        this.SceneSection()
        this.DeviceListSection()
      }
      .width('100%')
      .padding(16)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Auto)
  }

  @Builder
  StatsSection() {
    Row() {
      Column() {
        Text(this.deviceManager.getOnlineCount().toString())
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.status_online'))
        Text('Online')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 4 })
      }
      .layoutWeight(1)
      .padding(16)
      .borderRadius(12)
      .backgroundColor($r('app.color.card_background'))
      .alignItems(HorizontalAlign.Center)

      Column() {
        Text(this.deviceManager.getOfflineCount().toString())
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.status_offline'))
        Text('Offline')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 4 })
      }
      .layoutWeight(1)
      .padding(16)
      .borderRadius(12)
      .backgroundColor($r('app.color.card_background'))
      .alignItems(HorizontalAlign.Center)
      .margin({ left: 8 })

      Column() {
        Text(this.deviceManager.alerts.length.toString())
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.status_alert'))
        Text('Alerts')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 4 })
      }
      .layoutWeight(1)
      .padding(16)
      .borderRadius(12)
      .backgroundColor($r('app.color.card_background'))
      .alignItems(HorizontalAlign.Center)
      .margin({ left: 8 })
    }
    .width('100%')
    .margin({ bottom: 16 })
  }

  @Builder
  SceneSection() {
    Column() {
      Text('Quick Scenes')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .margin({ bottom: 12 })

      Row() {
        ForEach(this.deviceManager.scenes, (scene: Record<string, string>) => {
          Button(scene['name'])
            .fontSize(14)
            .fontColor(Color.White)
            .backgroundColor($r('app.color.primary'))
            .borderRadius(20)
            .padding({ left: 20, right: 20, top: 8, bottom: 8 })
            .onClick(() => {
              this.deviceManager.executeScene(scene['id']);
            })
        }, (scene: Record<string, string>) => scene['id'])
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceAround)
    }
    .width('100%')
    .padding(16)
    .borderRadius(12)
    .backgroundColor($r('app.color.card_background'))
    .margin({ bottom: 16 })
  }

  @Builder
  DeviceListSection() {
    Column() {
      Text('All Devices')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .margin({ bottom: 12 })

      ForEach(this.deviceManager.devices, (device: DeviceInfo) => {
        Row() {
          Text(this.getDeviceIcon(device))
            .fontSize(24)
          Column() {
            Text(device.name)
              .fontSize(15)
              .fontColor($r('app.color.text_primary'))
            Text(device.state.online ? 'Online' : 'Offline')
              .fontSize(12)
              .fontColor(device.state.online ? $r('app.color.status_online') : $r('app.color.status_offline'))
              .margin({ top: 2 })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          .margin({ left: 12 })
          Text(this.getDeviceStatusText(device))
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
        .padding(12)
        .borderRadius(8)
        .backgroundColor($r('app.color.card_background'))
        .margin({ bottom: 6 })
        .alignItems(VerticalAlign.Center)
      }, (device: DeviceInfo) => device.id)
    }
    .width('100%')
  }

  private getDeviceIcon(device: DeviceInfo): string {
    if (device.type === DeviceType.DOOR) {
      return device.state.isLocked ? '🔒' : '🔓';
    }
    if (device.type === DeviceType.LIGHT) {
      return device.state.isOn ? '💡' : '⚪';
    }
    if (device.type === DeviceType.SENSOR) {
      return '🌡';
    }
    if (device.type === DeviceType.AC) {
      return device.state.acPower ? '❄' : '⏻';
    }
    return '📦';
  }

  private getDeviceStatusText(device: DeviceInfo): string {
    if (device.type === DeviceType.DOOR) {
      return device.state.isLocked ? 'Locked' : 'Unlocked';
    }
    if (device.type === DeviceType.LIGHT) {
      return device.state.isOn ? 'On ' + device.state.brightness.toFixed(0) + '%' : 'Off';
    }
    if (device.type === DeviceType.SENSOR) {
      return device.state.temperature.toFixed(1) + '°C / ' + device.state.humidity.toFixed(0) + '%';
    }
    if (device.type === DeviceType.AC) {
      return device.state.acPower ? 'On ' + device.state.targetTemp.toFixed(0) + '°C' : 'Off';
    }
    return '';
  }
}
