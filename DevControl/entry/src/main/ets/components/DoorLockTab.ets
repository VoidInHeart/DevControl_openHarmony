import { DeviceInfo, DeviceType, AccessLogEntry, AlertEntry } from '../model/DeviceModel';
import { DeviceManager } from '../model/DeviceManager';

@Component
export struct DoorLockTab {
  @Consume deviceManager: DeviceManager;

  build() {
    Scroll() {
      Column() {
        this.DoorCardsSection()
        this.AlertSection()
        this.AccessLogSection()
      }
      .width('100%')
      .padding(16)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Auto)
  }

  @Builder
  DoorCardsSection() {
    Column() {
      Text('Smart Door Locks')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .margin({ bottom: 12 })

      ForEach(this.deviceManager.getDevicesByType(DeviceType.DOOR), (device: DeviceInfo) => {
        this.DoorCard(device)
      }, (device: DeviceInfo) => device.id)
    }
    .width('100%')
  }

  @Builder
  DoorCard(device: DeviceInfo) {
    Column() {
      Text(device.state.isLocked ? '🔒' : '🔓')
        .fontSize(64)
        .fontColor(device.state.isLocked ? $r('app.color.lock_icon_locked') : $r('app.color.lock_icon_unlocked'))
        .margin({ top: 16 })

      Text(device.name)
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .margin({ top: 8 })

      Text(device.state.isLocked ? 'Locked' : 'Unlocked')
        .fontSize(16)
        .fontColor(device.state.isLocked ? $r('app.color.lock_icon_locked') : $r('app.color.lock_icon_unlocked'))
        .margin({ top: 4 })

      Row() {
        Text('Battery: ' + device.state.batteryLevel.toFixed(0) + '%')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
      }
      .margin({ top: 4 })

      Row() {
        Button('Lock')
          .fontSize(14)
          .fontColor(Color.White)
          .backgroundColor($r('app.color.lock_icon_locked'))
          .borderRadius(20)
          .padding({ left: 32, right: 32, top: 8, bottom: 8 })
          .enabled(!device.state.isLocked)
          .opacity(device.state.isLocked ? 0.4 : 1)
          .onClick(() => {
            this.deviceManager.sendCommand(device.id, 'lock', '');
          })

        Button('Unlock')
          .fontSize(14)
          .fontColor(Color.White)
          .backgroundColor($r('app.color.lock_icon_unlocked'))
          .borderRadius(20)
          .padding({ left: 32, right: 32, top: 8, bottom: 8 })
          .enabled(device.state.isLocked)
          .opacity(device.state.isLocked ? 1 : 0.4)
          .onClick(() => {
            this.deviceManager.sendCommand(device.id, 'unlock', '');
          })
      }
      .margin({ top: 16, bottom: 16 })
      .justifyContent(FlexAlign.SpaceEvenly)
      .width('100%')
    }
    .width('100%')
    .borderRadius(16)
    .backgroundColor($r('app.color.card_background'))
    .alignItems(HorizontalAlign.Center)
    .margin({ bottom: 12 })
  }

  @Builder
  AlertSection() {
    Column() {
      Row() {
        Text('Alerts')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Blank()
        if (this.deviceManager.alerts.length > 0) {
          Button('Clear')
            .fontSize(12)
            .fontColor($r('app.color.primary'))
            .backgroundColor(Color.Transparent)
            .padding(0)
            .onClick(() => {
              this.deviceManager.clearAlerts();
            })
        }
      }
      .width('100%')

      if (this.deviceManager.alerts.length === 0) {
        Text('No alerts')
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 12 })
          .width('100%')
          .textAlign(TextAlign.Center)
      } else {
        ForEach(this.deviceManager.alerts.slice(0, 5), (alert: AlertEntry) => {
          Row() {
            Text(alert.level === 'warning' ? '⚠' : 'ℹ')
              .fontSize(16)
              .fontColor(alert.level === 'warning' ? $r('app.color.status_warning') : $r('app.color.primary'))
            Column() {
              Text(alert.message)
                .fontSize(14)
                .fontColor($r('app.color.text_primary'))
              Text(alert.time)
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
                .margin({ top: 2 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            .margin({ left: 8 })
          }
          .width('100%')
          .padding({ top: 8, bottom: 8 })
          .alignItems(VerticalAlign.Center)
        }, (alert: AlertEntry, index: number) => alert.time + index.toString())
      }
    }
    .width('100%')
    .padding(16)
    .borderRadius(16)
    .backgroundColor($r('app.color.card_background'))
    .margin({ bottom: 12 })
  }

  @Builder
  AccessLogSection() {
    Column() {
      Row() {
        Text('Access Log')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Blank()
        if (this.deviceManager.accessLogs.length > 0) {
          Button('Clear')
            .fontSize(12)
            .fontColor($r('app.color.primary'))
            .backgroundColor(Color.Transparent)
            .padding(0)
            .onClick(() => {
              this.deviceManager.clearAccessLogs();
            })
        }
      }
      .width('100%')

      if (this.deviceManager.accessLogs.length === 0) {
        Text('No access logs')
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 12 })
          .width('100%')
          .textAlign(TextAlign.Center)
      } else {
        ForEach(this.deviceManager.accessLogs.slice(0, 10), (log: AccessLogEntry) => {
          Row() {
            Text(log.result === 'success' ? '✓' : '✗')
              .fontSize(16)
              .fontColor(log.result === 'success' ? $r('app.color.status_online') : $r('app.color.status_alert'))
            Column() {
              Text(log.deviceId + ' - ' + log.action)
                .fontSize(14)
                .fontColor($r('app.color.text_primary'))
              Text(log.time)
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
                .margin({ top: 2 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            .margin({ left: 8 })
          }
          .width('100%')
          .padding({ top: 8, bottom: 8 })
          .alignItems(VerticalAlign.Center)
        }, (log: AccessLogEntry, index: number) => log.time + index.toString())
      }
    }
    .width('100%')
    .padding(16)
    .borderRadius(16)
    .backgroundColor($r('app.color.card_background'))
  }
}
