import React, { useState } from 'react';
import {
  View,
  Text,
  ScrollView,
  StyleSheet,
  TouchableOpacity,
  Modal,
  Platform,
} from 'react-native';
import { useTheme } from '../hooks/useTheme';
import { useStore } from '../store';
import { MealType, FoodItem } from '../types';
import { calculateMealNutrition } from '../utils/calculations';
import AddFoodScreen from './AddFoodScreen';
import { BorderRadius, FontSize, FontWeight, Spacing } from '../constants/theme';
import { format, addDays } from 'date-fns';
import { de, enUS } from 'date-fns/locale';

interface PlannedMeal {
  food: FoodItem;
  quantity: number;
  mealType: MealType;
}

interface DayPlan {
  date: string;
  meals: PlannedMeal[];
}

interface Props {
  visible: boolean;
  onClose: () => void;
}

const mealIcons: Record<MealType, string> = {
  breakfast: '🌅',
  lunch: '☀️',
  dinner: '🌙',
  snacks: '🍪',
};

const mealLabels: Record<string, Record<MealType, string>> = {
  de: { breakfast: 'Frühstück', lunch: 'Mittagessen', dinner: 'Abendessen', snacks: 'Snacks' },
  en: { breakfast: 'Breakfast', lunch: 'Lunch', dinner: 'Dinner', snacks: 'Snacks' },
};

export default function MealPlanScreen({ visible, onClose }: Props) {
  const theme = useTheme();
  const settings = useStore(s => s.settings);
  const goals = useStore(s => s.goals);
  const lang = settings.language;
  const locale = lang === 'de' ? de : enUS;
  const isPremium = settings.subscription !== 'free';

  const [plans, setPlans] = useState<DayPlan[]>(() => {
    const today = new Date();
    return Array.from({ length: 7 }, (_, i) => ({
      date: addDays(today, i).toISOString().split('T')[0],
      meals: [],
    }));
  });

  const [selectedDay, setSelectedDay] = useState(0);
  const [addFoodFor, setAddFoodFor] = useState<MealType | null>(null);

  const currentPlan = plans[selectedDay];
  const mealTypes: MealType[] = ['breakfast', 'lunch', 'dinner', 'snacks'];

  const dayTotals = currentPlan.meals.reduce(
    (acc, m) => {
      const n = calculateMealNutrition(m.food, m.quantity);
      return {
        calories: acc.calories + n.calories,
        protein: acc.protein + n.protein,
        carbs: acc.carbs + n.carbs,
        fat: acc.fat + n.fat,
      };
    },
    { calories: 0, protein: 0, carbs: 0, fat: 0 }
  );

  const removeMeal = (mealIndex: number) => {
    const updated = [...plans];
    updated[selectedDay] = {
      ...currentPlan,
      meals: currentPlan.meals.filter((_, i) => i !== mealIndex),
    };
    setPlans(updated);
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
              {lang === 'de' ? 'Mahlzeitenplanung' : 'Meal Planning'}
            </Text>
            <View style={{ width: 40 }} />
          </View>
          <View style={styles.premiumGate}>
            <Text style={{ fontSize: 48 }}>📅</Text>
            <Text style={[styles.premiumTitle, { color: theme.text }]}>
              {lang === 'de' ? 'Premium Feature' : 'Premium Feature'}
            </Text>
            <Text style={[styles.premiumDesc, { color: theme.textSecondary }]}>
              {lang === 'de'
                ? 'Plane deine Mahlzeiten für die ganze Woche im Voraus und halte dein Kalorienziel mühelos ein.'
                : 'Plan your meals for the entire week ahead and effortlessly stay on track with your calorie goals.'}
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
            {lang === 'de' ? 'Mahlzeitenplanung' : 'Meal Planning'}
          </Text>
          <View style={{ width: 40 }} />
        </View>

        <ScrollView horizontal showsHorizontalScrollIndicator={false} style={styles.dayTabs} contentContainerStyle={styles.dayTabsContent}>
          {plans.map((plan, i) => {
            const date = new Date(plan.date + 'T12:00:00');
            const isSelected = i === selectedDay;
            const dayLabel = i === 0
              ? (lang === 'de' ? 'Heute' : 'Today')
              : i === 1
                ? (lang === 'de' ? 'Morgen' : 'Tomorrow')
                : format(date, 'EEE', { locale });
            const dateLabel = format(date, 'd', { locale });

            return (
              <TouchableOpacity
                key={plan.date}
                style={[
                  styles.dayTab,
                  {
                    backgroundColor: isSelected ? theme.primary : theme.surface,
                    borderColor: isSelected ? theme.primary : theme.border,
                  },
                ]}
                onPress={() => setSelectedDay(i)}
              >
                <Text style={[styles.dayTabLabel, { color: isSelected ? '#fff' : theme.textSecondary }]}>
                  {dayLabel}
                </Text>
                <Text style={[styles.dayTabDate, { color: isSelected ? '#fff' : theme.text }]}>
                  {dateLabel}
                </Text>
              </TouchableOpacity>
            );
          })}
        </ScrollView>

        <View style={[styles.daySummary, { backgroundColor: theme.surface }]}>
          <View style={styles.summaryItem}>
            <Text style={[styles.summaryValue, { color: dayTotals.calories > goals.calories ? theme.warning : theme.calories }]}>
              {dayTotals.calories}
            </Text>
            <Text style={[styles.summaryLabel, { color: theme.textTertiary }]}>/ {goals.calories} kcal</Text>
          </View>
          <View style={[styles.summaryDivider, { backgroundColor: theme.border }]} />
          <View style={styles.summaryItem}>
            <Text style={[styles.summaryValue, { color: theme.protein }]}>{Math.round(dayTotals.protein)}g</Text>
            <Text style={[styles.summaryLabel, { color: theme.textTertiary }]}>P</Text>
          </View>
          <View style={[styles.summaryDivider, { backgroundColor: theme.border }]} />
          <View style={styles.summaryItem}>
            <Text style={[styles.summaryValue, { color: theme.carbs }]}>{Math.round(dayTotals.carbs)}g</Text>
            <Text style={[styles.summaryLabel, { color: theme.textTertiary }]}>K</Text>
          </View>
          <View style={[styles.summaryDivider, { backgroundColor: theme.border }]} />
          <View style={styles.summaryItem}>
            <Text style={[styles.summaryValue, { color: theme.fat }]}>{Math.round(dayTotals.fat)}g</Text>
            <Text style={[styles.summaryLabel, { color: theme.textTertiary }]}>F</Text>
          </View>
        </View>

        <ScrollView contentContainerStyle={styles.content} showsVerticalScrollIndicator={false}>
          {mealTypes.map(type => {
            const typeMeals = currentPlan.meals
              .map((m, i) => ({ ...m, index: i }))
              .filter(m => m.mealType === type);
            const typeCals = typeMeals.reduce((s, m) => s + calculateMealNutrition(m.food, m.quantity).calories, 0);

            return (
              <View key={type} style={[styles.mealSection, { backgroundColor: theme.surface, shadowColor: theme.cardShadow }]}>
                <TouchableOpacity
                  style={styles.mealHeader}
                  onPress={() => setAddFoodFor(type)}
                  activeOpacity={0.7}
                >
                  <View style={styles.mealHeaderLeft}>
                    <Text style={styles.mealIcon}>{mealIcons[type]}</Text>
                    <Text style={[styles.mealTitle, { color: theme.text }]}>
                      {mealLabels[lang][type]}
                    </Text>
                  </View>
                  <View style={styles.mealHeaderRight}>
                    <Text style={[styles.mealCals, { color: theme.textSecondary }]}>{typeCals} kcal</Text>
                    <View style={[styles.addBtn, { backgroundColor: theme.primary }]}>
                      <Text style={styles.addBtnText}>+</Text>
                    </View>
                  </View>
                </TouchableOpacity>

                {typeMeals.map(meal => {
                  const n = calculateMealNutrition(meal.food, meal.quantity);
                  return (
                    <TouchableOpacity
                      key={meal.index}
                      style={[styles.mealItem, { borderTopColor: theme.border }]}
                      onLongPress={() => removeMeal(meal.index)}
                    >
                      <View style={styles.mealItemInfo}>
                        <Text style={[styles.mealItemName, { color: theme.text }]} numberOfLines={1}>
                          {meal.food.name}
                        </Text>
                        <Text style={[styles.mealItemDetail, { color: theme.textTertiary }]}>
                          {meal.quantity}{meal.food.servingUnit}
                        </Text>
                      </View>
                      <Text style={[styles.mealItemCals, { color: theme.textSecondary }]}>{n.calories} kcal</Text>
                    </TouchableOpacity>
                  );
                })}
              </View>
            );
          })}
          <View style={{ height: 40 }} />
        </ScrollView>

        {addFoodFor && (
          <AddFoodScreen
            visible
            mealType={addFoodFor}
            onClose={() => setAddFoodFor(null)}
          />
        )}
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
  dayTabs: { maxHeight: 72, flexGrow: 0 },
  dayTabsContent: { paddingHorizontal: Spacing.lg, paddingVertical: Spacing.md, gap: Spacing.sm },
  dayTab: {
    paddingHorizontal: Spacing.lg,
    paddingVertical: Spacing.sm,
    borderRadius: BorderRadius.md,
    borderWidth: 1,
    alignItems: 'center',
    minWidth: 64,
  },
  dayTabLabel: { fontSize: FontSize.xs, fontWeight: FontWeight.medium },
  dayTabDate: { fontSize: FontSize.lg, fontWeight: FontWeight.bold },
  daySummary: {
    flexDirection: 'row',
    justifyContent: 'space-around',
    alignItems: 'center',
    paddingVertical: Spacing.md,
    marginHorizontal: Spacing.lg,
    marginTop: Spacing.sm,
    borderRadius: BorderRadius.lg,
  },
  summaryItem: { alignItems: 'center' },
  summaryValue: { fontSize: FontSize.md, fontWeight: FontWeight.bold },
  summaryLabel: { fontSize: 10, marginTop: 1 },
  summaryDivider: { width: 1, height: 24 },
  content: { padding: Spacing.lg },
  mealSection: {
    borderRadius: BorderRadius.lg,
    marginBottom: Spacing.md,
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 1,
    shadowRadius: 6,
    elevation: 3,
  },
  mealHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    padding: Spacing.lg,
  },
  mealHeaderLeft: { flexDirection: 'row', alignItems: 'center', gap: Spacing.sm },
  mealIcon: { fontSize: 20 },
  mealTitle: { fontSize: FontSize.md, fontWeight: FontWeight.semibold },
  mealHeaderRight: { flexDirection: 'row', alignItems: 'center', gap: Spacing.md },
  mealCals: { fontSize: FontSize.sm, fontWeight: FontWeight.medium },
  addBtn: { width: 26, height: 26, borderRadius: 13, justifyContent: 'center', alignItems: 'center' },
  addBtnText: { color: '#fff', fontSize: 16, fontWeight: FontWeight.bold, marginTop: -1 },
  mealItem: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: Spacing.lg,
    paddingVertical: Spacing.md,
    borderTopWidth: StyleSheet.hairlineWidth,
  },
  mealItemInfo: { flex: 1, marginRight: Spacing.md },
  mealItemName: { fontSize: FontSize.sm, fontWeight: FontWeight.medium },
  mealItemDetail: { fontSize: FontSize.xs, marginTop: 1 },
  mealItemCals: { fontSize: FontSize.sm, fontWeight: FontWeight.medium },
  premiumGate: { flex: 1, justifyContent: 'center', alignItems: 'center', padding: Spacing.xxl },
  premiumTitle: { fontSize: FontSize.xl, fontWeight: FontWeight.bold, marginTop: Spacing.lg },
  premiumDesc: { fontSize: FontSize.sm, textAlign: 'center', marginTop: Spacing.sm, lineHeight: 22, maxWidth: 300 },
  upgradeBtn: { paddingHorizontal: Spacing.xxl, paddingVertical: Spacing.md, borderRadius: BorderRadius.md, marginTop: Spacing.xxl },
  upgradeBtnText: { color: '#fff', fontSize: FontSize.md, fontWeight: FontWeight.semibold },
});
