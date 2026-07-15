import { DeviceInfo, DeviceType } from '../model/DeviceModel';
import { DeviceManager } from '../model/DeviceManager';

@Component
export struct LightingTab {
  @Consume deviceManager: DeviceManager;
  @State autoModeEnabled: boolean = false;
  @State sensitivity: number = 50;

  build() {
    Scroll() {
      Column() {
        Text('Room Lights')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
          .margin({ bottom: 16 })

        ForEach(this.deviceManager.getDevicesByType(DeviceType.LIGHT), (device: DeviceInfo) => {
          this.LightCard(device)
        }, (device: DeviceInfo) => device.id)

        this.AutoModeSection()
      }
      .width('100%')
      .padding(16)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Auto)
  }

  @Builder
  LightCard(device: DeviceInfo) {
    Column() {
      Row() {
        Text(device.state.isOn ? '💡' : '⚪')
          .fontSize(32)
          .fontColor(device.state.isOn ? $r('app.color.light_icon_on') : $r('app.color.light_icon_off'))
        Column() {
          Text(device.name)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Text(device.state.isOn ? 'On - ' + device.state.brightness.toFixed(0) + '%' : 'Off')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        .margin({ left: 12 })
        Toggle({ type: ToggleType.Switch, isOn: device.state.isOn })
          .onChange((isOn: boolean) => {
            if (isOn) {
              this.deviceManager.sendCommand(device.id, 'turnOn', '100');
            } else {
              this.deviceManager.sendCommand(device.id, 'turnOff', '');
            }
          })
          .selectedColor($r('app.color.primary'))
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (device.state.isOn) {
        Row() {
          Text('Brightness')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .width(80)
          Slider({
            value: device.state.brightness,
            min: 0,
            max: 100,
            step: 5,
            style: SliderStyle.OutSet
          })
            .layoutWeight(1)
            .trackColor($r('app.color.divider'))
            .selectedColor($r('app.color.primary'))
            .onChange((value: number) => {
              this.deviceManager.sendCommand(device.id, 'setBrightness', value.toFixed(0));
            })
          Text(device.state.brightness.toFixed(0) + '%')
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .width(44)
            .textAlign(TextAlign.End)
        }
        .width('100%')
        .margin({ top: 12 })
        .alignItems(VerticalAlign.Center)
      }
    }
    .width('100%')
    .padding(16)
    .borderRadius(16)
    .backgroundColor($r('app.color.card_background'))
    .margin({ bottom: 12 })
  }

  @Builder
  AutoModeSection() {
    Column() {
      Row() {
        Column() {
          Text('Motion Sensor Auto Mode')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Text('Automatically turn lights on/off based on motion')
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 4 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.autoModeEnabled })
          .onChange((isOn: boolean) => {
            this.autoModeEnabled = isOn;
            if (isOn) {
              this.deviceManager.addAlert('system', 'info', 'Auto mode enabled');
            }
          })
          .selectedColor($r('app.color.status_online'))
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.autoModeEnabled) {
        Row() {
          Text('Sensitivity')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .width(90)
          Slider({
            value: this.sensitivity,
            min: 0,
            max: 100,
            step: 10,
            style: SliderStyle.OutSet
          })
            .layoutWeight(1)
            .trackColor($r('app.color.divider'))
            .selectedColor($r('app.color.accent'))
            .onChange((value: number) => {
              this.sensitivity = value;
            })
          Text(this.sensitivity.toFixed(0) + '%')
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .width(44)
            .textAlign(TextAlign.End)
        }
        .width('100%')
        .margin({ top: 12 })
        .alignItems(VerticalAlign.Center)
      }
    }
    .width('100%')
    .padding(16)
    .borderRadius(16)
    .backgroundColor($r('app.color.card_background'))
    .margin({ top: 4 })
  }
}
