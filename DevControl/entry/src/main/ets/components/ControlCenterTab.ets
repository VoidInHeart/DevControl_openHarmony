import { router } from '@kit.ArkUI';
import {
  ACMode,
  AirConditionerDevice,
  CommandPayload,
  DeviceInfo,
  DeviceType,
  DoorLockDevice,
  EnvironmentDevice,
  LightDevice
} from '../model/DeviceModel';
import { DeviceFeature, DeviceRegistry } from '../model/DeviceRegistry';
import { DeviceManager } from '../model/DeviceManager';
import { GenericDevice } from '../model/GenericDeviceModel';
import { CurtainIcon } from './CurtainIcon';
import { LockIcon } from './LockIcon';

@Component
export struct ControlCenterTab {
  @Consume deviceManager: DeviceManager;
  @StorageLink('homeSelectedRoom') selectedRoom: string = 'all';
  @State showMetricSheet: boolean = false;
  @State showAddMenu: boolean = false;
  @State activeMetric: string = '';
  private roomSegmentsScroller: Scroller = new Scroller();

  build() {
    Column() {
      if (this.deviceManager.deviceStateRevision >= 0) {
        Column() {
          this.HomeHeader()
          this.RoomSegments()
        }
        .width('100%')
        .padding({ left: 18, right: 18, top: 42, bottom: 0 })

        List() {
          ListItem() {
            this.StatusStrip()
          }
          if (this.selectedRoom === 'all') {
            ListItem() {
              this.FeatureSection()
            }
          }
          ListItem() {
            this.DeviceSectionTitle()
          }
          ForEach(this.visibleDevices(), (device: DeviceInfo) => {
            ListItem() {
              this.DeviceRow(device)
            }
          }, (device: DeviceInfo) => device.id + ':' + device.stateVersion.toString())
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 18, right: 18, top: 0, bottom: 0 })
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .layoutWeight(1)
    .backgroundColor('#DCEAF2')
    .bindSheet(this.showMetricSheet, this.MetricSheet(), {
      height: '70%',
      dragBar: true,
      showClose: false,
      maskColor: '#33000000',
      onDisappear: () => {
        this.showMetricSheet = false;
      }
    })
  }

  @Builder
  HomeHeader() {
    Stack({ alignContent: Alignment.TopEnd }) {
      Row() {
        Column() {
          Text('DevControl 的家')
            .fontSize(30)
            .fontWeight(FontWeight.Bold)
            .fontColor('#14263A')
          Text(this.headerSubtitle())
            .fontSize(13)
            .fontColor('#748294')
            .margin({ top: 6 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Stack({ alignContent: Alignment.Center }) {
          Text('+')
            .fontSize(32)
            .fontWeight(FontWeight.Medium)
            .fontColor('#1769C2')
            .width('100%')
            .height('100%')
            .lineHeight(46)
            .textAlign(TextAlign.Center)
            .translate({ y: -2 })
        }
          .width(46)
          .height(46)
          .id('home-add-device-button')
          .backgroundColor('#E4F0FF')
          .borderRadius(23)
          .onClick(() => {
            this.showAddMenu = !this.showAddMenu;
          })
      }
      .width('100%')
      if (this.showAddMenu) {
        Column() {
          Row() {
            Text('▣')
              .fontSize(20)
              .fontColor('#1769C2')
              .width(34)
              .textAlign(TextAlign.Center)
            Column() {
              Text('添加设备')
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor('#14263A')
              Text('通过二维码安全接入')
                .fontSize(11)
                .fontColor('#748294')
                .margin({ top: 2 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
          }
          .id('home-add-device-menu-item')
          .width('100%')
          .height(58)
          .padding({ left: 8, right: 8 })
          .borderRadius(12)
          .onClick(() => {
            this.showAddMenu = false;
            router.pushUrl({ url: 'pages/AddDevice' });
          })
          Divider()
            .color('#EDF1F5')
          Row() {
            Text('⌂')
              .fontSize(22)
              .fontColor('#1769C2')
              .width(34)
              .textAlign(TextAlign.Center)
            Column() {
              Text('添加房间')
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor('#14263A')
              Text('新建后可用于设备归属')
                .fontSize(11)
                .fontColor('#748294')
                .margin({ top: 2 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
          }
          .id('home-add-room-menu-item')
          .width('100%')
          .height(58)
          .padding({ left: 8, right: 8 })
          .borderRadius(12)
          .onClick(() => {
            this.showAddMenu = false;
            router.pushUrl({ url: 'pages/AddRoom' });
          })
        }
        .id('home-add-menu')
        .width(206)
        .padding(8)
        .backgroundColor(Color.White)
        .borderRadius(16)
        .margin({ top: 56, right: 0 })
        .zIndex(20)
      }
    }
    .width('100%')
    .margin({ bottom: 10 })
    .zIndex(10)
  }

  @Builder
  StatusStrip() {
    Row() {
      this.TemperaturePill()
      this.HumidityPill()
      this.LightsPill()
      this.OnlinePill()
    }
    .width('100%')
    .justifyContent(FlexAlign.SpaceBetween)
    .margin({ bottom: 16 })
  }

  @Builder
  TemperaturePill() {
    Column() {
      Text('│')
        .fontSize(20)
        .opacity(0.85)
      Text(this.averageTemperature())
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor('#1769C2')
        .margin({ top: 3 })
      Text(this.temperatureLabel())
        .fontSize(11)
        .fontColor('#748294')
        .margin({ top: 3 })
    }
    .width('23%')
    .height(86)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor('#EAF4FF')
    .borderRadius(20)
    .onClick(() => {
      this.openMetricSheet('temperature');
    })
  }

  @Builder
  HumidityPill() {
    Column() {
      Text('●')
        .fontSize(20)
        .opacity(0.85)
      Text(this.averageHumidity())
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor('#1769C2')
        .margin({ top: 3 })
      Text(this.humidityLabel())
        .fontSize(11)
        .fontColor('#748294')
        .margin({ top: 3 })
    }
    .width('23%')
    .height(86)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor('#EEF9F4')
    .borderRadius(20)
    .onClick(() => {
      this.openMetricSheet('humidity');
    })
  }

  @Builder
  LightsPill() {
    Column() {
      Text('○')
        .fontSize(20)
        .opacity(0.85)
      Text(this.lightsOnCount().toString())
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor('#1769C2')
        .margin({ top: 3 })
      Text('亮灯')
        .fontSize(11)
        .fontColor('#748294')
        .margin({ top: 3 })
    }
    .width('23%')
    .height(86)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor('#FFF7E8')
    .borderRadius(20)
    .onClick(() => {
      this.openMetricSheet('lights');
    })
  }

  @Builder
  OnlinePill() {
    Column() {
      Text('●')
        .fontSize(20)
        .opacity(0.85)
      Text(this.onlineDeviceCount().toString())
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor('#1769C2')
        .margin({ top: 3 })
      Text('在线')
        .fontSize(11)
        .fontColor('#748294')
        .margin({ top: 3 })
    }
    .width('23%')
    .height(86)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor('#F0EEFF')
    .borderRadius(20)
    .onClick(() => {
      this.openMetricSheet('online');
    })
  }

  @Builder
  MetricSheet() {
    Column() {
      Row() {
        Column() {
          Text(this.metricSheetTitle())
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor('#14263A')
          Text(this.metricSheetSubtitle())
            .fontSize(13)
            .fontColor('#748294')
            .margin({ top: 4 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Text('×')
          .fontSize(28)
          .fontColor('#748294')
          .width(44)
          .height(44)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.showMetricSheet = false;
          })
      }
      .width('100%')
      .padding({ left: 20, right: 12, top: 14, bottom: 12 })

      Scroll() {
        Column() {
          if (this.activeMetric === 'temperature') {
            this.TemperatureMetricContent()
          } else if (this.activeMetric === 'humidity') {
            this.HumidityMetricContent()
          } else if (this.activeMetric === 'lights') {
            this.LightsMetricContent()
          } else {
            this.OnlineMetricContent()
          }
        }
        .width('100%')
        .padding({ left: 20, right: 20, bottom: 28 })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.White)
  }

  @Builder
  LightsMetricContent() {
    Column() {
      Text('正在开启的灯')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor('#14263A')
        .width('100%')
        .margin({ bottom: 12 })
      if (this.activeLights().length === 0) {
        this.SheetEmptyState('当前没有开启的灯')
      } else {
        ForEach(this.activeLights(), (device: LightDevice) => {
          Row() {
            Text('○')
              .fontSize(28)
              .fontColor('#A46A00')
              .width(48)
              .height(48)
              .textAlign(TextAlign.Center)
              .backgroundColor('#FFF4D8')
              .borderRadius(16)
            Column() {
              Text(device.name)
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor('#14263A')
              Text('亮度 ' + device.state.brightness.toFixed(0) + '%')
                .fontSize(12)
                .fontColor('#748294')
                .margin({ top: 4 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            .margin({ left: 12 })
            Toggle({ type: ToggleType.Switch, isOn: device.state.power })
              .enabled(this.canControlDevice(device))
              .opacity(this.canControlDevice(device) ? 1 : 0.45)
              .selectedColor('#1769C2')
              .onChange((isOn: boolean) => {
                this.deviceManager.setLightPower(device, isOn);
              })
          }
          .width('100%')
          .padding(14)
          .borderRadius(20)
          .backgroundColor('#F7FBFF')
          .margin({ bottom: 10 })
          .alignItems(VerticalAlign.Center)
        }, (device: LightDevice) => device.id + ':' + device.stateVersion.toString())
      }
    }
    .width('100%')
  }

  @Builder
  TemperatureMetricContent() {
    Column() {
      Text('已接入空调')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor('#14263A')
        .width('100%')
        .margin({ bottom: 12 })
      if (this.scopedAirConditioners().length === 0) {
        this.SheetEmptyState('当前范围暂未接入空调')
      } else {
        ForEach(this.scopedAirConditioners(), (device: AirConditionerDevice) => {
          Column() {
            Row() {
              Text('❄')
                .fontSize(24)
                .fontColor('#1769C2')
                .width(48)
                .height(48)
                .textAlign(TextAlign.Center)
                .backgroundColor('#EAF4FF')
                .borderRadius(16)
              Column() {
                Text(device.name)
                  .fontSize(16)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#14263A')
                Text(device.state.power ? '已开启' : '已关闭')
                  .fontSize(12)
                  .fontColor('#748294')
                  .margin({ top: 4 })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              .margin({ left: 12 })
              Toggle({ type: ToggleType.Switch, isOn: device.state.power })
                .enabled(this.canControlDevice(device))
                .opacity(this.canControlDevice(device) ? 1 : 0.45)
                .selectedColor('#1769C2')
                .onChange((isOn: boolean) => {
                  this.deviceManager.setAcPower(device, isOn);
                })
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)

            Row() {
              Text('目标温度')
                .fontSize(13)
                .fontColor('#748294')
              Blank()
              Text(device.state.targetTemperatureCelsius.toFixed(0) + '°C')
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor('#1769C2')
            }
            .width('100%')
            .margin({ top: 18 })
            Slider({
              value: device.state.targetTemperatureCelsius,
              min: 16,
              max: 30,
              step: 1,
              style: SliderStyle.OutSet
            })
              .width('100%')
              .enabled(this.canControlDevice(device))
              .sliderInteractionMode(SliderInteraction.SLIDE_AND_CLICK)
              .selectedColor('#1769C2')
              .onChange((value: number, mode: SliderChangeMode) => {
                if (this.shouldCommitSlider(mode)) {
                  this.deviceManager.setAcTemperature(device, value);
                }
              })
          }
          .width('100%')
          .padding(16)
          .borderRadius(20)
          .backgroundColor('#F7FBFF')
          .margin({ bottom: 10 })
        }, (device: AirConditionerDevice) => device.id + ':' + device.stateVersion.toString())
      }
    }
    .width('100%')
  }

  @Builder
  HumidityMetricContent() {
    Column() {
      Text('当前湿度 ' + this.averageHumidity())
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor('#14263A')
        .width('100%')
      ForEach(this.scopedEnvironmentDevices(), (device: EnvironmentDevice) => {
        Text(device.name + ' · ' + device.state.humidityPercent.toFixed(0) + '%')
          .fontSize(13)
          .fontColor('#748294')
          .width('100%')
          .margin({ top: 8 })
      }, (device: EnvironmentDevice) => device.id + ':' + device.stateVersion.toString())
      this.HumidityDeviceControls()
    }
    .width('100%')
  }

  @Builder
  HumidityDeviceControls() {
    Column() {
      Text('除湿空调')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor('#14263A')
        .width('100%')
        .margin({ top: 22, bottom: 12 })
      if (this.scopedAirConditioners().length === 0) {
        this.SheetEmptyState('当前范围暂无可用空调')
      } else {
        ForEach(this.scopedAirConditioners(), (device: AirConditionerDevice) => {
          Row() {
            Text('❄')
              .fontSize(23)
              .fontColor('#1769C2')
              .width(46)
              .height(46)
              .lineHeight(46)
              .textAlign(TextAlign.Center)
              .backgroundColor('#EAF4FF')
              .borderRadius(15)
            Column() {
              Text(device.name)
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor('#14263A')
              Text(this.isDehumidifying(device) ? '除湿中' : '关闭')
                .fontSize(12)
                .fontColor('#748294')
                .margin({ top: 4 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            .margin({ left: 12 })
            Toggle({ type: ToggleType.Switch, isOn: this.isDehumidifying(device) })
              .enabled(this.canControlDevice(device))
              .opacity(this.canControlDevice(device) ? 1 : 0.45)
              .selectedColor('#1769C2')
              .onChange((isOn: boolean) => {
                this.deviceManager.setAcDehumidify(device, isOn);
              })
          }
          .width('100%')
          .padding(14)
          .borderRadius(20)
          .backgroundColor('#F7FBFF')
          .margin({ bottom: 10 })
          .alignItems(VerticalAlign.Center)
        }, (device: AirConditionerDevice) => device.id + ':' + device.stateVersion.toString())
      }

      Text('加湿器')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor('#14263A')
        .width('100%')
        .margin({ top: 12, bottom: 12 })
      if (this.scopedHumidifiers().length === 0) {
        this.SheetEmptyState('当前范围暂无可用加湿器')
      } else {
        ForEach(this.scopedHumidifiers(), (device: GenericDevice) => {
          Row() {
            Text('≈')
              .fontSize(28)
              .fontWeight(FontWeight.Bold)
              .fontColor('#0F8F66')
              .width(46)
              .height(46)
              .lineHeight(43)
              .textAlign(TextAlign.Center)
              .backgroundColor('#E8F8F3')
              .borderRadius(15)
            Column() {
              Text(device.name)
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor('#14263A')
              Text('目标湿度 ' + this.humidifierTarget(device).toFixed(0) + '%')
                .fontSize(12)
                .fontColor('#748294')
                .margin({ top: 4 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            .margin({ left: 12 })
            Toggle({ type: ToggleType.Switch, isOn: this.genericPower(device) })
              .enabled(this.canControlDevice(device))
              .opacity(this.canControlDevice(device) ? 1 : 0.45)
              .selectedColor('#0F8F66')
              .onChange((isOn: boolean) => {
                this.setGenericPower(device, isOn);
              })
          }
          .width('100%')
          .padding(14)
          .borderRadius(20)
          .backgroundColor('#F7FBFF')
          .margin({ bottom: 10 })
          .alignItems(VerticalAlign.Center)
        }, (device: GenericDevice) => device.id + ':' + device.stateVersion.toString())
      }
    }
    .width('100%')
  }

  @Builder
  OnlineMetricContent() {
    Column() {
      Text(this.onlineDeviceCount().toString() + ' 台设备在线')
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor('#14263A')
        .width('100%')
        .margin({ bottom: 16 })
      if (this.onlineDevices().length === 0) {
        this.SheetEmptyState('当前范围没有在线设备')
      } else {
        ForEach(this.onlineDevices(), (device: DeviceInfo) => {
          Row() {
            this.DeviceIconBadge(device, 46)
            Column() {
              Text(device.name)
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor('#14263A')
              Text(this.deviceSummary(device))
                .fontSize(12)
                .fontColor('#748294')
                .margin({ top: 4 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            .margin({ left: 12 })
            Text('在线')
              .fontSize(12)
              .fontColor('#0F8F66')
          }
          .width('100%')
          .padding(14)
          .borderRadius(20)
          .backgroundColor('#F7FBFF')
          .margin({ bottom: 10 })
          .alignItems(VerticalAlign.Center)
        }, (device: DeviceInfo) => device.id + ':' + device.stateVersion.toString())
      }
    }
    .width('100%')
  }

  @Builder
  SheetEmptyState(message: string) {
    Text(message)
      .fontSize(14)
      .fontColor('#748294')
      .width('100%')
      .padding(20)
      .textAlign(TextAlign.Center)
      .borderRadius(20)
      .backgroundColor('#F7FBFF')
  }

  @Builder
  RoomSegments() {
    Scroll(this.roomSegmentsScroller) {
      Row() {
        this.RoomButton('all', '全屋')
        ForEach(this.displayRoomIds(), (roomId: string) => {
          this.RoomButton(roomId, this.roomLabel(roomId))
        }, (roomId: string) => roomId)
      }
    }
    .width('100%')
    .height(48)
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .margin({ bottom: 14 })
  }

  @Builder
  RoomButton(roomId: string, label: string) {
    Column() {
      Text(label)
        .fontSize(16)
        .fontWeight(this.selectedRoom === roomId ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(this.selectedRoom === roomId ? '#14263A' : '#8A98A8')
        .textAlign(TextAlign.Center)
      Text('')
        .width(this.selectedRoom === roomId ? 30 : 0)
        .height(3)
        .backgroundColor('#1769C2')
        .borderRadius(2)
        .margin({ top: 7 })
    }
      .width(78)
      .height(44)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .onClick(() => {
        this.selectedRoom = roomId;
      })
  }

  @Builder
  SceneCard() {
    Row() {
      Column() {
        Text('快捷场景')
          .fontSize(19)
          .fontWeight(FontWeight.Bold)
          .fontColor('#14263A')
        Text('一键切换回家和离家状态')
          .fontSize(13)
          .fontColor('#748294')
          .margin({ top: 6, bottom: 14 })
        Row() {
          Button('回家')
            .height(40)
            .layoutWeight(1)
            .borderRadius(20)
            .backgroundColor('#1769C2')
            .onClick(() => {
              this.deviceManager.executeHomeScene();
            })
          Button('离家')
            .height(40)
            .layoutWeight(1)
            .fontColor('#1769C2')
            .borderRadius(20)
            .backgroundColor('#EAF4FF')
            .margin({ left: 10 })
            .onClick(() => {
              this.deviceManager.executeAwayScene();
            })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Text('↯')
        .fontSize(34)
        .fontColor('#1769C2')
        .width(64)
        .height(64)
        .textAlign(TextAlign.Center)
        .backgroundColor('#F4F8FF')
        .borderRadius(24)
        .margin({ left: 12 })
    }
    .width('100%')
    .padding(18)
    .backgroundColor(Color.White)
    .borderRadius(24)
    .margin({ bottom: 18 })
  }

  @Builder
  FeatureSection() {
    Column() {
      this.SectionTitle('功能分类')
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
        ForEach(DeviceRegistry.getHomeFeatures(this.deviceManager.devices), (feature: DeviceFeature) => {
          this.FeatureCard(feature)
        }, (feature: DeviceFeature) => feature.id)
      }
      .width('100%')
    }
    .width('100%')
    .margin({ bottom: 6 })
  }


  @Builder
  FeatureCard(feature: DeviceFeature) {
    Column() {
      Text(feature.title)
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor('#14263A')
        .width('100%')
      Text(this.featureSummary(feature))
        .fontSize(10)
        .fontColor('#748294')
        .width('100%')
        .margin({ top: 4 })
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Blank()
      Row() {
        Stack({ alignContent: Alignment.Center }) {
          if (feature.id === 'locks') {
            LockIcon({ locked: true, iconSize: 26 })
          } else if (feature.id === 'curtains') {
            CurtainIcon({ iconSize: 32 })
          } else {
            Text(feature.icon)
              .fontSize(34)
              .width(54)
              .height(54)
              .lineHeight(54)
              .textAlign(TextAlign.Center)
          }
        }
        .id('feature-icon-' + feature.id)
        .width(54)
        .height(54)
        .backgroundColor(this.featureTint(feature.id))
        .borderRadius(18)
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
    }
    .width('31.8%')
    .height(118)
    .padding(12)
    .margin({ bottom: 12 })
    .borderRadius(22)
    .backgroundColor('#F7FBFF')
    .onClick(() => {
      this.openFeature(feature.id);
    })
  }

  @Builder
  DeviceSectionTitle() {
    Row() {
      Column() {
        Text(this.deviceSectionTitle())
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#14263A')
      }
      .alignItems(HorizontalAlign.Start)
      Blank()
    }
    .width('100%')
    .margin({ bottom: 12 })
  }

  @Builder
  DeviceRow(device: DeviceInfo) {
    Row() {
      this.DeviceIconBadge(device, 50)
      Column() {
        Text(device.name)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor('#14263A')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.deviceSummary(device))
          .fontSize(12)
          .fontColor(device.online ? '#748294' : '#D64545')
          .margin({ top: 5 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 12 })
      Text(device.online ? '在线' : '离线')
        .fontSize(11)
        .fontColor(device.online ? '#0F8F66' : '#D64545')
        .padding({ left: 10, right: 10, top: 5, bottom: 5 })
        .backgroundColor(device.online ? '#EAF8F1' : '#FFF1F1')
        .borderRadius(12)
    }
    .width('100%')
    .padding(14)
    .margin({ bottom: 10 })
    .borderRadius(24)
    .backgroundColor('#F7FBFF')
    .onClick(() => {
      router.pushUrl({
        url: 'pages/DeviceDetail',
        params: { deviceId: device.id }
      });
    })
  }

  @Builder
  DeviceIconBadge(device: DeviceInfo, badgeSize: number) {
    Stack({ alignContent: Alignment.Center }) {
      if (device.type === DeviceType.DOOR_LOCK) {
        LockIcon({ locked: (device as DoorLockDevice).state.locked, iconSize: badgeSize - 20 })
      } else if (this.isCurtainDevice(device)) {
        CurtainIcon({ iconSize: badgeSize - 18 })
      } else {
        Text(this.deviceIcon(device))
          .fontSize(badgeSize - 27)
          .width(badgeSize)
          .height(badgeSize)
          .lineHeight(badgeSize)
          .textAlign(TextAlign.Center)
      }
    }
    .width(badgeSize)
    .height(badgeSize)
    .backgroundColor(this.deviceTint(device))
    .borderRadius(badgeSize === 46 ? 16 : 18)
  }

  @Builder
  SectionTitle(title: string) {
    Row() {
      Column() {
        Text(title)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#14263A')
      }
      .alignItems(HorizontalAlign.Start)
      Blank()
    }
    .width('100%')
    .margin({ bottom: 12 })
  }

  private openFeature(featureId: string): void {
    router.pushUrl({
      url: 'pages/FeatureDevices',
      params: { featureId: featureId }
    });
  }

  private visibleDevices(): DeviceInfo[] {
    return this.devicesForSelectedRoom();
  }

  private scopedDevices(): DeviceInfo[] {
    return this.devicesForSelectedRoom();
  }

  private devicesForSelectedRoom(): DeviceInfo[] {
    const result: DeviceInfo[] = [];
    const devices = this.deviceManager.devices;
    for (let index = 0; index < devices.length; index++) {
      if (this.selectedRoom === 'all' || devices[index].roomId === this.selectedRoom) {
        result.push(devices[index]);
      }
    }
    return result;
  }

  private scopedEnvironmentDevices(): EnvironmentDevice[] {
    const result: EnvironmentDevice[] = [];
    const devices = this.scopedDevices();
    for (let index = 0; index < devices.length; index++) {
      if (devices[index].type === DeviceType.ENVIRONMENT) {
        result.push(devices[index] as EnvironmentDevice);
      }
    }
    return result;
  }

  private scopedAirConditioners(): AirConditionerDevice[] {
    const result: AirConditionerDevice[] = [];
    const devices = this.scopedDevices();
    for (let index = 0; index < devices.length; index++) {
      if (devices[index].type === DeviceType.AIR_CONDITIONER) {
        result.push(devices[index] as AirConditionerDevice);
      }
    }
    return result;
  }

  private scopedHumidifiers(): GenericDevice[] {
    const result: GenericDevice[] = [];
    const devices = this.scopedDevices();
    for (let index = 0; index < devices.length; index++) {
      if (devices[index].type === 'humidifier') {
        result.push(devices[index] as GenericDevice);
      }
    }
    return result;
  }

  private isDehumidifying(device: AirConditionerDevice): boolean {
    return device.state.power && device.state.mode === ACMode.DRY;
  }

  private genericPower(device: GenericDevice): boolean {
    const value = device.state['power'];
    return typeof value === 'boolean' && value;
  }

  private humidifierTarget(device: GenericDevice): number {
    const value = device.state['targetHumidityPercent'];
    return typeof value === 'number' ? value : 55;
  }

  private setGenericPower(device: GenericDevice, power: boolean): void {
    const payload: CommandPayload = {};
    payload['power'] = power;
    this.deviceManager.executeDeviceAction(device, 'setPower', payload);
  }

  private activeLights(): LightDevice[] {
    const result: LightDevice[] = [];
    const devices = this.scopedDevices();
    for (let index = 0; index < devices.length; index++) {
      if (devices[index].type === DeviceType.LIGHT) {
        const light = devices[index] as LightDevice;
        if (light.state.power) {
          result.push(light);
        }
      }
    }
    return result;
  }

  private onlineDevices(): DeviceInfo[] {
    const result: DeviceInfo[] = [];
    const devices = this.scopedDevices();
    for (let index = 0; index < devices.length; index++) {
      if (devices[index].online) {
        result.push(devices[index]);
      }
    }
    return result;
  }

  private onlineDeviceCount(): number {
    return this.onlineDevices().length;
  }

  private deviceSectionTitle(): string {
    if (this.selectedRoom === 'all') {
      return '全屋设备';
    }
    return this.roomLabel(this.selectedRoom) + '设备';
  }

  private temperatureLabel(): string {
    return this.selectedRoom === 'all' ? '均温' : '室温';
  }

  private humidityLabel(): string {
    return this.selectedRoom === 'all' ? '均湿' : '湿度';
  }

  private openMetricSheet(metric: string): void {
    this.activeMetric = metric;
    this.showMetricSheet = true;
  }

  private metricSheetTitle(): string {
    if (this.activeMetric === 'temperature') {
      return '室温控制';
    }
    if (this.activeMetric === 'humidity') {
      return '湿度管理';
    }
    if (this.activeMetric === 'lights') {
      return '亮灯管理';
    }
    return '在线设备';
  }

  private metricSheetSubtitle(): string {
    return this.selectedRoom === 'all' ? '全屋范围' : this.roomLabel(this.selectedRoom);
  }

  private canControlDevice(device: DeviceInfo): boolean {
    return this.deviceManager.isOnline() && device.online &&
      !this.deviceManager.isDevicePending(device.id);
  }

  private shouldCommitSlider(mode: SliderChangeMode): boolean {
    return mode === SliderChangeMode.End || mode === SliderChangeMode.Click;
  }

  private availableRoomIds(): string[] {
    const allRoomIds = this.deviceManager.getRoomIds();
    const result: string[] = [];
    for (let index = 0; index < allRoomIds.length; index++) {
      if (this.deviceManager.getDevicesByRoom(allRoomIds[index]).length > 0) {
        result.push(allRoomIds[index]);
      }
    }
    return result;
  }

  private displayRoomIds(): string[] {
    const rooms = this.deviceManager.getSelectableRooms();
    const result: string[] = [];
    for (let index = 0; index < rooms.length; index++) {
      result.push(rooms[index].id);
    }
    return result;
  }

  private roomLabel(roomId: string): string {
    return this.deviceManager.getRoomName(roomId);
  }

  private featureTint(featureId: string): string {
    if (featureId === 'lighting') {
      return '#FFF4D8';
    }
    if (featureId === 'environment') {
      return '#E8F8F3';
    }
    if (featureId === 'locks') {
      return '#EEF1FF';
    }
    if (featureId === 'curtains') {
      return '#EAF4FF';
    }
    return '#F2F5F9';
  }

  private featureSummary(feature: DeviceFeature): string {
    const devices = DeviceRegistry.getDevicesByFeature(this.deviceManager.devices, feature.id);
    if (feature.id === 'lighting') {
      return this.lightsOnCount().toString() + ' 盏开启 · 共 ' + devices.length.toString() + ' 盏';
    }
    if (feature.id === 'locks') {
      return devices.length.toString() + ' 把门锁 · 家庭安全入口';
    }
    if (feature.id === 'environment') {
      return devices.length.toString() + ' 台设备 · 温湿度与空调';
    }
    return devices.length.toString() + ' 台设备 · ' + feature.title;
  }

  private deviceIcon(device: DeviceInfo): string {
    if (device.type === DeviceType.LIGHT) {
      return '○';
    }
    if (device.type === DeviceType.ENVIRONMENT) {
      return '≈';
    }
    if (device.type === DeviceType.AIR_CONDITIONER) {
      return '❄';
    }
    if (this.isCurtainDevice(device)) {
      return '';
    }
    if (DeviceRegistry.getCapability(device.type) === null) {
      return (device as GenericDevice).category.icon;
    }
    const doorLock = device as DoorLockDevice;
    return doorLock.state.locked ? '🔒' : '🔓';
  }

  private deviceTint(device: DeviceInfo): string {
    if (device.type === DeviceType.LIGHT) {
      return '#FFF4D8';
    }
    if (device.type === DeviceType.ENVIRONMENT) {
      return '#E8F8F3';
    }
    if (device.type === DeviceType.AIR_CONDITIONER) {
      return '#EAF4FF';
    }
    if (this.isCurtainDevice(device)) {
      return '#EAF4FF';
    }
    if (DeviceRegistry.getCapability(device.type) === null) {
      return (device as GenericDevice).category.id === 'environment' ?
        '#E8F8F3' : '#F2F5F9';
    }
    return '#EEF1FF';
  }

  private isCurtainDevice(device: DeviceInfo): boolean {
    return DeviceRegistry.getCapability(device.type) === null &&
      (device as GenericDevice).category.id === 'curtains';
  }

  private deviceSummary(device: DeviceInfo): string {
    if (!device.online) {
      return '设备离线';
    }
    if (device.type === DeviceType.LIGHT) {
      const light = device as LightDevice;
      return light.state.power ? '开启 · 亮度 ' + light.state.brightness.toFixed(0) + '%' : '关闭';
    }
    if (device.type === DeviceType.ENVIRONMENT) {
      const environment = device as EnvironmentDevice;
      return environment.state.temperatureCelsius.toFixed(1) + '°C · ' +
        environment.state.humidityPercent.toFixed(0) + '% 湿度';
    }
    if (device.type === DeviceType.AIR_CONDITIONER) {
      const airConditioner = device as AirConditionerDevice;
      return airConditioner.state.power ?
        this.modeLabel(airConditioner.state.mode) + ' · ' +
          airConditioner.state.targetTemperatureCelsius.toFixed(0) + '°C' : '关闭';
    }
    if (DeviceRegistry.getCapability(device.type) === null) {
      return DeviceRegistry.present(device).summary;
    }
    const doorLock = device as DoorLockDevice;
    if (doorLock.state.jammed) {
      return '锁体异常';
    }
    return doorLock.state.locked ? '已上锁' : '已解锁';
  }

  private modeLabel(mode: string): string {
    if (mode === 'cool') {
      return '制冷';
    }
    if (mode === 'heat') {
      return '制热';
    }
    if (mode === 'dry') {
      return '除湿';
    }
    if (mode === 'fan') {
      return '送风';
    }
    return '自动';
  }

  private headerSubtitle(): string {
    return '全屋设备已连接 · ' + this.deviceManager.getConnectionLabel();
  }

  private averageTemperature(): string {
    const sensors = this.scopedEnvironmentDevices();
    if (sensors.length === 0) {
      return '--';
    }
    let total = 0;
    for (let index = 0; index < sensors.length; index++) {
      total += sensors[index].state.temperatureCelsius;
    }
    return (total / sensors.length).toFixed(1) + '°';
  }

  private averageHumidity(): string {
    const sensors = this.scopedEnvironmentDevices();
    if (sensors.length === 0) {
      return '--';
    }
    let total = 0;
    for (let index = 0; index < sensors.length; index++) {
      total += sensors[index].state.humidityPercent;
    }
    return (total / sensors.length).toFixed(0) + '%';
  }

  private lightsOnCount(): number {
    let count = 0;
    const devices = this.scopedDevices();
    for (let index = 0; index < devices.length; index++) {
      if (devices[index].type === DeviceType.LIGHT) {
        const light = devices[index] as LightDevice;
        if (light.state.power) {
          count++;
        }
      }
    }
    return count;
  }

}
