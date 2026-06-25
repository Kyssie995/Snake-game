import React, { useMemo, useState } from 'react';
import { View, Text, ScrollView, StyleSheet, TouchableOpacity } from 'react-native';
import Svg, { Rect, Line, Text as SvgText } from 'react-native-svg';
import { useTheme } from '../hooks/useTheme';
import { useStore } from '../store';
import { t } from '../i18n';
import { calculateDailyTotals } from '../utils/calculations';
import { BorderRadius, FontSize, FontWeight, Spacing } from '../constants/theme';
import { subDays, format } from 'date-fns';
import { de, enUS } from 'date-fns/locale';

type Period = 'daily' | 'weekly' | 'monthly';

export default function StatsScreen() {
  const theme = useTheme();
  const meals = useStore(s => s.meals);
  const goals = useStore(s => s.goals);
  const settings = useStore(s => s.settings);
  const [period, setPeriod] = useState<Period>('weekly');

  const locale = settings.language === 'de' ? de : enUS;

  const data = useMemo(() => {
    const today = new Date();
    const days = period === 'daily' ? 1 : period === 'weekly' ? 7 : 30;
    const result: { date: string; label: string; calories: number; protein: number; carbs: number; fat: number }[] = [];

    for (let i = days - 1; i >= 0; i--) {
      const date = subDays(today, i);
      const dateStr = date.toISOString().split('T')[0];
      const dayMeals = meals[dateStr] || [];
      const totals = calculateDailyTotals(dayMeals);
      result.push({
        date: dateStr,
        label: days <= 7 ? format(date, 'EEE', { locale }) : format(date, 'd', { locale }),
        ...totals,
      });
    }
    return result;
  }, [meals, period, locale]);

  const avgCalories = data.length > 0 ? Math.round(data.reduce((s, d) => s + d.calories, 0) / data.length) : 0;
  const avgProtein = data.length > 0 ? Math.round(data.reduce((s, d) => s + d.protein, 0) / data.length) : 0;
  const avgCarbs = data.length > 0 ? Math.round(data.reduce((s, d) => s + d.carbs, 0) / data.length) : 0;
  const avgFat = data.length > 0 ? Math.round(data.reduce((s, d) => s + d.fat, 0) / data.length) : 0;
  const totalCalories = data.reduce((s, d) => s + d.calories, 0);
  const daysTracked = data.filter(d => d.calories > 0).length;
  const goalHitDays = data.filter(d => d.calories > 0 && d.calories <= goals.calories * 1.1).length;

  const chartWidth = 320;
  const chartHeight = 180;
  const chartPadding = 35;
  const maxCal = Math.max(...data.map(d => d.calories), goals.calories, 1);
  const barWidth = period === 'monthly'
    ? Math.max((chartWidth - chartPadding * 2) / data.length - 1, 2)
    : Math.max((chartWidth - chartPadding * 2) / data.length - 4, 8);

  const isPremiumPeriod = period === 'monthly' && settings.subscription === 'free';

  const renderCalorieChart = () => {
    if (isPremiumPeriod) {
      return (
        <View style={[styles.premiumOverlay, { backgroundColor: theme.surfaceSecondary }]}>
          <Text style={{ fontSize: 28 }}>🔒</Text>
          <Text style={[styles.premiumText, { color: theme.textSecondary }]}>
            {settings.language === 'de' ? 'Premium-Feature' : 'Premium Feature'}
          </Text>
          <Text style={[styles.premiumSubtext, { color: theme.textTertiary }]}>
            {settings.language === 'de' ? 'Monats- & Jahresansicht freischalten' : 'Unlock monthly & yearly views'}
          </Text>
        </View>
      );
    }

    return (
      <Svg width={chartWidth} height={chartHeight}>
        <Line
          x1={chartPadding}
          y1={chartHeight - chartPadding}
          x2={chartWidth - 10}
          y2={chartHeight - chartPadding}
          stroke={theme.border}
          strokeWidth={0.5}
        />
        {[0, 0.5, 1].map((frac, i) => {
          const y = chartPadding + frac * (chartHeight - chartPadding * 2);
          const val = Math.round(maxCal * (1 - frac));
          return (
            <React.Fragment key={i}>
              <Line
                x1={chartPadding}
                y1={y}
                x2={chartWidth - 10}
                y2={y}
                stroke={theme.border}
                strokeWidth={0.5}
                strokeDasharray="4,4"
              />
              <SvgText x={2} y={y + 4} fontSize={9} fill={theme.textTertiary}>
                {val}
              </SvgText>
            </React.Fragment>
          );
        })}

        {/* Goal line */}
        {(() => {
          const goalY = chartPadding + ((maxCal - goals.calories) / maxCal) * (chartHeight - chartPadding * 2);
          return (
            <Line
              x1={chartPadding}
              y1={goalY}
              x2={chartWidth - 10}
              y2={goalY}
              stroke={theme.primary}
              strokeWidth={1}
              strokeDasharray="6,3"
              opacity={0.6}
            />
          );
        })()}

        {data.map((d, i) => {
          const barH = maxCal > 0 ? (d.calories / maxCal) * (chartHeight - chartPadding * 2) : 0;
          const x = chartPadding + i * ((chartWidth - chartPadding * 2) / data.length) + 2;
          const y = chartHeight - chartPadding - barH;
          const isOverGoal = d.calories > goals.calories;

          return (
            <React.Fragment key={i}>
              <Rect
                x={x}
                y={y}
                width={barWidth}
                height={Math.max(barH, 0)}
                rx={barWidth > 4 ? 3 : 1}
                fill={d.calories === 0 ? theme.surfaceSecondary : isOverGoal ? theme.warning : theme.primary}
                opacity={d.calories === 0 ? 0.3 : 0.85}
              />
              {period !== 'monthly' && (
                <SvgText
                  x={x + barWidth / 2}
                  y={chartHeight - chartPadding + 14}
                  fontSize={9}
                  fill={theme.textTertiary}
                  textAnchor="middle"
                >
                  {d.label}
                </SvgText>
              )}
            </React.Fragment>
          );
        })}
      </Svg>
    );
  };

  return (
    <ScrollView
      style={[styles.container, { backgroundColor: theme.background }]}
      contentContainerStyle={styles.content}
      showsVerticalScrollIndicator={false}
    >
      <Text style={[styles.title, { color: theme.text }]}>{t('stats.title')}</Text>

      <View style={styles.periodTabs}>
        {(['daily', 'weekly', 'monthly'] as Period[]).map(p => (
          <TouchableOpacity
            key={p}
            style={[
              styles.periodTab,
              period === p && { backgroundColor: theme.primary },
            ]}
            onPress={() => setPeriod(p)}
          >
            <Text style={[
              styles.periodTabText,
              { color: period === p ? '#fff' : theme.textSecondary },
            ]}>
              {t(`stats.${p}`)}
            </Text>
          </TouchableOpacity>
        ))}
      </View>

      <View style={[styles.card, { backgroundColor: theme.surface, shadowColor: theme.cardShadow }]}>
        <Text style={[styles.cardTitle, { color: theme.text }]}>
          {t('dashboard.calories')}
        </Text>
        <View style={styles.chartContainer}>
          {renderCalorieChart()}
        </View>
      </View>

      <View style={styles.statsGrid}>
        <View style={[styles.statCard, { backgroundColor: theme.surface, shadowColor: theme.cardShadow }]}>
          <Text style={[styles.statLabel, { color: theme.textTertiary }]}>
            Ø {t('dashboard.calories')}
          </Text>
          <Text style={[styles.statValue, { color: theme.calories }]}>{avgCalories}</Text>
          <Text style={[styles.statUnit, { color: theme.textTertiary }]}>kcal</Text>
        </View>
        <View style={[styles.statCard, { backgroundColor: theme.surface, shadowColor: theme.cardShadow }]}>
          <Text style={[styles.statLabel, { color: theme.textTertiary }]}>
            {t('stats.total')}
          </Text>
          <Text style={[styles.statValue, { color: theme.text }]}>{totalCalories}</Text>
          <Text style={[styles.statUnit, { color: theme.textTertiary }]}>kcal</Text>
        </View>
        <View style={[styles.statCard, { backgroundColor: theme.surface, shadowColor: theme.cardShadow }]}>
          <Text style={[styles.statLabel, { color: theme.textTertiary }]}>
            {settings.language === 'de' ? 'Getrackt' : 'Tracked'}
          </Text>
          <Text style={[styles.statValue, { color: theme.primary }]}>{daysTracked}</Text>
          <Text style={[styles.statUnit, { color: theme.textTertiary }]}>
            {settings.language === 'de' ? 'Tage' : 'days'}
          </Text>
        </View>
        <View style={[styles.statCard, { backgroundColor: theme.surface, shadowColor: theme.cardShadow }]}>
          <Text style={[styles.statLabel, { color: theme.textTertiary }]}>
            {settings.language === 'de' ? 'Ziel erreicht' : 'Goal hit'}
          </Text>
          <Text style={[styles.statValue, { color: theme.success }]}>{goalHitDays}</Text>
          <Text style={[styles.statUnit, { color: theme.textTertiary }]}>
            {settings.language === 'de' ? 'Tage' : 'days'}
          </Text>
        </View>
      </View>

      <View style={[styles.card, { backgroundColor: theme.surface, shadowColor: theme.cardShadow }]}>
        <Text style={[styles.cardTitle, { color: theme.text }]}>
          Ø Makros
        </Text>
        <MacroRow label={t('dashboard.protein')} value={avgProtein} goal={goals.protein} color={theme.protein} unit="g" bgColor={theme.surfaceSecondary} />
        <MacroRow label={t('dashboard.carbs')} value={avgCarbs} goal={goals.carbs} color={theme.carbs} unit="g" bgColor={theme.surfaceSecondary} />
        <MacroRow label={t('dashboard.fat')} value={avgFat} goal={goals.fat} color={theme.fat} unit="g" bgColor={theme.surfaceSecondary} />
      </View>

      <View style={{ height: 100 }} />
    </ScrollView>
  );
}

function MacroRow({ label, value, goal, color, unit, bgColor }: {
  label: string; value: number; goal: number; color: string; unit: string; bgColor: string;
}) {
  const progress = goal > 0 ? Math.min(value / goal, 1) : 0;
  return (
    <View style={macroStyles.row}>
      <View style={macroStyles.header}>
        <Text style={[macroStyles.label, { color }]}>{label}</Text>
        <Text style={[macroStyles.values, { color }]}>
          {value} / {goal}{unit}
        </Text>
      </View>
      <View style={[macroStyles.track, { backgroundColor: bgColor }]}>
        <View style={[macroStyles.fill, { backgroundColor: color, width: `${progress * 100}%` }]} />
      </View>
    </View>
  );
}

const macroStyles = StyleSheet.create({
  row: { marginBottom: Spacing.md },
  header: { flexDirection: 'row', justifyContent: 'space-between', marginBottom: 4 },
  label: { fontSize: FontSize.sm, fontWeight: FontWeight.medium },
  values: { fontSize: FontSize.sm, fontWeight: FontWeight.semibold },
  track: { height: 6, borderRadius: 3, overflow: 'hidden' },
  fill: { height: '100%', borderRadius: 3 },
});

const styles = StyleSheet.create({
  container: { flex: 1 },
  content: { padding: Spacing.lg, paddingTop: Spacing.xxl },
  title: { fontSize: FontSize.xxl, fontWeight: FontWeight.bold, marginBottom: Spacing.lg },
  periodTabs: {
    flexDirection: 'row',
    backgroundColor: 'transparent',
    gap: Spacing.sm,
    marginBottom: Spacing.lg,
  },
  periodTab: {
    flex: 1,
    paddingVertical: Spacing.sm,
    borderRadius: BorderRadius.md,
    alignItems: 'center',
  },
  periodTabText: { fontSize: FontSize.sm, fontWeight: FontWeight.semibold },
  card: {
    borderRadius: BorderRadius.lg,
    padding: Spacing.lg,
    marginBottom: Spacing.lg,
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 1,
    shadowRadius: 6,
    elevation: 3,
  },
  cardTitle: { fontSize: FontSize.lg, fontWeight: FontWeight.semibold, marginBottom: Spacing.md },
  chartContainer: { alignItems: 'center' },
  statsGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: Spacing.md,
    marginBottom: Spacing.lg,
  },
  statCard: {
    width: '47%',
    borderRadius: BorderRadius.lg,
    padding: Spacing.lg,
    alignItems: 'center',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 1,
    shadowRadius: 6,
    elevation: 3,
  },
  statLabel: { fontSize: FontSize.xs, fontWeight: FontWeight.medium, marginBottom: 4 },
  statValue: { fontSize: FontSize.xxl, fontWeight: FontWeight.bold },
  statUnit: { fontSize: FontSize.xs, marginTop: 2 },
  premiumOverlay: {
    width: 320,
    height: 180,
    borderRadius: BorderRadius.md,
    justifyContent: 'center',
    alignItems: 'center',
    gap: Spacing.sm,
  },
  premiumText: { fontSize: FontSize.md, fontWeight: FontWeight.semibold },
  premiumSubtext: { fontSize: FontSize.sm },
});
