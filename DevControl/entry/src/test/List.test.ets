import localUnitTest from './LocalUnit.test';
import deviceRegistryTest from './DeviceRegistry.test';
import deviceRegistrationTest from './DeviceRegistration.test';

export default function testsuite() {
  localUnitTest();
  deviceRegistryTest();
  deviceRegistrationTest();
}
