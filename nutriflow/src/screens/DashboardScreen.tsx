import React from 'react';
import { View, Text, ScrollView, StyleSheet, TouchableOpacity } from 'react-native';
import { useNavigation } from '@react-navigation/native';
import { useTheme } from '../hooks/useTheme';
import { useStore } from '../store';
import { t } from '../i18n';
import ProgressRing from '../components/ProgressRing';
import ProgressBar from '../components/ProgressBar';
import WaterCard from '../components/WaterCard';
import { BorderRadius, FontSize, FontWeight, Spacing } from '../constants/theme';

export default function DashboardScreen() {
  const theme = useTheme();
  const navigation = useNavigation<any>();
  const goals = useStore(s => s.goals);
  const totals = useStore(s => s.getDailyTotals());
  const profile = useStore(s => s.profile);
  const dailyWater = useStore(s => s.getDailyWater());
  const streak = useStore(s => s.streak);

  const remaining = Math.max(goals.calories - totals.calories, 0);
  const calorieProgress = goals.calories > 0 ? totals.calories / goals.calories : 0;
  const dailyPercent = Math.min(Math.round(calorieProgress * 100), 100);

  return (
    <ScrollView
      style={[styles.container, { backgroundColor: theme.background }]}
      contentContainerStyle={styles.content}
      showsVerticalScrollIndicator={false}
    >
      <View style={styles.headerRow}>
        <View>
          <Text style={[styles.greeting, { color: theme.textSecondary }]}>
            {t('common.today')}
          </Text>
          <Text style={[styles.title, { color: theme.text }]}>
            {t('tabs.dashboard')}
          </Text>
        </View>
        {streak.currentStreak > 0 && (
          <View style={[styles.streakBadge, { backgroundColor: theme.accent + '20' }]}>
            <Text style={styles.streakIcon}>🔥</Text>
            <Text style={[styles.streakText, { color: theme.accent }]}>
              {streak.currentStreak}
            </Text>
          </View>
        )}
      </View>

      <View style={[styles.calorieCard, { backgroundColor: theme.surface, shadowColor: theme.cardShadow }]}>
        <View style={styles.calorieCenter}>
          <ProgressRing
            size={160}
            strokeWidth={12}
            progress={calorieProgress}
            color={theme.primary}
            bgColor={theme.surfaceSecondary}
            textColor={theme.text}
            value={String(remaining)}
            label={t('dashboard.remaining')}
            labelColor={theme.textSecondary}
          />
        </View>

        <View style={styles.calorieStats}>
          <View style={styles.calorieStat}>
            <Text style={[styles.calorieStatValue, { color: theme.primary }]}>
              {totals.calories}
            </Text>
            <Text style={[styles.calorieStatLabel, { color: theme.textTertiary }]}>
              {t('dashboard.eaten')}
            </Text>
          </View>
          <View style={[styles.calorieDivider, { backgroundColor: theme.border }]} />
          <View style={styles.calorieStat}>
            <Text style={[styles.calorieStatValue, { color: theme.text }]}>
              {goals.calories}
            </Text>
            <Text style={[styles.calorieStatLabel, { color: theme.textTertiary }]}>
              {t('dashboard.calories')}
            </Text>
          </View>
        </View>

        <View style={[styles.progressContainer, { backgroundColor: theme.surfaceSecondary }]}>
          <View style={[styles.progressFill, { backgroundColor: theme.primary, width: `${dailyPercent}%` }]} />
        </View>
        <Text style={[styles.progressLabel, { color: theme.textTertiary }]}>
          {t('dashboard.dailyProgress')}: {dailyPercent}%
        </Text>
      </View>

      <View style={[styles.macroCard, { backgroundColor: theme.surface, shadowColor: theme.cardShadow }]}>
        <Text style={[styles.sectionTitle, { color: theme.text }]}>Makros</Text>
        <ProgressBar label={t('dashboard.protein')} current={totals.protein} goal={goals.protein} color={theme.protein} />
        <ProgressBar label={t('dashboard.carbs')} current={totals.carbs} goal={goals.carbs} color={theme.carbs} />
        <ProgressBar label={t('dashboard.fat')} current={totals.fat} goal={goals.fat} color={theme.fat} />
        <ProgressBar label={t('dashboard.fiber')} current={totals.fiber} goal={goals.fiber} color={theme.fiber} />
      </View>

      <View style={styles.quickStats}>
        <TouchableOpacity
          style={[styles.quickStatCard, { backgroundColor: theme.surface, shadowColor: theme.cardShadow }]}
          onPress={() => navigation.navigate('Progress')}
          activeOpacity={0.7}
        >
          <Text style={styles.quickStatIcon}>⚖️</Text>
          <Text style={[styles.quickStatValue, { color: theme.text }]}>
            {profile?.currentWeight || '—'} kg
          </Text>
          <Text style={[styles.quickStatLabel, { color: theme.textTertiary }]}>
            {t('dashboard.weight')}
          </Text>
        </TouchableOpacity>

        <TouchableOpacity
          style={[styles.quickStatCard, { backgroundColor: theme.surface, shadowColor: theme.cardShadow }]}
          activeOpacity={0.7}
        >
          <Text style={styles.quickStatIcon}>💧</Text>
          <Text style={[styles.quickStatValue, { color: theme.text }]}>
            {(dailyWater / 1000).toFixed(1)} L
          </Text>
          <Text style={[styles.quickStatLabel, { color: theme.textTertiary }]}>
            {t('dashboard.water')}
          </Text>
        </TouchableOpacity>
      </View>

      <WaterCard />

      <TouchableOpacity
        style={[styles.addButton, { backgroundColor: theme.primary }]}
        onPress={() => navigation.navigate('Diary')}
        activeOpacity={0.8}
      >
        <Text style={styles.addButtonText}>+ {t('meals.addFood')}</Text>
      </TouchableOpacity>

      <View style={{ height: 32 }} />
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  content: {
    padding: Spacing.lg,
    paddingTop: Spacing.xxl,
  },
  headerRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: Spacing.xl,
  },
  greeting: {
    fontSize: FontSize.sm,
    fontWeight: FontWeight.medium,
  },
  title: {
    fontSize: FontSize.xxl,
    fontWeight: FontWeight.bold,
  },
  streakBadge: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: Spacing.md,
    paddingVertical: Spacing.xs,
    borderRadius: BorderRadius.full,
    gap: 4,
  },
  streakIcon: {
    fontSize: 16,
  },
  streakText: {
    fontSize: FontSize.md,
    fontWeight: FontWeight.bold,
  },
  calorieCard: {
    borderRadius: BorderRadius.xl,
    padding: Spacing.xl,
    marginBottom: Spacing.lg,
    alignItems: 'center',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 1,
    shadowRadius: 12,
    elevation: 5,
  },
  calorieCenter: {
    marginBottom: Spacing.xl,
  },
  calorieStats: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.xxl,
    marginBottom: Spacing.lg,
  },
  calorieStat: {
    alignItems: 'center',
  },
  calorieStatValue: {
    fontSize: FontSize.xl,
    fontWeight: FontWeight.bold,
  },
  calorieStatLabel: {
    fontSize: FontSize.xs,
    fontWeight: FontWeight.medium,
    marginTop: 2,
  },
  calorieDivider: {
    width: 1,
    height: 32,
  },
  progressContainer: {
    width: '100%',
    height: 6,
    borderRadius: BorderRadius.full,
    overflow: 'hidden',
  },
  progressFill: {
    height: '100%',
    borderRadius: BorderRadius.full,
  },
  progressLabel: {
    fontSize: FontSize.xs,
    fontWeight: FontWeight.medium,
    marginTop: Spacing.xs,
  },
  macroCard: {
    borderRadius: BorderRadius.xl,
    padding: Spacing.xl,
    marginBottom: Spacing.lg,
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 1,
    shadowRadius: 8,
    elevation: 3,
  },
  sectionTitle: {
    fontSize: FontSize.lg,
    fontWeight: FontWeight.semibold,
    marginBottom: Spacing.lg,
  },
  quickStats: {
    flexDirection: 'row',
    gap: Spacing.md,
    marginBottom: Spacing.lg,
  },
  quickStatCard: {
    flex: 1,
    borderRadius: BorderRadius.lg,
    padding: Spacing.lg,
    alignItems: 'center',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 1,
    shadowRadius: 8,
    elevation: 3,
  },
  quickStatIcon: {
    fontSize: 24,
    marginBottom: Spacing.xs,
  },
  quickStatValue: {
    fontSize: FontSize.lg,
    fontWeight: FontWeight.bold,
  },
  quickStatLabel: {
    fontSize: FontSize.xs,
    fontWeight: FontWeight.medium,
    marginTop: 2,
  },
  addButton: {
    borderRadius: BorderRadius.lg,
    paddingVertical: Spacing.lg,
    alignItems: 'center',
    marginTop: Spacing.sm,
  },
  addButtonText: {
    color: '#fff',
    fontSize: FontSize.md,
    fontWeight: FontWeight.semibold,
  },
});
