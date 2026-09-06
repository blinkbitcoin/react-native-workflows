// Minimal Expo config for the consumer fixture. scripts/native/expo-config.sh
// reads name/slug/scheme/ios.bundleIdentifier/android.package out of
// `expo config --json`; scripts/ci/native-hash.sh only hashes this file's bytes.
import type { ExpoConfig } from 'expo/config';

const config: ExpoConfig = {
  name: 'Consumer Min',
  slug: 'consumer-min',
  scheme: 'consumermin',
  version: '0.0.0',
  ios: { bundleIdentifier: 'com.example.consumermin' },
  android: { package: 'com.example.consumermin' },
};

export default config;
