import { Okop } from '../../types';

export async function getConfigSections(): Promise<Okop.ConfigSection[]> {
  return uci.load('okop').then(() => uci.sections('okop'));
}
