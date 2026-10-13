import { StatusBar } from 'expo-status-bar';
import * as Application from 'expo-application';
import Constants from 'expo-constants';
import * as Updates from 'expo-updates';
import { ScrollView, StyleSheet, Text, View } from 'react-native';

const Row = ({ label, value }) => (
  <View style={styles.row}>
    <Text style={styles.label}>{label}</Text>
    <Text selectable style={styles.value}>
      {value}
    </Text>
  </View>
);

const fmt = (v) => {
  if (v === null || v === undefined) return '—';
  if (typeof v === 'object') return JSON.stringify(v);
  return String(v);
};

export default function App() {
  const expoConfig = Constants.expoConfig ?? {};

  return (
    <View style={styles.container}>
      <ScrollView contentContainerStyle={styles.scroll}>
        <Text style={styles.title}>AAB runtimeVersion MRE</Text>
        <Text style={styles.subtitle}>
          Compare these values between the sideloaded APK and the Play-installed AAB build.
        </Text>

        <Text style={styles.section}>Native (expo-updates)</Text>
        <Row label="Updates.runtimeVersion" value={fmt(Updates.runtimeVersion)} />
        <Row label="Updates.channel" value={fmt(Updates.channel)} />
        <Row label="Updates.updateId" value={fmt(Updates.updateId)} />
        <Row label="Updates.isEmbeddedLaunch" value={fmt(Updates.isEmbeddedLaunch)} />
        <Row label="Updates.isEnabled" value={fmt(Updates.isEnabled)} />
        <Row label="manifest.runtimeVersion" value={fmt(Updates.manifest?.runtimeVersion)} />
        <Row label="manifest.id" value={fmt(Updates.manifest?.id)} />

        <Text style={styles.section}>JS config (expo-constants)</Text>
        <Row label="expoConfig.version" value={fmt(expoConfig.version)} />
        <Row label="expoConfig.runtimeVersion" value={fmt(expoConfig.runtimeVersion)} />
        <Row label="android.runtimeVersion" value={fmt(expoConfig.android?.runtimeVersion)} />

        <Text style={styles.section}>Binary (expo-application)</Text>
        <Row label="nativeApplicationVersion" value={fmt(Application.nativeApplicationVersion)} />
        <Row label="nativeBuildVersion" value={fmt(Application.nativeBuildVersion)} />
        <Row label="applicationId" value={fmt(Application.applicationId)} />

        <Text style={styles.verdict}>
          {fmt(Updates.runtimeVersion) === fmt(expoConfig.android?.runtimeVersion ?? expoConfig.version)
            ? '✅ native runtime matches config'
            : '❌ STALE native runtime — bug reproduced'}
        </Text>
      </ScrollView>
      <StatusBar style="auto" />
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#fff',
  },
  scroll: {
    paddingTop: 64,
    paddingHorizontal: 20,
    paddingBottom: 40,
  },
  title: {
    fontSize: 22,
    fontWeight: '700',
    marginBottom: 4,
  },
  subtitle: {
    fontSize: 13,
    color: '#555',
    marginBottom: 16,
  },
  section: {
    fontSize: 14,
    fontWeight: '700',
    marginTop: 16,
    marginBottom: 6,
    color: '#111',
  },
  row: {
    paddingVertical: 5,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: '#ddd',
  },
  label: {
    fontSize: 12,
    color: '#666',
  },
  value: {
    fontSize: 15,
    color: '#000',
    fontVariant: ['tabular-nums'],
  },
  verdict: {
    marginTop: 24,
    fontSize: 16,
    fontWeight: '700',
  },
});
