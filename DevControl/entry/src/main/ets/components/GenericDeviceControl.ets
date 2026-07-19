import { CommandPayload } from '../model/DeviceModel';
import { DeviceManager } from '../model/DeviceManager';
import { immersiveCardEffect } from '../common/ImmersiveUi';
import {
  DeviceControl,
  DeviceControlKind,
  DeviceControlOption,
  GenericDevice
} from '../model/GenericDeviceModel';
import { CurtainIcon } from './CurtainIcon';

@Component
export struct GenericDeviceControl {
  @Consume deviceManager: DeviceManager;
  @Prop deviceId: string = '';

  build() {
    Scroll() {
      Column() {
        if (this.currentDevice() === null) {
          this.EmptyState()
        } else {
          this.DeviceStatus(this.currentDevice() as GenericDevice)
          ForEach(
            (this.currentDevice() as GenericDevice).controls,
            (control: DeviceControl) => {
              this.ControlCard(control)
            },
            (control: DeviceControl) => control.id
          )
          if (this.deviceManager.lastError.length > 0) {
            Text(this.deviceManager.lastError)
              .fontSize(13)
              .fontColor($r('app.color.status_alert'))
              .width('100%')
              .padding(12)
              .margin({ top: 4 })
              .borderRadius(12)
              .backgroundColor('#FFF2F0')
          }
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 20, bottom: 28 })
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Auto)
  }

  @Builder
  DeviceStatus(device: GenericDevice) {
    Row() {
      Stack({ alignContent: Alignment.Center }) {
        if (device.category.id === 'curtains') {
          CurtainIcon({ iconSize: 34 })
        } else if (device.category.id === 'environment') {
          Image($r('app.media.device_environment'))
            .width(30)
            .height(30)
            .objectFit(ImageFit.Contain)
        } else {
          Text(device.category.icon)
            .fontSize(38)
            .width(58)
            .height(58)
            .lineHeight(58)
            .textAlign(TextAlign.Center)
        }
      }
        .width(58)
        .height(58)
        .backgroundColor(device.category.id === 'environment' ? '#E8F8F3' : '#EAF5FF')
        .borderRadius(18)
      Column() {
        Text(device.name)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Text(device.online ? '设备在线' : '设备离线')
          .fontSize(13)
          .fontColor(device.online ? $r('app.color.status_online') :
            $r('app.color.status_offline'))
          .margin({ top: 4 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 14 })
      if (this.deviceManager.isDevicePending(device.id)) {
        Text('处理中')
          .fontSize(12)
          .fontColor($r('app.color.status_warning'))
      }
    }
    .width('100%')
    .padding(16)
    .margin({ bottom: 12 })
    .borderRadius(18)
    .backgroundColor(Color.White)
    .visualEffect(immersiveCardEffect())
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  ControlCard(control: DeviceControl) {
    Column() {
      Text(control.label)
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
      if (control.kind === DeviceControlKind.BUTTON) {
        Button(control.label)
          .width('100%')
          .margin({ top: 14 })
          .enabled(this.canControl())
          .opacity(this.canControl() ? 1 : 0.45)
          .onClick(() => {
            this.submit(control, {});
          })
      } else if (control.kind === DeviceControlKind.TOGGLE) {
        Row() {
          Text(this.booleanState(control) ? '已开启' : '已关闭')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .layoutWeight(1)
          Toggle({
            type: ToggleType.Switch,
            isOn: this.booleanState(control)
          })
            .enabled(this.canControl())
            .opacity(this.canControl() ? 1 : 0.45)
            .onChange((value: boolean) => {
              const payload: CommandPayload = {};
              payload[control.payloadKey] = value;
              this.submit(control, payload);
            })
            .selectedColor($r('app.color.primary'))
        }
        .width('100%')
        .margin({ top: 14 })
        .alignItems(VerticalAlign.Center)
      } else if (control.kind === DeviceControlKind.SLIDER) {
        Row() {
          Slider({
            value: this.numberState(control),
            min: control.minimum,
            max: control.maximum,
            step: control.step,
            style: SliderStyle.OutSet
          })
            .layoutWeight(1)
            .enabled(this.canControl())
            .sliderInteractionMode(SliderInteraction.SLIDE_AND_CLICK)
            .trackColor($r('app.color.divider'))
            .selectedColor($r('app.color.primary'))
            .onChange((value: number, mode: SliderChangeMode) => {
              if (
                mode === SliderChangeMode.End ||
                mode === SliderChangeMode.Click
              ) {
                const payload: CommandPayload = {};
                payload[control.payloadKey] = value;
                this.submit(control, payload);
              }
            })
          Text(this.numberState(control).toFixed(0) + control.unit)
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .width(54)
            .textAlign(TextAlign.End)
        }
        .width('100%')
        .margin({ top: 14 })
        .alignItems(VerticalAlign.Center)
      } else if (control.kind === DeviceControlKind.ENUM) {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(control.options, (option: DeviceControlOption) => {
            Button(option.label)
              .fontSize(13)
              .fontColor(this.stringState(control) === option.value ?
                Color.White : $r('app.color.text_primary'))
              .backgroundColor(this.stringState(control) === option.value ?
                $r('app.color.primary') : '#EAF5FF')
              .margin({ right: 8, top: 10 })
              .enabled(this.canControl())
              .onClick(() => {
                const payload: CommandPayload = {};
                payload[control.payloadKey] = option.value;
                this.submit(control, payload);
              })
          }, (option: DeviceControlOption) => option.value)
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(16)
    .margin({ bottom: 12 })
    .borderRadius(18)
    .backgroundColor(Color.White)
    .visualEffect(immersiveCardEffect())
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  EmptyState() {
    Column() {
      Text('设备能力不可用')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
      Text('请重新同步网关设备快照。')
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .margin({ top: 8 })
    }
    .width('100%')
    .padding(32)
    .alignItems(HorizontalAlign.Center)
  }

  private currentDevice(): GenericDevice | null {
    const device = this.deviceManager.getDeviceById(this.deviceId);
    return device === null ? null : device as GenericDevice;
  }

  private canControl(): boolean {
    const device = this.currentDevice();
    return device !== null &&
      this.deviceManager.isOnline() &&
      device.online &&
      !this.deviceManager.isDevicePending(device.id);
  }

  private booleanState(control: DeviceControl): boolean {
    const device = this.currentDevice();
    if (device === null) {
      return false;
    }
    const value = device.state[control.stateKey];
    return typeof value === 'boolean' ? value : false;
  }

  private numberState(control: DeviceControl): number {
    const device = this.currentDevice();
    if (device === null) {
      return control.minimum;
    }
    const value = device.state[control.stateKey];
    return typeof value === 'number' ? value : control.minimum;
  }

  private stringState(control: DeviceControl): string {
    const device = this.currentDevice();
    if (device === null) {
      return '';
    }
    const value = device.state[control.stateKey];
    return typeof value === 'string' ? value : '';
  }

  private submit(control: DeviceControl, payload: CommandPayload): void {
    const device = this.currentDevice();
    if (device === null || !this.canControl()) {
      return;
    }
    if (!control.requiresConfirmation) {
      this.deviceManager.executeDeviceAction(device, control.action, payload);
      return;
    }
    AlertDialog.show({
      title: '确认设备操作',
      message: '即将执行“' + control.label + '”，请确认操作。',
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '确认',
        action: () => {
          this.deviceManager.executeDeviceAction(device, control.action, payload);
        }
      }
    });
  }
}

