import { common } from '@kit.AbilityKit';
import { ControlCenterTab } from '../components/ControlCenterTab';
import { PairingPage } from '../components/PairingPage';
import { SettingsTab } from '../components/SettingsTab';
import { DeviceApplication } from '../model/DeviceApplication';
import { DeviceManager } from '../model/DeviceManager';
import { SceneExecutionDetail } from '../model/DeviceModel';

@Entry
@Component
struct Index {
  @Provide deviceManager: DeviceManager = DeviceApplication.getDeviceManager();
  @State currentTab: string = 'home';

  aboutToAppear(): void {
    const context = getContext(this) as common.UIAbilityContext;
    this.deviceManager.initialize(context);
  }

  onPageShow(): void {
    if (
      this.deviceManager.initialized &&
      !this.deviceManager.pairingRequired &&
      !this.deviceManager.isOnline()
    ) {
      this.deviceManager.reconnect();
    }
  }

  build() {
    Column() {
      if (this.deviceManager.pairingRequired) {
        PairingPage()
      } else {
        Column() {
          if (this.currentTab === 'home') {
            ControlCenterTab()
          } else if (this.currentTab === 'smart') {
            this.SmartTab()
          } else {
            SettingsTab()
          }
        }
        .width('100%')
        .layoutWeight(1)
        this.BottomTabBar()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#DCEAF2')
  }

  @Builder
  BottomTabBar() {
    Row() {
      this.TabButton('home', '⌂', '家')
      this.TabButton('smart', '↯', '智能')
      this.TabButton('settings', '○', '设置')
    }
    .width('100%')
    .height(72)
    .padding({ left: 28, right: 28, top: 8, bottom: 8 })
    .justifyContent(FlexAlign.SpaceBetween)
    .backgroundColor(Color.White)
  }

  @Builder
  TabButton(tab: string, icon: string, label: string) {
    Column() {
      Text(icon)
        .fontSize(27)
        .fontWeight(FontWeight.Bold)
        .fontColor(tab === this.currentTab ? '#1769C2' : '#6F8094')
        .opacity(1)
      Text(label)
        .fontSize(12)
        .fontWeight(tab === this.currentTab ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(tab === this.currentTab ? '#1769C2' : '#6F8094')
        .opacity(1)
        .margin({ top: 2 })
    }
    .width(78)
    .height(60)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(Color.Transparent)
    .borderRadius(22)
    .onClick(() => {
      this.currentTab = tab;
    })
  }

  @Builder
  SmartTab() {
    Scroll() {
      Column() {
        Row() {
          Column() {
            Text('智能')
              .fontSize(30)
              .fontWeight(FontWeight.Bold)
              .fontColor('#14263A')
            Text('把常用场景和自动化放在这里')
              .fontSize(13)
              .fontColor('#748294')
              .margin({ top: 6 })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')
        .margin({ bottom: 18 })

        this.ScenePanel()
        this.AutomationPanel()
        this.SceneResultPanel()
      }
      .width('100%')
      .padding({ left: 18, right: 18, top: 42, bottom: 24 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#DCEAF2')
    .scrollBar(BarState.Off)
  }

  @Builder
  ScenePanel() {
    Column() {
      Text('快捷场景')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor('#14263A')
        .width('100%')
      Text('适合演示设备联动：回家恢复状态，离家关闭灯光和空调并锁门。')
        .fontSize(13)
        .fontColor('#748294')
        .width('100%')
        .margin({ top: 6, bottom: 16 })
      Row() {
        this.SceneButton('回家', '恢复家庭状态', '#1769C2', Color.White, true)
        this.SceneButton('离家', '关灯、关空调、锁门', '#EAF4FF', '#1769C2', false)
      }
      .width('100%')
    }
    .width('100%')
    .padding(18)
    .borderRadius(24)
    .backgroundColor(Color.White)
    .margin({ bottom: 14 })
  }

  @Builder
  SceneButton(title: string, subtitle: string, bg: string, fg: ResourceColor, home: boolean) {
    Column() {
      Text(title)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(fg)
      Text(subtitle)
        .fontSize(11)
        .fontColor(fg)
        .opacity(0.75)
        .margin({ top: 5 })
    }
    .layoutWeight(1)
    .height(94)
    .padding(14)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(bg)
    .borderRadius(22)
    .margin({ right: home ? 10 : 0 })
    .onClick(() => {
      if (home) {
        this.deviceManager.executeHomeScene();
      } else {
        this.deviceManager.executeAwayScene();
      }
    })
  }

  @Builder
  AutomationPanel() {
    Column() {
      Text('自动化')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor('#14263A')
        .width('100%')
      this.AutomationRow('照明自动化', '有人且光线较暗时开灯，无人一段时间后关灯')
      this.AutomationRow('空调模拟', '温湿度会随空调模式逐步变化')
      this.AutomationRow('门锁保护', '解锁需要二次确认，并支持自动上锁')
    }
    .width('100%')
    .padding(18)
    .borderRadius(24)
    .backgroundColor(Color.White)
    .margin({ bottom: 14 })
  }

  @Builder
  AutomationRow(title: string, subtitle: string) {
    Row() {
      Text('·')
        .fontSize(28)
        .fontColor('#1769C2')
        .width(24)
      Column() {
        Text(title)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor('#14263A')
        Text(subtitle)
          .fontSize(12)
          .fontColor('#748294')
          .margin({ top: 4 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .margin({ top: 14 })
  }

  @Builder
  SceneResultPanel() {
    Column() {
      Text('最近场景结果')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor('#14263A')
        .width('100%')
      if (this.deviceManager.sceneResults.length === 0) {
        Text('执行回家或离家后，这里会显示每个设备的结果。')
          .fontSize(13)
          .fontColor('#748294')
          .width('100%')
          .margin({ top: 8 })
      } else {
        ForEach(this.deviceManager.sceneResults, (item: SceneExecutionDetail) => {
          Row() {
            Text(item.deviceId)
              .fontSize(12)
              .fontColor('#748294')
              .layoutWeight(1)
            Text(item.success ? '成功' : item.errorCode)
              .fontSize(12)
              .fontColor(item.success ? '#0F8F66' : '#D64545')
          }
          .width('100%')
          .margin({ top: 10 })
        }, (item: SceneExecutionDetail) => item.deviceId)
      }
    }
    .width('100%')
    .padding(18)
    .borderRadius(24)
    .backgroundColor(Color.White)
  }
}
