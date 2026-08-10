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
} from 'react-native';
import { useTheme } from '../hooks/useTheme';
import { useStore } from '../store';
import { t } from '../i18n';
import { NutritionGoals } from '../types';
import { BorderRadius, FontSize, FontWeight, Spacing } from '../constants/theme';

interface Props {
  visible: boolean;
  onClose: () => void;
}

export default function EditGoalsScreen({ visible, onClose }: Props) {
  const theme = useTheme();
  const goals = useStore(s => s.goals);
  const setGoals = useStore(s => s.setGoals);
  const settings = useStore(s => s.settings);

  const [calories, setCalories] = useState(String(goals.calories));
  const [protein, setProtein] = useState(String(goals.protein));
  const [carbs, setCarbs] = useState(String(goals.carbs));
  const [fat, setFat] = useState(String(goals.fat));
  const [fiber, setFiber] = useState(String(goals.fiber));
  const [water, setWater] = useState(String(goals.water));

  const handleSave = async () => {
    const updatedGoals: NutritionGoals = {
      calories: parseInt(calories) || goals.calories,
      protein: parseInt(protein) || goals.protein,
      carbs: parseInt(carbs) || goals.carbs,
      fat: parseInt(fat) || goals.fat,
      fiber: parseInt(fiber) || goals.fiber,
      water: parseFloat(water) || goals.water,
    };
    await setGoals(updatedGoals);
    onClose();
  };

  const calcProteinCals = (parseInt(protein) || 0) * 4;
  const calcCarbsCals = (parseInt(carbs) || 0) * 4;
  const calcFatCals = (parseInt(fat) || 0) * 9;
  const macroCals = calcProteinCals + calcCarbsCals + calcFatCals;
  const targetCals = parseInt(calories) || 0;
  const diff = targetCals - macroCals;

  const Field = ({ label, value, onChangeText, unit, color }: {
    label: string; value: string; onChangeText: (v: string) => void; unit: string; color: string;
  }) => (
    <View style={styles.field}>
      <View style={styles.fieldHeader}>
        <View style={[styles.colorDot, { backgroundColor: color }]} />
        <Text style={[styles.fieldLabel, { color: theme.text }]}>{label}</Text>
      </View>
      <View style={styles.fieldInputRow}>
        <TextInput
          style={[styles.fieldInput, { color: theme.text, borderColor: theme.border, backgroundColor: theme.surfaceSecondary }]}
          value={value}
          onChangeText={onChangeText}
          keyboardType="decimal-pad"
          selectTextOnFocus
        />
        <Text style={[styles.fieldUnit, { color: theme.textTertiary }]}>{unit}</Text>
      </View>
    </View>
  );

  return (
    <Modal visible={visible} animationType="slide" presentationStyle="pageSheet">
      <View style={[styles.container, { backgroundColor: theme.background }]}>
        <View style={[styles.header, { borderBottomColor: theme.border }]}>
          <TouchableOpacity onPress={onClose}>
            <Text style={[styles.cancelBtn, { color: theme.primary }]}>{t('common.cancel')}</Text>
          </TouchableOpacity>
          <Text style={[styles.headerTitle, { color: theme.text }]}>{t('profile.editGoals')}</Text>
          <TouchableOpacity onPress={handleSave}>
            <Text style={[styles.saveBtn, { color: theme.primary }]}>{t('common.save')}</Text>
          </TouchableOpacity>
        </View>

        <ScrollView contentContainerStyle={styles.content} showsVerticalScrollIndicator={false}>
          <Field
            label={t('dashboard.calories')}
            value={calories}
            onChangeText={setCalories}
            unit="kcal"
            color={theme.calories}
          />

          <View style={[styles.divider, { backgroundColor: theme.border }]} />

          <Text style={[styles.sectionTitle, { color: theme.text }]}>Makros</Text>

          <Field label={t('dashboard.protein')} value={protein} onChangeText={setProtein} unit="g" color={theme.protein} />
          <Field label={t('dashboard.carbs')} value={carbs} onChangeText={setCarbs} unit="g" color={theme.carbs} />
          <Field label={t('dashboard.fat')} value={fat} onChangeText={setFat} unit="g" color={theme.fat} />

          <View style={[styles.macroCheck, { backgroundColor: diff === 0 ? theme.success + '15' : theme.warning + '15' }]}>
            <Text style={[styles.macroCheckText, { color: diff === 0 ? theme.success : theme.warning }]}>
              {settings.language === 'de'
                ? `Makros ergeben ${macroCals} kcal (${diff > 0 ? '+' : ''}${diff} kcal ${diff === 0 ? '✓' : 'Differenz'})`
                : `Macros total ${macroCals} kcal (${diff > 0 ? '+' : ''}${diff} kcal ${diff === 0 ? '✓' : 'difference'})`}
            </Text>
          </View>

          <View style={[styles.divider, { backgroundColor: theme.border }]} />

          <Field label={t('dashboard.fiber')} value={fiber} onChangeText={setFiber} unit="g" color={theme.fiber} />
          <Field label={t('dashboard.water')} value={water} onChangeText={setWater} unit="L" color={theme.water} />
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
  cancelBtn: { fontSize: FontSize.md, fontWeight: FontWeight.medium, width: 70 },
  headerTitle: { fontSize: FontSize.lg, fontWeight: FontWeight.semibold },
  saveBtn: { fontSize: FontSize.md, fontWeight: FontWeight.semibold, width: 70, textAlign: 'right' },
  content: { padding: Spacing.xl },
  sectionTitle: { fontSize: FontSize.lg, fontWeight: FontWeight.semibold, marginBottom: Spacing.lg },
  field: { marginBottom: Spacing.lg },
  fieldHeader: { flexDirection: 'row', alignItems: 'center', marginBottom: Spacing.sm },
  colorDot: { width: 10, height: 10, borderRadius: 5, marginRight: Spacing.sm },
  fieldLabel: { fontSize: FontSize.md, fontWeight: FontWeight.medium },
  fieldInputRow: { flexDirection: 'row', alignItems: 'center', gap: Spacing.sm },
  fieldInput: {
    flex: 1,
    height: 48,
    borderWidth: 1.5,
    borderRadius: BorderRadius.md,
    paddingHorizontal: Spacing.lg,
    fontSize: FontSize.lg,
    fontWeight: FontWeight.semibold,
  },
  fieldUnit: { fontSize: FontSize.md, fontWeight: FontWeight.medium, width: 40 },
  divider: { height: 1, marginVertical: Spacing.xl },
  macroCheck: {
    padding: Spacing.md,
    borderRadius: BorderRadius.md,
    marginTop: Spacing.sm,
  },
  macroCheckText: { fontSize: FontSize.sm, fontWeight: FontWeight.medium, textAlign: 'center' },
});
