import abilityDelegatorRegistry from '@ohos.app.ability.abilityDelegatorRegistry';
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { describe, expect, it } from '@ohos/hypium';
import { SceneDeviceAction } from '../../../main/ets/model/DeviceModel';
import {
  SavedAutomationRule,
  SavedQuickScene,
  SavedSmartRules,
  SmartRuleStore
} from '../../../main/ets/service/SmartRuleStore';

const PREFERENCES_NAME = 'devcontrol_smart_rules';
const SMART_RULES_KEY = 'savedRules';

function sampleRules(): SavedSmartRules {
  const rules = new SavedSmartRules();
  rules.templateId = 'cooling';
  rules.templateTitle = '空调自动制冷模式';
  rules.templateEnabled = false;
  rules.customTitle = '晚间自动化';
  rules.customConditionId = 'motionDark';
  rules.customActionId = 'livingLight';
  rules.customCondition = '有人且较暗';
  rules.customAction = '打开灯光';
  rules.customEnabled = true;

  const firstRule = new SavedAutomationRule();
  firstRule.id = 'template-cooling';
  firstRule.kind = 'template';
  firstRule.title = '制冷自动化';
  firstRule.templateId = 'cooling';
  firstRule.enabled = false;
  rules.automations.push(firstRule);

  const secondRule = new SavedAutomationRule();
  secondRule.id = 'custom-evening';
  secondRule.kind = 'custom';
  secondRule.title = '晚间自动化';
  secondRule.conditionId = 'motionDark';
  secondRule.actionId = 'livingLight';
  secondRule.condition = '有人且较暗';
  secondRule.action = '打开灯光';
  secondRule.enabled = true;
  rules.automations.push(secondRule);
  rules.activeQuickSceneId = 'away';

  const scene = new SavedQuickScene();
  scene.id = 'custom-evening';
  scene.name = '睡前模式';
  scene.customized = true;
  const lightAction = new SceneDeviceAction();
  lightAction.deviceId = 'light-living-01';
  lightAction.operation = 'off';
  scene.actions.push(lightAction);
  const lockAction = new SceneDeviceAction();
  lockAction.deviceId = 'door-entry-01';
  lockAction.operation = 'off';
  scene.actions.push(lockAction);
  rules.quickScenes.push(scene);
  return rules;
}

export default function smartRuleStoreTest() {
  describe('SmartRuleStoreTest', () => {
    it('persistsRulesAndCustomSceneActions', 0, async () => {
      const context = abilityDelegatorRegistry.getAbilityDelegator()
        .getAppContext() as common.UIAbilityContext;
      const preferencesStore = await preferences.getPreferences(context, PREFERENCES_NAME);
      const previous = await preferencesStore.get(SMART_RULES_KEY, '') as string;
      const store = new SmartRuleStore(context);
      try {
        await store.save(sampleRules());
        const restored = await store.restore();
        expect(restored.templateId).assertEqual('cooling');
        expect(restored.templateEnabled).assertFalse();
        expect(restored.customTitle).assertEqual('晚间自动化');
        expect(restored.automations.length).assertEqual(2);
        expect(restored.automations[0].id).assertEqual('template-cooling');
        expect(restored.automations[0].enabled).assertFalse();
        expect(restored.automations[1].actionId).assertEqual('livingLight');
        expect(restored.activeQuickSceneId).assertEqual('away');
        expect(restored.quickScenes.length).assertEqual(1);
        expect(restored.quickScenes[0].name).assertEqual('睡前模式');
        expect(restored.quickScenes[0].actions.length).assertEqual(2);
        expect(restored.quickScenes[0].actions[0].operation).assertEqual('off');
        expect(restored.quickScenes[0].actions[1].deviceId).assertEqual('door-entry-01');
      } finally {
        if (previous.length > 0) {
          await preferencesStore.put(SMART_RULES_KEY, previous);
        } else {
          await preferencesStore.delete(SMART_RULES_KEY);
        }
        await preferencesStore.flush();
      }
    });
  });
}
