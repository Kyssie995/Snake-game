import React, { useState } from 'react';
import {
  View,
  Text,
  ScrollView,
  StyleSheet,
  TouchableOpacity,
  Switch,
  Modal,
  Platform,
  Alert,
} from 'react-native';
import { useTheme } from '../hooks/useTheme';
import { useStore } from '../store';
import { BorderRadius, FontSize, FontWeight, Spacing } from '../constants/theme';

interface Props {
  visible: boolean;
  onClose: () => void;
}

interface Integration {
  id: string;
  name: string;
  icon: string;
  description: { de: string; en: string };
  available: boolean;
  platform: 'ios' | 'android' | 'both';
  syncOptions: string[];
}

export default function HealthIntegrationsScreen({ visible, onClose }: Props) {
  const theme = useTheme();
  const settings = useStore(s => s.settings);
  const lang = settings.language;
  const isPremium = settings.subscription !== 'free';

  const [connectedServices, setConnectedServices] = useState<Record<string, boolean>>({});

  const integrations: Integration[] = [
    {
      id: 'apple_health',
      name: 'Apple Health',
      icon: '🍎',
      description: {
        de: 'Synchronisiere Kalorien, Gewicht und Schritte mit Apple Health.',
        en: 'Sync calories, weight, and steps with Apple Health.',
      },
      available: Platform.OS === 'ios',
      platform: 'ios',
      syncOptions: ['calories', 'weight', 'water', 'steps'],
    },
    {
      id: 'google_fit',
      name: 'Google Fit',
      icon: '💚',
      description: {
        de: 'Verbinde dich mit Google Fit für Aktivitäts- und Gewichtsdaten.',
        en: 'Connect with Google Fit for activity and weight data.',
      },
      available: Platform.OS === 'android',
      platform: 'android',
      syncOptions: ['calories', 'weight', 'steps'],
    },
    {
      id: 'garmin',
      name: 'Garmin Connect',
      icon: '⌚',
      description: {
        de: 'Importiere Aktivitätsdaten von deiner Garmin-Uhr.',
        en: 'Import activity data from your Garmin watch.',
      },
      available: true,
      platform: 'both',
      syncOptions: ['calories_burned', 'steps', 'heart_rate'],
    },
    {
      id: 'fitbit',
      name: 'Fitbit',
      icon: '💙',
      description: {
        de: 'Synchronisiere Aktivitäts- und Schlafdaten mit Fitbit.',
        en: 'Sync activity and sleep data with Fitbit.',
      },
      available: true,
      platform: 'both',
      syncOptions: ['calories_burned', 'steps', 'sleep'],
    },
    {
      id: 'samsung_health',
      name: 'Samsung Health',
      icon: '🔵',
      description: {
        de: 'Verbinde dich mit Samsung Health für umfassende Gesundheitsdaten.',
        en: 'Connect with Samsung Health for comprehensive health data.',
      },
      available: Platform.OS === 'android',
      platform: 'android',
      syncOptions: ['calories', 'weight', 'steps', 'heart_rate'],
    },
  ];

  const toggleConnection = (id: string) => {
    if (connectedServices[id]) {
      setConnectedServices(prev => ({ ...prev, [id]: false }));
    } else {
      Alert.alert(
        lang === 'de' ? 'Verbinden' : 'Connect',
        lang === 'de'
          ? 'In der finalen Version wird hier die Verbindung hergestellt.'
          : 'In the final version, the connection will be established here.',
        [
          { text: lang === 'de' ? 'Abbrechen' : 'Cancel', style: 'cancel' },
          {
            text: lang === 'de' ? 'Verbinden' : 'Connect',
            onPress: () => setConnectedServices(prev => ({ ...prev, [id]: true })),
          },
        ]
      );
    }
  };

  const syncLabelMap: Record<string, { de: string; en: string }> = {
    calories: { de: 'Kalorien', en: 'Calories' },
    weight: { de: 'Gewicht', en: 'Weight' },
    water: { de: 'Wasser', en: 'Water' },
    steps: { de: 'Schritte', en: 'Steps' },
    calories_burned: { de: 'Verbrannte Kalorien', en: 'Calories Burned' },
    heart_rate: { de: 'Herzfrequenz', en: 'Heart Rate' },
    sleep: { de: 'Schlaf', en: 'Sleep' },
  };

  if (!isPremium) {
    return (
      <Modal visible={visible} animationType="slide" presentationStyle="pageSheet">
        <View style={[styles.container, { backgroundColor: theme.background }]}>
          <View style={[styles.header, { borderBottomColor: theme.border }]}>
            <TouchableOpacity onPress={onClose}>
              <Text style={[styles.closeBtn, { color: theme.primary }]}>✕</Text>
            </TouchableOpacity>
            <Text style={[styles.headerTitle, { color: theme.text }]}>
              {lang === 'de' ? 'Integrationen' : 'Integrations'}
            </Text>
            <View style={{ width: 40 }} />
          </View>
          <View style={styles.premiumGate}>
            <Text style={{ fontSize: 48 }}>❤️</Text>
            <Text style={[styles.premiumTitle, { color: theme.text }]}>Premium Feature</Text>
            <Text style={[styles.premiumDesc, { color: theme.textSecondary }]}>
              {lang === 'de'
                ? 'Verbinde NutriFlow mit Apple Health, Google Fit und mehr für automatische Synchronisation.'
                : 'Connect NutriFlow with Apple Health, Google Fit, and more for automatic sync.'}
            </Text>
            <TouchableOpacity style={[styles.upgradeBtn, { backgroundColor: theme.primary }]}>
              <Text style={styles.upgradeBtnText}>
                {lang === 'de' ? 'Upgrade auf Premium' : 'Upgrade to Premium'}
              </Text>
            </TouchableOpacity>
          </View>
        </View>
      </Modal>
    );
  }

  return (
    <Modal visible={visible} animationType="slide" presentationStyle="pageSheet">
      <View style={[styles.container, { backgroundColor: theme.background }]}>
        <View style={[styles.header, { borderBottomColor: theme.border }]}>
          <TouchableOpacity onPress={onClose}>
            <Text style={[styles.closeBtn, { color: theme.primary }]}>✕</Text>
          </TouchableOpacity>
          <Text style={[styles.headerTitle, { color: theme.text }]}>
            {lang === 'de' ? 'Integrationen' : 'Integrations'}
          </Text>
          <View style={{ width: 40 }} />
        </View>

        <ScrollView contentContainerStyle={styles.content} showsVerticalScrollIndicator={false}>
          <Text style={[styles.subtitle, { color: theme.textSecondary }]}>
            {lang === 'de'
              ? 'Verbinde deine Gesundheits-Apps für automatische Synchronisation.'
              : 'Connect your health apps for automatic synchronization.'}
          </Text>

          {integrations.map(integration => {
            const isConnected = connectedServices[integration.id] || false;
            const platformLabel = integration.platform === 'ios' ? 'iOS' : integration.platform === 'android' ? 'Android' : 'iOS & Android';

            return (
              <View
                key={integration.id}
                style={[
                  styles.integrationCard,
                  {
                    backgroundColor: theme.surface,
                    shadowColor: theme.cardShadow,
                    borderColor: isConnected ? theme.success : 'transparent',
                    borderWidth: isConnected ? 1 : 0,
                  },
                ]}
              >
                <View style={styles.integrationHeader}>
                  <View style={styles.integrationLeft}>
                    <Text style={styles.integrationIcon}>{integration.icon}</Text>
                    <View style={styles.integrationInfo}>
                      <Text style={[styles.integrationName, { color: theme.text }]}>{integration.name}</Text>
                      <Text style={[styles.platformTag, { color: theme.textTertiary }]}>{platformLabel}</Text>
                    </View>
                  </View>
                  <Switch
                    value={isConnected}
                    onValueChange={() => toggleConnection(integration.id)}
                    trackColor={{ false: theme.surfaceSecondary, true: theme.success + '50' }}
                    thumbColor={isConnected ? theme.success : theme.textTertiary}
                  />
                </View>

                <Text style={[styles.integrationDesc, { color: theme.textTertiary }]}>
                  {integration.description[lang]}
                </Text>

                {isConnected && (
                  <View style={styles.syncOptions}>
                    <Text style={[styles.syncTitle, { color: theme.textSecondary }]}>
                      {lang === 'de' ? 'Synchronisiert:' : 'Syncing:'}
                    </Text>
                    <View style={styles.syncTags}>
                      {integration.syncOptions.map(opt => (
                        <View key={opt} style={[styles.syncTag, { backgroundColor: theme.success + '15' }]}>
                          <Text style={[styles.syncTagText, { color: theme.success }]}>
                            {syncLabelMap[opt]?.[lang] || opt}
                          </Text>
                        </View>
                      ))}
                    </View>
                  </View>
                )}
              </View>
            );
          })}

          <View style={[styles.infoCard, { backgroundColor: theme.surfaceSecondary }]}>
            <Text style={styles.infoIcon}>🔒</Text>
            <Text style={[styles.infoText, { color: theme.textSecondary }]}>
              {lang === 'de'
                ? 'Deine Gesundheitsdaten werden sicher und lokal verarbeitet. NutriFlow speichert keine Daten auf externen Servern.'
                : 'Your health data is processed securely and locally. NutriFlow does not store data on external servers.'}
            </Text>
          </View>

          <View style={{ height: 40 }} />
        </ScrollView>
      </View>
    </Modal>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1 },
  header: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: Spacing.lg,
    paddingTop: Platform.OS === 'ios' ? 56 : Spacing.lg,
    paddingBottom: Spacing.md,
    borderBottomWidth: StyleSheet.hairlineWidth,
  },
  closeBtn: { fontSize: 20, fontWeight: FontWeight.medium, width: 40 },
  headerTitle: { fontSize: FontSize.lg, fontWeight: FontWeight.semibold },
  content: { padding: Spacing.lg },
  subtitle: { fontSize: FontSize.sm, marginBottom: Spacing.xl, lineHeight: 20 },
  integrationCard: {
    borderRadius: BorderRadius.lg,
    padding: Spacing.lg,
    marginBottom: Spacing.md,
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 1,
    shadowRadius: 6,
    elevation: 3,
  },
  integrationHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: Spacing.sm,
  },
  integrationLeft: { flexDirection: 'row', alignItems: 'center', gap: Spacing.md },
  integrationIcon: { fontSize: 28 },
  integrationInfo: {},
  integrationName: { fontSize: FontSize.md, fontWeight: FontWeight.semibold },
  platformTag: { fontSize: FontSize.xs, marginTop: 1 },
  integrationDesc: { fontSize: FontSize.xs, lineHeight: 16, marginBottom: Spacing.sm },
  syncOptions: { marginTop: Spacing.sm },
  syncTitle: { fontSize: FontSize.xs, fontWeight: FontWeight.medium, marginBottom: Spacing.sm },
  syncTags: { flexDirection: 'row', flexWrap: 'wrap', gap: Spacing.xs },
  syncTag: { paddingHorizontal: Spacing.sm, paddingVertical: 3, borderRadius: BorderRadius.full },
  syncTagText: { fontSize: FontSize.xs, fontWeight: FontWeight.medium },
  infoCard: {
    flexDirection: 'row',
    borderRadius: BorderRadius.lg,
    padding: Spacing.lg,
    marginTop: Spacing.lg,
    gap: Spacing.md,
    alignItems: 'flex-start',
  },
  infoIcon: { fontSize: 20 },
  infoText: { flex: 1, fontSize: FontSize.xs, lineHeight: 18 },
  premiumGate: { flex: 1, justifyContent: 'center', alignItems: 'center', padding: Spacing.xxl },
  premiumTitle: { fontSize: FontSize.xl, fontWeight: FontWeight.bold, marginTop: Spacing.lg },
  premiumDesc: { fontSize: FontSize.sm, textAlign: 'center', marginTop: Spacing.sm, lineHeight: 22, maxWidth: 300 },
  upgradeBtn: { paddingHorizontal: Spacing.xxl, paddingVertical: Spacing.md, borderRadius: BorderRadius.md, marginTop: Spacing.xxl },
  upgradeBtnText: { color: '#fff', fontSize: FontSize.md, fontWeight: FontWeight.semibold },
});
