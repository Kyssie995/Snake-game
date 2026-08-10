import React, { useState } from 'react';
import {
  View,
  Text,
  TextInput,
  StyleSheet,
  TouchableOpacity,
  ScrollView,
  Modal,
  Platform,
  KeyboardAvoidingView,
} from 'react-native';
import { useTheme } from '../hooks/useTheme';
import { useStore } from '../store';
import { t } from '../i18n';
import { BorderRadius, FontSize, FontWeight, Spacing } from '../constants/theme';

interface Props {
  visible: boolean;
  onClose: () => void;
}

export default function CreateFoodScreen({ visible, onClose }: Props) {
  const theme = useTheme();
  const addCustomFood = useStore(s => s.addCustomFood);

  const [name, setName] = useState('');
  const [brand, setBrand] = useState('');
  const [calories, setCalories] = useState('');
  const [protein, setProtein] = useState('');
  const [carbs, setCarbs] = useState('');
  const [fat, setFat] = useState('');
  const [fiber, setFiber] = useState('');
  const [servingSize, setServingSize] = useState('100');
  const [servingUnit, setServingUnit] = useState('g');

  const canSave = name.length > 0 && calories.length > 0;

  const handleSave = async () => {
    if (!canSave) return;
    await addCustomFood({
      name,
      brand: brand || undefined,
      calories: parseFloat(calories) || 0,
      protein: parseFloat(protein) || 0,
      carbs: parseFloat(carbs) || 0,
      fat: parseFloat(fat) || 0,
      fiber: parseFloat(fiber) || 0,
      servingSize: parseFloat(servingSize) || 100,
      servingUnit,
    });
    onClose();
    setName('');
    setBrand('');
    setCalories('');
    setProtein('');
    setCarbs('');
    setFat('');
    setFiber('');
    setServingSize('100');
  };

  const Field = ({ label, value, onChangeText, placeholder, numeric = false }: {
    label: string; value: string; onChangeText: (t: string) => void; placeholder: string; numeric?: boolean;
  }) => (
    <View style={styles.field}>
      <Text style={[styles.fieldLabel, { color: theme.textSecondary }]}>{label}</Text>
      <TextInput
        style={[styles.fieldInput, { color: theme.text, borderColor: theme.border, backgroundColor: theme.surfaceSecondary }]}
        value={value}
        onChangeText={onChangeText}
        placeholder={placeholder}
        placeholderTextColor={theme.textTertiary}
        keyboardType={numeric ? 'decimal-pad' : 'default'}
      />
    </View>
  );

  return (
    <Modal visible={visible} animationType="slide" presentationStyle="pageSheet">
      <KeyboardAvoidingView
        style={[styles.container, { backgroundColor: theme.background }]}
        behavior={Platform.OS === 'ios' ? 'padding' : undefined}
      >
        <View style={[styles.header, { borderBottomColor: theme.border }]}>
          <TouchableOpacity onPress={onClose}>
            <Text style={[styles.cancelBtn, { color: theme.primary }]}>{t('common.cancel')}</Text>
          </TouchableOpacity>
          <Text style={[styles.headerTitle, { color: theme.text }]}>Eigenes Lebensmittel</Text>
          <TouchableOpacity onPress={handleSave} disabled={!canSave}>
            <Text style={[styles.saveBtn, { color: canSave ? theme.primary : theme.textTertiary }]}>
              {t('common.save')}
            </Text>
          </TouchableOpacity>
        </View>

        <ScrollView contentContainerStyle={styles.content} showsVerticalScrollIndicator={false}>
          <Field label="Name *" value={name} onChangeText={setName} placeholder="z.B. Protein Shake" />
          <Field label="Marke" value={brand} onChangeText={setBrand} placeholder="Optional" />

          <Text style={[styles.sectionLabel, { color: theme.text }]}>Nährwerte pro 100g</Text>

          <View style={styles.row}>
            <Field label="Kalorien *" value={calories} onChangeText={setCalories} placeholder="0" numeric />
            <Field label="Protein (g)" value={protein} onChangeText={setProtein} placeholder="0" numeric />
          </View>
          <View style={styles.row}>
            <Field label="Kohlenhydrate (g)" value={carbs} onChangeText={setCarbs} placeholder="0" numeric />
            <Field label="Fett (g)" value={fat} onChangeText={setFat} placeholder="0" numeric />
          </View>
          <View style={styles.row}>
            <Field label="Ballaststoffe (g)" value={fiber} onChangeText={setFiber} placeholder="0" numeric />
            <Field label="Portionsgröße" value={servingSize} onChangeText={setServingSize} placeholder="100" numeric />
          </View>

          <View style={styles.unitRow}>
            <Text style={[styles.fieldLabel, { color: theme.textSecondary }]}>Einheit</Text>
            <View style={styles.unitOptions}>
              {['g', 'ml', 'Stk'].map(unit => (
                <TouchableOpacity
                  key={unit}
                  style={[
                    styles.unitBtn,
                    { backgroundColor: servingUnit === unit ? theme.primary : theme.surfaceSecondary },
                  ]}
                  onPress={() => setServingUnit(unit)}
                >
                  <Text style={[styles.unitBtnText, { color: servingUnit === unit ? '#fff' : theme.text }]}>
                    {unit}
                  </Text>
                </TouchableOpacity>
              ))}
            </View>
          </View>
        </ScrollView>
      </KeyboardAvoidingView>
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
  cancelBtn: { fontSize: FontSize.md, fontWeight: FontWeight.medium },
  headerTitle: { fontSize: FontSize.lg, fontWeight: FontWeight.semibold },
  saveBtn: { fontSize: FontSize.md, fontWeight: FontWeight.semibold },
  content: { padding: Spacing.lg },
  field: { flex: 1, marginBottom: Spacing.md },
  fieldLabel: { fontSize: FontSize.xs, fontWeight: FontWeight.medium, marginBottom: 4 },
  fieldInput: {
    height: 44,
    borderWidth: 1,
    borderRadius: BorderRadius.sm,
    paddingHorizontal: Spacing.md,
    fontSize: FontSize.md,
  },
  sectionLabel: { fontSize: FontSize.lg, fontWeight: FontWeight.semibold, marginTop: Spacing.lg, marginBottom: Spacing.md },
  row: { flexDirection: 'row', gap: Spacing.md },
  unitRow: { marginTop: Spacing.md },
  unitOptions: { flexDirection: 'row', gap: Spacing.sm, marginTop: 4 },
  unitBtn: { paddingHorizontal: Spacing.xl, paddingVertical: Spacing.sm, borderRadius: BorderRadius.md },
  unitBtnText: { fontSize: FontSize.sm, fontWeight: FontWeight.medium },
});
