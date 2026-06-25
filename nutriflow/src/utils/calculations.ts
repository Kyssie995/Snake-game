import { UserProfile, NutritionGoals, MealEntry, FoodItem } from '../types';

export function calculateBMR(profile: UserProfile): number {
  if (profile.gender === 'male') {
    return 10 * profile.currentWeight + 6.25 * profile.height - 5 * profile.age + 5;
  }
  return 10 * profile.currentWeight + 6.25 * profile.height - 5 * profile.age - 161;
}

export function calculateTDEE(profile: UserProfile): number {
  const bmr = calculateBMR(profile);
  const multipliers = {
    sedentary: 1.2,
    light: 1.375,
    moderate: 1.55,
    active: 1.725,
    veryActive: 1.9,
  };
  return Math.round(bmr * multipliers[profile.activityLevel]);
}

export function calculateGoals(profile: UserProfile): NutritionGoals {
  let tdee = calculateTDEE(profile);

  if (profile.goal === 'lose') {
    tdee -= 500;
  } else if (profile.goal === 'gain') {
    tdee += 300;
  }

  const calories = Math.round(tdee);
  const protein = Math.round(profile.currentWeight * (profile.goal === 'gain' ? 2.0 : 1.6));
  const fat = Math.round((calories * 0.25) / 9);
  const proteinCalories = protein * 4;
  const fatCalories = fat * 9;
  const carbCalories = calories - proteinCalories - fatCalories;
  const carbs = Math.round(carbCalories / 4);

  return {
    calories,
    protein,
    carbs,
    fat,
    fiber: 30,
    water: profile.gender === 'male' ? 3.0 : 2.5,
  };
}

export function calculateMealNutrition(foodItem: FoodItem, quantity: number) {
  const factor = quantity / 100;
  return {
    calories: Math.round(foodItem.calories * factor),
    protein: Math.round(foodItem.protein * factor * 10) / 10,
    carbs: Math.round(foodItem.carbs * factor * 10) / 10,
    fat: Math.round(foodItem.fat * factor * 10) / 10,
    fiber: Math.round(foodItem.fiber * factor * 10) / 10,
  };
}

export function calculateDailyTotals(meals: MealEntry[]) {
  return meals.reduce(
    (totals, entry) => {
      const nutrition = calculateMealNutrition(entry.foodItem, entry.quantity);
      return {
        calories: totals.calories + nutrition.calories,
        protein: totals.protein + nutrition.protein,
        carbs: totals.carbs + nutrition.carbs,
        fat: totals.fat + nutrition.fat,
        fiber: totals.fiber + nutrition.fiber,
      };
    },
    { calories: 0, protein: 0, carbs: 0, fat: 0, fiber: 0 }
  );
}

export function formatDate(date: Date): string {
  return date.toISOString().split('T')[0];
}

export function getTodayString(): string {
  return formatDate(new Date());
}
