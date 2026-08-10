import React from 'react';
import {
  View,
  Text,
  ScrollView,
  StyleSheet,
  TouchableOpacity,
  Modal,
  Platform,
  Linking,
} from 'react-native';
import { useTheme } from '../hooks/useTheme';
import { useStore } from '../store';
import { BorderRadius, FontSize, FontWeight, Spacing } from '../constants/theme';

interface Props {
  visible: boolean;
  onClose: () => void;
}

export default function PrivacyScreen({ visible, onClose }: Props) {
  const theme = useTheme();
  const lang = useStore(s => s.settings.language);

  const sections = lang === 'de' ? [
    {
      title: 'Datenschutz bei NutriFlow',
      icon: '🔒',
      content: 'NutriFlow speichert alle deine Daten ausschließlich lokal auf deinem Gerät. Wir haben keinen Zugriff auf deine Ernährungs-, Gewichts- oder Gesundheitsdaten.',
    },
    {
      title: 'Welche Daten werden gespeichert?',
      icon: '📋',
      content: '• Profildaten (Name, Alter, Geschlecht, Größe, Gewicht)\n• Ernährungstagebuch (Mahlzeiten, Kalorien, Makronährstoffe)\n• Gewichtsverlauf\n• Wasseraufnahme\n• App-Einstellungen und Präferenzen',
    },
    {
      title: 'Wo werden Daten gespeichert?',
      icon: '📱',
      content: 'Alle Daten werden lokal auf deinem Gerät in verschlüsseltem Speicher abgelegt. Es erfolgt keine Übertragung an externe Server.',
    },
    {
      title: 'Deine Rechte (DSGVO)',
      icon: '⚖️',
      content: '• Recht auf Auskunft (Art. 15 DSGVO)\n• Recht auf Berichtigung (Art. 16 DSGVO)\n• Recht auf Löschung (Art. 17 DSGVO)\n• Recht auf Datenübertragbarkeit (Art. 20 DSGVO)\n\nDu kannst deine Daten jederzeit über die Export-Funktion herunterladen oder die App deinstallieren, um alle Daten zu löschen.',
    },
    {
      title: 'Drittanbieter',
      icon: '🔗',
      content: 'NutriFlow verwendet keine Tracking-Dienste, Werbung oder Analytics. Health-Integrationen (Apple Health, Google Fit) werden nur bei expliziter Zustimmung aktiviert.',
    },
  ] : [
    {
      title: 'Privacy at NutriFlow',
      icon: '🔒',
      content: 'NutriFlow stores all your data exclusively on your device. We have no access to your nutrition, weight, or health data.',
    },
    {
      title: 'What data is stored?',
      icon: '📋',
      content: '• Profile data (name, age, gender, height, weight)\n• Food diary (meals, calories, macronutrients)\n• Weight history\n• Water intake\n• App settings and preferences',
    },
    {
      title: 'Where is data stored?',
      icon: '📱',
      content: 'All data is stored locally on your device in encrypted storage. No data is transmitted to external servers.',
    },
    {
      title: 'Your Rights (GDPR)',
      icon: '⚖️',
      content: '• Right of access (Art. 15 GDPR)\n• Right to rectification (Art. 16 GDPR)\n• Right to erasure (Art. 17 GDPR)\n• Right to data portability (Art. 20 GDPR)\n\nYou can download your data at any time via the Export function or uninstall the app to delete all data.',
    },
    {
      title: 'Third Parties',
      icon: '🔗',
      content: 'NutriFlow does not use any tracking services, advertising, or analytics. Health integrations (Apple Health, Google Fit) are only activated with explicit consent.',
    },
  ];

  return (
    <Modal visible={visible} animationType="slide" presentationStyle="pageSheet">
      <View style={[styles.container, { backgroundColor: theme.background }]}>
        <View style={[styles.header, { borderBottomColor: theme.border }]}>
          <TouchableOpacity onPress={onClose}>
            <Text style={[styles.closeBtn, { color: theme.primary }]}>✕</Text>
          </TouchableOpacity>
          <Text style={[styles.headerTitle, { color: theme.text }]}>
            {lang === 'de' ? 'Datenschutz' : 'Privacy'}
          </Text>
          <View style={{ width: 40 }} />
        </View>

        <ScrollView contentContainerStyle={styles.content} showsVerticalScrollIndicator={false}>
          {sections.map((section, i) => (
            <View key={i} style={[styles.card, { backgroundColor: theme.surface, shadowColor: theme.cardShadow }]}>
              <View style={styles.cardHeader}>
                <Text style={styles.cardIcon}>{section.icon}</Text>
                <Text style={[styles.cardTitle, { color: theme.text }]}>{section.title}</Text>
              </View>
              <Text style={[styles.cardContent, { color: theme.textSecondary }]}>{section.content}</Text>
            </View>
          ))}

          <TouchableOpacity
            style={[styles.contactBtn, { borderColor: theme.border }]}
            onPress={() => Linking.openURL('mailto:privacy@nutriflow.app')}
          >
            <Text style={[styles.contactBtnText, { color: theme.primary }]}>
              {lang === 'de' ? 'Datenschutzanfrage senden' : 'Send Privacy Request'}
            </Text>
          </TouchableOpacity>

          <Text style={[styles.footerText, { color: theme.textTertiary }]}>
            {lang === 'de' ? 'Stand: Juni 2026 · NutriFlow v1.0.0' : 'Last updated: June 2026 · NutriFlow v1.0.0'}
          </Text>

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
  card: {
    borderRadius: BorderRadius.lg,
    padding: Spacing.lg,
    marginBottom: Spacing.md,
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 1,
    shadowRadius: 6,
    elevation: 3,
  },
  cardHeader: { flexDirection: 'row', alignItems: 'center', gap: Spacing.md, marginBottom: Spacing.md },
  cardIcon: { fontSize: 22 },
  cardTitle: { fontSize: FontSize.md, fontWeight: FontWeight.semibold, flex: 1 },
  cardContent: { fontSize: FontSize.sm, lineHeight: 22 },
  contactBtn: {
    borderWidth: 1,
    borderRadius: BorderRadius.md,
    paddingVertical: Spacing.lg,
    alignItems: 'center',
    marginTop: Spacing.lg,
  },
  contactBtnText: { fontSize: FontSize.md, fontWeight: FontWeight.semibold },
  footerText: { fontSize: FontSize.xs, textAlign: 'center', marginTop: Spacing.lg },
});
