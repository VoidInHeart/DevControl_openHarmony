import { DeviceInfo, DeviceType, ACMode } from '../model/DeviceModel';
import { DeviceManager } from '../model/DeviceManager';
import { BrandAdapter, createBrandAdapter } from '../model/BrandAdapter';
import { Constants } from '../common/Constants';

@Component
export struct TemperatureTab {
  @Consume deviceManager: DeviceManager;
  @State selectedACIndex: number = 0;

  private get acDevices(): DeviceInfo[] {
    return this.deviceManager.getDevicesByType(DeviceType.AC);
  }

  private get sensorDevices(): DeviceInfo[] {
    return this.deviceManager.getDevicesByType(DeviceType.SENSOR);
  }

  build() {
    Scroll() {
      Column() {
        this.SensorSection()
        this.ACControlSection()
        this.BrandSelectSection()
      }
      .width('100%')
      .padding(16)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Auto)
  }

  @Builder
  SensorSection() {
    Column() {
      Text('Environment Monitor')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .margin({ bottom: 12 })

      ForEach(this.sensorDevices, (sensor: DeviceInfo) => {
        Row() {
          Column() {
            Text('🌡 Temperature')
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
            Text(sensor.state.temperature.toFixed(1) + '°C')
              .fontSize(28)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.getTempColor(sensor.state.temperature))
              .margin({ top: 4 })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Center)

          Column() {
            Text('💧 Humidity')
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
            Text(sensor.state.humidity.toFixed(0) + '%')
              .fontSize(28)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.primary'))
              .margin({ top: 4 })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Center)
        }
        .width('100%')
        .padding(16)
        .borderRadius(16)
        .backgroundColor($r('app.color.card_background'))
        .margin({ bottom: 8 })
      }, (sensor: DeviceInfo) => sensor.id)
    }
    .width('100%')
    .margin({ bottom: 16 })
  }

  @Builder
  ACControlSection() {
    Column() {
      Text('Air Conditioner Control')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .margin({ bottom: 12 })

      if (this.acDevices.length > 0) {
        this.ACUnitCard(this.acDevices[this.selectedACIndex])
      } else {
        Text('No AC devices available')
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
      }
    }
    .width('100%')
  }

  @Builder
  ACUnitCard(ac: DeviceInfo) {
    Column() {
      Row() {
        Text(ac.state.acPower ? '❄' : '⏻')
          .fontSize(36)
          .fontColor(ac.state.acPower ? $r('app.color.temp_cool') : $r('app.color.status_offline'))
        Column() {
          Text(ac.name)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Text(ac.brand.charAt(0).toUpperCase() + ac.brand.slice(1) + ' - ' + (ac.state.acPower ? 'Running' : 'Off'))
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        .margin({ left: 12 })
        Toggle({ type: ToggleType.Switch, isOn: ac.state.acPower })
          .onChange((isOn: boolean) => {
            if (isOn) {
              this.deviceManager.sendCommand(ac.id, 'acPowerOn', '');
            } else {
              this.deviceManager.sendCommand(ac.id, 'acPowerOff', '');
            }
          })
          .selectedColor($r('app.color.primary'))
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (ac.state.acPower) {
        Column() {
          Row() {
            Text('Target Temperature')
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
            Text(ac.state.targetTemp.toFixed(0) + '°C')
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.primary'))
          }
          .width('100%')
          .justifyContent(FlexAlign.SpaceBetween)
          .margin({ top: 16 })

          Slider({
            value: ac.state.targetTemp,
            min: Constants.TEMP_MIN,
            max: Constants.TEMP_MAX,
            step: 1,
            style: SliderStyle.OutSet
          })
            .width('100%')
            .trackColor($r('app.color.divider'))
            .selectedColor($r('app.color.temp_cool'))
            .onChange((value: number) => {
              const adapter: BrandAdapter = createBrandAdapter(ac.brand);
              this.deviceManager.sendCommand(ac.id, 'setTargetTemp', value.toFixed(0));
            })

          Row() {
            Text('Target Humidity')
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
            Text(ac.state.targetHumidity.toFixed(0) + '%')
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.primary'))
          }
          .width('100%')
          .justifyContent(FlexAlign.SpaceBetween)
          .margin({ top: 12 })

          Slider({
            value: ac.state.targetHumidity,
            min: Constants.HUMIDITY_MIN,
            max: Constants.HUMIDITY_MAX,
            step: 5,
            style: SliderStyle.OutSet
          })
            .width('100%')
            .trackColor($r('app.color.divider'))
            .selectedColor($r('app.color.primary'))
            .onChange((value: number) => {
              this.deviceManager.sendCommand(ac.id, 'setTargetHumidity', value.toFixed(0));
            })

          Row() {
            Text('Mode')
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
          }
          .width('100%')
          .margin({ top: 12 })

          Row() {
            this.ModeButton('Cool', 0, ac.state.acMode === ACMode.COOL)
            this.ModeButton('Heat', 1, ac.state.acMode === ACMode.HEAT)
            this.ModeButton('Fan', 2, ac.state.acMode === ACMode.FAN)
            this.ModeButton('Auto', 3, ac.state.acMode === ACMode.AUTO)
          }
          .width('100%')
          .justifyContent(FlexAlign.SpaceAround)
          .margin({ top: 8 })
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(16)
    .borderRadius(16)
    .backgroundColor($r('app.color.card_background'))
    .margin({ bottom: 12 })
  }

  @Builder
  ModeButton(label: string, mode: number, isActive: boolean) {
    Button(label)
      .fontSize(13)
      .fontColor(isActive ? Color.White : $r('app.color.text_primary'))
      .backgroundColor(isActive ? $r('app.color.primary') : $r('app.color.card_background'))
      .borderRadius(16)
      .padding({ left: 16, right: 16, top: 6, bottom: 6 })
      .onClick(() => {
        if (this.acDevices.length > 0) {
          const ac = this.acDevices[this.selectedACIndex];
          this.deviceManager.sendCommand(ac.id, 'setACMode', mode.toString());
        }
      })
  }

  @Builder
  BrandSelectSection() {
    Column() {
      Text('AC Unit Selection')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .margin({ bottom: 8 })

      Row() {
        ForEach(this.acDevices, (ac: DeviceInfo, index: number) => {
          Button(ac.brand.charAt(0).toUpperCase() + ac.brand.slice(1))
            .fontSize(13)
            .fontColor(this.selectedACIndex === index ? Color.White : $r('app.color.text_primary'))
            .backgroundColor(this.selectedACIndex === index ? $r('app.color.primary') : $r('app.color.card_background'))
            .borderRadius(16)
            .padding({ left: 16, right: 16, top: 6, bottom: 6 })
            .onClick(() => {
              this.selectedACIndex = index;
            })
        }, (ac: DeviceInfo) => ac.id)
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceAround)
    }
    .width('100%')
    .padding(16)
    .borderRadius(16)
    .backgroundColor($r('app.color.card_background'))
  }

  private getTempColor(temp: number): Resource {
    if (temp > 28) {
      return $r('app.color.temp_hot');
    }
    if (temp < 18) {
      return $r('app.color.temp_cool');
    }
    return $r('app.color.temp_normal');
  }
}
