import {
  AirConditionerDevice,
  DeviceInfo,
  DeviceType,
  DoorLockDevice,
  EnvironmentDevice,
  LightDevice,
  SceneExecutionDetail
} from '../model/DeviceModel';
import { DeviceManager } from '../model/DeviceManager';

@Component
export struct ControlCenterTab {
  @Consume deviceManager: DeviceManager;

  build() {
    Scroll() {
      Column() {
        this.ConnectionSection()
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
  ConnectionSection() {
    Column() {
      Row() {
        Text(this.deviceManager.isOnline() ? '●' : '●')
          .fontSize(12)
          .fontColor(this.deviceManager.isOnline() ?
            $r('app.color.status_online') : $r('app.color.status_offline'))
        Text('网关' + this.deviceManager.getConnectionLabel())
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .margin({ left: 8 })
        Blank()
        if (this.deviceManager.connectionState === 'reconnecting') {
          Text('自动重连中')
            .fontSize(12)
            .fontColor($r('app.color.status_warning'))
        }
      }
      .width('100%')

      if (!this.deviceManager.isOnline()) {
        Text('当前展示最后一次同步快照，所有控制操作已禁用。')
          .fontSize(12)
          .fontColor($r('app.color.status_warning'))
          .width('100%')
          .margin({ top: 8 })
      }
      if (this.deviceManager.lastError.length > 0) {
        Text(this.deviceManager.lastErrorCode + ' · ' + this.deviceManager.lastError)
          .fontSize(12)
          .fontColor($r('app.color.status_alert'))
          .width('100%')
          .margin({ top: 8 })
      }
    }
    .width('100%')
    .padding(16)
    .borderRadius(12)
    .backgroundColor($r('app.color.card_background'))
    .margin({ bottom: 16 })
  }

  @Builder
  StatsSection() {
    Row() {
      this.StatCard(
        this.deviceManager.devices.filter((device: DeviceInfo) => device.online).length.toString(),
        '在线设备',
        $r('app.color.status_online')
      )
      this.StatCard(
        this.deviceManager.devices.filter((device: DeviceInfo) => !device.online).length.toString(),
        '离线设备',
        $r('app.color.status_offline')
      )
      this.StatCard(this.deviceManager.alerts.length.toString(), '安全告警',
        $r('app.color.status_alert'))
    }
    .width('100%')
    .margin({ bottom: 16 })
  }

  @Builder
  StatCard(value: string, label: string, color: Resource) {
    Column() {
      Text(value)
        .fontSize(26)
        .fontWeight(FontWeight.Bold)
        .fontColor(color)
      Text(label)
        .fontSize(11)
        .fontColor($r('app.color.text_secondary'))
        .margin({ top: 4 })
    }
    .layoutWeight(1)
    .padding({ top: 14, bottom: 14 })
    .borderRadius(12)
    .backgroundColor($r('app.color.card_background'))
    .alignItems(HorizontalAlign.Center)
    .margin({ left: 3, right: 3 })
  }

  @Builder
  SceneSection() {
    Column() {
      Text('快捷场景')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
      Text('在家模式开启灯光和空调；离家模式关闭设备并锁定入户门。')
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .margin({ top: 6, bottom: 12 })
      Row() {
        Button(this.deviceManager.isDevicePending('scene-home') ? '正在执行…' : '在家模式')
          .layoutWeight(1)
          .enabled(this.canExecuteScene())
          .opacity(this.canExecuteScene() ? 1 : 0.45)
          .margin({ right: 4 })
          .onClick(() => {
            this.deviceManager.executeHomeScene();
          })
        Button(this.deviceManager.isDevicePending('scene-away') ? '正在执行…' : '离家模式')
          .layoutWeight(1)
          .enabled(this.canExecuteScene())
          .opacity(this.canExecuteScene() ? 1 : 0.45)
          .margin({ left: 4 })
          .onClick(() => {
            this.deviceManager.executeAwayScene();
          })
      }
        .width('100%')
      if (this.deviceManager.sceneResults.length > 0) {
        Column() {
          ForEach(this.deviceManager.sceneResults, (item: SceneExecutionDetail) => {
            Row() {
              Text(this.sceneDeviceName(item.deviceId))
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
                .layoutWeight(1)
              Text(item.success ? '成功' : '失败 ' + item.errorCode)
                .fontSize(12)
                .fontColor(item.success ?
                  $r('app.color.status_online') : $r('app.color.status_alert'))
            }
            .width('100%')
            .margin({ top: 8 })
          }, (item: SceneExecutionDetail) => item.deviceId)
        }
        .width('100%')
        .margin({ top: 8 })
      }
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
      Text('全部设备')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .margin({ bottom: 12 })

      if (this.deviceManager.devices.length === 0) {
        Text('正在等待网关设备快照…')
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding(24)
      } else {
        ForEach(this.deviceManager.devices, (device: DeviceInfo) => {
          Row() {
            Column() {
              Text(this.getDeviceIcon(device))
                .fontSize(26)
            }
            .width(44)
            .height(44)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            Column() {
              Text(device.name)
                .fontSize(15)
                .fontColor($r('app.color.text_primary'))
              Text(device.online ? '在线' : '离线')
                .fontSize(12)
                .fontColor(device.online ?
                  $r('app.color.status_online') : $r('app.color.status_offline'))
                .margin({ top: 2 })
            }
            .alignItems(HorizontalAlign.Start)
            .justifyContent(FlexAlign.Center)
            .height(44)
            .layoutWeight(1)
            .margin({ left: 8 })
            Column() {
              Text(this.getDeviceStatusText(device))
                .fontSize(13)
                .fontColor($r('app.color.text_secondary'))
              if (this.deviceManager.isDevicePending(device.id)) {
                Text('处理中')
                  .fontSize(11)
                  .fontColor($r('app.color.status_warning'))
                  .margin({ top: 2 })
              }
            }
            .alignItems(HorizontalAlign.End)
            .justifyContent(FlexAlign.Center)
            .height(44)
          }
          .width('100%')
          .padding(12)
          .borderRadius(8)
          .backgroundColor($r('app.color.card_background'))
          .margin({ bottom: 6 })
          .alignItems(VerticalAlign.Center)
        }, (device: DeviceInfo) => device.id + ':' + device.stateVersion.toString())
      }
    }
    .width('100%')
  }

  private getDeviceIcon(device: DeviceInfo): string {
    if (device.type === DeviceType.DOOR_LOCK) {
      return (device as DoorLockDevice).state.locked ? '🔒' : '🔓';
    }
    if (device.type === DeviceType.LIGHT) {
      return (device as LightDevice).state.power ? '💡' : '○';
    }
    if (device.type === DeviceType.ENVIRONMENT) {
      return '🌡';
    }
    if (device.type === DeviceType.AIR_CONDITIONER) {
      return (device as AirConditionerDevice).state.power ? '❄' : '⏻';
    }
    return '□';
  }

  private getDeviceStatusText(device: DeviceInfo): string {
    if (device.type === DeviceType.DOOR_LOCK) {
      const door = device as DoorLockDevice;
      return door.state.jammed ? '卡滞' : (door.state.locked ? '已锁定' : '已解锁');
    }
    if (device.type === DeviceType.LIGHT) {
      const light = device as LightDevice;
      return light.state.power ? '开启 ' + light.state.brightness.toFixed(0) + '%' : '关闭';
    }
    if (device.type === DeviceType.ENVIRONMENT) {
      const environment = device as EnvironmentDevice;
      return environment.state.temperatureCelsius.toFixed(1) + '°C / ' +
        environment.state.humidityPercent.toFixed(0) + '%';
    }
    const ac = device as AirConditionerDevice;
    return ac.state.power ? ac.state.mode + ' · ' +
      ac.state.targetTemperatureCelsius.toFixed(0) + '°C' : '关闭';
  }

  private sceneDeviceName(deviceId: string): string {
    const device = this.deviceManager.getDeviceById(deviceId);
    return device === null ? deviceId : device.name;
  }

  private canExecuteScene(): boolean {
    return this.deviceManager.isOnline() &&
      !this.deviceManager.isDevicePending('scene-home') &&
      !this.deviceManager.isDevicePending('scene-away');
  }
}
