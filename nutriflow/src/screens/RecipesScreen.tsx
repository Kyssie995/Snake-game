import React, { useState } from 'react';
import {
  View,
  Text,
  StyleSheet,
  TouchableOpacity,
  FlatList,
  TextInput,
  Modal,
  Platform,
  ScrollView,
} from 'react-native';
import { useTheme } from '../hooks/useTheme';
import { useStore } from '../store';
import { t } from '../i18n';
import { FoodItem, MealType } from '../types';
import { calculateMealNutrition } from '../utils/calculations';
import { BorderRadius, FontSize, FontWeight, Spacing } from '../constants/theme';

export interface Recipe {
  id: string;
  name: string;
  ingredients: { food: FoodItem; quantity: number }[];
  servings: number;
}

interface Props {
  visible: boolean;
  mealType: MealType;
  onClose: () => void;
}

export default function RecipesScreen({ visible, mealType, onClose }: Props) {
  const theme = useTheme();
  const foods = useStore(s => s.foods);
  const customFoods = useStore(s => s.customFoods);
  const addMeal = useStore(s => s.addMeal);
  const settings = useStore(s => s.settings);

  const [showCreate, setShowCreate] = useState(false);
  const [recipeName, setRecipeName] = useState('');
  const [servings, setServings] = useState('1');
  const [ingredients, setIngredients] = useState<{ food: FoodItem; quantity: number }[]>([]);
  const [searchQuery, setSearchQuery] = useState('');
  const [showIngredientSearch, setShowIngredientSearch] = useState(false);

  const allFoods = [...foods, ...customFoods];

  const filteredFoods = searchQuery.trim()
    ? allFoods.filter(f => f.name.toLowerCase().includes(searchQuery.toLowerCase()))
    : allFoods.slice(0, 15);

  const recipeTotals = ingredients.reduce(
    (totals, ing) => {
      const n = calculateMealNutrition(ing.food, ing.quantity);
      return {
        calories: totals.calories + n.calories,
        protein: totals.protein + n.protein,
        carbs: totals.carbs + n.carbs,
        fat: totals.fat + n.fat,
      };
    },
    { calories: 0, protein: 0, carbs: 0, fat: 0 }
  );

  const perServing = {
    calories: Math.round(recipeTotals.calories / (parseInt(servings) || 1)),
    protein: Math.round(recipeTotals.protein / (parseInt(servings) || 1) * 10) / 10,
    carbs: Math.round(recipeTotals.carbs / (parseInt(servings) || 1) * 10) / 10,
    fat: Math.round(recipeTotals.fat / (parseInt(servings) || 1) * 10) / 10,
  };

  const handleAddIngredient = (food: FoodItem) => {
    setIngredients([...ingredients, { food, quantity: food.servingSize }]);
    setShowIngredientSearch(false);
    setSearchQuery('');
  };

  const handleSaveAsFood = async () => {
    if (!recipeName.trim() || ingredients.length === 0) return;
    const totalWeight = ingredients.reduce((sum, ing) => sum + ing.quantity, 0);
    const servingCount = parseInt(servings) || 1;

    const recipeFood: Omit<FoodItem, 'id' | 'isFavorite'> = {
      name: recipeName,
      calories: Math.round((recipeTotals.calories / totalWeight) * 100),
      protein: Math.round((recipeTotals.protein / totalWeight) * 100 * 10) / 10,
      carbs: Math.round((recipeTotals.carbs / totalWeight) * 100 * 10) / 10,
      fat: Math.round((recipeTotals.fat / totalWeight) * 100 * 10) / 10,
      fiber: 0,
      servingSize: Math.round(totalWeight / servingCount),
      servingUnit: 'g',
    };

    const { addCustomFood } = useStore.getState();
    await addCustomFood(recipeFood);
    setShowCreate(false);
    setRecipeName('');
    setIngredients([]);
    setServings('1');
  };

  const handleQuickAdd = async () => {
    if (ingredients.length === 0) return;
    const totalWeight = ingredients.reduce((sum, ing) => sum + ing.quantity, 0);
    const servingCount = parseInt(servings) || 1;

    const tempFood: FoodItem = {
      id: 'recipe-temp',
      name: recipeName || 'Rezept',
      calories: Math.round((recipeTotals.calories / totalWeight) * 100),
      protein: Math.round((recipeTotals.protein / totalWeight) * 100 * 10) / 10,
      carbs: Math.round((recipeTotals.carbs / totalWeight) * 100 * 10) / 10,
      fat: Math.round((recipeTotals.fat / totalWeight) * 100 * 10) / 10,
      fiber: 0,
      servingSize: Math.round(totalWeight / servingCount),
      servingUnit: 'g',
      isFavorite: false,
    };

    await addMeal(tempFood, tempFood.servingSize, mealType);
    setShowCreate(false);
    setRecipeName('');
    setIngredients([]);
    setServings('1');
    onClose();
  };

  return (
    <Modal visible={visible} animationType="slide" presentationStyle="pageSheet">
      <View style={[styles.container, { backgroundColor: theme.background }]}>
        <View style={[styles.header, { borderBottomColor: theme.border }]}>
          <TouchableOpacity onPress={onClose}>
            <Text style={[styles.closeBtn, { color: theme.primary }]}>{t('common.cancel')}</Text>
          </TouchableOpacity>
          <Text style={[styles.headerTitle, { color: theme.text }]}>{t('meals.recipes')}</Text>
          <TouchableOpacity onPress={() => setShowCreate(true)}>
            <Text style={[styles.addBtn, { color: theme.primary }]}>+</Text>
          </TouchableOpacity>
        </View>

        {!showCreate ? (
          <View style={styles.emptyState}>
            <Text style={{ fontSize: 48 }}>🍳</Text>
            <Text style={[styles.emptyTitle, { color: theme.text }]}>
              {settings.language === 'de' ? 'Eigene Rezepte' : 'Your Recipes'}
            </Text>
            <Text style={[styles.emptyDesc, { color: theme.textTertiary }]}>
              {settings.language === 'de'
                ? 'Erstelle Rezepte aus deinen Lieblingszutaten und tracke sie mit einem Tap.'
                : 'Create recipes from your favorite ingredients and track them with one tap.'}
            </Text>
            <TouchableOpacity
              style={[styles.createBtn, { backgroundColor: theme.primary }]}
              onPress={() => setShowCreate(true)}
            >
              <Text style={styles.createBtnText}>
                {settings.language === 'de' ? 'Rezept erstellen' : 'Create Recipe'}
              </Text>
            </TouchableOpacity>
          </View>
        ) : (
          <ScrollView contentContainerStyle={styles.createContent} showsVerticalScrollIndicator={false}>
            <TextInput
              style={[styles.nameInput, { color: theme.text, borderColor: theme.border, backgroundColor: theme.surfaceSecondary }]}
              value={recipeName}
              onChangeText={setRecipeName}
              placeholder={settings.language === 'de' ? 'Rezeptname' : 'Recipe name'}
              placeholderTextColor={theme.textTertiary}
              autoFocus
            />

            <View style={styles.servingsRow}>
              <Text style={[styles.servingsLabel, { color: theme.textSecondary }]}>
                {settings.language === 'de' ? 'Portionen' : 'Servings'}
              </Text>
              <TextInput
                style={[styles.servingsInput, { color: theme.text, borderColor: theme.border }]}
                value={servings}
                onChangeText={setServings}
                keyboardType="number-pad"
              />
            </View>

            <View style={styles.ingredientsHeader}>
              <Text style={[styles.sectionLabel, { color: theme.text }]}>
                {settings.language === 'de' ? 'Zutaten' : 'Ingredients'} ({ingredients.length})
              </Text>
              <TouchableOpacity
                style={[styles.addIngBtn, { backgroundColor: theme.primary }]}
                onPress={() => setShowIngredientSearch(true)}
              >
                <Text style={styles.addIngBtnText}>+</Text>
              </TouchableOpacity>
            </View>

            {ingredients.map((ing, index) => {
              const n = calculateMealNutrition(ing.food, ing.quantity);
              return (
                <View key={index} style={[styles.ingredientRow, { borderBottomColor: theme.border }]}>
                  <View style={styles.ingredientInfo}>
                    <Text style={[styles.ingredientName, { color: theme.text }]}>{ing.food.name}</Text>
                    <Text style={[styles.ingredientDetail, { color: theme.textTertiary }]}>
                      {ing.quantity}{ing.food.servingUnit} · {n.calories} kcal
                    </Text>
                  </View>
                  <TouchableOpacity
                    onPress={() => setIngredients(ingredients.filter((_, i) => i !== index))}
                  >
                    <Text style={[styles.removeBtn, { color: theme.error }]}>✕</Text>
                  </TouchableOpacity>
                </View>
              );
            })}

            {ingredients.length > 0 && (
              <View style={[styles.totalCard, { backgroundColor: theme.surfaceSecondary }]}>
                <Text style={[styles.totalTitle, { color: theme.text }]}>
                  {settings.language === 'de' ? 'Pro Portion' : 'Per Serving'}
                </Text>
                <View style={styles.totalRow}>
                  <NutrientPill label="kcal" value={perServing.calories} color={theme.calories} />
                  <NutrientPill label="P" value={perServing.protein} color={theme.protein} />
                  <NutrientPill label="K" value={perServing.carbs} color={theme.carbs} />
                  <NutrientPill label="F" value={perServing.fat} color={theme.fat} />
                </View>
              </View>
            )}

            <View style={styles.actionButtons}>
              <TouchableOpacity
                style={[styles.actionBtn, { backgroundColor: theme.surfaceSecondary }]}
                onPress={handleSaveAsFood}
                disabled={ingredients.length === 0}
              >
                <Text style={[styles.actionBtnText, { color: ingredients.length > 0 ? theme.text : theme.textTertiary }]}>
                  {settings.language === 'de' ? 'Speichern' : 'Save'}
                </Text>
              </TouchableOpacity>
              <TouchableOpacity
                style={[styles.actionBtn, { backgroundColor: theme.primary }]}
                onPress={handleQuickAdd}
                disabled={ingredients.length === 0}
              >
                <Text style={[styles.actionBtnText, { color: '#fff' }]}>
                  {settings.language === 'de' ? 'Hinzufügen' : 'Add'}
                </Text>
              </TouchableOpacity>
            </View>
          </ScrollView>
        )}

        <Modal visible={showIngredientSearch} animationType="slide" presentationStyle="pageSheet">
          <View style={[styles.container, { backgroundColor: theme.background }]}>
            <View style={[styles.header, { borderBottomColor: theme.border }]}>
              <TouchableOpacity onPress={() => { setShowIngredientSearch(false); setSearchQuery(''); }}>
                <Text style={[styles.closeBtn, { color: theme.primary }]}>{t('common.cancel')}</Text>
              </TouchableOpacity>
              <Text style={[styles.headerTitle, { color: theme.text }]}>
                {settings.language === 'de' ? 'Zutat wählen' : 'Pick Ingredient'}
              </Text>
              <View style={{ width: 60 }} />
            </View>
            <View style={[styles.searchBar, { backgroundColor: theme.surfaceSecondary }]}>
              <TextInput
                style={[styles.searchInput, { color: theme.text }]}
                value={searchQuery}
                onChangeText={setSearchQuery}
                placeholder={t('meals.search')}
                placeholderTextColor={theme.textTertiary}
                autoFocus
              />
            </View>
            <FlatList
              data={filteredFoods}
              keyExtractor={item => item.id}
              contentContainerStyle={{ paddingHorizontal: Spacing.lg }}
              renderItem={({ item }) => (
                <TouchableOpacity
                  style={[styles.searchItem, { borderBottomColor: theme.border }]}
                  onPress={() => handleAddIngredient(item)}
                >
                  <Text style={[styles.searchItemName, { color: theme.text }]}>{item.name}</Text>
                  <Text style={[styles.searchItemDetail, { color: theme.textTertiary }]}>
                    {item.servingSize}{item.servingUnit} · {Math.round(item.calories * item.servingSize / 100)} kcal
                  </Text>
                </TouchableOpacity>
              )}
            />
          </View>
        </Modal>
      </View>
    </Modal>
  );
}

function NutrientPill({ label, value, color }: { label: string; value: number; color: string }) {
  return (
    <View style={pillStyles.container}>
      <Text style={[pillStyles.value, { color }]}>{value}</Text>
      <Text style={[pillStyles.label, { color: color + '99' }]}>{label}</Text>
    </View>
  );
}

const pillStyles = StyleSheet.create({
  container: { alignItems: 'center', flex: 1 },
  value: { fontSize: FontSize.lg, fontWeight: FontWeight.bold },
  label: { fontSize: FontSize.xs, marginTop: 2 },
});

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
  closeBtn: { fontSize: FontSize.md, fontWeight: FontWeight.medium, width: 60 },
  headerTitle: { fontSize: FontSize.lg, fontWeight: FontWeight.semibold },
  addBtn: { fontSize: 24, fontWeight: FontWeight.bold, width: 60, textAlign: 'right' },
  emptyState: { flex: 1, justifyContent: 'center', alignItems: 'center', padding: Spacing.xxl },
  emptyTitle: { fontSize: FontSize.xl, fontWeight: FontWeight.bold, marginTop: Spacing.lg },
  emptyDesc: { fontSize: FontSize.sm, textAlign: 'center', marginTop: Spacing.sm, lineHeight: 20 },
  createBtn: {
    paddingHorizontal: Spacing.xxl,
    paddingVertical: Spacing.md,
    borderRadius: BorderRadius.md,
    marginTop: Spacing.xl,
  },
  createBtnText: { color: '#fff', fontSize: FontSize.md, fontWeight: FontWeight.semibold },
  createContent: { padding: Spacing.lg },
  nameInput: {
    height: 48,
    borderWidth: 1.5,
    borderRadius: BorderRadius.md,
    paddingHorizontal: Spacing.lg,
    fontSize: FontSize.md,
    fontWeight: FontWeight.medium,
    marginBottom: Spacing.lg,
  },
  servingsRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    marginBottom: Spacing.xl,
  },
  servingsLabel: { fontSize: FontSize.md, fontWeight: FontWeight.medium },
  servingsInput: {
    width: 60,
    height: 40,
    borderWidth: 1,
    borderRadius: BorderRadius.sm,
    textAlign: 'center',
    fontSize: FontSize.md,
    fontWeight: FontWeight.semibold,
  },
  ingredientsHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: Spacing.md,
  },
  sectionLabel: { fontSize: FontSize.lg, fontWeight: FontWeight.semibold },
  addIngBtn: {
    width: 32,
    height: 32,
    borderRadius: 16,
    justifyContent: 'center',
    alignItems: 'center',
  },
  addIngBtnText: { color: '#fff', fontSize: 18, fontWeight: FontWeight.bold },
  ingredientRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingVertical: Spacing.md,
    borderBottomWidth: StyleSheet.hairlineWidth,
  },
  ingredientInfo: { flex: 1 },
  ingredientName: { fontSize: FontSize.md, fontWeight: FontWeight.medium },
  ingredientDetail: { fontSize: FontSize.xs, marginTop: 2 },
  removeBtn: { fontSize: 16, padding: Spacing.sm },
  totalCard: {
    borderRadius: BorderRadius.lg,
    padding: Spacing.lg,
    marginTop: Spacing.lg,
  },
  totalTitle: { fontSize: FontSize.md, fontWeight: FontWeight.semibold, marginBottom: Spacing.md, textAlign: 'center' },
  totalRow: { flexDirection: 'row' },
  actionButtons: {
    flexDirection: 'row',
    gap: Spacing.md,
    marginTop: Spacing.xl,
  },
  actionBtn: {
    flex: 1,
    paddingVertical: Spacing.lg,
    borderRadius: BorderRadius.md,
    alignItems: 'center',
  },
  actionBtnText: { fontSize: FontSize.md, fontWeight: FontWeight.semibold },
  searchBar: {
    margin: Spacing.lg,
    borderRadius: BorderRadius.md,
    paddingHorizontal: Spacing.md,
    height: 44,
    justifyContent: 'center',
  },
  searchInput: { fontSize: FontSize.md, height: '100%' },
  searchItem: {
    paddingVertical: Spacing.md,
    borderBottomWidth: StyleSheet.hairlineWidth,
  },
  searchItemName: { fontSize: FontSize.md, fontWeight: FontWeight.medium },
  searchItemDetail: { fontSize: FontSize.xs, marginTop: 2 },
});
