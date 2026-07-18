import { AccessLogEntry, AlertEntry, DeviceType, DoorLockDevice } from '../model/DeviceModel';
import { DeviceManager } from '../model/DeviceManager';
import { LockIcon } from './LockIcon';

@Component
export struct DoorLockTab {
  @Consume deviceManager: DeviceManager;
  @Prop deviceId: string = '';
  @Prop showTitle: boolean = true;

  build() {
    Scroll() {
      Column() {
        if (this.showTitle) {
          Text('智能门锁')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
            .margin({ bottom: 12 })
        }
        ForEach(this.visibleDoorLocks(), (device: DoorLockDevice) => {
          this.DoorCard(device)
          this.AutoLockCard(device)
        }, (device: DoorLockDevice) => device.id + ':' + device.stateVersion.toString())
        this.AlertSection()
        this.AccessLogSection()
      }
      .width('100%')
      .padding(16)
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Auto)
  }

  @Builder
  DoorCard(device: DoorLockDevice) {
    Column() {
      Row() {
        Stack({ alignContent: Alignment.Center }) {
          LockIcon({ locked: device.state.locked, iconSize: 30 })
        }
          .width(62)
          .height(62)
          .backgroundColor(device.state.locked ? '#EEF1FF' : '#EAF8F1')
          .borderRadius(22)
        Column() {
          Text(device.name)
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor('#14263A')
          Text(device.state.jammed ? '锁体异常，拒绝远程操作' :
            (device.state.locked ? '已上锁 · 家庭安全入口' : '已解锁 · 请确认门口安全'))
            .fontSize(12)
            .fontColor(device.state.jammed ? $r('app.color.status_alert') : '#748294')
            .margin({ top: 5 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        .margin({ left: 14 })
        if (this.deviceManager.isDevicePending(device.id)) {
          this.PendingBadge()
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row() {
        this.StatusCell('门锁', device.state.locked ? '已锁' : '未锁')
        this.StatusCell('电量', device.state.batteryPercent.toFixed(0) + '%')
        this.StatusCell('自动上锁', device.state.autoLockEnabled ? '开启' : '关闭')
      }
      .width('100%')
      .margin({ top: 16 })

      Row() {
        Button('锁门')
          .fontSize(14)
          .fontColor(Color.White)
          .backgroundColor($r('app.color.lock_icon_locked'))
          .enabled(this.canControl(device) && !device.state.locked)
          .opacity(this.canControl(device) && !device.state.locked ? 1 : 0.4)
          .onClick(() => {
            this.deviceManager.setDoorLocked(device, true);
          })
        Button('解锁')
          .fontSize(14)
          .fontColor(Color.White)
          .backgroundColor($r('app.color.lock_icon_unlocked'))
          .enabled(this.canControl(device) && device.state.locked)
          .opacity(this.canControl(device) && device.state.locked ? 1 : 0.4)
          .onClick(() => {
            AlertDialog.show({
              title: '确认远程解锁',
              message: '即将解锁“' + device.name + '”。请确认门口环境安全。',
              primaryButton: {
                value: '取消',
                action: () => {
                }
              },
              secondaryButton: {
                value: '确认解锁',
                fontColor: $r('app.color.status_alert'),
                action: () => {
                  this.deviceManager.setDoorLocked(device, false);
                }
              }
            });
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceEvenly)
      .margin({ top: 16 })
    }
    .width('100%')
    .padding(18)
    .borderRadius(24)
    .backgroundColor('#F7FBFF')
    .alignItems(HorizontalAlign.Center)
    .margin({ bottom: 12 })
  }

  @Builder
  StatusCell(label: string, value: string) {
    Column() {
      Text(value)
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor('#14263A')
      Text(label)
        .fontSize(11)
        .fontColor('#748294')
        .margin({ top: 4 })
    }
    .layoutWeight(1)
    .height(58)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(Color.White)
    .borderRadius(18)
    .margin({ right: 8 })
  }

  @Builder
  PendingBadge() {
    Row() {
      Text('•')
        .fontSize(16)
        .fontColor('#D28A00')
        .margin({ right: 4 })
      Text('同步中')
        .fontSize(11)
        .fontColor('#8A5A00')
    }
    .height(28)
    .padding({ left: 9, right: 10 })
    .backgroundColor('#FFF3D6')
    .borderRadius(14)
  }

  @Builder
  AutoLockCard(device: DoorLockDevice) {
    Column() {
      Row() {
        Column() {
          Text('自动上锁')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Text('解锁后由网关定时重新锁定')
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 3 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        Toggle({ type: ToggleType.Switch, isOn: device.state.autoLockEnabled })
          .enabled(this.canControl(device))
          .onChange((enabled: boolean) => {
            this.deviceManager.setDoorAutoLock(
              device,
              enabled,
              device.state.autoLockDelaySeconds
            );
          })
      }
      .width('100%')
      Row() {
        Text('延时')
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .width(44)
        Slider({
          value: device.state.autoLockDelaySeconds,
          min: 5,
          max: 60,
          step: 1,
          style: SliderStyle.OutSet
        })
          .layoutWeight(1)
          .enabled(this.canControl(device))
          .sliderInteractionMode(SliderInteraction.SLIDE_AND_CLICK)
          .onChange((value: number, mode: SliderChangeMode) => {
            if (this.shouldCommitSlider(mode)) {
              this.deviceManager.setDoorAutoLock(device, device.state.autoLockEnabled, value);
            }
          })
        Text(device.state.autoLockDelaySeconds.toFixed(0) + ' 秒')
          .fontSize(12)
          .width(46)
          .textAlign(TextAlign.End)
      }
      .width('100%')
      .margin({ top: 12 })
    }
    .width('100%')
    .padding(16)
    .borderRadius(24)
    .backgroundColor('#F7FBFF')
    .margin({ bottom: 12 })
  }

  @Builder
  AlertSection() {
    Column() {
      Text('安全告警')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
      if (this.deviceManager.alerts.length === 0) {
        Text('暂无告警')
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .textAlign(TextAlign.Center)
          .margin({ top: 12 })
      } else {
        ForEach(this.deviceManager.alerts.slice(0, 8), (alert: AlertEntry) => {
          Row() {
            Text('⚠')
              .fontColor($r('app.color.status_warning'))
            Column() {
              Text(alert.message)
                .fontSize(13)
                .fontColor($r('app.color.text_primary'))
              Text(alert.time + ' · ' + alert.code)
                .fontSize(11)
                .fontColor($r('app.color.text_secondary'))
                .margin({ top: 2 })
            }
            .alignItems(HorizontalAlign.Start)
            .margin({ left: 8 })
          }
          .width('100%')
          .padding({ top: 8, bottom: 8 })
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
      Text('不可清除的门锁审计记录')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
      if (this.doorLogs().length === 0) {
        Text('暂无门锁操作记录')
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .textAlign(TextAlign.Center)
          .margin({ top: 12 })
      } else {
        ForEach(this.doorLogs(), (log: AccessLogEntry) => {
          Row() {
            Text(log.result === 'success' ? '✓' : '×')
              .fontColor(log.result === 'success' ?
                $r('app.color.status_online') : $r('app.color.status_alert'))
            Column() {
              Text(log.deviceId + ' · ' + log.action)
                .fontSize(13)
                .fontColor($r('app.color.text_primary'))
              Text(log.time + (log.errorCode.length > 0 ? ' · ' + log.errorCode : ''))
                .fontSize(11)
                .fontColor($r('app.color.text_secondary'))
                .margin({ top: 2 })
            }
            .alignItems(HorizontalAlign.Start)
            .margin({ left: 8 })
          }
          .width('100%')
          .padding({ top: 8, bottom: 8 })
        }, (log: AccessLogEntry, index: number) => log.time + index.toString())
      }
    }
    .width('100%')
    .padding(16)
    .borderRadius(16)
    .backgroundColor($r('app.color.card_background'))
  }

  private canControl(device: DoorLockDevice): boolean {
    return this.deviceManager.isOnline() && device.online && !device.state.jammed &&
      !this.deviceManager.isDevicePending(device.id);
  }

  private shouldCommitSlider(mode: SliderChangeMode): boolean {
    return mode === SliderChangeMode.End || mode === SliderChangeMode.Click;
  }

  private doorLogs(): AccessLogEntry[] {
    const result: AccessLogEntry[] = [];
    for (let index = 0; index < this.deviceManager.accessLogs.length; index++) {
      const log = this.deviceManager.accessLogs[index];
      const device = this.deviceManager.getDeviceById(log.deviceId);
      if (
        (this.deviceId.length > 0 && log.deviceId === this.deviceId) ||
        (this.deviceId.length === 0 && device !== null && device.type === DeviceType.DOOR_LOCK)
      ) {
        result.push(log);
      }
      if (result.length >= 10) {
        break;
      }
    }
    return result;
  }

  private visibleDoorLocks(): DoorLockDevice[] {
    if (this.deviceId.length === 0) {
      return this.deviceManager.getDoorLocks();
    }
    const result: DoorLockDevice[] = [];
    const devices = this.deviceManager.getDoorLocks();
    for (let index = 0; index < devices.length; index++) {
      if (devices[index].id === this.deviceId) {
        result.push(devices[index]);
      }
    }
    return result;
  }
}
