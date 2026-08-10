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

export default function AboutScreen({ visible, onClose }: Props) {
  const theme = useTheme();
  const lang = useStore(s => s.settings.language);

  const features = lang === 'de' ? [
    { icon: '⚡', title: 'Blitzschnell', desc: 'Kalorien zählen in unter 5 Sekunden' },
    { icon: '📊', title: 'Makro Tracking', desc: 'Protein, Kohlenhydrate, Fett & Ballaststoffe' },
    { icon: '📷', title: 'Barcode Scanner', desc: 'Produkte einfach scannen' },
    { icon: '📅', title: 'Mahlzeitenplanung', desc: 'Woche im Voraus planen' },
    { icon: '🏆', title: 'Challenges', desc: 'Motivation durch Gamification' },
    { icon: '🔒', title: 'DSGVO-konform', desc: 'Alle Daten lokal auf deinem Gerät' },
  ] : [
    { icon: '⚡', title: 'Lightning Fast', desc: 'Count calories in under 5 seconds' },
    { icon: '📊', title: 'Macro Tracking', desc: 'Protein, carbs, fat & fiber' },
    { icon: '📷', title: 'Barcode Scanner', desc: 'Scan products easily' },
    { icon: '📅', title: 'Meal Planning', desc: 'Plan your week ahead' },
    { icon: '🏆', title: 'Challenges', desc: 'Motivation through gamification' },
    { icon: '🔒', title: 'GDPR Compliant', desc: 'All data stored locally on your device' },
  ];

  return (
    <Modal visible={visible} animationType="slide" presentationStyle="pageSheet">
      <View style={[styles.container, { backgroundColor: theme.background }]}>
        <View style={[styles.header, { borderBottomColor: theme.border }]}>
          <TouchableOpacity onPress={onClose}>
            <Text style={[styles.closeBtn, { color: theme.primary }]}>✕</Text>
          </TouchableOpacity>
          <Text style={[styles.headerTitle, { color: theme.text }]}>
            {lang === 'de' ? 'Über NutriFlow' : 'About NutriFlow'}
          </Text>
          <View style={{ width: 40 }} />
        </View>

        <ScrollView contentContainerStyle={styles.content} showsVerticalScrollIndicator={false}>
          <View style={styles.logoSection}>
            <View style={[styles.logoCircle, { backgroundColor: theme.primary + '15' }]}>
              <Text style={styles.logoEmoji}>🍎</Text>
            </View>
            <Text style={[styles.appName, { color: theme.text }]}>NutriFlow</Text>
            <Text style={[styles.version, { color: theme.textTertiary }]}>Version 1.0.0</Text>
            <Text style={[styles.tagline, { color: theme.textSecondary }]}>
              {lang === 'de'
                ? 'Kalorien zählen in unter 5 Sekunden.'
                : 'Count calories in under 5 seconds.'}
            </Text>
          </View>

          <View style={[styles.missionCard, { backgroundColor: theme.surface, shadowColor: theme.cardShadow }]}>
            <Text style={[styles.missionTitle, { color: theme.text }]}>
              {lang === 'de' ? 'Unsere Mission' : 'Our Mission'}
            </Text>
            <Text style={[styles.missionText, { color: theme.textSecondary }]}>
              {lang === 'de'
                ? 'NutriFlow macht gesunde Ernährung einfach, schnell und motivierend. Wir glauben, dass Kalorienzählen nicht kompliziert sein muss — sondern so natürlich wie ein Blick aufs Handy.'
                : 'NutriFlow makes healthy eating simple, fast, and motivating. We believe calorie counting shouldn\'t be complicated — it should be as natural as checking your phone.'}
            </Text>
          </View>

          <Text style={[styles.featuresTitle, { color: theme.text }]}>
            {lang === 'de' ? 'Features' : 'Features'}
          </Text>

          {features.map((feature, i) => (
            <View key={i} style={[styles.featureRow, { backgroundColor: theme.surface }]}>
              <Text style={styles.featureIcon}>{feature.icon}</Text>
              <View style={styles.featureInfo}>
                <Text style={[styles.featureTitle, { color: theme.text }]}>{feature.title}</Text>
                <Text style={[styles.featureDesc, { color: theme.textTertiary }]}>{feature.desc}</Text>
              </View>
            </View>
          ))}

          <View style={[styles.linksCard, { backgroundColor: theme.surface }]}>
            <TouchableOpacity style={[styles.linkRow, { borderBottomColor: theme.border }]}>
              <Text style={[styles.linkText, { color: theme.primary }]}>
                {lang === 'de' ? 'Nutzungsbedingungen' : 'Terms of Service'}
              </Text>
              <Text style={[styles.linkChevron, { color: theme.textTertiary }]}>›</Text>
            </TouchableOpacity>
            <TouchableOpacity style={[styles.linkRow, { borderBottomColor: theme.border }]}>
              <Text style={[styles.linkText, { color: theme.primary }]}>
                {lang === 'de' ? 'Datenschutzerklärung' : 'Privacy Policy'}
              </Text>
              <Text style={[styles.linkChevron, { color: theme.textTertiary }]}>›</Text>
            </TouchableOpacity>
            <TouchableOpacity style={styles.linkRow}>
              <Text style={[styles.linkText, { color: theme.primary }]}>
                {lang === 'de' ? 'Feedback senden' : 'Send Feedback'}
              </Text>
              <Text style={[styles.linkChevron, { color: theme.textTertiary }]}>›</Text>
            </TouchableOpacity>
          </View>

          <Text style={[styles.copyright, { color: theme.textTertiary }]}>
            © 2026 NutriFlow. {lang === 'de' ? 'Alle Rechte vorbehalten.' : 'All rights reserved.'}
          </Text>
          <Text style={[styles.madeWith, { color: theme.textTertiary }]}>
            {lang === 'de' ? 'Mit ❤️ in Deutschland gemacht' : 'Made with ❤️ in Germany'}
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
  logoSection: { alignItems: 'center', paddingVertical: Spacing.xxl },
  logoCircle: {
    width: 80,
    height: 80,
    borderRadius: 40,
    justifyContent: 'center',
    alignItems: 'center',
    marginBottom: Spacing.md,
  },
  logoEmoji: { fontSize: 40 },
  appName: { fontSize: 28, fontWeight: FontWeight.bold },
  version: { fontSize: FontSize.sm, marginTop: 4 },
  tagline: { fontSize: FontSize.md, marginTop: Spacing.sm, textAlign: 'center' },
  missionCard: {
    borderRadius: BorderRadius.lg,
    padding: Spacing.xl,
    marginBottom: Spacing.xl,
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 1,
    shadowRadius: 6,
    elevation: 3,
  },
  missionTitle: { fontSize: FontSize.lg, fontWeight: FontWeight.bold, marginBottom: Spacing.sm },
  missionText: { fontSize: FontSize.sm, lineHeight: 22 },
  featuresTitle: { fontSize: FontSize.lg, fontWeight: FontWeight.bold, marginBottom: Spacing.md },
  featureRow: {
    flexDirection: 'row',
    alignItems: 'center',
    padding: Spacing.md,
    borderRadius: BorderRadius.md,
    marginBottom: Spacing.sm,
    gap: Spacing.md,
  },
  featureIcon: { fontSize: 24, width: 32, textAlign: 'center' },
  featureInfo: { flex: 1 },
  featureTitle: { fontSize: FontSize.md, fontWeight: FontWeight.semibold },
  featureDesc: { fontSize: FontSize.xs, marginTop: 1 },
  linksCard: { borderRadius: BorderRadius.lg, marginTop: Spacing.xl, overflow: 'hidden' },
  linkRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    padding: Spacing.lg,
    borderBottomWidth: StyleSheet.hairlineWidth,
  },
  linkText: { fontSize: FontSize.md, fontWeight: FontWeight.medium },
  linkChevron: { fontSize: 22 },
  copyright: { fontSize: FontSize.xs, textAlign: 'center', marginTop: Spacing.xxl },
  madeWith: { fontSize: FontSize.xs, textAlign: 'center', marginTop: Spacing.xs },
});
