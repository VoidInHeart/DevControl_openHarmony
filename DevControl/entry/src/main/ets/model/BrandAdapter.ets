export class BrandAdapter {
  brandName: string = '';

  getTurnOnCommand(): string {
    return 'acPowerOn';
  }

  getTurnOffCommand(): string {
    return 'acPowerOff';
  }

  getSetTempCommand(temp: number): string {
    return 'setTargetTemp,' + temp.toString();
  }

  getSetHumidityCommand(hum: number): string {
    return 'setTargetHumidity,' + hum.toString();
  }

  getSetModeCommand(mode: number): string {
    return 'setACMode,' + mode.toString();
  }
}

export class HaierAdapter extends BrandAdapter {
  constructor() {
    super();
    this.brandName = 'Haier';
  }

  override getSetTempCommand(temp: number): string {
    return 'setTargetTemp,' + temp.toString() + ',haier';
  }
}

export class GreeAdapter extends BrandAdapter {
  constructor() {
    super();
    this.brandName = 'Gree';
  }

  override getSetTempCommand(temp: number): string {
    return 'setTargetTemp,' + temp.toString() + ',gree';
  }
}

export class MideaAdapter extends BrandAdapter {
  constructor() {
    super();
    this.brandName = 'Midea';
  }

  override getSetTempCommand(temp: number): string {
    return 'setTargetTemp,' + temp.toString() + ',midea';
  }
}

export function createBrandAdapter(brand: string): BrandAdapter {
  if (brand === 'haier') {
    return new HaierAdapter();
  }
  if (brand === 'gree') {
    return new GreeAdapter();
  }
  if (brand === 'midea') {
    return new MideaAdapter();
  }
  return new BrandAdapter();
}
