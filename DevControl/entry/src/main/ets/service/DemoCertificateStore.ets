import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';

const DEMO_CA_RESOURCE = 'demo_ca.crt';
const DEMO_CA_FILE = 'devcontrol_demo_ca.crt';

export class DemoCertificateStore {
  static async prepare(context: common.UIAbilityContext): Promise<string> {
    const certificate = await context.resourceManager.getRawFileContent(DEMO_CA_RESOURCE);
    if (certificate.length === 0) {
      throw new Error('演示 CA 证书内容为空');
    }
    const path = context.filesDir + '/' + DEMO_CA_FILE;
    const file = fileIo.openSync(
      path,
      fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC
    );
    try {
      fileIo.writeSync(file.fd, certificate.buffer);
    } finally {
      fileIo.closeSync(file);
    }
    return path;
  }
}
