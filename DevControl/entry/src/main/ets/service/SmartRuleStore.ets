import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { SceneDeviceAction } from '../model/DeviceModel';

const PREFERENCES_NAME = 'devcontrol_smart_rules';
const SMART_RULES_KEY = 'savedRules';
const MAX_TEXT_LENGTH = 120;
const MAX_AUTOMATIONS = 24;
const MAX_QUICK_SCENES = 8;
const MAX_SCENE_ACTIONS = 64;

export class SavedAutomationRule {
  id: string = '';
  kind: string = '';
  title: string = '';
  templateId: string = '';
  conditionId: string = '';
  actionId: string = '';
  condition: string = '';
  action: string = '';
  enabled: boolean = true;
}

export class SavedQuickScene {
  id: string = '';
  name: string = '';
  builtIn: boolean = false;
  customized: boolean = false;
  actions: SceneDeviceAction[] = [];
}

/**
 * The small rule library displayed in the Smart tab. Rules are intentionally
 * stored separately from the gateway session: they contain no credentials and
 * remain available after the app restarts or reconnects to the same gateway.
 */
export class SavedSmartRules {
  // Kept for reading installations saved by versions that supported only one
  // recommended rule and one custom rule. New saves use `automations`.
  templateId: string = '';
  templateTitle: string = '';
  templateEnabled: boolean = true;
  customTitle: string = '';
  customConditionId: string = '';
  customActionId: string = '';
  customCondition: string = '';
  customAction: string = '';
  customEnabled: boolean = true;
  automations: SavedAutomationRule[] = [];
  activeQuickSceneId: string = 'home';
  quickScenes: SavedQuickScene[] = [];
}

export class SmartRuleStore {
  private context: common.UIAbilityContext;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  async restore(): Promise<SavedSmartRules> {
    const store = await preferences.getPreferences(this.context, PREFERENCES_NAME);
    const text = await store.get(SMART_RULES_KEY, '') as string;
    if (text.length === 0) {
      return new SavedSmartRules();
    }
    try {
      const raw = JSON.parse(text) as Record<string, Object>;
      return this.parse(raw);
    } catch (error) {
      // A malformed local preference must not prevent the Smart page from
      // loading. The next successful save replaces the invalid value.
      return new SavedSmartRules();
    }
  }

  async save(rules: SavedSmartRules): Promise<void> {
    const store = await preferences.getPreferences(this.context, PREFERENCES_NAME);
    await store.put(SMART_RULES_KEY, JSON.stringify(rules));
    await store.flush();
  }

  private parse(raw: Record<string, Object>): SavedSmartRules {
    const rules = new SavedSmartRules();
    rules.templateId = this.text(raw['templateId']);
    rules.templateTitle = this.text(raw['templateTitle']);
    rules.templateEnabled = this.boolean(raw['templateEnabled'], true);
    rules.customTitle = this.text(raw['customTitle']);
    rules.customConditionId = this.text(raw['customConditionId']);
    rules.customActionId = this.text(raw['customActionId']);
    rules.customCondition = this.text(raw['customCondition']);
    rules.customAction = this.text(raw['customAction']);
    rules.customEnabled = this.boolean(raw['customEnabled'], true);
    rules.automations = this.automations(raw['automations']);
    if (rules.automations.length === 0) {
      rules.automations = this.legacyAutomations(rules);
    }
    rules.activeQuickSceneId = this.quickSceneMode(raw['activeQuickSceneId']);
    rules.quickScenes = this.scenes(raw['quickScenes']);
    return rules;
  }

  private quickSceneMode(value: Object | undefined): string {
    return value === 'away' ? 'away' : 'home';
  }

  private automations(value: Object | undefined): SavedAutomationRule[] {
    if (!Array.isArray(value)) {
      return [];
    }
    const rawRules = value as object[];
    const rules: SavedAutomationRule[] = [];
    for (let index = 0; index < rawRules.length && rules.length < MAX_AUTOMATIONS; index++) {
      const item = rawRules[index];
      if (typeof item !== 'object' || item === null || Array.isArray(item)) {
        continue;
      }
      const raw = item as Record<string, Object>;
      const kind = this.text(raw['kind']);
      const id = this.text(raw['id']);
      const title = this.text(raw['title']);
      if ((kind !== 'template' && kind !== 'custom') || id.length === 0 || title.length === 0) {
        continue;
      }
      const rule = new SavedAutomationRule();
      rule.id = id;
      rule.kind = kind;
      rule.title = title;
      rule.templateId = this.text(raw['templateId']);
      rule.conditionId = this.text(raw['conditionId']);
      rule.actionId = this.text(raw['actionId']);
      rule.condition = this.text(raw['condition']);
      rule.action = this.text(raw['action']);
      rule.enabled = this.boolean(raw['enabled'], true);
      if (
        (rule.kind === 'template' && rule.templateId.length === 0) ||
        (rule.kind === 'custom' && (rule.conditionId.length === 0 || rule.actionId.length === 0))
      ) {
        continue;
      }
      rules.push(rule);
    }
    return rules;
  }

  private legacyAutomations(legacy: SavedSmartRules): SavedAutomationRule[] {
    const rules: SavedAutomationRule[] = [];
    if (legacy.templateId.length > 0 && legacy.templateTitle.length > 0) {
      const template = new SavedAutomationRule();
      template.id = 'legacy-template';
      template.kind = 'template';
      template.title = legacy.templateTitle;
      template.templateId = legacy.templateId;
      template.enabled = legacy.templateEnabled;
      rules.push(template);
    }
    if (
      legacy.customTitle.length > 0 &&
      legacy.customConditionId.length > 0 &&
      legacy.customActionId.length > 0
    ) {
      const custom = new SavedAutomationRule();
      custom.id = 'legacy-custom';
      custom.kind = 'custom';
      custom.title = legacy.customTitle;
      custom.conditionId = legacy.customConditionId;
      custom.actionId = legacy.customActionId;
      custom.condition = legacy.customCondition;
      custom.action = legacy.customAction;
      custom.enabled = legacy.customEnabled;
      rules.push(custom);
    }
    return rules;
  }

  private scenes(value: Object | undefined): SavedQuickScene[] {
    if (!Array.isArray(value)) {
      return [];
    }
    const rawScenes = value as object[];
    const scenes: SavedQuickScene[] = [];
    for (let index = 0; index < rawScenes.length && scenes.length < MAX_QUICK_SCENES; index++) {
      const item = rawScenes[index];
      if (typeof item !== 'object' || item === null || Array.isArray(item)) {
        continue;
      }
      const raw = item as Record<string, Object>;
      const id = this.text(raw['id']);
      const name = this.text(raw['name']);
      if (id.length === 0 || name.length === 0) {
        continue;
      }
      const scene = new SavedQuickScene();
      scene.id = id;
      scene.name = name;
      scene.builtIn = this.boolean(raw['builtIn'], false);
      scene.customized = this.boolean(raw['customized'], false);
      scene.actions = this.actions(raw['actions']);
      scenes.push(scene);
    }
    return scenes;
  }

  private actions(value: Object | undefined): SceneDeviceAction[] {
    if (!Array.isArray(value)) {
      return [];
    }
    const rawActions = value as object[];
    const actions: SceneDeviceAction[] = [];
    for (let index = 0; index < rawActions.length && actions.length < MAX_SCENE_ACTIONS; index++) {
      const item = rawActions[index];
      if (typeof item !== 'object' || item === null || Array.isArray(item)) {
        continue;
      }
      const raw = item as Record<string, Object>;
      const deviceId = this.text(raw['deviceId']);
      const operation = raw['operation'];
      if (
        deviceId.length === 0 ||
        (operation !== 'keep' && operation !== 'on' && operation !== 'off')
      ) {
        continue;
      }
      const action = new SceneDeviceAction();
      action.deviceId = deviceId;
      action.operation = operation as string;
      actions.push(action);
    }
    return actions;
  }

  private text(value: Object | undefined): string {
    if (typeof value !== 'string' || value.length > MAX_TEXT_LENGTH) {
      return '';
    }
    return value;
  }

  private boolean(value: Object | undefined, fallback: boolean): boolean {
    return typeof value === 'boolean' ? value : fallback;
  }
}
