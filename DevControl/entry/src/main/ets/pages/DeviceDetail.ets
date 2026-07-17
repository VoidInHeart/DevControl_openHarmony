import { router } from '@kit.ArkUI';
import {
  ACMode,
  AirConditionerDevice,
  DeviceInfo,
  DeviceType,
  DoorLockDevice,
  EnvironmentDevice,
  LightDevice
} from '../model/DeviceModel';
import { DeviceApplication } from '../model/DeviceApplication';
import { DeviceManager } from '../model/DeviceManager';
import { DeviceRegistry } from '../model/DeviceRegistry';

@Entry
@Component
struct DeviceDetail {
  @Provide deviceManager: DeviceManager = DeviceApplication.getDeviceManager();
  @State deviceId: string = '';

  aboutToAppear(): void {
    const params = router.getParams() as Record<string, Object>;
    const deviceId = params['deviceId'];
    if (typeof deviceId === 'string') {
      this.deviceId = deviceId;
    }
  }

  build() {
    Column() {
      this.NavigationHeader()
      Scroll() {
        Column() {
          this.DetailContent()
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 32 })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#EAF5FF')
  }

  @Builder
  NavigationHeader() {
    Row() {
      Text('‹')
        .fontSize(40)
        .fontColor($r('app.color.text_primary'))
        .width(44)
        .height(48)
        .textAlign(TextAlign.Center)
        .onClick(() => {
          router.back();
        })
      Text(this.currentTitle())
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
      Text(this.currentRoom())
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
    }
    .width('100%')
    .height(64)
    .padding({ left: 8, right: 20 })
    .backgroundColor(Color.White)
  }

  @Builder
  DetailContent() {
    if (this.currentDevice() === null) {
      Column() {
        Text('设备不可用')
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Text('设备可能已被移除，或尚未同步到本地。')
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 8 })
      }
      .width('100%')
      .padding(24)
      .margin({ top: 20 })
      .borderRadius(20)
      .backgroundColor(Color.White)
      .alignItems(HorizontalAlign.Center)
    } else {
      this.DeviceHero(this.currentDevice() as DeviceInfo)
      if ((this.currentDevice() as DeviceInfo).type === DeviceType.LIGHT) {
        this.LightControls(this.currentDevice() as LightDevice)
      } else if ((this.currentDevice() as DeviceInfo).type === DeviceType.ENVIRONMENT) {
        this.EnvironmentDetails(this.currentDevice() as EnvironmentDevice)
      } else if ((this.currentDevice() as DeviceInfo).type === DeviceType.AIR_CONDITIONER) {
        this.AirConditionerControls(this.currentDevice() as AirConditionerDevice)
      } else if ((this.currentDevice() as DeviceInfo).type === DeviceType.DOOR_LOCK) {
        this.DoorLockControls(this.currentDevice() as DoorLockDevice)
      }
    }
  }

  @Builder
  DeviceHero(device: DeviceInfo) {
    Column() {
      Text(this.deviceIcon(device))
        .fontSize(56)
      Text(device.name)
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .margin({ top: 10 })
      Text(this.deviceSummary(device))
        .fontSize(15)
        .fontColor(device.online ? $r('app.color.text_secondary') : $r('app.color.status_offline'))
        .margin({ top: 5 })
      Text(DeviceRegistry.getRoomLabel(device.roomId) + ' · ' +
        (device.online ? '在线' : '离线'))
        .fontSize(12)
        .fontColor(device.online ? $r('app.color.status_online') : $r('app.color.status_offline'))
        .margin({ top: 10 })
    }
    .width('100%')
    .padding(24)
    .margin({ top: 20, bottom: 12 })
    .borderRadius(24)
    .backgroundColor(Color.White)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  LightControls(device: LightDevice) {
    Column() {
      this.SectionTitle('灯光控制')
      Row() {
        Text('开关')
          .fontSize(16)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: device.state.power })
          .enabled(this.canControl(device))
          .selectedColor($r('app.color.primary'))
          .onChange((isOn: boolean) => {
            this.deviceManager.setLightPower(device, isOn);
          })
      }
      .width('100%')
      this.SliderRow('亮度', device.state.brightness, 0, 100, 10, '%', (value: number) => {
        this.deviceManager.setLightBrightness(device, value);
      }, this.canControl(device))
      this.SectionTitle('自动化')
      Row() {
        Column() {
          Text('人体与照度联动')
            .fontSize(16)
            .fontColor($r('app.color.text_primary'))
          Text('无人在低照度时自动控制灯光')
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
      this.SliderRow('照度阈值', device.state.automation.illuminanceThresholdLux,
        10, 500, 10, ' lx', (value: number) => {
          this.deviceManager.setLightAutomation(
            device,
            device.state.automation.enabled,
            value,
            device.state.automation.noPresenceDelaySeconds
          );
        }, this.canControl(device))
    }
    .width('100%')
    .padding(20)
    .margin({ bottom: 12 })
    .borderRadius(20)
    .backgroundColor(Color.White)
  }

  @Builder
  EnvironmentDetails(device: EnvironmentDevice) {
    Column() {
      this.SectionTitle('实时环境')
      Row() {
        this.ValueCard('温度', device.state.temperatureCelsius.toFixed(1) + '°C')
        this.ValueCard('湿度', device.state.humidityPercent.toFixed(0) + '%')
      }
      .width('100%')
      Row() {
        Text('光照 ' + device.state.illuminanceLux.toFixed(0) + ' lx')
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .layoutWeight(1)
        Text(device.state.presence ? '检测到有人' : '当前无人')
          .fontSize(14)
          .fontColor(device.state.presence ? $r('app.color.status_online') :
            $r('app.color.text_secondary'))
      }
      .width('100%')
      .margin({ top: 18 })
      if (!device.state.dataValid) {
        Text('传感器数据异常，暂不参与自动化规则。')
          .fontSize(13)
          .fontColor($r('app.color.status_alert'))
          .width('100%')
          .margin({ top: 12 })
      }
    }
    .width('100%')
    .padding(20)
    .margin({ bottom: 12 })
    .borderRadius(20)
    .backgroundColor(Color.White)
  }

  @Builder
  AirConditionerControls(device: AirConditionerDevice) {
    Column() {
      this.SectionTitle('空调控制')
      Row() {
        Text('开关')
          .fontSize(16)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: device.state.power })
          .enabled(this.canControl(device))
          .selectedColor($r('app.color.primary'))
          .onChange((isOn: boolean) => {
            this.deviceManager.setAcPower(device, isOn);
          })
      }
      .width('100%')
      this.SliderRow('目标温度', device.state.targetTemperatureCelsius,
        16, 30, 1, '°C', (value: number) => {
          this.deviceManager.setAcTemperature(device, value);
        }, this.canControl(device))
      Text('运行模式')
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .margin({ top: 16, bottom: 8 })
      Flex({ wrap: FlexWrap.Wrap }) {
        this.ModeButton(device, '自动', ACMode.AUTO)
        this.ModeButton(device, '制冷', ACMode.COOL)
        this.ModeButton(device, '制热', ACMode.HEAT)
        this.ModeButton(device, '除湿', ACMode.DRY)
        this.ModeButton(device, '送风', ACMode.FAN)
      }
      .width('100%')
    }
    .width('100%')
    .padding(20)
    .margin({ bottom: 12 })
    .borderRadius(20)
    .backgroundColor(Color.White)
  }

  @Builder
  DoorLockControls(device: DoorLockDevice) {
    Column() {
      this.SectionTitle('门锁控制')
      Text(device.state.jammed ? '锁体异常，请确认门锁状态' :
        (device.state.locked ? '门锁已上锁' : '门锁已解锁'))
        .fontSize(16)
        .fontColor(device.state.jammed ? $r('app.color.status_alert') :
          $r('app.color.text_primary'))
        .width('100%')
      Text('电量 ' + device.state.batteryPercent.toFixed(0) + '%')
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .margin({ top: 6, bottom: 16 })
      Row() {
        Button('上锁')
          .layoutWeight(1)
          .margin({ right: 6 })
          .fontColor(Color.White)
          .backgroundColor($r('app.color.lock_icon_locked'))
          .enabled(this.canControl(device) && !device.state.locked)
          .onClick(() => {
            this.deviceManager.setDoorLocked(device, true);
          })
        Button('解锁')
          .layoutWeight(1)
          .margin({ left: 6 })
          .fontColor(Color.White)
          .backgroundColor($r('app.color.lock_icon_unlocked'))
          .enabled(this.canControl(device) && device.state.locked)
          .onClick(() => {
            this.deviceManager.setDoorLocked(device, false);
          })
      }
      .width('100%')
      this.SectionTitle('自动上锁')
      Row() {
        Text('解锁后自动上锁')
          .fontSize(16)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: device.state.autoLockEnabled })
          .enabled(this.canControl(device))
          .onChange((enabled: boolean) => {
            this.deviceManager.setDoorAutoLock(device, enabled, device.state.autoLockDelaySeconds);
          })
      }
      .width('100%')
      this.SliderRow('自动上锁延时', device.state.autoLockDelaySeconds,
        5, 60, 1, ' 秒', (value: number) => {
          this.deviceManager.setDoorAutoLock(device, device.state.autoLockEnabled, value);
        }, this.canControl(device))
    }
    .width('100%')
    .padding(20)
    .margin({ bottom: 12 })
    .borderRadius(20)
    .backgroundColor(Color.White)
  }

  @Builder
  SliderRow(
    label: string,
    value: number,
    minimum: number,
    maximum: number,
    step: number,
    unit: string,
    onCommit: (value: number) => void,
    enabled: boolean
  ) {
    Column() {
      Row() {
        Text(label)
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .layoutWeight(1)
        Text(value.toFixed(0) + unit)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.primary'))
      }
      .width('100%')
      Slider({ value: value, min: minimum, max: maximum, step: step, style: SliderStyle.OutSet })
        .width('100%')
        .enabled(enabled)
        .selectedColor($r('app.color.primary'))
        .sliderInteractionMode(SliderInteraction.SLIDE_AND_CLICK)
        .onChange((changedValue: number, mode: SliderChangeMode) => {
          if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
            onCommit(changedValue);
          }
        })
    }
    .width('100%')
    .margin({ top: 18 })
  }

  @Builder
  SectionTitle(value: string) {
    Text(value)
      .fontSize(19)
      .fontWeight(FontWeight.Bold)
      .fontColor($r('app.color.text_primary'))
      .width('100%')
      .margin({ bottom: 16 })
  }

  @Builder
  ValueCard(label: string, value: string) {
    Column() {
      Text(label)
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
      Text(value)
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.primary'))
        .margin({ top: 5 })
    }
    .width('48%')
    .padding(16)
    .borderRadius(16)
    .backgroundColor('#EAF5FF')
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  ModeButton(device: AirConditionerDevice, label: string, mode: string) {
    Button(label)
      .fontSize(13)
      .fontColor(device.state.mode === mode ? Color.White : $r('app.color.text_primary'))
      .backgroundColor(device.state.mode === mode ? $r('app.color.primary') : '#EAF5FF')
      .enabled(this.canControl(device))
      .margin({ right: 8, bottom: 8 })
      .onClick(() => {
        this.deviceManager.setAcMode(device, mode);
      })
  }

  private currentDevice(): DeviceInfo | null {
    return this.deviceManager.getDeviceById(this.deviceId);
  }

  private currentTitle(): string {
    const device = this.currentDevice();
    return device === null ? '设备详情' : device.name;
  }

  private deviceIcon(device: DeviceInfo): string {
    return DeviceRegistry.present(device).icon;
  }

  private deviceSummary(device: DeviceInfo): string {
    return DeviceRegistry.present(device).summary;
  }

  private currentRoom(): string {
    const device = this.currentDevice();
    return device === null ? '' : DeviceRegistry.getRoomLabel(device.roomId);
  }

  private canControl(device: DeviceInfo): boolean {
    return this.deviceManager.isOnline() && device.online &&
      !this.deviceManager.isDevicePending(device.id);
  }
}
