import { LightDevice } from '../model/DeviceModel';
import { DeviceManager } from '../model/DeviceManager';

@Component
export struct LightingTab {
  @Consume deviceManager: DeviceManager;

  build() {
    Scroll() {
      Column() {
        Text('照明中心')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
          .margin({ bottom: 16 })

        ForEach(this.deviceManager.getLights(), (device: LightDevice) => {
          this.LightCard(device)
          this.AutomationCard(device)
        }, (device: LightDevice) => device.id + ':' + device.stateVersion.toString())
      }
      .width('100%')
      .padding(16)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Auto)
  }

  @Builder
  LightCard(device: LightDevice) {
    Column() {
      Row() {
        Text(device.state.power ? '💡' : '○')
          .fontSize(32)
          .fontColor(device.state.power ?
            $r('app.color.light_icon_on') : $r('app.color.light_icon_off'))
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
    .borderRadius(16)
    .backgroundColor($r('app.color.card_background'))
    .margin({ bottom: 12 })
  }

  @Builder
  AutomationCard(device: LightDevice) {
    Column() {
      Row() {
        Column() {
          Text('人体与照度自动照明')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Text('手动控制后由网关保留5分钟优先权')
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
    .borderRadius(16)
    .backgroundColor($r('app.color.card_background'))
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
}
