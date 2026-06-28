import { BackupExtensionAbility, BundleVersion } from '@kit.CoreFileKit';
import { Logger, DOMAIN_APP } from '../common/utils/Logger'

const logger = new Logger(DOMAIN_APP, 'EntryBackupAbility')

export default class EntryBackupAbility extends BackupExtensionAbility {
  async onBackup() {
    logger.info('onBackup ok');
    await Promise.resolve();
  }

  async onRestore(bundleVersion: BundleVersion) {
    logger.info('onRestore ok %{public}s', JSON.stringify(bundleVersion));
    await Promise.resolve();
  }
}