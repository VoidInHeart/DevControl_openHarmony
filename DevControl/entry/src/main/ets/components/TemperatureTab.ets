import {
  ACMode,
  AirConditionerDevice,
  DeviceBrand,
  EnvironmentDevice,
  EnvironmentHistoryPoint
} from '../model/DeviceModel';
import { DeviceManager } from '../model/DeviceManager';

@Component
export struct TemperatureTab {
  @Consume deviceManager: DeviceManager;
  @Prop deviceId: string = '';
  @Prop showTitle: boolean = true;

  build() {
    Scroll() {
      Column() {
        if (this.visibleEnvironmentDevices().length > 0) {
          this.EnvironmentSection()
          this.HistorySection()
        }
        ForEach(this.visibleAirConditioners(), (device: AirConditionerDevice) => {
          this.AirConditionerCard(device)
        }, (device: AirConditionerDevice) => device.id + ':' + device.stateVersion.toString())
      }
      .width('100%')
      .padding(16)
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Auto)
  }

  @Builder
  EnvironmentSection() {
    Column() {
      if (this.showTitle) {
        Text('环境监测')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
          .margin({ bottom: 12 })
      }

      ForEach(this.visibleEnvironmentDevices(), (sensor: EnvironmentDevice) => {
        Column() {
          Row() {
            this.ValueCard('🌡 温度', sensor.state.temperatureCelsius.toFixed(1) + '°C',
              this.getTempColor(sensor.state.temperatureCelsius))
            this.ValueCard('💧 湿度', sensor.state.humidityPercent.toFixed(0) + '%',
              $r('app.color.primary'))
          }
          .width('100%')
          Row() {
            Text('照度 ' + sensor.state.illuminanceLux.toFixed(0) + ' lx')
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
            Blank()
            Text(sensor.state.presence ? '检测到有人' : '当前无人')
              .fontSize(13)
              .fontColor(sensor.state.presence ?
                $r('app.color.status_online') : $r('app.color.text_secondary'))
          }
          .width('100%')
          .margin({ top: 12 })
          if (!sensor.state.dataValid) {
            Text('传感器数据超出有效范围，已停止参与自动规则。')
              .fontSize(12)
              .fontColor($r('app.color.status_alert'))
              .width('100%')
              .margin({ top: 8 })
          }
        }
        .width('100%')
        .padding(16)
        .borderRadius(16)
        .backgroundColor($r('app.color.card_background'))
      }, (sensor: EnvironmentDevice) => sensor.id + ':' + sensor.stateVersion.toString())
    }
    .width('100%')
    .margin({ bottom: 16 })
  }

  @Builder
  ValueCard(label: string, value: string, color: Resource) {
    Column() {
      Text(label)
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
      Text(value)
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor(color)
        .margin({ top: 4 })
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  HistorySection() {
    Column() {
      Row() {
        Text('最近24小时趋势')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Blank()
        Text(this.deviceManager.environmentHistory.length.toString() + ' 条记录')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
      Text(this.temperatureSparkline())
        .fontSize(24)
        .fontColor($r('app.color.temp_cool'))
        .width('100%')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 12 })
      Text(this.historySummary())
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .margin({ top: 8 })
    }
    .width('100%')
    .padding(16)
    .borderRadius(16)
    .backgroundColor($r('app.color.card_background'))
    .margin({ bottom: 16 })
  }

  @Builder
  AirConditionerCard(device: AirConditionerDevice) {
    Column() {
      Row() {
        Text(device.state.power ? '❄' : '⏻')
          .fontSize(36)
          .fontColor(device.state.power ?
            $r('app.color.temp_cool') : $r('app.color.status_offline'))
        Column() {
          Text(device.name)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Text(this.brandLabel(device.state.brand) + ' · ' +
            (device.state.power ? '运行中' : '已关闭'))
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        .margin({ left: 12 })
        if (this.deviceManager.isDevicePending(device.id)) {
          Text('处理中')
            .fontSize(12)
            .fontColor($r('app.color.status_warning'))
            .margin({ right: 8 })
        }
        Toggle({ type: ToggleType.Switch, isOn: device.state.power })
          .enabled(this.canControl(device))
          .onChange((power: boolean) => {
            this.deviceManager.setAcPower(device, power);
          })
      }
      .width('100%')

      Row() {
        Text('目标温度')
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
        Blank()
        Text(device.state.targetTemperatureCelsius.toFixed(0) + '°C')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary'))
      }
      .width('100%')
      .margin({ top: 16 })
      Slider({
        value: device.state.targetTemperatureCelsius,
        min: 16,
        max: 30,
        step: 1,
        style: SliderStyle.OutSet
      })
        .width('100%')
        .enabled(this.canControl(device))
        .sliderInteractionMode(SliderInteraction.SLIDE_AND_CLICK)
        .onChange((value: number, mode: SliderChangeMode) => {
          if (this.shouldCommitSlider(mode)) {
            this.deviceManager.setAcTemperature(device, value);
          }
        })

      Text('运行模式')
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .margin({ top: 12, bottom: 8 })
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
        this.ModeButton(device, '自动', ACMode.AUTO)
        this.ModeButton(device, '制冷', ACMode.COOL)
        this.ModeButton(device, '制热', ACMode.HEAT)
        this.ModeButton(device, '除湿', ACMode.DRY)
        this.ModeButton(device, '送风', ACMode.FAN)
      }
      .width('100%')

      Text('模拟品牌适配器')
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .margin({ top: 14, bottom: 8 })
      Row() {
        this.BrandButton(device, '海尔 Sim', DeviceBrand.HAIER_SIM)
        this.BrandButton(device, '格力 Sim', DeviceBrand.GREE_SIM)
        this.BrandButton(device, '美的 Sim', DeviceBrand.MIDEA_SIM)
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)

      if (device.state.lastAdapterFrame.length > 0) {
        Text(device.state.lastAdapterFrame)
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .margin({ top: 10 })
      }
    }
    .width('100%')
    .padding(16)
    .borderRadius(16)
    .backgroundColor($r('app.color.card_background'))
    .margin({ bottom: 12 })
  }

  @Builder
  ModeButton(device: AirConditionerDevice, label: string, mode: string) {
    Button(label)
      .fontSize(12)
      .fontColor(device.state.mode === mode ? Color.White : $r('app.color.text_primary'))
      .backgroundColor(device.state.mode === mode ?
        $r('app.color.primary') : $r('app.color.start_window_background'))
      .enabled(this.canControl(device))
      .margin({ right: 4, bottom: 6 })
      .onClick(() => {
        this.deviceManager.setAcMode(device, mode);
      })
  }

  @Builder
  BrandButton(device: AirConditionerDevice, label: string, brand: string) {
    Button(label)
      .fontSize(11)
      .fontColor(device.state.brand === brand ? Color.White : $r('app.color.text_primary'))
      .backgroundColor(device.state.brand === brand ?
        $r('app.color.primary') : $r('app.color.start_window_background'))
      .enabled(this.canControl(device))
      .onClick(() => {
        this.deviceManager.setAcBrand(device, brand);
      })
  }

  private canControl(device: AirConditionerDevice): boolean {
    return this.deviceManager.isOnline() && device.online &&
      !this.deviceManager.isDevicePending(device.id);
  }

  private shouldCommitSlider(mode: SliderChangeMode): boolean {
    return mode === SliderChangeMode.End || mode === SliderChangeMode.Click;
  }

  private brandLabel(brand: string): string {
    if (brand === DeviceBrand.GREE_SIM) {
      return '格力 Sim';
    }
    if (brand === DeviceBrand.MIDEA_SIM) {
      return '美的 Sim';
    }
    return '海尔 Sim';
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

  private temperatureSparkline(): string {
    const values = this.sampleHistory();
    if (values.length === 0) {
      return '暂无历史趋势';
    }
    let minimum = values[0].temperatureCelsius;
    let maximum = values[0].temperatureCelsius;
    for (let index = 1; index < values.length; index++) {
      minimum = Math.min(minimum, values[index].temperatureCelsius);
      maximum = Math.max(maximum, values[index].temperatureCelsius);
    }
    const levels: string[] = ['▁', '▂', '▃', '▄', '▅', '▆', '▇', '█'];
    let result = '';
    const range = Math.max(0.1, maximum - minimum);
    for (let index = 0; index < values.length; index++) {
      const level = Math.min(7, Math.floor(
        (values[index].temperatureCelsius - minimum) / range * 7
      ));
      result += levels[level];
    }
    return result;
  }

  private historySummary(): string {
    const values = this.sampleHistory();
    if (values.length === 0) {
      return '网关产生遥测后将在这里显示温度变化。';
    }
    let minimum = values[0].temperatureCelsius;
    let maximum = values[0].temperatureCelsius;
    for (let index = 1; index < values.length; index++) {
      minimum = Math.min(minimum, values[index].temperatureCelsius);
      maximum = Math.max(maximum, values[index].temperatureCelsius);
    }
    return '采样最低 ' + minimum.toFixed(1) + '°C，最高 ' + maximum.toFixed(1) + '°C';
  }

  private sampleHistory(): EnvironmentHistoryPoint[] {
    const source = this.deviceManager.environmentHistory;
    if (source.length <= 32) {
      return source;
    }
    const result: EnvironmentHistoryPoint[] = [];
    const step = source.length / 32;
    for (let index = 0; index < 32; index++) {
      result.push(source[Math.floor(index * step)]);
    }
    return result;
  }

  private visibleEnvironmentDevices(): EnvironmentDevice[] {
    if (this.deviceId.length === 0) {
      return this.deviceManager.getEnvironmentDevices();
    }
    const result: EnvironmentDevice[] = [];
    const devices = this.deviceManager.getEnvironmentDevices();
    for (let index = 0; index < devices.length; index++) {
      if (devices[index].id === this.deviceId) {
        result.push(devices[index]);
      }
    }
    return result;
  }

  private visibleAirConditioners(): AirConditionerDevice[] {
    if (this.deviceId.length === 0) {
      return this.deviceManager.getAirConditioners();
    }
    const result: AirConditionerDevice[] = [];
    const devices = this.deviceManager.getAirConditioners();
    for (let index = 0; index < devices.length; index++) {
      if (devices[index].id === this.deviceId) {
        result.push(devices[index]);
      }
    }
    return result;
  }
}
