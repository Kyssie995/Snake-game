import React, { useState, useMemo } from 'react';
import {
  View,
  Text,
  TextInput,
  StyleSheet,
  TouchableOpacity,
  FlatList,
  Modal,
  Platform,
} from 'react-native';
import { useTheme } from '../hooks/useTheme';
import { useStore } from '../store';
import { t } from '../i18n';
import { FoodItem, MealType } from '../types';
import { calculateMealNutrition } from '../utils/calculations';
import { BorderRadius, FontSize, FontWeight, Spacing } from '../constants/theme';

interface Props {
  visible: boolean;
  mealType: MealType;
  onClose: () => void;
}

type Tab = 'search' | 'recent' | 'favorites' | 'custom';

export default function AddFoodScreen({ visible, mealType, onClose }: Props) {
  const theme = useTheme();
  const [query, setQuery] = useState('');
  const [activeTab, setActiveTab] = useState<Tab>('search');
  const [selectedFood, setSelectedFood] = useState<FoodItem | null>(null);
  const [quantity, setQuantity] = useState('');

  const foods = useStore(s => s.foods);
  const customFoods = useStore(s => s.customFoods);
  const recentFoods = useStore(s => s.recentFoods);
  const addMeal = useStore(s => s.addMeal);
  const toggleFavorite = useStore(s => s.toggleFavorite);

  const allFoods = useMemo(() => [...foods, ...customFoods], [foods, customFoods]);

  const filteredFoods = useMemo(() => {
    switch (activeTab) {
      case 'recent':
        return recentFoods;
      case 'favorites':
        return allFoods.filter(f => f.isFavorite);
      case 'custom':
        return customFoods;
      default: {
        if (!query.trim()) return allFoods.slice(0, 20);
        const q = query.toLowerCase();
        return allFoods.filter(
          f => f.name.toLowerCase().includes(q) || f.brand?.toLowerCase().includes(q)
        );
      }
    }
  }, [activeTab, query, allFoods, recentFoods, customFoods]);

  const handleAdd = async () => {
    if (!selectedFood) return;
    const qty = parseFloat(quantity) || selectedFood.servingSize;
    await addMeal(selectedFood, qty, mealType);
    setSelectedFood(null);
    setQuantity('');
    setQuery('');
    onClose();
  };

  const handleQuickAdd = async (food: FoodItem) => {
    await addMeal(food, food.servingSize, mealType);
    onClose();
  };

  const tabs: { key: Tab; label: string }[] = [
    { key: 'search', label: t('meals.search').replace('...', '') },
    { key: 'recent', label: t('meals.recent') },
    { key: 'favorites', label: t('meals.favorites') },
    { key: 'custom', label: t('meals.custom') },
  ];

  const renderFoodItem = ({ item }: { item: FoodItem }) => {
    const nutrition = calculateMealNutrition(item, item.servingSize);
    return (
      <TouchableOpacity
        style={[styles.foodItem, { borderBottomColor: theme.border }]}
        onPress={() => {
          setSelectedFood(item);
          setQuantity(String(item.servingSize));
        }}
        onLongPress={() => handleQuickAdd(item)}
        activeOpacity={0.7}
      >
        <View style={styles.foodInfo}>
          <Text style={[styles.foodName, { color: theme.text }]} numberOfLines={1}>
            {item.name}
          </Text>
          {item.brand && (
            <Text style={[styles.foodBrand, { color: theme.textTertiary }]}>{item.brand}</Text>
          )}
          <Text style={[styles.foodServing, { color: theme.textTertiary }]}>
            {item.servingSize}{item.servingUnit} · {nutrition.calories} kcal
          </Text>
        </View>
        <View style={styles.foodActions}>
          <TouchableOpacity onPress={() => toggleFavorite(item.id)} style={styles.favBtn}>
            <Text style={{ fontSize: 18 }}>{item.isFavorite ? '⭐' : '☆'}</Text>
          </TouchableOpacity>
          <View style={[styles.quickAddBtn, { backgroundColor: theme.primary + '20' }]}>
            <Text style={[styles.quickAddText, { color: theme.primary }]}>+</Text>
          </View>
        </View>
      </TouchableOpacity>
    );
  };

  return (
    <Modal visible={visible} animationType="slide" presentationStyle="pageSheet">
      <View style={[styles.container, { backgroundColor: theme.background }]}>
        <View style={[styles.header, { borderBottomColor: theme.border }]}>
          <TouchableOpacity onPress={onClose}>
            <Text style={[styles.cancelBtn, { color: theme.primary }]}>{t('common.cancel')}</Text>
          </TouchableOpacity>
          <Text style={[styles.headerTitle, { color: theme.text }]}>
            {t(`meals.${mealType}`)}
          </Text>
          <View style={{ width: 60 }} />
        </View>

        <View style={[styles.searchBar, { backgroundColor: theme.surfaceSecondary }]}>
          <Text style={styles.searchIcon}>🔍</Text>
          <TextInput
            style={[styles.searchInput, { color: theme.text }]}
            placeholder={t('meals.search')}
            placeholderTextColor={theme.textTertiary}
            value={query}
            onChangeText={text => {
              setQuery(text);
              setActiveTab('search');
            }}
            autoFocus
            returnKeyType="search"
          />
          {query.length > 0 && (
            <TouchableOpacity onPress={() => setQuery('')}>
              <Text style={[styles.clearBtn, { color: theme.textTertiary }]}>✕</Text>
            </TouchableOpacity>
          )}
        </View>

        <View style={styles.tabs}>
          {tabs.map(tab => (
            <TouchableOpacity
              key={tab.key}
              style={[
                styles.tab,
                activeTab === tab.key && { borderBottomColor: theme.primary, borderBottomWidth: 2 },
              ]}
              onPress={() => setActiveTab(tab.key)}
            >
              <Text
                style={[
                  styles.tabText,
                  { color: activeTab === tab.key ? theme.primary : theme.textTertiary },
                ]}
              >
                {tab.label}
              </Text>
            </TouchableOpacity>
          ))}
        </View>

        <FlatList
          data={filteredFoods}
          keyExtractor={item => item.id}
          renderItem={renderFoodItem}
          contentContainerStyle={styles.list}
          ListEmptyComponent={
            <View style={styles.empty}>
              <Text style={[styles.emptyText, { color: theme.textTertiary }]}>
                {t('meals.noResults')}
              </Text>
            </View>
          }
        />

        {selectedFood && (
          <View style={[styles.addPanel, { backgroundColor: theme.surface, borderTopColor: theme.border }]}>
            <Text style={[styles.selectedName, { color: theme.text }]} numberOfLines={1}>
              {selectedFood.name}
            </Text>
            <View style={styles.quantityRow}>
              <TextInput
                style={[styles.quantityInput, { color: theme.text, borderColor: theme.border }]}
                value={quantity}
                onChangeText={setQuantity}
                keyboardType="numeric"
                selectTextOnFocus
              />
              <Text style={[styles.unitText, { color: theme.textSecondary }]}>
                {selectedFood.servingUnit}
              </Text>
              <View style={styles.nutritionPreview}>
                <Text style={[styles.previewCals, { color: theme.primary }]}>
                  {calculateMealNutrition(selectedFood, parseFloat(quantity) || 0).calories} kcal
                </Text>
              </View>
              <TouchableOpacity
                style={[styles.addFoodBtn, { backgroundColor: theme.primary }]}
                onPress={handleAdd}
              >
                <Text style={styles.addFoodBtnText}>{t('meals.add')}</Text>
              </TouchableOpacity>
            </View>
          </View>
        )}
      </View>
    </Modal>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  header: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: Spacing.lg,
    paddingTop: Platform.OS === 'ios' ? 56 : Spacing.lg,
    paddingBottom: Spacing.md,
    borderBottomWidth: StyleSheet.hairlineWidth,
  },
  cancelBtn: {
    fontSize: FontSize.md,
    fontWeight: FontWeight.medium,
    width: 60,
  },
  headerTitle: {
    fontSize: FontSize.lg,
    fontWeight: FontWeight.semibold,
  },
  searchBar: {
    flexDirection: 'row',
    alignItems: 'center',
    margin: Spacing.lg,
    borderRadius: BorderRadius.md,
    paddingHorizontal: Spacing.md,
    height: 44,
  },
  searchIcon: {
    fontSize: 16,
    marginRight: Spacing.sm,
  },
  searchInput: {
    flex: 1,
    fontSize: FontSize.md,
    height: '100%',
  },
  clearBtn: {
    fontSize: 16,
    padding: Spacing.xs,
  },
  tabs: {
    flexDirection: 'row',
    paddingHorizontal: Spacing.lg,
    marginBottom: Spacing.sm,
  },
  tab: {
    flex: 1,
    paddingVertical: Spacing.sm,
    alignItems: 'center',
    borderBottomWidth: 2,
    borderBottomColor: 'transparent',
  },
  tabText: {
    fontSize: FontSize.sm,
    fontWeight: FontWeight.medium,
  },
  list: {
    paddingHorizontal: Spacing.lg,
  },
  foodItem: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingVertical: Spacing.md,
    borderBottomWidth: StyleSheet.hairlineWidth,
  },
  foodInfo: {
    flex: 1,
    marginRight: Spacing.md,
  },
  foodName: {
    fontSize: FontSize.md,
    fontWeight: FontWeight.medium,
  },
  foodBrand: {
    fontSize: FontSize.xs,
    marginTop: 1,
  },
  foodServing: {
    fontSize: FontSize.xs,
    marginTop: 2,
  },
  foodActions: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.sm,
  },
  favBtn: {
    padding: 4,
  },
  quickAddBtn: {
    width: 32,
    height: 32,
    borderRadius: BorderRadius.full,
    justifyContent: 'center',
    alignItems: 'center',
  },
  quickAddText: {
    fontSize: 20,
    fontWeight: FontWeight.bold,
    marginTop: -1,
  },
  empty: {
    alignItems: 'center',
    paddingVertical: Spacing.xxxl,
  },
  emptyText: {
    fontSize: FontSize.md,
  },
  addPanel: {
    paddingHorizontal: Spacing.lg,
    paddingVertical: Spacing.lg,
    paddingBottom: Platform.OS === 'ios' ? 36 : Spacing.lg,
    borderTopWidth: StyleSheet.hairlineWidth,
  },
  selectedName: {
    fontSize: FontSize.md,
    fontWeight: FontWeight.semibold,
    marginBottom: Spacing.sm,
  },
  quantityRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.sm,
  },
  quantityInput: {
    width: 70,
    height: 40,
    borderWidth: 1,
    borderRadius: BorderRadius.sm,
    textAlign: 'center',
    fontSize: FontSize.md,
    fontWeight: FontWeight.semibold,
  },
  unitText: {
    fontSize: FontSize.sm,
    fontWeight: FontWeight.medium,
  },
  nutritionPreview: {
    flex: 1,
    alignItems: 'flex-end',
  },
  previewCals: {
    fontSize: FontSize.md,
    fontWeight: FontWeight.bold,
  },
  addFoodBtn: {
    paddingHorizontal: Spacing.xl,
    paddingVertical: Spacing.sm,
    borderRadius: BorderRadius.md,
  },
  addFoodBtnText: {
    color: '#fff',
    fontSize: FontSize.md,
    fontWeight: FontWeight.semibold,
  },
});
