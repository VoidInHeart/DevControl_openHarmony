import abilityTest from './Ability.test';
import gatewaySessionStoreTest from './GatewaySessionStore.test';
import smartRuleStoreTest from './SmartRuleStore.test';

export default function testsuite() {
  abilityTest();
  gatewaySessionStoreTest();
  smartRuleStoreTest();
}
