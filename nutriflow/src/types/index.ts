export interface FoodItem {
  id: string;
  name: string;
  brand?: string;
  barcode?: string;
  calories: number;
  protein: number;
  carbs: number;
  fat: number;
  fiber: number;
  servingSize: number;
  servingUnit: string;
  isFavorite: boolean;
}

export interface MealEntry {
  id: string;
  foodItem: FoodItem;
  quantity: number;
  mealType: MealType;
  date: string;
  timestamp: number;
}

export type MealType = 'breakfast' | 'lunch' | 'dinner' | 'snacks';

export interface DailyLog {
  date: string;
  meals: MealEntry[];
  water: number;
  weight?: number;
}

export interface WeightEntry {
  date: string;
  weight: number;
}

export interface UserProfile {
  name: string;
  age: number;
  height: number;
  currentWeight: number;
  goalWeight: number;
  activityLevel: 'sedentary' | 'light' | 'moderate' | 'active' | 'veryActive';
  goal: 'lose' | 'maintain' | 'gain';
  gender: 'male' | 'female';
  setupComplete: boolean;
}

export interface NutritionGoals {
  calories: number;
  protein: number;
  carbs: number;
  fat: number;
  fiber: number;
  water: number;
}

export interface Streak {
  currentStreak: number;
  longestStreak: number;
  lastTrackedDate: string;
}

export interface Badge {
  id: string;
  name: string;
  description: string;
  icon: string;
  earned: boolean;
  earnedDate?: string;
}

export type SubscriptionTier = 'free' | 'student' | 'premium' | 'lifetime';

export interface AppSettings {
  theme: 'light' | 'dark' | 'system';
  language: 'de' | 'en';
  mealCategories: MealCategory[];
  subscription: SubscriptionTier;
}

export interface MealCategory {
  id: MealType;
  name: string;
  icon: string;
}
