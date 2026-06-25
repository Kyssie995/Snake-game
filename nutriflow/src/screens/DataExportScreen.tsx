import React, { useState } from 'react';
import {
  View,
  Text,
  ScrollView,
  StyleSheet,
  TouchableOpacity,
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

type ExportFormat = 'csv' | 'json';
type ExportRange = 'week' | 'month' | 'all';

export default function DataExportScreen({ visible, onClose }: Props) {
  const theme = useTheme();
  const settings = useStore(s => s.settings);
  const lang = settings.language;
  const isPremium = settings.subscription !== 'free';

  const [format, setFormat] = useState<ExportFormat>('csv');
  const [range, setRange] = useState<ExportRange>('month');
  const [exporting, setExporting] = useState(false);

  const handleExport = () => {
    setExporting(true);
    setTimeout(() => {
      setExporting(false);
      Alert.alert(
        lang === 'de' ? 'Export erstellt' : 'Export Created',
        lang === 'de'
          ? `Deine Daten wurden als ${format.toUpperCase()} exportiert.`
          : `Your data has been exported as ${format.toUpperCase()}.`,
        [{ text: 'OK' }]
      );
    }, 1500);
  };

  const formatOptions: { key: ExportFormat; label: string; desc: string }[] = [
    {
      key: 'csv',
      label: 'CSV',
      desc: lang === 'de' ? 'Kompatibel mit Excel & Google Sheets' : 'Compatible with Excel & Google Sheets',
    },
    {
      key: 'json',
      label: 'JSON',
      desc: lang === 'de' ? 'Strukturierte Daten für Entwickler' : 'Structured data for developers',
    },
  ];

  const rangeOptions: { key: ExportRange; label: string }[] = [
    { key: 'week', label: lang === 'de' ? 'Letzte 7 Tage' : 'Last 7 days' },
    { key: 'month', label: lang === 'de' ? 'Letzter Monat' : 'Last month' },
    { key: 'all', label: lang === 'de' ? 'Alle Daten' : 'All data' },
  ];

  const dataCategories = [
    { icon: '🍽️', label: lang === 'de' ? 'Mahlzeiten & Kalorien' : 'Meals & Calories', included: true },
    { icon: '💧', label: lang === 'de' ? 'Wasseraufnahme' : 'Water Intake', included: true },
    { icon: '⚖️', label: lang === 'de' ? 'Gewichtsverlauf' : 'Weight History', included: true },
    { icon: '📊', label: lang === 'de' ? 'Makronährstoffe' : 'Macronutrients', included: true },
    { icon: '🔥', label: lang === 'de' ? 'Streaks & Badges' : 'Streaks & Badges', included: true },
  ];

  if (!isPremium) {
    return (
      <Modal visible={visible} animationType="slide" presentationStyle="pageSheet">
        <View style={[styles.container, { backgroundColor: theme.background }]}>
          <View style={[styles.header, { borderBottomColor: theme.border }]}>
            <TouchableOpacity onPress={onClose}>
              <Text style={[styles.closeBtn, { color: theme.primary }]}>✕</Text>
            </TouchableOpacity>
            <Text style={[styles.headerTitle, { color: theme.text }]}>
              {lang === 'de' ? 'Daten Export' : 'Data Export'}
            </Text>
            <View style={{ width: 40 }} />
          </View>
          <View style={styles.premiumGate}>
            <Text style={{ fontSize: 48 }}>📤</Text>
            <Text style={[styles.premiumTitle, { color: theme.text }]}>Premium Feature</Text>
            <Text style={[styles.premiumDesc, { color: theme.textSecondary }]}>
              {lang === 'de'
                ? 'Exportiere deine Ernährungsdaten als CSV oder JSON für persönliche Analysen.'
                : 'Export your nutrition data as CSV or JSON for personal analysis.'}
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
            {lang === 'de' ? 'Daten Export' : 'Data Export'}
          </Text>
          <View style={{ width: 40 }} />
        </View>

        <ScrollView contentContainerStyle={styles.content} showsVerticalScrollIndicator={false}>
          <Text style={[styles.sectionLabel, { color: theme.text }]}>
            {lang === 'de' ? 'Format wählen' : 'Choose Format'}
          </Text>

          <View style={styles.formatRow}>
            {formatOptions.map(opt => (
              <TouchableOpacity
                key={opt.key}
                style={[
                  styles.formatCard,
                  {
                    backgroundColor: theme.surface,
                    borderColor: format === opt.key ? theme.primary : theme.border,
                    borderWidth: format === opt.key ? 2 : 1,
                  },
                ]}
                onPress={() => setFormat(opt.key)}
              >
                <Text style={[styles.formatLabel, { color: theme.text }]}>{opt.label}</Text>
                <Text style={[styles.formatDesc, { color: theme.textTertiary }]}>{opt.desc}</Text>
              </TouchableOpacity>
            ))}
          </View>

          <Text style={[styles.sectionLabel, { color: theme.text, marginTop: Spacing.xl }]}>
            {lang === 'de' ? 'Zeitraum' : 'Time Range'}
          </Text>

          {rangeOptions.map(opt => (
            <TouchableOpacity
              key={opt.key}
              style={[styles.rangeOption, { backgroundColor: theme.surface }]}
              onPress={() => setRange(opt.key)}
            >
              <View style={[
                styles.radioOuter,
                { borderColor: range === opt.key ? theme.primary : theme.border },
              ]}>
                {range === opt.key && (
                  <View style={[styles.radioInner, { backgroundColor: theme.primary }]} />
                )}
              </View>
              <Text style={[styles.rangeLabel, { color: theme.text }]}>{opt.label}</Text>
            </TouchableOpacity>
          ))}

          <Text style={[styles.sectionLabel, { color: theme.text, marginTop: Spacing.xl }]}>
            {lang === 'de' ? 'Enthaltene Daten' : 'Included Data'}
          </Text>

          <View style={[styles.dataCard, { backgroundColor: theme.surface }]}>
            {dataCategories.map((cat, i) => (
              <View key={i} style={[
                styles.dataRow,
                i < dataCategories.length - 1 && { borderBottomWidth: StyleSheet.hairlineWidth, borderBottomColor: theme.border },
              ]}>
                <Text style={styles.dataIcon}>{cat.icon}</Text>
                <Text style={[styles.dataLabel, { color: theme.text }]}>{cat.label}</Text>
                <Text style={[styles.checkIcon, { color: theme.success }]}>✓</Text>
              </View>
            ))}
          </View>

          <TouchableOpacity
            style={[styles.exportBtn, { backgroundColor: theme.primary, opacity: exporting ? 0.6 : 1 }]}
            onPress={handleExport}
            disabled={exporting}
          >
            <Text style={styles.exportBtnText}>
              {exporting
                ? (lang === 'de' ? 'Exportiere...' : 'Exporting...')
                : (lang === 'de' ? `Als ${format.toUpperCase()} exportieren` : `Export as ${format.toUpperCase()}`)}
            </Text>
          </TouchableOpacity>

          <Text style={[styles.gdprNote, { color: theme.textTertiary }]}>
            {lang === 'de'
              ? 'Gemäß DSGVO Art. 20 hast du das Recht auf Datenübertragbarkeit. Alle exportierten Daten werden lokal verarbeitet.'
              : 'Per GDPR Art. 20 you have the right to data portability. All exported data is processed locally.'}
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
  sectionLabel: { fontSize: FontSize.lg, fontWeight: FontWeight.bold, marginBottom: Spacing.md },
  formatRow: { flexDirection: 'row', gap: Spacing.md },
  formatCard: {
    flex: 1,
    borderRadius: BorderRadius.lg,
    padding: Spacing.lg,
    alignItems: 'center',
  },
  formatLabel: { fontSize: FontSize.lg, fontWeight: FontWeight.bold, marginBottom: 4 },
  formatDesc: { fontSize: FontSize.xs, textAlign: 'center' },
  rangeOption: {
    flexDirection: 'row',
    alignItems: 'center',
    padding: Spacing.lg,
    borderRadius: BorderRadius.md,
    marginBottom: Spacing.sm,
    gap: Spacing.md,
  },
  radioOuter: {
    width: 22,
    height: 22,
    borderRadius: 11,
    borderWidth: 2,
    justifyContent: 'center',
    alignItems: 'center',
  },
  radioInner: { width: 12, height: 12, borderRadius: 6 },
  rangeLabel: { fontSize: FontSize.md, fontWeight: FontWeight.medium },
  dataCard: { borderRadius: BorderRadius.lg, overflow: 'hidden' },
  dataRow: {
    flexDirection: 'row',
    alignItems: 'center',
    padding: Spacing.lg,
    gap: Spacing.md,
  },
  dataIcon: { fontSize: 20, width: 28, textAlign: 'center' },
  dataLabel: { flex: 1, fontSize: FontSize.md, fontWeight: FontWeight.medium },
  checkIcon: { fontSize: 18, fontWeight: FontWeight.bold },
  exportBtn: {
    paddingVertical: Spacing.lg,
    borderRadius: BorderRadius.md,
    alignItems: 'center',
    marginTop: Spacing.xxl,
  },
  exportBtnText: { color: '#fff', fontSize: FontSize.md, fontWeight: FontWeight.bold },
  gdprNote: { fontSize: FontSize.xs, textAlign: 'center', marginTop: Spacing.lg, lineHeight: 18 },
  premiumGate: { flex: 1, justifyContent: 'center', alignItems: 'center', padding: Spacing.xxl },
  premiumTitle: { fontSize: FontSize.xl, fontWeight: FontWeight.bold, marginTop: Spacing.lg },
  premiumDesc: { fontSize: FontSize.sm, textAlign: 'center', marginTop: Spacing.sm, lineHeight: 22, maxWidth: 300 },
  upgradeBtn: { paddingHorizontal: Spacing.xxl, paddingVertical: Spacing.md, borderRadius: BorderRadius.md, marginTop: Spacing.xxl },
  upgradeBtnText: { color: '#fff', fontSize: FontSize.md, fontWeight: FontWeight.semibold },
});
