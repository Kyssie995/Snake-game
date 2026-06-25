import { create } from 'zustand';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { v4 as uuidv4 } from 'uuid';
import {
  FoodItem,
  MealEntry,
  MealType,
  WeightEntry,
  UserProfile,
  NutritionGoals,
  Streak,
  Badge,
  AppSettings,
} from '../types';
import { calculateGoals, calculateDailyTotals, getTodayString } from '../utils/calculations';
import { defaultFoods } from '../data/foods';
import { setLanguage } from '../i18n';
import { syncToFirestore, loadFromFirestore } from '../services/firestore';

const STORAGE_KEYS = {
  PROFILE: 'nutriflow_profile',
  GOALS: 'nutriflow_goals',
  MEALS: 'nutriflow_meals',
  WATER: 'nutriflow_water',
  WEIGHTS: 'nutriflow_weights',
  FOODS: 'nutriflow_foods',
  FAVORITES: 'nutriflow_favorites',
  RECENT: 'nutriflow_recent',
  STREAK: 'nutriflow_streak',
  BADGES: 'nutriflow_badges',
  SETTINGS: 'nutriflow_settings',
};

interface NutriFlowState {
  isLoading: boolean;
  firebaseUid: string | null;
  profile: UserProfile | null;
  goals: NutritionGoals;
  meals: Record<string, MealEntry[]>;
  waterLog: Record<string, number>;
  weights: WeightEntry[];
  foods: FoodItem[];
  customFoods: FoodItem[];
  recentFoods: FoodItem[];
  streak: Streak;
  badges: Badge[];
  settings: AppSettings;
  selectedDate: string;

  initialize: (uid?: string) => Promise<void>;
  setFirebaseUid: (uid: string | null) => void;
  setProfile: (profile: UserProfile) => Promise<void>;
  setGoals: (goals: NutritionGoals) => Promise<void>;
  addMeal: (foodItem: FoodItem, quantity: number, mealType: MealType) => Promise<void>;
  removeMeal: (date: string, mealId: string) => Promise<void>;
  addWater: (amount: number) => Promise<void>;
  addWeight: (weight: number) => Promise<void>;
  toggleFavorite: (foodId: string) => Promise<void>;
  addCustomFood: (food: Omit<FoodItem, 'id' | 'isFavorite'>) => Promise<void>;
  setSelectedDate: (date: string) => void;
  updateSettings: (settings: Partial<AppSettings>) => Promise<void>;
  resetStore: () => Promise<void>;
  getDailyMeals: (date?: string) => MealEntry[];
  getDailyWater: (date?: string) => number;
  getDailyTotals: (date?: string) => { calories: number; protein: number; carbs: number; fat: number; fiber: number };
}

const defaultGoals: NutritionGoals = {
  calories: 2000,
  protein: 120,
  carbs: 250,
  fat: 65,
  fiber: 30,
  water: 2.5,
};

const defaultBadges: Badge[] = [
  { id: 'streak_7', name: '7 Tage Streak', description: '7 Tage in Folge getrackt', icon: '7', earned: false },
  { id: 'streak_30', name: '30 Tage Streak', description: '30 Tage in Folge getrackt', icon: '30', earned: false },
  { id: 'streak_100', name: '100 Tage Streak', description: '100 Tage in Folge getrackt', icon: '100', earned: false },
  { id: 'protein_goal', name: 'Protein-Ziel', description: 'Proteinziel erreicht', icon: 'P', earned: false },
  { id: 'calorie_goal', name: 'Kalorienziel', description: 'Kalorienziel erreicht', icon: 'C', earned: false },
  { id: 'weight_goal', name: 'Gewichtsziel', description: 'Zielgewicht erreicht', icon: 'W', earned: false },
];

const defaultSettings: AppSettings = {
  theme: 'dark',
  language: 'de',
  mealCategories: [
    { id: 'breakfast', name: 'Frühstück', icon: 'sunrise' },
    { id: 'lunch', name: 'Mittagessen', icon: 'sun' },
    { id: 'dinner', name: 'Abendessen', icon: 'sunset' },
    { id: 'snacks', name: 'Snacks', icon: 'cookie' },
  ],
  subscription: 'free',
};

function cloudSync(uid: string | null, data: Record<string, any>) {
  if (uid) {
    syncToFirestore(uid, data);
  }
}

export const useStore = create<NutriFlowState>((set, get) => ({
  isLoading: true,
  firebaseUid: null,
  profile: null,
  goals: defaultGoals,
  meals: {},
  waterLog: {},
  weights: [],
  foods: defaultFoods,
  customFoods: [],
  recentFoods: [],
  streak: { currentStreak: 0, longestStreak: 0, lastTrackedDate: '' },
  badges: defaultBadges,
  settings: defaultSettings,
  selectedDate: getTodayString(),

  setFirebaseUid: (uid: string | null) => set({ firebaseUid: uid }),

  initialize: async (uid?: string) => {
    try {
      // Load local data first
      const [profileStr, goalsStr, mealsStr, waterStr, weightsStr, recentStr, streakStr, badgesStr, settingsStr, customFoodsStr] =
        await Promise.all([
          AsyncStorage.getItem(STORAGE_KEYS.PROFILE),
          AsyncStorage.getItem(STORAGE_KEYS.GOALS),
          AsyncStorage.getItem(STORAGE_KEYS.MEALS),
          AsyncStorage.getItem(STORAGE_KEYS.WATER),
          AsyncStorage.getItem(STORAGE_KEYS.WEIGHTS),
          AsyncStorage.getItem(STORAGE_KEYS.RECENT),
          AsyncStorage.getItem(STORAGE_KEYS.STREAK),
          AsyncStorage.getItem(STORAGE_KEYS.BADGES),
          AsyncStorage.getItem(STORAGE_KEYS.SETTINGS),
          AsyncStorage.getItem(STORAGE_KEYS.FOODS),
        ]);

      let settings = settingsStr ? JSON.parse(settingsStr) : defaultSettings;
      let profile = profileStr ? JSON.parse(profileStr) : null;
      let goals = goalsStr ? JSON.parse(goalsStr) : defaultGoals;
      let meals = mealsStr ? JSON.parse(mealsStr) : {};
      let waterLog = waterStr ? JSON.parse(waterStr) : {};
      let weights = weightsStr ? JSON.parse(weightsStr) : [];
      let customFoods = customFoodsStr ? JSON.parse(customFoodsStr) : [];
      let recentFoods = recentStr ? JSON.parse(recentStr) : [];
      let streak = streakStr ? JSON.parse(streakStr) : { currentStreak: 0, longestStreak: 0, lastTrackedDate: '' };
      let badges = badgesStr ? JSON.parse(badgesStr) : defaultBadges;

      // If logged in, try to merge cloud data (cloud wins for non-local-only data)
      if (uid) {
        const cloudData = await loadFromFirestore(uid);
        if (cloudData) {
          if (cloudData.profile) profile = cloudData.profile;
          if (cloudData.goals) goals = cloudData.goals;
          if (cloudData.settings) settings = cloudData.settings;
          if (cloudData.streak) streak = cloudData.streak;
          if (cloudData.badges) badges = cloudData.badges;
          if (cloudData.weights?.length) weights = cloudData.weights;
          // Merge meals: keep both local and cloud entries
          if (cloudData.meals) {
            for (const [date, entries] of Object.entries(cloudData.meals)) {
              const localEntries = meals[date] || [];
              const localIds = new Set(localEntries.map((e: MealEntry) => e.id));
              const newEntries = entries.filter((e: MealEntry) => !localIds.has(e.id));
              meals[date] = [...localEntries, ...newEntries];
            }
          }
          if (cloudData.waterLog) {
            for (const [date, amount] of Object.entries(cloudData.waterLog)) {
              waterLog[date] = Math.max(waterLog[date] || 0, amount as number);
            }
          }
          if (cloudData.customFoods?.length) customFoods = cloudData.customFoods;
          if (cloudData.recentFoods?.length) recentFoods = cloudData.recentFoods;

          // Save merged data locally
          await Promise.all([
            AsyncStorage.setItem(STORAGE_KEYS.PROFILE, JSON.stringify(profile)),
            AsyncStorage.setItem(STORAGE_KEYS.GOALS, JSON.stringify(goals)),
            AsyncStorage.setItem(STORAGE_KEYS.MEALS, JSON.stringify(meals)),
            AsyncStorage.setItem(STORAGE_KEYS.WATER, JSON.stringify(waterLog)),
            AsyncStorage.setItem(STORAGE_KEYS.WEIGHTS, JSON.stringify(weights)),
            AsyncStorage.setItem(STORAGE_KEYS.SETTINGS, JSON.stringify(settings)),
            AsyncStorage.setItem(STORAGE_KEYS.STREAK, JSON.stringify(streak)),
            AsyncStorage.setItem(STORAGE_KEYS.BADGES, JSON.stringify(badges)),
            AsyncStorage.setItem(STORAGE_KEYS.FOODS, JSON.stringify(customFoods)),
            AsyncStorage.setItem(STORAGE_KEYS.RECENT, JSON.stringify(recentFoods)),
          ]);
        } else if (profile?.setupComplete) {
          // First login — push existing local data to cloud
          const favoritesStr = await AsyncStorage.getItem(STORAGE_KEYS.FAVORITES);
          const favoriteIds: string[] = favoritesStr ? JSON.parse(favoritesStr) : [];
          syncToFirestore(uid, {
            profile, goals, meals, waterLog, weights, customFoods,
            recentFoods, favoriteIds, streak, badges, settings,
          });
        }
      }

      setLanguage(settings.language || 'de');

      const favoritesStr = await AsyncStorage.getItem(STORAGE_KEYS.FAVORITES);
      const favoriteIds: string[] = favoritesStr ? JSON.parse(favoritesStr) : [];
      const foods = defaultFoods.map(f => ({
        ...f,
        isFavorite: favoriteIds.includes(f.id),
      }));

      set({
        isLoading: false,
        firebaseUid: uid || null,
        profile,
        goals,
        meals,
        waterLog,
        weights,
        foods,
        customFoods,
        recentFoods,
        streak,
        badges,
        settings,
      });
    } catch {
      set({ isLoading: false, firebaseUid: uid || null });
    }
  },

  setProfile: async (profile: UserProfile) => {
    const goals = calculateGoals(profile);
    await Promise.all([
      AsyncStorage.setItem(STORAGE_KEYS.PROFILE, JSON.stringify(profile)),
      AsyncStorage.setItem(STORAGE_KEYS.GOALS, JSON.stringify(goals)),
    ]);
    set({ profile, goals });
    cloudSync(get().firebaseUid, { profile, goals });
  },

  setGoals: async (goals: NutritionGoals) => {
    await AsyncStorage.setItem(STORAGE_KEYS.GOALS, JSON.stringify(goals));
    set({ goals });
    cloudSync(get().firebaseUid, { goals });
  },

  addMeal: async (foodItem: FoodItem, quantity: number, mealType: MealType) => {
    const { meals, recentFoods, streak, badges } = get();
    const today = getTodayString();
    const entry: MealEntry = {
      id: uuidv4(),
      foodItem,
      quantity,
      mealType,
      date: today,
      timestamp: Date.now(),
    };

    const dayMeals = [...(meals[today] || []), entry];
    const updatedMeals = { ...meals, [today]: dayMeals };

    const updatedRecent = [foodItem, ...recentFoods.filter(f => f.id !== foodItem.id)].slice(0, 20);

    let updatedStreak = { ...streak };
    if (streak.lastTrackedDate !== today) {
      const yesterday = new Date();
      yesterday.setDate(yesterday.getDate() - 1);
      const yesterdayStr = yesterday.toISOString().split('T')[0];

      if (streak.lastTrackedDate === yesterdayStr) {
        updatedStreak.currentStreak += 1;
      } else {
        updatedStreak.currentStreak = 1;
      }
      updatedStreak.lastTrackedDate = today;
      if (updatedStreak.currentStreak > updatedStreak.longestStreak) {
        updatedStreak.longestStreak = updatedStreak.currentStreak;
      }
    }

    const updatedBadges = [...badges];
    const streakBadges: Record<number, string> = { 7: 'streak_7', 30: 'streak_30', 100: 'streak_100' };
    for (const [days, badgeId] of Object.entries(streakBadges)) {
      if (updatedStreak.currentStreak >= Number(days)) {
        const badge = updatedBadges.find(b => b.id === badgeId);
        if (badge && !badge.earned) {
          badge.earned = true;
          badge.earnedDate = today;
        }
      }
    }

    await Promise.all([
      AsyncStorage.setItem(STORAGE_KEYS.MEALS, JSON.stringify(updatedMeals)),
      AsyncStorage.setItem(STORAGE_KEYS.RECENT, JSON.stringify(updatedRecent)),
      AsyncStorage.setItem(STORAGE_KEYS.STREAK, JSON.stringify(updatedStreak)),
      AsyncStorage.setItem(STORAGE_KEYS.BADGES, JSON.stringify(updatedBadges)),
    ]);

    set({ meals: updatedMeals, recentFoods: updatedRecent, streak: updatedStreak, badges: updatedBadges });
    cloudSync(get().firebaseUid, {
      meals: updatedMeals, recentFoods: updatedRecent,
      streak: updatedStreak, badges: updatedBadges,
    });
  },

  removeMeal: async (date: string, mealId: string) => {
    const { meals } = get();
    const dayMeals = (meals[date] || []).filter(m => m.id !== mealId);
    const updatedMeals = { ...meals, [date]: dayMeals };
    await AsyncStorage.setItem(STORAGE_KEYS.MEALS, JSON.stringify(updatedMeals));
    set({ meals: updatedMeals });
    cloudSync(get().firebaseUid, { meals: updatedMeals });
  },

  addWater: async (amount: number) => {
    const { waterLog } = get();
    const today = getTodayString();
    const current = waterLog[today] || 0;
    const updated = { ...waterLog, [today]: current + amount };
    await AsyncStorage.setItem(STORAGE_KEYS.WATER, JSON.stringify(updated));
    set({ waterLog: updated });
    cloudSync(get().firebaseUid, { waterLog: updated });
  },

  addWeight: async (weight: number) => {
    const { weights, profile, badges } = get();
    const today = getTodayString();
    const existing = weights.findIndex(w => w.date === today);
    let updatedWeights: WeightEntry[];
    if (existing >= 0) {
      updatedWeights = [...weights];
      updatedWeights[existing] = { date: today, weight };
    } else {
      updatedWeights = [...weights, { date: today, weight }];
    }

    if (profile) {
      const updatedProfile = { ...profile, currentWeight: weight };
      await AsyncStorage.setItem(STORAGE_KEYS.PROFILE, JSON.stringify(updatedProfile));

      const updatedBadges = [...badges];
      if (profile.goal === 'lose' && weight <= profile.goalWeight) {
        const badge = updatedBadges.find(b => b.id === 'weight_goal');
        if (badge && !badge.earned) {
          badge.earned = true;
          badge.earnedDate = today;
        }
      }
      if (profile.goal === 'gain' && weight >= profile.goalWeight) {
        const badge = updatedBadges.find(b => b.id === 'weight_goal');
        if (badge && !badge.earned) {
          badge.earned = true;
          badge.earnedDate = today;
        }
      }
      await AsyncStorage.setItem(STORAGE_KEYS.BADGES, JSON.stringify(updatedBadges));
      set({ profile: updatedProfile, badges: updatedBadges });
      cloudSync(get().firebaseUid, { profile: updatedProfile, badges: updatedBadges });
    }

    await AsyncStorage.setItem(STORAGE_KEYS.WEIGHTS, JSON.stringify(updatedWeights));
    set({ weights: updatedWeights });
    cloudSync(get().firebaseUid, { weights: updatedWeights });
  },

  toggleFavorite: async (foodId: string) => {
    const { foods, customFoods } = get();
    const updatedFoods = foods.map(f => f.id === foodId ? { ...f, isFavorite: !f.isFavorite } : f);
    const updatedCustom = customFoods.map(f => f.id === foodId ? { ...f, isFavorite: !f.isFavorite } : f);
    const favoriteIds = [...updatedFoods, ...updatedCustom].filter(f => f.isFavorite).map(f => f.id);
    await Promise.all([
      AsyncStorage.setItem(STORAGE_KEYS.FAVORITES, JSON.stringify(favoriteIds)),
      AsyncStorage.setItem(STORAGE_KEYS.FOODS, JSON.stringify(updatedCustom)),
    ]);
    set({ foods: updatedFoods, customFoods: updatedCustom });
    cloudSync(get().firebaseUid, { favoriteIds, customFoods: updatedCustom });
  },

  addCustomFood: async (food: Omit<FoodItem, 'id' | 'isFavorite'>) => {
    const { customFoods } = get();
    const newFood: FoodItem = { ...food, id: uuidv4(), isFavorite: false };
    const updated = [...customFoods, newFood];
    await AsyncStorage.setItem(STORAGE_KEYS.FOODS, JSON.stringify(updated));
    set({ customFoods: updated });
    cloudSync(get().firebaseUid, { customFoods: updated });
  },

  setSelectedDate: (date: string) => set({ selectedDate: date }),

  updateSettings: async (newSettings: Partial<AppSettings>) => {
    const { settings } = get();
    const updated = { ...settings, ...newSettings };
    if (newSettings.language) {
      setLanguage(newSettings.language);
    }
    await AsyncStorage.setItem(STORAGE_KEYS.SETTINGS, JSON.stringify(updated));
    set({ settings: updated });
    cloudSync(get().firebaseUid, { settings: updated });
  },

  resetStore: async () => {
    await Promise.all(Object.values(STORAGE_KEYS).map(k => AsyncStorage.removeItem(k)));
    set({
      isLoading: false,
      firebaseUid: null,
      profile: null,
      goals: defaultGoals,
      meals: {},
      waterLog: {},
      weights: [],
      foods: defaultFoods,
      customFoods: [],
      recentFoods: [],
      streak: { currentStreak: 0, longestStreak: 0, lastTrackedDate: '' },
      badges: defaultBadges,
      settings: defaultSettings,
      selectedDate: getTodayString(),
    });
  },

  getDailyMeals: (date?: string) => {
    const { meals, selectedDate } = get();
    return meals[date || selectedDate] || [];
  },

  getDailyWater: (date?: string) => {
    const { waterLog, selectedDate } = get();
    return waterLog[date || selectedDate] || 0;
  },

  getDailyTotals: (date?: string) => {
    const dailyMeals = get().getDailyMeals(date);
    return calculateDailyTotals(dailyMeals);
  },
}));
