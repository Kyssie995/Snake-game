import React, { useState } from 'react';
import { View, Text, ScrollView, StyleSheet, TouchableOpacity } from 'react-native';
import { useTheme } from '../hooks/useTheme';
import { useStore } from '../store';
import { t } from '../i18n';
import { MealType } from '../types';
import MealCard from '../components/MealCard';
import AddFoodScreen from './AddFoodScreen';
import { BorderRadius, FontSize, FontWeight, Spacing } from '../constants/theme';
import { format, addDays, subDays } from 'date-fns';
import { de, enUS } from 'date-fns/locale';

export default function DiaryScreen() {
  const theme = useTheme();
  const [addFoodModal, setAddFoodModal] = useState<MealType | null>(null);
  const selectedDate = useStore(s => s.selectedDate);
  const setSelectedDate = useStore(s => s.setSelectedDate);
  const totals = useStore(s => s.getDailyTotals());
  const goals = useStore(s => s.goals);
  const settings = useStore(s => s.settings);

  const locale = settings.language === 'de' ? de : enUS;
  const dateObj = new Date(selectedDate + 'T12:00:00');
  const today = new Date().toISOString().split('T')[0];
  const isToday = selectedDate === today;

  const formattedDate = isToday
    ? t('common.today')
    : format(dateObj, 'EEEE, d. MMMM', { locale });

  const goBack = () => {
    const prev = subDays(dateObj, 1);
    setSelectedDate(prev.toISOString().split('T')[0]);
  };

  const goForward = () => {
    const next = addDays(dateObj, 1);
    const nextStr = next.toISOString().split('T')[0];
    if (nextStr <= today) {
      setSelectedDate(nextStr);
    }
  };

  const mealTypes: MealType[] = ['breakfast', 'lunch', 'dinner', 'snacks'];

  return (
    <View style={[styles.container, { backgroundColor: theme.background }]}>
      <View style={[styles.dateNav, { borderBottomColor: theme.border }]}>
        <TouchableOpacity onPress={goBack} style={styles.navBtn}>
          <Text style={[styles.navArrow, { color: theme.primary }]}>‹</Text>
        </TouchableOpacity>
        <TouchableOpacity
          onPress={() => setSelectedDate(today)}
          style={styles.dateCenter}
        >
          <Text style={[styles.dateText, { color: theme.text }]}>{formattedDate}</Text>
        </TouchableOpacity>
        <TouchableOpacity
          onPress={goForward}
          style={styles.navBtn}
          disabled={isToday}
        >
          <Text style={[styles.navArrow, { color: isToday ? theme.textTertiary : theme.primary }]}>
            ›
          </Text>
        </TouchableOpacity>
      </View>

      <View style={[styles.summary, { backgroundColor: theme.surface }]}>
        <View style={styles.summaryItem}>
          <Text style={[styles.summaryValue, { color: theme.calories }]}>{totals.calories}</Text>
          <Text style={[styles.summaryLabel, { color: theme.textTertiary }]}>kcal</Text>
        </View>
        <View style={[styles.summaryDivider, { backgroundColor: theme.border }]} />
        <View style={styles.summaryItem}>
          <Text style={[styles.summaryValue, { color: theme.protein }]}>{Math.round(totals.protein)}g</Text>
          <Text style={[styles.summaryLabel, { color: theme.textTertiary }]}>P</Text>
        </View>
        <View style={[styles.summaryDivider, { backgroundColor: theme.border }]} />
        <View style={styles.summaryItem}>
          <Text style={[styles.summaryValue, { color: theme.carbs }]}>{Math.round(totals.carbs)}g</Text>
          <Text style={[styles.summaryLabel, { color: theme.textTertiary }]}>K</Text>
        </View>
        <View style={[styles.summaryDivider, { backgroundColor: theme.border }]} />
        <View style={styles.summaryItem}>
          <Text style={[styles.summaryValue, { color: theme.fat }]}>{Math.round(totals.fat)}g</Text>
          <Text style={[styles.summaryLabel, { color: theme.textTertiary }]}>F</Text>
        </View>
      </View>

      <ScrollView contentContainerStyle={styles.content} showsVerticalScrollIndicator={false}>
        {mealTypes.map(type => (
          <MealCard
            key={type}
            mealType={type}
            onAdd={() => setAddFoodModal(type)}
          />
        ))}
        <View style={{ height: 100 }} />
      </ScrollView>

      {addFoodModal && (
        <AddFoodScreen
          visible
          mealType={addFoodModal}
          onClose={() => setAddFoodModal(null)}
        />
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  dateNav: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: Spacing.lg,
    paddingTop: Spacing.md,
    paddingBottom: Spacing.md,
    borderBottomWidth: StyleSheet.hairlineWidth,
  },
  navBtn: {
    width: 44,
    height: 44,
    justifyContent: 'center',
    alignItems: 'center',
  },
  navArrow: {
    fontSize: 28,
    fontWeight: FontWeight.bold,
  },
  dateCenter: {
    flex: 1,
    alignItems: 'center',
  },
  dateText: {
    fontSize: FontSize.md,
    fontWeight: FontWeight.semibold,
  },
  summary: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-around',
    paddingVertical: Spacing.md,
    marginHorizontal: Spacing.lg,
    marginTop: Spacing.md,
    borderRadius: BorderRadius.lg,
  },
  summaryItem: {
    alignItems: 'center',
    paddingHorizontal: Spacing.md,
  },
  summaryValue: {
    fontSize: FontSize.lg,
    fontWeight: FontWeight.bold,
  },
  summaryLabel: {
    fontSize: FontSize.xs,
    fontWeight: FontWeight.medium,
    marginTop: 2,
  },
  summaryDivider: {
    width: 1,
    height: 24,
  },
  content: {
    padding: Spacing.lg,
  },
});
