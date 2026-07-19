import { describe, expect, it } from '@ohos/hypium';
import { DeviceRegistrationQr } from '../main/ets/service/DeviceRegistration';

function validRegistrationText(): string {
  return JSON.stringify({
    'schema': 'devcontrol.device-registration',
    'protocolVersion': '1.0',
    'deviceId': 'CURTAIN-001',
    'deviceName': '测试窗帘',
    'deviceType': 'curtain',
    'categoryId': 'curtains',
    'roomId': 'living',
    'capabilities': ['setPosition', 'stop'],
    'gatewayProofFormat': 'jws',
    'gatewayProof': 'eyJhbGciOiJFUzI1NiJ9.eyJkZXZpY2VJZCI6IkNVUlRBSU4tMDAxIn0.signature-value-1234'
  });
}

export default function deviceRegistrationTest() {
  describe('DeviceRegistrationQr', () => {
    it('parses a signed capability declaration', 0, () => {
      const request = DeviceRegistrationQr.parse(validRegistrationText());
      expect(request.deviceId).assertEqual('CURTAIN-001');
      expect(request.deviceName).assertEqual('测试窗帘');
      expect(request.deviceType).assertEqual('curtain');
      expect(request.categoryId).assertEqual('curtains');
      expect(request.roomId).assertEqual('living');
      expect(request.capabilities.length).assertEqual(2);
      expect(request.gatewayProofFormat).assertEqual('jws');
    });

    it('accepts an app-scheme wrapped declaration', 0, () => {
      const request = DeviceRegistrationQr.parse(
        'devcontrol://register?payload=' + encodeURIComponent(validRegistrationText())
      );
      expect(request.capabilities[0]).assertEqual('setPosition');
    });

    it('rejects duplicate capabilities and unsigned declarations', 0, () => {
      let duplicateRejected = false;
      try {
        const duplicate = JSON.parse(validRegistrationText()) as Record<string, Object>;
        duplicate['capabilities'] = ['setPosition', 'setPosition'];
        DeviceRegistrationQr.parse(JSON.stringify(duplicate));
      } catch (error) {
        duplicateRejected = true;
      }
      expect(duplicateRejected).assertTrue();

      let proofRejected = false;
      try {
        const unsigned = JSON.parse(validRegistrationText()) as Record<string, Object>;
        unsigned['gatewayProof'] = 'not-a-signed-proof';
        DeviceRegistrationQr.parse(JSON.stringify(unsigned));
      } catch (error) {
        proofRejected = true;
      }
      expect(proofRejected).assertTrue();
    });

    it('rejects invalid schema, identifiers and malformed URI payloads', 0, () => {
      let schemaRejected = false;
      try {
        const unsupported = JSON.parse(validRegistrationText()) as Record<string, Object>;
        unsupported['schema'] = 'other.registration';
        DeviceRegistrationQr.parse(JSON.stringify(unsupported));
      } catch (error) {
        schemaRejected = true;
      }
      expect(schemaRejected).assertTrue();

      let identifierRejected = false;
      try {
        const unsafe = JSON.parse(validRegistrationText()) as Record<string, Object>;
        unsafe['deviceType'] = 'curtain control';
        DeviceRegistrationQr.parse(JSON.stringify(unsafe));
      } catch (error) {
        identifierRejected = true;
      }
      expect(identifierRejected).assertTrue();

      let uriRejected = false;
      try {
        DeviceRegistrationQr.parse('devcontrol://register?payload=%ZZ');
      } catch (error) {
        uriRejected = true;
      }
      expect(uriRejected).assertTrue();
    });

    it('requires a usable device name and room id', 0, () => {
      const blankName = JSON.parse(validRegistrationText()) as Record<string, Object>;
      blankName['deviceName'] = '   ';
      let blankNameRejected = false;
      try {
        DeviceRegistrationQr.parse(JSON.stringify(blankName));
      } catch (error) {
        blankNameRejected = true;
      }

      const invalidRoom = JSON.parse(validRegistrationText()) as Record<string, Object>;
      invalidRoom['roomId'] = 'living room';
      let invalidRoomRejected = false;
      try {
        DeviceRegistrationQr.parse(JSON.stringify(invalidRoom));
      } catch (error) {
        invalidRoomRejected = true;
      }

      expect(blankNameRejected).assertTrue();
      expect(invalidRoomRejected).assertTrue();
    });
  });
}
