import type { ConfigContext, ExpoConfig } from 'expo/config';

export default ({ config }: ConfigContext): ExpoConfig => ({
  ...config,
  name: 'RN Mobile Template (dev)',
  slug: 'react-native-mobile-template',
  scheme: 'rnmt',
});
