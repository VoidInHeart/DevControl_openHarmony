import { DeviceInfo, DeviceType } from '../model/DeviceModel';

@Component
export struct DeviceCard {
  @Prop device: DeviceInfo = new DeviceInfo();
  onToggle: (deviceId: string) => void = () => {};

  build() {
    Column() {
      Row() {
        Text(this.getDeviceIcon())
          .fontSize(28)
          .fontColor(this.getStatusColor())
        Column() {
          Text(this.device.name)
            .fontSize(16)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.device.state.online ? 'Online' : 'Offline')
            .fontSize(12)
            .fontColor(this.device.state.online ? $r('app.color.status_online') : $r('app.color.status_offline'))
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        .margin({ left: 12 })
        if (this.device.type === DeviceType.LIGHT || this.device.type === DeviceType.AC) {
          Toggle({ type: ToggleType.Switch, isOn: this.device.state.isOn || this.device.state.acPower })
            .onChange((isOn: boolean) => {
              this.onToggle(this.device.id);
            })
            .selectedColor($r('app.color.primary'))
        }
        if (this.device.type === DeviceType.DOOR) {
          Toggle({ type: ToggleType.Switch, isOn: !this.device.state.isLocked })
            .onChange((isOn: boolean) => {
              this.onToggle(this.device.id);
            })
            .selectedColor($r('app.color.status_online'))
        }
      }
      .width('100%')
      .padding(16)
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .borderRadius(16)
    .backgroundColor($r('app.color.card_background'))
    .margin({ bottom: 8 })
  }

  private getDeviceIcon(): string {
    if (this.device.type === DeviceType.DOOR) {
      return this.device.state.isLocked ? '🔒' : '🔓';
    }
    if (this.device.type === DeviceType.LIGHT) {
      return this.device.state.isOn ? '💡' : '⚪';
    }
    if (this.device.type === DeviceType.SENSOR) {
      return '🌡';
    }
    if (this.device.type === DeviceType.AC) {
      return this.device.state.acPower ? '❄' : '⏻';
    }
    return '📦';
  }

  private getStatusColor(): Resource {
    if (this.device.type === DeviceType.DOOR) {
      return this.device.state.isLocked ? $r('app.color.lock_icon_locked') : $r('app.color.lock_icon_unlocked');
    }
    if (this.device.type === DeviceType.LIGHT) {
      return this.device.state.isOn ? $r('app.color.light_icon_on') : $r('app.color.light_icon_off');
    }
    if (this.device.type === DeviceType.AC) {
      return this.device.state.acPower ? $r('app.color.temp_cool') : $r('app.color.status_offline');
    }
    return $r('app.color.primary');
  }
}
