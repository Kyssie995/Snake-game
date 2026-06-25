import React, { useState } from 'react';
import {
  View,
  Text,
  ScrollView,
  StyleSheet,
  TouchableOpacity,
  TextInput,
  Modal,
  Platform,
} from 'react-native';
import { useTheme } from '../hooks/useTheme';
import { useStore } from '../store';
import { BorderRadius, FontSize, FontWeight, Spacing } from '../constants/theme';

interface ShoppingItem {
  id: string;
  name: string;
  quantity: string;
  checked: boolean;
  category: string;
}

interface Props {
  visible: boolean;
  onClose: () => void;
}

const categories: Record<string, { de: string; en: string; icon: string }> = {
  produce: { de: 'Obst & Gemüse', en: 'Produce', icon: '🥬' },
  dairy: { de: 'Milchprodukte', en: 'Dairy', icon: '🥛' },
  meat: { de: 'Fleisch & Fisch', en: 'Meat & Fish', icon: '🥩' },
  grains: { de: 'Getreide & Brot', en: 'Grains & Bread', icon: '🍞' },
  pantry: { de: 'Vorrat', en: 'Pantry', icon: '🫙' },
  other: { de: 'Sonstiges', en: 'Other', icon: '🛒' },
};

export default function ShoppingListScreen({ visible, onClose }: Props) {
  const theme = useTheme();
  const settings = useStore(s => s.settings);
  const lang = settings.language;
  const isPremium = settings.subscription !== 'free';

  const [items, setItems] = useState<ShoppingItem[]>([]);
  const [newItemName, setNewItemName] = useState('');
  const [newItemQty, setNewItemQty] = useState('');
  const [selectedCategory, setSelectedCategory] = useState('produce');

  const addItem = () => {
    if (!newItemName.trim()) return;
    const item: ShoppingItem = {
      id: Date.now().toString(),
      name: newItemName.trim(),
      quantity: newItemQty.trim() || '1x',
      checked: false,
      category: selectedCategory,
    };
    setItems([...items, item]);
    setNewItemName('');
    setNewItemQty('');
  };

  const toggleItem = (id: string) => {
    setItems(items.map(i => i.id === id ? { ...i, checked: !i.checked } : i));
  };

  const removeItem = (id: string) => {
    setItems(items.filter(i => i.id !== id));
  };

  const clearChecked = () => {
    setItems(items.filter(i => !i.checked));
  };

  const groupedItems = Object.keys(categories).reduce((acc, cat) => {
    const catItems = items.filter(i => i.category === cat);
    if (catItems.length > 0) acc[cat] = catItems;
    return acc;
  }, {} as Record<string, ShoppingItem[]>);

  const checkedCount = items.filter(i => i.checked).length;

  if (!isPremium) {
    return (
      <Modal visible={visible} animationType="slide" presentationStyle="pageSheet">
        <View style={[styles.container, { backgroundColor: theme.background }]}>
          <View style={[styles.header, { borderBottomColor: theme.border }]}>
            <TouchableOpacity onPress={onClose}>
              <Text style={[styles.closeBtn, { color: theme.primary }]}>✕</Text>
            </TouchableOpacity>
            <Text style={[styles.headerTitle, { color: theme.text }]}>
              {lang === 'de' ? 'Einkaufsliste' : 'Shopping List'}
            </Text>
            <View style={{ width: 40 }} />
          </View>
          <View style={styles.premiumGate}>
            <Text style={{ fontSize: 48 }}>🛒</Text>
            <Text style={[styles.premiumTitle, { color: theme.text }]}>Premium Feature</Text>
            <Text style={[styles.premiumDesc, { color: theme.textSecondary }]}>
              {lang === 'de'
                ? 'Erstelle Einkaufslisten basierend auf deinen geplanten Mahlzeiten.'
                : 'Create shopping lists based on your planned meals.'}
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
            {lang === 'de' ? 'Einkaufsliste' : 'Shopping List'}
          </Text>
          {checkedCount > 0 ? (
            <TouchableOpacity onPress={clearChecked}>
              <Text style={[styles.clearBtn, { color: theme.error }]}>
                {lang === 'de' ? 'Erledigte löschen' : 'Clear done'}
              </Text>
            </TouchableOpacity>
          ) : (
            <View style={{ width: 40 }} />
          )}
        </View>

        <View style={[styles.addRow, { backgroundColor: theme.surface }]}>
          <TextInput
            style={[styles.addInput, { color: theme.text, backgroundColor: theme.surfaceSecondary }]}
            value={newItemName}
            onChangeText={setNewItemName}
            placeholder={lang === 'de' ? 'Artikel hinzufügen...' : 'Add item...'}
            placeholderTextColor={theme.textTertiary}
            onSubmitEditing={addItem}
            returnKeyType="done"
          />
          <TextInput
            style={[styles.qtyInput, { color: theme.text, backgroundColor: theme.surfaceSecondary }]}
            value={newItemQty}
            onChangeText={setNewItemQty}
            placeholder="1x"
            placeholderTextColor={theme.textTertiary}
            keyboardType="default"
          />
          <TouchableOpacity
            style={[styles.addItemBtn, { backgroundColor: theme.primary }]}
            onPress={addItem}
          >
            <Text style={styles.addItemBtnText}>+</Text>
          </TouchableOpacity>
        </View>

        <ScrollView horizontal showsHorizontalScrollIndicator={false} style={styles.categoryTabs} contentContainerStyle={styles.categoryTabsContent}>
          {Object.entries(categories).map(([key, cat]) => (
            <TouchableOpacity
              key={key}
              style={[
                styles.categoryTab,
                {
                  backgroundColor: selectedCategory === key ? theme.primary : theme.surfaceSecondary,
                },
              ]}
              onPress={() => setSelectedCategory(key)}
            >
              <Text style={styles.categoryIcon}>{cat.icon}</Text>
              <Text style={[styles.categoryLabel, { color: selectedCategory === key ? '#fff' : theme.textSecondary }]}>
                {cat[lang]}
              </Text>
            </TouchableOpacity>
          ))}
        </ScrollView>

        <ScrollView contentContainerStyle={styles.content} showsVerticalScrollIndicator={false}>
          {items.length === 0 ? (
            <View style={styles.emptyState}>
              <Text style={{ fontSize: 40 }}>🛒</Text>
              <Text style={[styles.emptyText, { color: theme.textTertiary }]}>
                {lang === 'de' ? 'Deine Einkaufsliste ist leer' : 'Your shopping list is empty'}
              </Text>
            </View>
          ) : (
            Object.entries(groupedItems).map(([cat, catItems]) => (
              <View key={cat} style={styles.categoryGroup}>
                <View style={styles.categoryHeader}>
                  <Text style={styles.categoryHeaderIcon}>{categories[cat].icon}</Text>
                  <Text style={[styles.categoryHeaderText, { color: theme.text }]}>
                    {categories[cat][lang]}
                  </Text>
                  <Text style={[styles.categoryCount, { color: theme.textTertiary }]}>
                    {catItems.length}
                  </Text>
                </View>
                {catItems.map(item => (
                  <TouchableOpacity
                    key={item.id}
                    style={[styles.shoppingItem, { backgroundColor: theme.surface }]}
                    onPress={() => toggleItem(item.id)}
                    onLongPress={() => removeItem(item.id)}
                  >
                    <View style={[
                      styles.checkbox,
                      {
                        borderColor: item.checked ? theme.primary : theme.border,
                        backgroundColor: item.checked ? theme.primary : 'transparent',
                      },
                    ]}>
                      {item.checked && <Text style={styles.checkmark}>✓</Text>}
                    </View>
                    <Text style={[
                      styles.itemName,
                      { color: theme.text },
                      item.checked && { textDecorationLine: 'line-through', opacity: 0.5 },
                    ]}>
                      {item.name}
                    </Text>
                    <Text style={[styles.itemQty, { color: theme.textTertiary }]}>{item.quantity}</Text>
                  </TouchableOpacity>
                ))}
              </View>
            ))
          )}
          <View style={{ height: 40 }} />
        </ScrollView>
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
  clearBtn: { fontSize: FontSize.xs, fontWeight: FontWeight.medium },
  addRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.sm,
    padding: Spacing.lg,
  },
  addInput: {
    flex: 1,
    height: 42,
    borderRadius: BorderRadius.sm,
    paddingHorizontal: Spacing.md,
    fontSize: FontSize.md,
  },
  qtyInput: {
    width: 56,
    height: 42,
    borderRadius: BorderRadius.sm,
    paddingHorizontal: Spacing.sm,
    fontSize: FontSize.sm,
    textAlign: 'center',
  },
  addItemBtn: {
    width: 42,
    height: 42,
    borderRadius: BorderRadius.sm,
    justifyContent: 'center',
    alignItems: 'center',
  },
  addItemBtnText: { color: '#fff', fontSize: 20, fontWeight: FontWeight.bold },
  categoryTabs: { maxHeight: 44, flexGrow: 0 },
  categoryTabsContent: { paddingHorizontal: Spacing.lg, gap: Spacing.sm },
  categoryTab: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
    paddingHorizontal: Spacing.md,
    paddingVertical: Spacing.xs,
    borderRadius: BorderRadius.full,
  },
  categoryIcon: { fontSize: 14 },
  categoryLabel: { fontSize: FontSize.xs, fontWeight: FontWeight.medium },
  content: { padding: Spacing.lg },
  emptyState: { alignItems: 'center', paddingVertical: 60 },
  emptyText: { fontSize: FontSize.md, marginTop: Spacing.md },
  categoryGroup: { marginBottom: Spacing.lg },
  categoryHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.sm,
    marginBottom: Spacing.sm,
  },
  categoryHeaderIcon: { fontSize: 16 },
  categoryHeaderText: { fontSize: FontSize.md, fontWeight: FontWeight.semibold, flex: 1 },
  categoryCount: { fontSize: FontSize.xs },
  shoppingItem: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: Spacing.md,
    paddingHorizontal: Spacing.md,
    borderRadius: BorderRadius.sm,
    marginBottom: 2,
    gap: Spacing.md,
  },
  checkbox: {
    width: 22,
    height: 22,
    borderRadius: 6,
    borderWidth: 2,
    justifyContent: 'center',
    alignItems: 'center',
  },
  checkmark: { color: '#fff', fontSize: 13, fontWeight: FontWeight.bold },
  itemName: { flex: 1, fontSize: FontSize.md, fontWeight: FontWeight.medium },
  itemQty: { fontSize: FontSize.sm },
  premiumGate: { flex: 1, justifyContent: 'center', alignItems: 'center', padding: Spacing.xxl },
  premiumTitle: { fontSize: FontSize.xl, fontWeight: FontWeight.bold, marginTop: Spacing.lg },
  premiumDesc: { fontSize: FontSize.sm, textAlign: 'center', marginTop: Spacing.sm, lineHeight: 22, maxWidth: 300 },
  upgradeBtn: { paddingHorizontal: Spacing.xxl, paddingVertical: Spacing.md, borderRadius: BorderRadius.md, marginTop: Spacing.xxl },
  upgradeBtnText: { color: '#fff', fontSize: FontSize.md, fontWeight: FontWeight.semibold },
});
