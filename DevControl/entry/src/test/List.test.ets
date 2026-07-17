import localUnitTest from './LocalUnit.test';
import deviceRegistryTest from './DeviceRegistry.test';

export default function testsuite() {
  localUnitTest();
  deviceRegistryTest();
}
