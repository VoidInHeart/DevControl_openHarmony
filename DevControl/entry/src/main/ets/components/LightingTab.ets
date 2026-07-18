import { EnvironmentDevice, LightDevice } from '../model/DeviceModel';
import { DeviceRegistry } from '../model/DeviceRegistry';
import { DeviceManager } from '../model/DeviceManager';

@Component
export struct LightingTab {
  @Consume deviceManager: DeviceManager;
  @Prop deviceId: string = '';
  @Prop showTitle: boolean = true;

  build() {
    Scroll() {
      Column() {
        if (this.showTitle) {
          Text('灯光')
            .fontSize(28)
            .fontWeight(FontWeight.Bold)
            .fontColor('#14263A')
            .width('100%')
          Text('调节亮度和自动照明规则')
            .fontSize(13)
            .fontColor('#748294')
            .width('100%')
            .margin({ top: 6, bottom: 16 })
        }

        ForEach(this.visibleLights(), (device: LightDevice) => {
          this.LightCard(device)
          if (this.deviceId.length > 0) {
            this.AutomationCard(device)
          }
        }, (device: LightDevice) => device.id + ':' + device.stateVersion.toString())
      }
      .width('100%')
      .padding(16)
    }
    .width('100%')
    .layoutWeight(1)
    .backgroundColor('#DCEAF2')
    .scrollBar(BarState.Auto)
  }

  private visibleLights(): LightDevice[] {
    if (this.deviceId.length === 0) {
      return this.deviceManager.getLights();
    }
    const result: LightDevice[] = [];
    const lights = this.deviceManager.getLights();
    for (let index = 0; index < lights.length; index++) {
      if (lights[index].id === this.deviceId) {
        result.push(lights[index]);
      }
    }
    return result;
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
  LightCard(device: LightDevice) {
    Column() {
      if (this.deviceId.length > 0) {
        Text('电源与亮度')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#14263A')
          .width('100%')
          .margin({ bottom: 14 })
      }
      Row() {
        Text(device.state.power ? '●' : '○')
          .fontSize(30)
          .fontColor(device.state.power ? '#F2B84B' : '#8AA0B6')
          .width(56)
          .height(56)
          .textAlign(TextAlign.Center)
          .backgroundColor(device.state.power ? '#FFF4D8' : '#EEF5FB')
          .borderRadius(20)
          .opacity(this.getLightIconOpacity(device.state.power, device.state.brightness))
        Column() {
          Text(device.name)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Text(device.state.power ?
            '开启 · ' + device.state.brightness.toFixed(0) + '%' : '关闭')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 2 })
          Text(DeviceRegistry.getRoomLabel(device.roomId) + ' · ' +
            (device.online ? '在线' : '离线'))
            .fontSize(11)
            .fontColor('#8A98A8')
            .margin({ top: 4 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        .margin({ left: 12 })
        if (this.deviceManager.isDevicePending(device.id)) {
          this.PendingBadge()
        }
        Toggle({ type: ToggleType.Switch, isOn: device.state.power })
          .enabled(this.canControl(device))
          .opacity(this.canControl(device) ? 1 : 0.45)
          .onChange((isOn: boolean) => {
            this.deviceManager.setLightPower(device, isOn);
          })
          .selectedColor($r('app.color.primary'))
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row() {
        Text('亮度')
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .width(54)
        Slider({
          value: device.state.brightness,
          min: 0,
          max: 100,
          step: 10,
          style: SliderStyle.OutSet
        })
          .layoutWeight(1)
          .enabled(this.canControl(device))
          .sliderInteractionMode(SliderInteraction.SLIDE_AND_CLICK)
          .trackColor($r('app.color.divider'))
          .selectedColor($r('app.color.primary'))
          .onChange((value: number, mode: SliderChangeMode) => {
            if (this.shouldCommitSlider(mode)) {
              this.deviceManager.setLightBrightness(device, value);
            }
          })
        Text(device.state.brightness.toFixed(0) + '%')
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
          .width(44)
          .textAlign(TextAlign.End)
      }
      .width('100%')
      .margin({ top: 14 })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding(16)
    .borderRadius(24)
    .backgroundColor('#F7FBFF')
    .margin({ bottom: 12 })
  }

  @Builder
  AutomationCard(device: LightDevice) {
    Column() {
      Row() {
        Column() {
          Text('自动照明规则')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Text(this.automationRuleText(device))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 4 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: device.state.automation.enabled })
          .enabled(this.canControl(device))
          .onChange((enabled: boolean) => {
            this.deviceManager.setLightAutomation(
              device,
              enabled,
              device.state.automation.illuminanceThresholdLux,
              device.state.automation.noPresenceDelaySeconds
            );
          })
      }
      .width('100%')

      Row() {
        this.RuleStatus('房间状态', this.roomPresenceLabel(device.roomId))
        this.RuleStatus('当前光照', this.sensorIlluminance(device.roomId))
      }
      .width('100%')
      .margin({ top: 14 })

      Row() {
        Text('照度阈值')
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .width(72)
        Slider({
          value: device.state.automation.illuminanceThresholdLux,
          min: 10,
          max: 500,
          step: 10,
          style: SliderStyle.OutSet
        })
          .layoutWeight(1)
          .enabled(this.canControl(device))
          .sliderInteractionMode(SliderInteraction.SLIDE_AND_CLICK)
          .onChange((value: number, mode: SliderChangeMode) => {
            if (this.shouldCommitSlider(mode)) {
              this.deviceManager.setLightAutomation(
                device,
                device.state.automation.enabled,
                value,
                device.state.automation.noPresenceDelaySeconds
              );
            }
          })
        Text(device.state.automation.illuminanceThresholdLux.toFixed(0) + ' lx')
          .fontSize(12)
          .width(54)
          .textAlign(TextAlign.End)
      }
      .width('100%')
      .margin({ top: 14 })

      Row() {
        Text('无人延时')
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .width(72)
        Slider({
          value: device.state.automation.noPresenceDelaySeconds,
          min: 5,
          max: 600,
          step: 5,
          style: SliderStyle.OutSet
        })
          .layoutWeight(1)
          .enabled(this.canControl(device))
          .sliderInteractionMode(SliderInteraction.SLIDE_AND_CLICK)
          .onChange((value: number, mode: SliderChangeMode) => {
            if (this.shouldCommitSlider(mode)) {
              this.deviceManager.setLightAutomation(
                device,
                device.state.automation.enabled,
                device.state.automation.illuminanceThresholdLux,
                value
              );
            }
          })
        Text(device.state.automation.noPresenceDelaySeconds.toFixed(0) + ' 秒')
          .fontSize(12)
          .width(54)
          .textAlign(TextAlign.End)
      }
      .width('100%')
      .margin({ top: 10 })
    }
    .width('100%')
    .padding(16)
    .borderRadius(24)
    .backgroundColor('#F7FBFF')
  }

  @Builder
  RuleStatus(label: string, value: string) {
    Column() {
      Text(value)
        .fontSize(16)
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

  private canControl(device: LightDevice): boolean {
    return this.deviceManager.isOnline() && device.online &&
      !this.deviceManager.isDevicePending(device.id);
  }

  private shouldCommitSlider(mode: SliderChangeMode): boolean {
    return mode === SliderChangeMode.End || mode === SliderChangeMode.Click;
  }

  private getLightIconOpacity(isOn: boolean, brightness: number): number {
    if (!isOn) {
      return 0.15;
    }
    return 0.15 + Math.max(0, Math.min(100, brightness)) * 0.0085;
  }

  private roomSensor(roomId: string): EnvironmentDevice | null {
    const sensors = this.deviceManager.getEnvironmentDevices();
    for (let index = 0; index < sensors.length; index++) {
      if (sensors[index].roomId === roomId) {
        return sensors[index];
      }
    }
    return null;
  }

  private sensorPresence(roomId: string): string {
    const sensor = this.roomSensor(roomId);
    if (sensor === null) {
      return '--';
    }
    return sensor.state.presence ? '有人' : '无人';
  }

  private roomPresenceLabel(roomId: string): string {
    const sensor = this.roomSensor(roomId);
    if (sensor === null) {
      return '无传感器';
    }
    return sensor.state.presence ? '有人活动' : '无人活动';
  }

  private sensorIlluminance(roomId: string): string {
    const sensor = this.roomSensor(roomId);
    if (sensor === null) {
      return '--';
    }
    return sensor.state.illuminanceLux.toFixed(0) + ' lx';
  }

  private sensorValidity(roomId: string): string {
    const sensor = this.roomSensor(roomId);
    if (sensor === null) {
      return '--';
    }
    return sensor.state.dataValid ? '有效' : '异常';
  }

  private automationRuleText(device: LightDevice): string {
    if (this.roomSensor(device.roomId) === null) {
      return '该房间没有传感器，暂时不能自动判断是否开灯。';
    }
    return '有人活动且光线较暗时开灯，无人一段时间后关灯。';
  }
}
