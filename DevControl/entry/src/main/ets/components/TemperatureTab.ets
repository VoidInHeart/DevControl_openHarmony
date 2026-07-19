import {
  ACMode,
  ACFanSpeed,
  AirConditionerDevice,
  CommandPayload,
  DeviceBrand,
  EnvironmentDevice,
  EnvironmentHistoryPoint
} from '../model/DeviceModel';
import { DeviceManager } from '../model/DeviceManager';
import { GenericDevice } from '../model/GenericDeviceModel';

@Component
export struct TemperatureTab {
  @Consume deviceManager: DeviceManager;
  @Prop deviceId: string = '';
  @Prop showTitle: boolean = true;
  @State monitoringExpanded: boolean = true;
  @State airConditionersExpanded: boolean = true;
  @State humidifiersExpanded: boolean = true;
  @State bathHeatersExpanded: boolean = true;

  build() {
    if (this.deviceId.length > 0) {
      this.DeviceDetailContent()
    } else {
      this.EnvironmentFeatureContent()
    }
  }

  @Builder
  DeviceDetailContent() {
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
  EnvironmentFeatureContent() {
    List({ space: 10 }) {
      ListItemGroup({ header: this.MonitoringGroupHeader }) {
        if (this.monitoringExpanded) {
          ListItem() {
            this.EnvironmentSection()
          }
          ListItem() {
            this.HistorySection()
          }
        }
      }
      ListItemGroup({ header: this.AirConditionerGroupHeader }) {
        if (this.airConditionersExpanded) {
          ForEach(this.visibleAirConditioners(), (device: AirConditionerDevice) => {
            ListItem() {
              this.AirConditionerCard(device)
            }
          }, (device: AirConditionerDevice) => device.id + ':' + device.stateVersion.toString())
        }
      }
      ListItemGroup({ header: this.HumidifierGroupHeader }) {
        if (this.humidifiersExpanded) {
          ForEach(this.humidifiers(), (device: GenericDevice) => {
            ListItem() {
              this.HumidifierCard(device)
            }
          }, (device: GenericDevice) => device.id + ':' + device.stateVersion.toString())
        }
      }
      ListItemGroup({ header: this.BathHeaterGroupHeader }) {
        if (this.bathHeatersExpanded) {
          ForEach(this.bathHeaters(), (device: GenericDevice) => {
            ListItem() {
              this.BathHeaterCard(device)
            }
          }, (device: GenericDevice) => device.id + ':' + device.stateVersion.toString())
        }
      }
    }
    .width('100%')
    .layoutWeight(1)
    .padding(16)
    .scrollBar(BarState.Auto)
    .sticky(StickyStyle.Header)
  }

  @Builder
  MonitoringGroupHeader() {
    Row() {
      Column() {
        Text('环境监测')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#14263A')
        Text(this.visibleEnvironmentDevices().length.toString() + ' 台设备')
          .fontSize(12)
          .fontColor('#748294')
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      Blank()
      Text(this.monitoringExpanded ? '⌃' : '⌄')
        .fontSize(22)
        .fontColor('#748294')
    }
    .width('100%')
    .padding({ top: 8, bottom: 10 })
    .backgroundColor('#DCEAF2')
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.monitoringExpanded = !this.monitoringExpanded;
    })
  }

  @Builder
  AirConditionerGroupHeader() {
    Row() {
      Column() {
        Text('空调')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#14263A')
        Text(this.visibleAirConditioners().length.toString() + ' 台设备')
          .fontSize(12)
          .fontColor('#748294')
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      Blank()
      Text(this.airConditionersExpanded ? '⌃' : '⌄')
        .fontSize(22)
        .fontColor('#748294')
    }
    .width('100%')
    .padding({ top: 8, bottom: 10 })
    .backgroundColor('#DCEAF2')
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.airConditionersExpanded = !this.airConditionersExpanded;
    })
  }

  @Builder
  HumidifierGroupHeader() {
    Row() {
      Column() {
        Text('加湿器')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#14263A')
        Text(this.humidifiers().length.toString() + ' 台设备')
          .fontSize(12)
          .fontColor('#748294')
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      Blank()
      Text(this.humidifiersExpanded ? '⌃' : '⌄')
        .fontSize(22)
        .fontColor('#748294')
    }
    .width('100%')
    .padding({ top: 8, bottom: 10 })
    .backgroundColor('#DCEAF2')
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.humidifiersExpanded = !this.humidifiersExpanded;
    })
  }

  @Builder
  BathHeaterGroupHeader() {
    Row() {
      Column() {
        Text('浴霸')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#14263A')
        Text(this.bathHeaters().length.toString() + ' 台设备')
          .fontSize(12)
          .fontColor('#748294')
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      Blank()
      Text(this.bathHeatersExpanded ? '⌃' : '⌄')
        .fontSize(22)
        .fontColor('#748294')
    }
    .width('100%')
    .padding({ top: 8, bottom: 10 })
    .backgroundColor('#DCEAF2')
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.bathHeatersExpanded = !this.bathHeatersExpanded;
    })
  }

  @Builder
  EnvironmentSection() {
    Column() {
      ForEach(this.visibleEnvironmentDevices(), (sensor: EnvironmentDevice) => {
        Column() {
          Row() {
            Column() {
              Text(sensor.name)
                .fontSize(17)
                .fontWeight(FontWeight.Bold)
                .fontColor('#14263A')
              Text(sensor.state.dataValid ? '数据有效 · ' + (sensor.online ? '在线' : '离线') : '数据异常')
                .fontSize(12)
                .fontColor(sensor.state.dataValid ? '#748294' : $r('app.color.status_alert'))
                .margin({ top: 4 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
          }
          .width('100%')
          .margin({ bottom: 14 })

          Row() {
            this.ValueCard('温度', sensor.state.temperatureCelsius.toFixed(1) + '°C',
              this.getTempColor(sensor.state.temperatureCelsius))
            this.ValueCard('湿度', sensor.state.humidityPercent.toFixed(0) + '%',
              $r('app.color.primary'))
          }
          .width('100%')
          Row() {
            this.ValueCard('照度', sensor.state.illuminanceLux.toFixed(0) + ' lx',
              $r('app.color.text_primary'))
            this.ValueCard('人体', sensor.state.presence ? '有人' : '无人',
              sensor.state.presence ? $r('app.color.status_online') : $r('app.color.text_secondary'))
          }
          .width('100%')
          .margin({ top: 12 })
        }
        .width('100%')
        .padding(16)
        .borderRadius(24)
        .backgroundColor('#F7FBFF')
        .margin({ bottom: 12 })
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
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor(color)
        .margin({ top: 4 })
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
    .height(74)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(Color.White)
    .borderRadius(18)
    .margin({ right: 8 })
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
        Text('❄')
          .fontSize(28)
          .fontColor(device.state.power ? '#1769C2' : '#8AA0B6')
          .width(56)
          .height(56)
          .textAlign(TextAlign.Center)
          .backgroundColor(device.state.power ? '#EAF4FF' : '#EEF5FB')
          .borderRadius(20)
        Column() {
          Text(device.name)
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor('#14263A')
          Text(this.brandLabel(device.state.brand) + '适配 · ' +
            (device.state.power ? '运行中' : '已关闭') + ' · ' + this.fanSpeedLabel(device.state.fanSpeed))
            .fontSize(12)
            .fontColor('#748294')
            .margin({ top: 5 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        .margin({ left: 12 })
        if (this.deviceManager.isDevicePending(device.id)) {
          this.PendingBadge()
        }
        Toggle({ type: ToggleType.Switch, isOn: device.state.power })
          .enabled(this.canControl(device))
          .onChange((power: boolean) => {
            this.deviceManager.setAcPower(device, power);
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row() {
        Column() {
          Text('当前室温')
            .fontSize(12)
            .fontColor('#748294')
          Text(this.roomTemperature(device.roomId))
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#14263A')
            .margin({ top: 4 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        Column() {
          Text('目标温度')
            .fontSize(12)
            .fontColor('#748294')
          Row() {
            Button('-')
              .width(42)
              .height(42)
              .fontSize(20)
              .fontColor('#1769C2')
              .backgroundColor(Color.White)
              .enabled(this.canControl(device) && device.state.targetTemperatureCelsius > 16)
              .onClick(() => {
                this.deviceManager.setAcTemperature(device, device.state.targetTemperatureCelsius - 1);
              })
            Text(device.state.targetTemperatureCelsius.toFixed(0) + '°')
              .fontSize(36)
              .fontWeight(FontWeight.Bold)
              .fontColor('#1769C2')
              .width(86)
              .textAlign(TextAlign.Center)
            Button('+')
              .width(42)
              .height(42)
              .fontSize(20)
              .fontColor('#1769C2')
              .backgroundColor(Color.White)
              .enabled(this.canControl(device) && device.state.targetTemperatureCelsius < 30)
              .onClick(() => {
                this.deviceManager.setAcTemperature(device, device.state.targetTemperatureCelsius + 1);
              })
          }
          .margin({ top: 4 })
          .alignItems(VerticalAlign.Center)
        }
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
      .padding(16)
      .backgroundColor(Color.White)
      .borderRadius(22)
      .margin({ top: 18 })

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

      Text('风速')
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .margin({ top: 12, bottom: 8 })
      Row() {
        this.FanSpeedButton(device, '自动', ACFanSpeed.AUTO)
        this.FanSpeedButton(device, '低风', ACFanSpeed.LOW)
        this.FanSpeedButton(device, '中风', ACFanSpeed.MEDIUM)
        this.FanSpeedButton(device, '高风', ACFanSpeed.HIGH)
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)

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
        Column() {
          Text('最近下发控制帧')
            .fontSize(12)
            .fontColor('#748294')
            .width('100%')
          Text(device.state.lastAdapterFrame)
            .fontSize(11)
            .fontColor('#14263A')
            .width('100%')
            .margin({ top: 5 })
        }
        .width('100%')
        .padding(12)
        .backgroundColor(Color.White)
        .borderRadius(16)
        .margin({ top: 12 })
      }
    }
    .width('100%')
    .padding(16)
    .borderRadius(24)
    .backgroundColor('#F7FBFF')
    .margin({ bottom: 12 })
  }

  @Builder
  HumidifierCard(device: GenericDevice) {
    Column() {
      Row() {
        Text('≈')
          .fontSize(34)
          .fontWeight(FontWeight.Bold)
          .fontColor('#0F8F66')
          .width(56)
          .height(56)
          .lineHeight(52)
          .textAlign(TextAlign.Center)
          .backgroundColor('#E8F8F3')
          .borderRadius(20)
        Column() {
          Text(device.name)
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor('#14263A')
          Text(this.genericPower(device) ? '正在加湿' : '已关闭')
            .fontSize(12)
            .fontColor('#748294')
            .margin({ top: 5 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        .margin({ left: 12 })
        Toggle({ type: ToggleType.Switch, isOn: this.genericPower(device) })
          .enabled(this.canControlGeneric(device))
          .selectedColor('#0F8F66')
          .onChange((power: boolean) => {
            this.setGenericPower(device, power);
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row() {
        Text('目标湿度')
          .fontSize(14)
          .fontColor('#748294')
        Blank()
        Text(this.humidifierTarget(device).toFixed(0) + '%')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor('#0F8F66')
      }
      .width('100%')
      .margin({ top: 18, bottom: 8 })
      Slider({
        value: this.humidifierTarget(device),
        min: 35,
        max: 75,
        step: 1,
        style: SliderStyle.OutSet
      })
        .width('100%')
        .enabled(this.canControlGeneric(device))
        .selectedColor('#0F8F66')
        .sliderInteractionMode(SliderInteraction.SLIDE_AND_CLICK)
        .onChange((value: number, mode: SliderChangeMode) => {
          if (this.shouldCommitSlider(mode)) {
            this.setHumidifierTarget(device, value);
          }
        })
    }
    .width('100%')
    .padding(16)
    .borderRadius(24)
    .backgroundColor('#F7FBFF')
    .margin({ bottom: 12 })
  }

  @Builder
  BathHeaterCard(device: GenericDevice) {
    Column() {
      Row() {
        Text('♨')
          .fontSize(29)
          .fontColor('#C86A25')
          .width(56)
          .height(56)
          .lineHeight(56)
          .textAlign(TextAlign.Center)
          .backgroundColor('#FFF0E4')
          .borderRadius(20)
        Column() {
          Text(device.name)
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor('#14263A')
          Text(this.genericPower(device) ? this.bathHeaterModeLabel(device) : '已关闭')
            .fontSize(12)
            .fontColor('#748294')
            .margin({ top: 5 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        .margin({ left: 12 })
        Toggle({ type: ToggleType.Switch, isOn: this.genericPower(device) })
          .enabled(this.canControlGeneric(device))
          .selectedColor('#C86A25')
          .onChange((power: boolean) => {
            this.setGenericPower(device, power);
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text('运行模式')
        .fontSize(14)
        .fontColor('#748294')
        .width('100%')
        .margin({ top: 18, bottom: 8 })
      Row() {
        this.BathHeaterModeButton(device, '暖风', 'warm')
        this.BathHeaterModeButton(device, '换气', 'ventilate')
        this.BathHeaterModeButton(device, '干燥', 'dry')
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
    }
    .width('100%')
    .padding(16)
    .borderRadius(24)
    .backgroundColor('#F7FBFF')
    .margin({ bottom: 12 })
  }

  @Builder
  BathHeaterModeButton(device: GenericDevice, label: string, mode: string) {
    Button(label)
      .fontSize(13)
      .fontColor(this.bathHeaterMode(device) === mode ? '#C86A25' : '#14263A')
      .backgroundColor(this.bathHeaterMode(device) === mode ? '#FFF0E4' : Color.White)
      .enabled(this.canControlGeneric(device))
      .onClick(() => {
        this.setBathHeaterMode(device, mode);
      })
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
  ModeButton(device: AirConditionerDevice, label: string, mode: string) {
    Button(label)
      .fontSize(12)
      .fontColor(device.state.mode === mode ? '#1769C2' : $r('app.color.text_primary'))
      .backgroundColor(device.state.mode === mode ?
        '#EAF4FF' : Color.White)
      .enabled(this.canControl(device))
      .margin({ right: 4, bottom: 6 })
      .onClick(() => {
        this.deviceManager.setAcMode(device, mode);
      })
  }

  @Builder
  FanSpeedButton(device: AirConditionerDevice, label: string, fanSpeed: string) {
    Button(label)
      .fontSize(12)
      .fontColor(device.state.fanSpeed === fanSpeed ? '#1769C2' : $r('app.color.text_primary'))
      .backgroundColor(device.state.fanSpeed === fanSpeed ? '#EAF4FF' : Color.White)
      .enabled(this.canControl(device))
      .onClick(() => {
        this.deviceManager.setAcFanSpeed(device, fanSpeed);
      })
  }

  @Builder
  BrandButton(device: AirConditionerDevice, label: string, brand: string) {
    Button(label)
      .fontSize(11)
      .fontColor(device.state.brand === brand ? '#1769C2' : $r('app.color.text_primary'))
      .backgroundColor(device.state.brand === brand ?
        '#EAF4FF' : Color.White)
      .enabled(this.canControl(device))
      .onClick(() => {
        this.deviceManager.setAcBrand(device, brand);
      })
  }

  private canControl(device: AirConditionerDevice): boolean {
    return this.deviceManager.isOnline() && device.online &&
      !this.deviceManager.isDevicePending(device.id);
  }

  private canControlGeneric(device: GenericDevice): boolean {
    return this.deviceManager.isOnline() && device.online &&
      !this.deviceManager.isDevicePending(device.id);
  }

  private genericPower(device: GenericDevice): boolean {
    const value = device.state['power'];
    return typeof value === 'boolean' && value;
  }

  private humidifierTarget(device: GenericDevice): number {
    const value = device.state['targetHumidityPercent'];
    return typeof value === 'number' ? value : 55;
  }

  private bathHeaterMode(device: GenericDevice): string {
    const value = device.state['mode'];
    return typeof value === 'string' ? value : 'warm';
  }

  private bathHeaterModeLabel(device: GenericDevice): string {
    const mode = this.bathHeaterMode(device);
    if (mode === 'ventilate') {
      return '换气中';
    }
    if (mode === 'dry') {
      return '干燥中';
    }
    return '暖风中';
  }

  private setGenericPower(device: GenericDevice, power: boolean): void {
    const payload: CommandPayload = {};
    payload['power'] = power;
    this.deviceManager.executeDeviceAction(device, 'setPower', payload);
  }

  private setHumidifierTarget(device: GenericDevice, targetHumidityPercent: number): void {
    const payload: CommandPayload = {};
    payload['targetHumidityPercent'] = Math.round(targetHumidityPercent);
    this.deviceManager.executeDeviceAction(device, 'setTargetHumidity', payload);
  }

  private setBathHeaterMode(device: GenericDevice, mode: string): void {
    const payload: CommandPayload = {};
    payload['mode'] = mode;
    this.deviceManager.executeDeviceAction(device, 'setMode', payload);
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

  private fanSpeedLabel(fanSpeed: string): string {
    if (fanSpeed === ACFanSpeed.LOW) {
      return '低风';
    }
    if (fanSpeed === ACFanSpeed.MEDIUM) {
      return '中风';
    }
    if (fanSpeed === ACFanSpeed.HIGH) {
      return '高风';
    }
    return '自动风';
  }

  private roomTemperature(roomId: string): string {
    const sensors = this.deviceManager.getEnvironmentDevices();
    for (let index = 0; index < sensors.length; index++) {
      if (sensors[index].roomId === roomId) {
        return sensors[index].state.temperatureCelsius.toFixed(1) + '°C';
      }
    }
    return '--';
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

  private humidifiers(): GenericDevice[] {
    return this.genericDevicesByType('humidifier');
  }

  private bathHeaters(): GenericDevice[] {
    return this.genericDevicesByType('bathHeater');
  }

  private genericDevicesByType(type: string): GenericDevice[] {
    const result: GenericDevice[] = [];
    const devices = this.deviceManager.devices;
    for (let index = 0; index < devices.length; index++) {
      if (devices[index].type === type) {
        result.push(devices[index] as GenericDevice);
      }
    }
    return result;
  }
}
