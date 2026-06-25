import { doc, setDoc, getDoc } from 'firebase/firestore';
import { db } from '../config/firebase';
import type {
  UserProfile,
  NutritionGoals,
  MealEntry,
  WeightEntry,
  Streak,
  Badge,
  AppSettings,
  FoodItem,
} from '../types';

interface UserData {
  profile: UserProfile | null;
  goals: NutritionGoals;
  meals: Record<string, MealEntry[]>;
  waterLog: Record<string, number>;
  weights: WeightEntry[];
  customFoods: FoodItem[];
  recentFoods: FoodItem[];
  favoriteIds: string[];
  streak: Streak;
  badges: Badge[];
  settings: AppSettings;
}

function userDoc(uid: string) {
  return doc(db, 'users', uid);
}

export async function syncToFirestore(uid: string, data: Partial<UserData>): Promise<void> {
  try {
    await setDoc(userDoc(uid), data, { merge: true });
  } catch {
    // Silently fail — local data is the source of truth
  }
}

export async function loadFromFirestore(uid: string): Promise<UserData | null> {
  try {
    const snap = await getDoc(userDoc(uid));
    if (snap.exists()) {
      return snap.data() as UserData;
    }
    return null;
  } catch {
    return null;
  }
}
