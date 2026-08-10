import React, { useState } from 'react';
import {
  View,
  Text,
  ScrollView,
  StyleSheet,
  TouchableOpacity,
  TextInput,
  Modal,
  Platform,
} from 'react-native';
import Svg, { Polyline, Line, Text as SvgText } from 'react-native-svg';
import { useTheme } from '../hooks/useTheme';
import { useStore } from '../store';
import { t } from '../i18n';
import { BorderRadius, FontSize, FontWeight, Spacing } from '../constants/theme';

export default function ProgressScreen() {
  const theme = useTheme();
  const weights = useStore(s => s.weights);
  const profile = useStore(s => s.profile);
  const addWeight = useStore(s => s.addWeight);
  const streak = useStore(s => s.streak);
  const badges = useStore(s => s.badges);

  const [showAddWeight, setShowAddWeight] = useState(false);
  const [newWeight, setNewWeight] = useState(String(profile?.currentWeight || ''));
  const [activeTab, setActiveTab] = useState<'weight' | 'streaks'>('weight');

  const handleAddWeight = async () => {
    const w = parseFloat(newWeight);
    if (w > 0 && w < 500) {
      await addWeight(w);
      setShowAddWeight(false);
    }
  };

  const lastWeights = weights.slice(-14);
  const currentWeight = profile?.currentWeight || 0;
  const goalWeight = profile?.goalWeight || 0;
  const diff = currentWeight - goalWeight;
  const lastWeek = weights.length >= 2 ? currentWeight - weights[weights.length - 2].weight : 0;

  const chartWidth = 320;
  const chartHeight = 160;
  const chartPadding = 30;

  const renderWeightChart = () => {
    if (lastWeights.length < 2) {
      return (
        <View style={[styles.chartPlaceholder, { backgroundColor: theme.surfaceSecondary }]}>
          <Text style={[styles.chartPlaceholderText, { color: theme.textTertiary }]}>
            {weights.length === 0 ? 'Trage dein Gewicht ein, um den Verlauf zu sehen' : 'Mindestens 2 Einträge nötig'}
          </Text>
        </View>
      );
    }

    const values = lastWeights.map(w => w.weight);
    const minVal = Math.min(...values) - 1;
    const maxVal = Math.max(...values) + 1;
    const range = maxVal - minVal || 1;

    const points = values.map((val, i) => {
      const x = chartPadding + (i / (values.length - 1)) * (chartWidth - chartPadding * 2);
      const y = chartPadding + ((maxVal - val) / range) * (chartHeight - chartPadding * 2);
      return `${x},${y}`;
    }).join(' ');

    return (
      <Svg width={chartWidth} height={chartHeight}>
        {[0, 0.25, 0.5, 0.75, 1].map((frac, i) => {
          const y = chartPadding + frac * (chartHeight - chartPadding * 2);
          const val = (maxVal - frac * range).toFixed(1);
          return (
            <React.Fragment key={i}>
              <Line
                x1={chartPadding}
                y1={y}
                x2={chartWidth - chartPadding}
                y2={y}
                stroke={theme.border}
                strokeWidth={0.5}
              />
              <SvgText
                x={4}
                y={y + 4}
                fontSize={9}
                fill={theme.textTertiary}
              >
                {val}
              </SvgText>
            </React.Fragment>
          );
        })}
        <Polyline
          points={points}
          fill="none"
          stroke={theme.primary}
          strokeWidth={2.5}
          strokeLinecap="round"
          strokeLinejoin="round"
        />
      </Svg>
    );
  };

  return (
    <ScrollView
      style={[styles.container, { backgroundColor: theme.background }]}
      contentContainerStyle={styles.content}
      showsVerticalScrollIndicator={false}
    >
      <Text style={[styles.title, { color: theme.text }]}>{t('tabs.progress')}</Text>

      <View style={styles.tabRow}>
        <TouchableOpacity
          style={[styles.tabBtn, activeTab === 'weight' && { borderBottomColor: theme.primary, borderBottomWidth: 2 }]}
          onPress={() => setActiveTab('weight')}
        >
          <Text style={[styles.tabText, { color: activeTab === 'weight' ? theme.primary : theme.textTertiary }]}>
            {t('weight.title')}
          </Text>
        </TouchableOpacity>
        <TouchableOpacity
          style={[styles.tabBtn, activeTab === 'streaks' && { borderBottomColor: theme.primary, borderBottomWidth: 2 }]}
          onPress={() => setActiveTab('streaks')}
        >
          <Text style={[styles.tabText, { color: activeTab === 'streaks' ? theme.primary : theme.textTertiary }]}>
            {t('streaks.title')}
          </Text>
        </TouchableOpacity>
      </View>

      {activeTab === 'weight' ? (
        <>
          <View style={styles.weightCards}>
            <View style={[styles.weightCard, { backgroundColor: theme.surface, shadowColor: theme.cardShadow }]}>
              <Text style={[styles.weightCardLabel, { color: theme.textTertiary }]}>{t('weight.current')}</Text>
              <Text style={[styles.weightCardValue, { color: theme.text }]}>{currentWeight} kg</Text>
            </View>
            <View style={[styles.weightCard, { backgroundColor: theme.surface, shadowColor: theme.cardShadow }]}>
              <Text style={[styles.weightCardLabel, { color: theme.textTertiary }]}>{t('weight.goal')}</Text>
              <Text style={[styles.weightCardValue, { color: theme.primary }]}>{goalWeight} kg</Text>
            </View>
            <View style={[styles.weightCard, { backgroundColor: theme.surface, shadowColor: theme.cardShadow }]}>
              <Text style={[styles.weightCardLabel, { color: theme.textTertiary }]}>{t('weight.change')}</Text>
              <Text style={[styles.weightCardValue, { color: lastWeek <= 0 ? theme.success : theme.error }]}>
                {lastWeek > 0 ? '+' : ''}{lastWeek.toFixed(1)} kg
              </Text>
            </View>
            <View style={[styles.weightCard, { backgroundColor: theme.surface, shadowColor: theme.cardShadow }]}>
              <Text style={[styles.weightCardLabel, { color: theme.textTertiary }]}>{t('weight.toGoal')}</Text>
              <Text style={[styles.weightCardValue, { color: theme.accent }]}>
                {Math.abs(diff).toFixed(1)} kg
              </Text>
            </View>
          </View>

          <View style={[styles.chartCard, { backgroundColor: theme.surface, shadowColor: theme.cardShadow }]}>
            <Text style={[styles.chartTitle, { color: theme.text }]}>{t('weight.history')}</Text>
            <View style={styles.chartContainer}>{renderWeightChart()}</View>
          </View>

          <TouchableOpacity
            style={[styles.addWeightBtn, { backgroundColor: theme.primary }]}
            onPress={() => {
              setNewWeight(String(currentWeight));
              setShowAddWeight(true);
            }}
          >
            <Text style={styles.addWeightBtnText}>{t('weight.addWeight')}</Text>
          </TouchableOpacity>

          {weights.length > 0 && (
            <View style={[styles.historyCard, { backgroundColor: theme.surface, shadowColor: theme.cardShadow }]}>
              <Text style={[styles.chartTitle, { color: theme.text }]}>{t('weight.history')}</Text>
              {[...weights].reverse().slice(0, 10).map((entry, i) => (
                <View
                  key={entry.date}
                  style={[styles.historyRow, i > 0 && { borderTopColor: theme.border, borderTopWidth: StyleSheet.hairlineWidth }]}
                >
                  <Text style={[styles.historyDate, { color: theme.textSecondary }]}>{entry.date}</Text>
                  <Text style={[styles.historyWeight, { color: theme.text }]}>{entry.weight} kg</Text>
                </View>
              ))}
            </View>
          )}
        </>
      ) : (
        <>
          <View style={styles.streakCards}>
            <View style={[styles.streakCard, { backgroundColor: theme.surface, shadowColor: theme.cardShadow }]}>
              <Text style={styles.streakEmoji}>🔥</Text>
              <Text style={[styles.streakValue, { color: theme.accent }]}>{streak.currentStreak}</Text>
              <Text style={[styles.streakLabel, { color: theme.textTertiary }]}>{t('streaks.currentStreak')}</Text>
            </View>
            <View style={[styles.streakCard, { backgroundColor: theme.surface, shadowColor: theme.cardShadow }]}>
              <Text style={styles.streakEmoji}>🏆</Text>
              <Text style={[styles.streakValue, { color: theme.primary }]}>{streak.longestStreak}</Text>
              <Text style={[styles.streakLabel, { color: theme.textTertiary }]}>{t('streaks.longestStreak')}</Text>
            </View>
          </View>

          <View style={[styles.badgesCard, { backgroundColor: theme.surface, shadowColor: theme.cardShadow }]}>
            <Text style={[styles.chartTitle, { color: theme.text }]}>{t('streaks.badges')}</Text>
            {badges.map(badge => (
              <View
                key={badge.id}
                style={[styles.badgeRow, { opacity: badge.earned ? 1 : 0.4 }]}
              >
                <View style={[styles.badgeIcon, {
                  backgroundColor: badge.earned ? theme.primary + '20' : theme.surfaceSecondary,
                }]}>
                  <Text style={[styles.badgeIconText, { color: badge.earned ? theme.primary : theme.textTertiary }]}>
                    {badge.icon}
                  </Text>
                </View>
                <View style={styles.badgeInfo}>
                  <Text style={[styles.badgeName, { color: theme.text }]}>{badge.name}</Text>
                  <Text style={[styles.badgeDesc, { color: theme.textTertiary }]}>{badge.description}</Text>
                </View>
                {badge.earned && <Text style={styles.badgeCheck}>✓</Text>}
              </View>
            ))}
          </View>
        </>
      )}

      <View style={{ height: 100 }} />

      <Modal visible={showAddWeight} transparent animationType="fade">
        <View style={[styles.modalOverlay, { backgroundColor: theme.overlay }]}>
          <View style={[styles.modalContent, { backgroundColor: theme.surface }]}>
            <Text style={[styles.modalTitle, { color: theme.text }]}>{t('weight.addWeight')}</Text>
            <TextInput
              style={[styles.weightInput, { color: theme.text, borderColor: theme.border }]}
              value={newWeight}
              onChangeText={setNewWeight}
              keyboardType="decimal-pad"
              selectTextOnFocus
              autoFocus
            />
            <Text style={[styles.weightUnit, { color: theme.textTertiary }]}>kg</Text>
            <View style={styles.modalButtons}>
              <TouchableOpacity
                style={[styles.modalBtn, { backgroundColor: theme.surfaceSecondary }]}
                onPress={() => setShowAddWeight(false)}
              >
                <Text style={[styles.modalBtnText, { color: theme.text }]}>{t('common.cancel')}</Text>
              </TouchableOpacity>
              <TouchableOpacity
                style={[styles.modalBtn, { backgroundColor: theme.primary }]}
                onPress={handleAddWeight}
              >
                <Text style={[styles.modalBtnText, { color: '#fff' }]}>{t('common.save')}</Text>
              </TouchableOpacity>
            </View>
          </View>
        </View>
      </Modal>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1 },
  content: { padding: Spacing.lg, paddingTop: Spacing.xxl },
  title: { fontSize: FontSize.xxl, fontWeight: FontWeight.bold, marginBottom: Spacing.lg },
  tabRow: { flexDirection: 'row', marginBottom: Spacing.xl },
  tabBtn: { flex: 1, alignItems: 'center', paddingBottom: Spacing.sm, borderBottomWidth: 2, borderBottomColor: 'transparent' },
  tabText: { fontSize: FontSize.md, fontWeight: FontWeight.semibold },
  weightCards: { flexDirection: 'row', flexWrap: 'wrap', gap: Spacing.md, marginBottom: Spacing.lg },
  weightCard: {
    width: '47%',
    borderRadius: BorderRadius.lg,
    padding: Spacing.lg,
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 1,
    shadowRadius: 6,
    elevation: 3,
  },
  weightCardLabel: { fontSize: FontSize.xs, fontWeight: FontWeight.medium, marginBottom: 4 },
  weightCardValue: { fontSize: FontSize.xl, fontWeight: FontWeight.bold },
  chartCard: {
    borderRadius: BorderRadius.lg,
    padding: Spacing.lg,
    marginBottom: Spacing.lg,
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 1,
    shadowRadius: 6,
    elevation: 3,
  },
  chartTitle: { fontSize: FontSize.lg, fontWeight: FontWeight.semibold, marginBottom: Spacing.md },
  chartContainer: { alignItems: 'center' },
  chartPlaceholder: {
    width: 320,
    height: 160,
    borderRadius: BorderRadius.md,
    justifyContent: 'center',
    alignItems: 'center',
    padding: Spacing.lg,
  },
  chartPlaceholderText: { fontSize: FontSize.sm, textAlign: 'center' },
  addWeightBtn: {
    borderRadius: BorderRadius.lg,
    paddingVertical: Spacing.lg,
    alignItems: 'center',
    marginBottom: Spacing.lg,
  },
  addWeightBtnText: { color: '#fff', fontSize: FontSize.md, fontWeight: FontWeight.semibold },
  historyCard: {
    borderRadius: BorderRadius.lg,
    padding: Spacing.lg,
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 1,
    shadowRadius: 6,
    elevation: 3,
  },
  historyRow: { flexDirection: 'row', justifyContent: 'space-between', paddingVertical: Spacing.md },
  historyDate: { fontSize: FontSize.sm },
  historyWeight: { fontSize: FontSize.sm, fontWeight: FontWeight.semibold },
  streakCards: { flexDirection: 'row', gap: Spacing.md, marginBottom: Spacing.lg },
  streakCard: {
    flex: 1,
    borderRadius: BorderRadius.lg,
    padding: Spacing.xl,
    alignItems: 'center',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 1,
    shadowRadius: 6,
    elevation: 3,
  },
  streakEmoji: { fontSize: 32, marginBottom: Spacing.sm },
  streakValue: { fontSize: FontSize.xxxl, fontWeight: FontWeight.heavy },
  streakLabel: { fontSize: FontSize.xs, fontWeight: FontWeight.medium, marginTop: 4, textAlign: 'center' },
  badgesCard: {
    borderRadius: BorderRadius.lg,
    padding: Spacing.lg,
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 1,
    shadowRadius: 6,
    elevation: 3,
  },
  badgeRow: { flexDirection: 'row', alignItems: 'center', paddingVertical: Spacing.md },
  badgeIcon: {
    width: 44,
    height: 44,
    borderRadius: BorderRadius.full,
    justifyContent: 'center',
    alignItems: 'center',
    marginRight: Spacing.md,
  },
  badgeIconText: { fontSize: FontSize.md, fontWeight: FontWeight.bold },
  badgeInfo: { flex: 1 },
  badgeName: { fontSize: FontSize.sm, fontWeight: FontWeight.semibold },
  badgeDesc: { fontSize: FontSize.xs, marginTop: 2 },
  badgeCheck: { fontSize: 18, color: '#10B981' },
  modalOverlay: { flex: 1, justifyContent: 'center', alignItems: 'center' },
  modalContent: { width: 300, borderRadius: BorderRadius.xl, padding: Spacing.xxl, alignItems: 'center' },
  modalTitle: { fontSize: FontSize.lg, fontWeight: FontWeight.semibold, marginBottom: Spacing.xl },
  weightInput: {
    width: 120,
    height: 56,
    borderWidth: 2,
    borderRadius: BorderRadius.md,
    textAlign: 'center',
    fontSize: FontSize.xxl,
    fontWeight: FontWeight.bold,
  },
  weightUnit: { fontSize: FontSize.md, marginTop: Spacing.xs },
  modalButtons: { flexDirection: 'row', gap: Spacing.md, marginTop: Spacing.xxl, width: '100%' },
  modalBtn: { flex: 1, paddingVertical: Spacing.md, borderRadius: BorderRadius.md, alignItems: 'center' },
  modalBtnText: { fontSize: FontSize.md, fontWeight: FontWeight.semibold },
});
