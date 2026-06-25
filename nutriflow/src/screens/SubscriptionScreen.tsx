import React from 'react';
import {
  View,
  Text,
  ScrollView,
  StyleSheet,
  TouchableOpacity,
  Platform,
} from 'react-native';
import { useTheme } from '../hooks/useTheme';
import { useStore } from '../store';
import { t } from '../i18n';
import { SubscriptionTier } from '../types';
import { BorderRadius, FontSize, FontWeight, Spacing } from '../constants/theme';

interface Props {
  onClose: () => void;
}

interface PlanInfo {
  tier: SubscriptionTier;
  name: string;
  price: string;
  period: string;
  features: string[];
  highlight?: boolean;
}

export default function SubscriptionScreen({ onClose }: Props) {
  const theme = useTheme();
  const settings = useStore(s => s.settings);
  const updateSettings = useStore(s => s.updateSettings);
  const lang = settings.language;

  const plans: PlanInfo[] = [
    {
      tier: 'free',
      name: lang === 'de' ? 'Kostenlos' : 'Free',
      price: '0€',
      period: '',
      features: lang === 'de'
        ? ['Kalorien Tracking', 'Barcode Scanner', 'Gewichtstracking', 'Makro Tracking', 'Wasser Tracking', 'Favoriten', 'Eigene Mahlzeiten', 'Dark Mode']
        : ['Calorie Tracking', 'Barcode Scanner', 'Weight Tracking', 'Macro Tracking', 'Water Tracking', 'Favorites', 'Custom Meals', 'Dark Mode'],
    },
    {
      tier: 'student',
      name: 'Student',
      price: '2,99€',
      period: lang === 'de' ? '/Monat' : '/month',
      features: lang === 'de'
        ? ['Alles aus Free', 'Werbefrei', 'Erweiterte Statistiken', 'Unbegrenzte Historie', 'Health Integrationen']
        : ['Everything in Free', 'Ad-free', 'Extended Statistics', 'Unlimited History', 'Health Integrations'],
    },
    {
      tier: 'premium',
      name: 'Premium',
      price: '6,99€',
      period: lang === 'de' ? '/Monat' : '/month',
      features: lang === 'de'
        ? ['Alles aus Student', 'Mahlzeitenplanung', 'Einkaufslisten', 'Datenexport (CSV/PDF)', 'Erweiterte Analysen', 'Gewichtsprognosen', 'Challenges', 'Premium Statistiken']
        : ['Everything in Student', 'Meal Planning', 'Shopping Lists', 'Data Export (CSV/PDF)', 'Advanced Analytics', 'Weight Predictions', 'Challenges', 'Premium Statistics'],
      highlight: true,
    },
    {
      tier: 'lifetime',
      name: 'Lifetime',
      price: '79€',
      period: lang === 'de' ? 'einmalig' : 'one-time',
      features: lang === 'de'
        ? ['Alle Premium-Funktionen', 'Dauerhaft freigeschaltet', 'Keine weiteren Kosten', 'Alle zukünftigen Features']
        : ['All Premium Features', 'Permanently unlocked', 'No recurring costs', 'All future features'],
    },
  ];

  const handleSelect = async (tier: SubscriptionTier) => {
    await updateSettings({ subscription: tier });
  };

  return (
    <View style={[styles.container, { backgroundColor: theme.background }]}>
      <View style={[styles.header, { borderBottomColor: theme.border }]}>
        <TouchableOpacity onPress={onClose}>
          <Text style={[styles.closeBtn, { color: theme.primary }]}>✕</Text>
        </TouchableOpacity>
        <Text style={[styles.headerTitle, { color: theme.text }]}>NutriFlow Pro</Text>
        <View style={{ width: 40 }} />
      </View>

      <ScrollView contentContainerStyle={styles.content} showsVerticalScrollIndicator={false}>
        <Text style={[styles.heroTitle, { color: theme.text }]}>
          {lang === 'de' ? 'Upgrade dein Tracking' : 'Upgrade Your Tracking'}
        </Text>
        <Text style={[styles.heroSubtitle, { color: theme.textSecondary }]}>
          {lang === 'de'
            ? 'Schalte erweiterte Features frei und erreiche deine Ziele schneller.'
            : 'Unlock advanced features and reach your goals faster.'}
        </Text>

        {plans.map(plan => {
          const isActive = settings.subscription === plan.tier;
          return (
            <TouchableOpacity
              key={plan.tier}
              style={[
                styles.planCard,
                {
                  backgroundColor: theme.surface,
                  borderColor: plan.highlight ? theme.primary : isActive ? theme.success : theme.border,
                  borderWidth: plan.highlight || isActive ? 2 : 1,
                  shadowColor: theme.cardShadow,
                },
              ]}
              onPress={() => handleSelect(plan.tier)}
              activeOpacity={0.7}
            >
              {plan.highlight && (
                <View style={[styles.popularBadge, { backgroundColor: theme.primary }]}>
                  <Text style={styles.popularText}>
                    {lang === 'de' ? 'BELIEBT' : 'POPULAR'}
                  </Text>
                </View>
              )}
              {isActive && (
                <View style={[styles.activeBadge, { backgroundColor: theme.success }]}>
                  <Text style={styles.popularText}>
                    {lang === 'de' ? 'AKTIV' : 'ACTIVE'}
                  </Text>
                </View>
              )}

              <View style={styles.planHeader}>
                <Text style={[styles.planName, { color: theme.text }]}>{plan.name}</Text>
                <View style={styles.planPricing}>
                  <Text style={[styles.planPrice, { color: theme.primary }]}>{plan.price}</Text>
                  {plan.period ? (
                    <Text style={[styles.planPeriod, { color: theme.textTertiary }]}>{plan.period}</Text>
                  ) : null}
                </View>
              </View>

              <View style={styles.planFeatures}>
                {plan.features.map((feature, i) => (
                  <View key={i} style={styles.featureRow}>
                    <Text style={[styles.featureCheck, { color: theme.primary }]}>✓</Text>
                    <Text style={[styles.featureText, { color: theme.textSecondary }]}>{feature}</Text>
                  </View>
                ))}
              </View>
            </TouchableOpacity>
          );
        })}

        <Text style={[styles.yearlyNote, { color: theme.textTertiary }]}>
          {lang === 'de'
            ? 'Premium auch als Jahresabo: 49,99€/Jahr (spart 40%)'
            : 'Premium also available yearly: €49.99/year (save 40%)'}
        </Text>

        <View style={{ height: 40 }} />
      </ScrollView>
    </View>
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
  heroTitle: {
    fontSize: FontSize.xxl,
    fontWeight: FontWeight.bold,
    textAlign: 'center',
    marginBottom: Spacing.sm,
    marginTop: Spacing.lg,
  },
  heroSubtitle: {
    fontSize: FontSize.sm,
    textAlign: 'center',
    marginBottom: Spacing.xxl,
    lineHeight: 20,
  },
  planCard: {
    borderRadius: BorderRadius.xl,
    padding: Spacing.xl,
    marginBottom: Spacing.md,
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 1,
    shadowRadius: 8,
    elevation: 3,
    overflow: 'hidden',
  },
  popularBadge: {
    position: 'absolute',
    top: 0,
    right: 0,
    paddingHorizontal: Spacing.md,
    paddingVertical: 4,
    borderBottomLeftRadius: BorderRadius.sm,
  },
  activeBadge: {
    position: 'absolute',
    top: 0,
    right: 0,
    paddingHorizontal: Spacing.md,
    paddingVertical: 4,
    borderBottomLeftRadius: BorderRadius.sm,
  },
  popularText: { color: '#fff', fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5 },
  planHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: Spacing.md,
  },
  planName: { fontSize: FontSize.lg, fontWeight: FontWeight.bold },
  planPricing: { alignItems: 'flex-end' },
  planPrice: { fontSize: FontSize.xl, fontWeight: FontWeight.bold },
  planPeriod: { fontSize: FontSize.xs },
  planFeatures: { gap: Spacing.sm },
  featureRow: { flexDirection: 'row', alignItems: 'center', gap: Spacing.sm },
  featureCheck: { fontSize: 14, fontWeight: FontWeight.bold },
  featureText: { fontSize: FontSize.sm },
  yearlyNote: {
    fontSize: FontSize.xs,
    textAlign: 'center',
    marginTop: Spacing.lg,
    fontStyle: 'italic',
  },
});
