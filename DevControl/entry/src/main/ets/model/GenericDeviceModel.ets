const IDENTIFIER_PATTERN: RegExp = /^[A-Za-z][A-Za-z0-9._-]{0,63}$/;

export class DeviceControlKind {
  static readonly BUTTON: string = 'button';
  static readonly TOGGLE: string = 'toggle';
  static readonly SLIDER: string = 'slider';
  static readonly ENUM: string = 'enum';
}

export class DeviceCategory {
  id: string = '';
  title: string = '';
  icon: string = '';
  homeOnly: boolean = false;
}

export class DeviceControlOption {
  value: string = '';
  label: string = '';
}

export class DeviceControl {
  id: string = '';
  kind: string = '';
  label: string = '';
  action: string = '';
  stateKey: string = '';
  payloadKey: string = '';
  minimum: number = 0;
  maximum: number = 0;
  step: number = 1;
  unit: string = '';
  options: DeviceControlOption[] = [];
  primary: boolean = false;
  requiresConfirmation: boolean = false;
}

export class GenericDevice {
  id: string = '';
  name: string = '';
  roomId: string = '';
  type: string = '';
  online: boolean = false;
  stateVersion: number = 0;
  updatedAt: string = '';
  category: DeviceCategory = new DeviceCategory();
  state: Record<string, Object> = {};
  controls: DeviceControl[] = [];
}

function requireString(
  raw: Record<string, Object>,
  key: string,
  maximumLength: number = 128
): string {
  const value = raw[key];
  if (
    typeof value !== 'string' ||
    value.length === 0 ||
    value.length > maximumLength
  ) {
    throw new Error('Invalid string field: ' + key);
  }
  return value;
}

function requireIdentifier(raw: Record<string, Object>, key: string): string {
  const value = requireString(raw, key, 64);
  if (!IDENTIFIER_PATTERN.test(value)) {
    throw new Error('Invalid identifier field: ' + key);
  }
  return value;
}

function requireBoolean(raw: Record<string, Object>, key: string): boolean {
  const value = raw[key];
  if (typeof value !== 'boolean') {
    throw new Error('Invalid boolean field: ' + key);
  }
  return value;
}

function requireNumber(raw: Record<string, Object>, key: string): number {
  const value = raw[key];
  if (typeof value !== 'number' || !Number.isFinite(value)) {
    throw new Error('Invalid number field: ' + key);
  }
  return value;
}

function requireRecord(
  raw: Record<string, Object>,
  key: string
): Record<string, Object> {
  const value = raw[key];
  if (typeof value !== 'object' || value === null || Array.isArray(value)) {
    throw new Error('Invalid object field: ' + key);
  }
  return value as Record<string, Object>;
}

function optionalBoolean(
  raw: Record<string, Object>,
  key: string,
  fallback: boolean = false
): boolean {
  const value = raw[key];
  if (value === undefined || value === null) {
    return fallback;
  }
  if (typeof value !== 'boolean') {
    throw new Error('Invalid boolean field: ' + key);
  }
  return value;
}

function optionalString(
  raw: Record<string, Object>,
  key: string,
  maximumLength: number
): string {
  const value = raw[key];
  if (value === undefined || value === null) {
    return '';
  }
  if (typeof value !== 'string' || value.length > maximumLength) {
    throw new Error('Invalid string field: ' + key);
  }
  return value;
}

function parseCategory(raw: Record<string, Object>): DeviceCategory {
  const category = new DeviceCategory();
  category.id = requireIdentifier(raw, 'id');
  category.title = requireString(raw, 'title', 32);
  category.icon = requireString(raw, 'icon', 8);
  category.homeOnly = requireBoolean(raw, 'homeOnly');
  return category;
}

function parseOptions(value: Object): DeviceControlOption[] {
  if (!Array.isArray(value) || value.length === 0 || value.length > 20) {
    throw new Error('Invalid enum control options');
  }
  const result: DeviceControlOption[] = [];
  const values: string[] = [];
  for (let index = 0; index < value.length; index++) {
    const raw = value[index] as Record<string, Object>;
    if (typeof raw !== 'object' || raw === null || Array.isArray(raw)) {
      throw new Error('Invalid enum control option');
    }
    const option = new DeviceControlOption();
    option.value = requireString(raw, 'value', 64);
    option.label = requireString(raw, 'label', 32);
    if (values.indexOf(option.value) >= 0) {
      throw new Error('Duplicate enum control option');
    }
    values.push(option.value);
    result.push(option);
  }
  return result;
}

function validateControlState(
  control: DeviceControl,
  state: Record<string, Object>
): void {
  if (control.kind === DeviceControlKind.BUTTON) {
    return;
  }
  if (control.stateKey.length === 0 || control.payloadKey.length === 0) {
    throw new Error('Interactive control is missing state or payload key');
  }
  const value = state[control.stateKey];
  if (value === undefined || value === null) {
    throw new Error('Control state key is missing: ' + control.stateKey);
  }
  if (control.kind === DeviceControlKind.TOGGLE && typeof value !== 'boolean') {
    throw new Error('Toggle state must be boolean');
  }
  if (control.kind === DeviceControlKind.SLIDER) {
    if (
      typeof value !== 'number' ||
      !Number.isFinite(value) ||
      value < control.minimum ||
      value > control.maximum
    ) {
      throw new Error('Slider state is outside its declared range');
    }
  }
  if (control.kind === DeviceControlKind.ENUM) {
    if (typeof value !== 'string') {
      throw new Error('Enum state must be a string');
    }
    let found = false;
    for (let index = 0; index < control.options.length; index++) {
      if (control.options[index].value === value) {
        found = true;
        break;
      }
    }
    if (!found) {
      throw new Error('Enum state is not a declared option');
    }
  }
}

function parseControl(
  raw: Record<string, Object>,
  state: Record<string, Object>
): DeviceControl {
  const control = new DeviceControl();
  control.id = requireIdentifier(raw, 'id');
  control.kind = requireString(raw, 'kind', 16);
  if (
    control.kind !== DeviceControlKind.BUTTON &&
    control.kind !== DeviceControlKind.TOGGLE &&
    control.kind !== DeviceControlKind.SLIDER &&
    control.kind !== DeviceControlKind.ENUM
  ) {
    throw new Error('Unsupported generic control kind: ' + control.kind);
  }
  control.label = requireString(raw, 'label', 32);
  control.action = requireIdentifier(raw, 'action');
  const stateKey = raw['stateKey'];
  const payloadKey = raw['payloadKey'];
  if (stateKey !== undefined && stateKey !== null) {
    control.stateKey = requireIdentifier(raw, 'stateKey');
  }
  if (payloadKey !== undefined && payloadKey !== null) {
    control.payloadKey = requireIdentifier(raw, 'payloadKey');
  }
  control.unit = optionalString(raw, 'unit', 16);
  control.primary = optionalBoolean(raw, 'primary');
  control.requiresConfirmation = optionalBoolean(raw, 'requiresConfirmation');

  if (control.kind === DeviceControlKind.SLIDER) {
    control.minimum = requireNumber(raw, 'minimum');
    control.maximum = requireNumber(raw, 'maximum');
    control.step = requireNumber(raw, 'step');
    if (
      control.minimum >= control.maximum ||
      control.step <= 0 ||
      control.step > control.maximum - control.minimum
    ) {
      throw new Error('Invalid slider range');
    }
  }
  if (control.kind === DeviceControlKind.ENUM) {
    control.options = parseOptions(raw['options']);
  }
  validateControlState(control, state);
  return control;
}

export function parseGenericDevice(
  raw: Record<string, Object>
): GenericDevice {
  const device = new GenericDevice();
  device.id = requireString(raw, 'id');
  device.name = requireString(raw, 'name');
  device.roomId = requireString(raw, 'roomId');
  device.type = requireIdentifier(raw, 'type');
  device.online = requireBoolean(raw, 'online');
  device.stateVersion = requireNumber(raw, 'stateVersion');
  if (
    !Number.isInteger(device.stateVersion) ||
    device.stateVersion < 0
  ) {
    throw new Error('Invalid stateVersion');
  }
  device.updatedAt = requireString(raw, 'updatedAt');
  device.category = parseCategory(requireRecord(raw, 'category'));
  const state = requireRecord(raw, 'state');
  const stateKeys = Object.keys(state);
  if (stateKeys.length > 32) {
    throw new Error('Generic device state has too many fields');
  }
  for (let index = 0; index < stateKeys.length; index++) {
    const stateKey = stateKeys[index];
    if (!IDENTIFIER_PATTERN.test(stateKey)) {
      throw new Error('Invalid generic device state key: ' + stateKey);
    }
    const value = state[stateKey];
    if (
      value !== null &&
      typeof value !== 'string' &&
      typeof value !== 'number' &&
      typeof value !== 'boolean'
    ) {
      throw new Error('Generic device state must contain primitive values');
    }
    if (typeof value === 'number' && !Number.isFinite(value)) {
      throw new Error('Generic numeric state must be finite');
    }
    if (typeof value === 'string' && value.length > 256) {
      throw new Error('Generic string state is too long');
    }
  }
  device.state = state;

  const controlsValue = raw['controls'];
  if (
    !Array.isArray(controlsValue) ||
    controlsValue.length === 0 ||
    controlsValue.length > 32
  ) {
    throw new Error('Generic device controls are invalid');
  }
  const controlIds: string[] = [];
  const rawControls = controlsValue as object[];
  for (let index = 0; index < rawControls.length; index++) {
    const rawControl = rawControls[index];
    if (
      typeof rawControl !== 'object' ||
      rawControl === null ||
      Array.isArray(rawControl)
    ) {
      throw new Error('Generic device control must be an object');
    }
    const control = parseControl(
      rawControl as Record<string, Object>,
      state
    );
    if (controlIds.indexOf(control.id) >= 0) {
      throw new Error('Duplicate generic control id');
    }
    controlIds.push(control.id);
    device.controls.push(control);
  }
  return device;
}

export function serializeGenericDevice(
  device: GenericDevice
): Record<string, Object> {
  const category: Record<string, Object> = {
    'id': device.category.id,
    'title': device.category.title,
    'icon': device.category.icon,
    'homeOnly': device.category.homeOnly
  };
  const controls: Record<string, Object>[] = [];
  for (let index = 0; index < device.controls.length; index++) {
    const control = device.controls[index];
    const raw: Record<string, Object> = {
      'id': control.id,
      'kind': control.kind,
      'label': control.label,
      'action': control.action
    };
    if (control.stateKey.length > 0) {
      raw['stateKey'] = control.stateKey;
    }
    if (control.payloadKey.length > 0) {
      raw['payloadKey'] = control.payloadKey;
    }
    if (control.kind === DeviceControlKind.SLIDER) {
      raw['minimum'] = control.minimum;
      raw['maximum'] = control.maximum;
      raw['step'] = control.step;
    }
    if (control.kind === DeviceControlKind.ENUM) {
      raw['options'] = control.options;
    }
    if (control.unit.length > 0) {
      raw['unit'] = control.unit;
    }
    if (control.primary) {
      raw['primary'] = true;
    }
    if (control.requiresConfirmation) {
      raw['requiresConfirmation'] = true;
    }
    controls.push(raw);
  }
  return {
    'id': device.id,
    'name': device.name,
    'roomId': device.roomId,
    'type': device.type,
    'online': device.online,
    'stateVersion': device.stateVersion,
    'updatedAt': device.updatedAt,
    'category': category,
    'state': device.state,
    'controls': controls
  };
}

