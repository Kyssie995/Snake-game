import React from 'react';
import { View, Text, StyleSheet, TouchableOpacity } from 'react-native';
import { MealType, MealEntry } from '../types';
import { useTheme } from '../hooks/useTheme';
import { useStore } from '../store';
import { calculateMealNutrition } from '../utils/calculations';
import { t } from '../i18n';
import { BorderRadius, FontSize, FontWeight, Spacing } from '../constants/theme';

interface Props {
  mealType: MealType;
  onAdd: () => void;
}

const mealIcons: Record<MealType, string> = {
  breakfast: '🌅',
  lunch: '☀️',
  dinner: '🌙',
  snacks: '🍪',
};

export default function MealCard({ mealType, onAdd }: Props) {
  const theme = useTheme();
  const selectedDate = useStore(s => s.selectedDate);
  const allMeals = useStore(s => s.meals);
  const removeMeal = useStore(s => s.removeMeal);
  const dailyMeals = allMeals[selectedDate] || [];
  const meals = dailyMeals.filter(m => m.mealType === mealType);

  const totalCals = meals.reduce((sum, m) => {
    const n = calculateMealNutrition(m.foodItem, m.quantity);
    return sum + n.calories;
  }, 0);

  return (
    <View style={[styles.card, { backgroundColor: theme.surface, shadowColor: theme.cardShadow }]}>
      <TouchableOpacity style={styles.header} onPress={onAdd} activeOpacity={0.7}>
        <View style={styles.headerLeft}>
          <Text style={styles.icon}>{mealIcons[mealType]}</Text>
          <Text style={[styles.title, { color: theme.text }]}>
            {t(`meals.${mealType}`)}
          </Text>
        </View>
        <View style={styles.headerRight}>
          <Text style={[styles.totalCals, { color: theme.textSecondary }]}>
            {totalCals} kcal
          </Text>
          <View style={[styles.addButton, { backgroundColor: theme.primary }]}>
            <Text style={styles.addIcon}>+</Text>
          </View>
        </View>
      </TouchableOpacity>

      {meals.map(meal => {
        const nutrition = calculateMealNutrition(meal.foodItem, meal.quantity);
        return (
          <TouchableOpacity
            key={meal.id}
            style={[styles.mealItem, { borderTopColor: theme.border }]}
            onLongPress={() => removeMeal(selectedDate, meal.id)}
            activeOpacity={0.7}
          >
            <View style={styles.mealInfo}>
              <Text style={[styles.mealName, { color: theme.text }]} numberOfLines={1}>
                {meal.foodItem.name}
              </Text>
              <Text style={[styles.mealDetail, { color: theme.textTertiary }]}>
                {meal.quantity}{meal.foodItem.servingUnit}
              </Text>
            </View>
            <Text style={[styles.mealCals, { color: theme.textSecondary }]}>
              {nutrition.calories} kcal
            </Text>
          </TouchableOpacity>
        );
      })}
    </View>
  );
}

const styles = StyleSheet.create({
  card: {
    borderRadius: BorderRadius.lg,
    marginBottom: Spacing.md,
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 1,
    shadowRadius: 8,
    elevation: 3,
  },
  header: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    padding: Spacing.lg,
  },
  headerLeft: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.sm,
  },
  icon: {
    fontSize: 22,
  },
  title: {
    fontSize: FontSize.md,
    fontWeight: FontWeight.semibold,
  },
  headerRight: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.md,
  },
  totalCals: {
    fontSize: FontSize.sm,
    fontWeight: FontWeight.medium,
  },
  addButton: {
    width: 28,
    height: 28,
    borderRadius: BorderRadius.full,
    justifyContent: 'center',
    alignItems: 'center',
  },
  addIcon: {
    color: '#fff',
    fontSize: 18,
    fontWeight: FontWeight.bold,
    marginTop: -1,
  },
  mealItem: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: Spacing.lg,
    paddingVertical: Spacing.md,
    borderTopWidth: StyleSheet.hairlineWidth,
  },
  mealInfo: {
    flex: 1,
    marginRight: Spacing.md,
  },
  mealName: {
    fontSize: FontSize.sm,
    fontWeight: FontWeight.medium,
  },
  mealDetail: {
    fontSize: FontSize.xs,
    marginTop: 2,
  },
  mealCals: {
    fontSize: FontSize.sm,
    fontWeight: FontWeight.medium,
  },
});
