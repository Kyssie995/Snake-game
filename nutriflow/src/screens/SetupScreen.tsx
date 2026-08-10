import React, { useState } from 'react';
import {
  View,
  Text,
  TextInput,
  StyleSheet,
  TouchableOpacity,
  ScrollView,
  Platform,
  KeyboardAvoidingView,
} from 'react-native';
import { useTheme } from '../hooks/useTheme';
import { useStore } from '../store';
import { t } from '../i18n';
import { UserProfile } from '../types';
import { calculateGoals } from '../utils/calculations';
import { BorderRadius, FontSize, FontWeight, Spacing } from '../constants/theme';

export default function SetupScreen() {
  const theme = useTheme();
  const setProfile = useStore(s => s.setProfile);

  const [step, setStep] = useState(0);
  const [name, setName] = useState('');
  const [age, setAge] = useState('');
  const [height, setHeight] = useState('');
  const [weight, setWeight] = useState('');
  const [goalWeight, setGoalWeight] = useState('');
  const [gender, setGender] = useState<'male' | 'female'>('male');
  const [activity, setActivity] = useState<UserProfile['activityLevel']>('moderate');
  const [goal, setGoal] = useState<UserProfile['goal']>('lose');

  const steps = [
    'welcome',
    'personal',
    'body',
    'activity',
    'goal',
    'summary',
  ];

  const canProceed = () => {
    switch (step) {
      case 0: return true;
      case 1: return name.length > 0 && age.length > 0;
      case 2: return height.length > 0 && weight.length > 0 && goalWeight.length > 0;
      case 3: return true;
      case 4: return true;
      case 5: return true;
      default: return false;
    }
  };

  const handleFinish = async () => {
    const profile: UserProfile = {
      name,
      age: parseInt(age) || 25,
      height: parseInt(height) || 175,
      currentWeight: parseFloat(weight) || 75,
      goalWeight: parseFloat(goalWeight) || 70,
      activityLevel: activity,
      goal,
      gender,
      setupComplete: true,
    };
    await setProfile(profile);
  };

  const handleNext = () => {
    if (step === steps.length - 1) {
      handleFinish();
    } else {
      setStep(step + 1);
    }
  };

  const previewProfile: UserProfile = {
    name,
    age: parseInt(age) || 25,
    height: parseInt(height) || 175,
    currentWeight: parseFloat(weight) || 75,
    goalWeight: parseFloat(goalWeight) || 70,
    activityLevel: activity,
    goal,
    gender,
    setupComplete: false,
  };
  const previewGoals = calculateGoals(previewProfile);

  const Option = ({ label, selected, onPress }: { label: string; selected: boolean; onPress: () => void }) => (
    <TouchableOpacity
      style={[
        styles.option,
        { backgroundColor: selected ? theme.primary : theme.surfaceSecondary },
      ]}
      onPress={onPress}
      activeOpacity={0.7}
    >
      <Text style={[styles.optionText, { color: selected ? '#fff' : theme.text }]}>{label}</Text>
    </TouchableOpacity>
  );

  const renderStep = () => {
    switch (step) {
      case 0:
        return (
          <View style={styles.welcomeContainer}>
            <Text style={styles.welcomeEmoji}>🥗</Text>
            <Text style={[styles.welcomeTitle, { color: theme.text }]}>{t('setup.welcome')}</Text>
            <Text style={[styles.welcomeSubtitle, { color: theme.textSecondary }]}>{t('setup.subtitle')}</Text>
          </View>
        );
      case 1:
        return (
          <View style={styles.formContainer}>
            <Text style={[styles.stepTitle, { color: theme.text }]}>{t('setup.name')}</Text>
            <TextInput
              style={[styles.input, { color: theme.text, borderColor: theme.border, backgroundColor: theme.surfaceSecondary }]}
              value={name}
              onChangeText={setName}
              placeholder={t('setup.name')}
              placeholderTextColor={theme.textTertiary}
              autoFocus
            />
            <Text style={[styles.stepTitle, { color: theme.text, marginTop: Spacing.xl }]}>{t('setup.age')}</Text>
            <TextInput
              style={[styles.input, { color: theme.text, borderColor: theme.border, backgroundColor: theme.surfaceSecondary }]}
              value={age}
              onChangeText={setAge}
              placeholder="25"
              placeholderTextColor={theme.textTertiary}
              keyboardType="number-pad"
            />
            <Text style={[styles.stepTitle, { color: theme.text, marginTop: Spacing.xl }]}>{t('setup.gender')}</Text>
            <View style={styles.optionsRow}>
              <Option label={t('setup.male')} selected={gender === 'male'} onPress={() => setGender('male')} />
              <Option label={t('setup.female')} selected={gender === 'female'} onPress={() => setGender('female')} />
            </View>
          </View>
        );
      case 2:
        return (
          <View style={styles.formContainer}>
            <Text style={[styles.stepTitle, { color: theme.text }]}>{t('setup.height')}</Text>
            <TextInput
              style={[styles.input, { color: theme.text, borderColor: theme.border, backgroundColor: theme.surfaceSecondary }]}
              value={height}
              onChangeText={setHeight}
              placeholder="175"
              placeholderTextColor={theme.textTertiary}
              keyboardType="number-pad"
              autoFocus
            />
            <Text style={[styles.stepTitle, { color: theme.text, marginTop: Spacing.xl }]}>{t('setup.weight')}</Text>
            <TextInput
              style={[styles.input, { color: theme.text, borderColor: theme.border, backgroundColor: theme.surfaceSecondary }]}
              value={weight}
              onChangeText={setWeight}
              placeholder="75"
              placeholderTextColor={theme.textTertiary}
              keyboardType="decimal-pad"
            />
            <Text style={[styles.stepTitle, { color: theme.text, marginTop: Spacing.xl }]}>{t('setup.goalWeight')}</Text>
            <TextInput
              style={[styles.input, { color: theme.text, borderColor: theme.border, backgroundColor: theme.surfaceSecondary }]}
              value={goalWeight}
              onChangeText={setGoalWeight}
              placeholder="70"
              placeholderTextColor={theme.textTertiary}
              keyboardType="decimal-pad"
            />
          </View>
        );
      case 3:
        return (
          <View style={styles.formContainer}>
            <Text style={[styles.stepTitle, { color: theme.text }]}>{t('setup.activity')}</Text>
            {([
              ['sedentary', t('setup.sedentary')],
              ['light', t('setup.light')],
              ['moderate', t('setup.moderate')],
              ['active', t('setup.active')],
              ['veryActive', t('setup.veryActive')],
            ] as const).map(([key, label]) => (
              <Option key={key} label={label} selected={activity === key} onPress={() => setActivity(key)} />
            ))}
          </View>
        );
      case 4:
        return (
          <View style={styles.formContainer}>
            <Text style={[styles.stepTitle, { color: theme.text }]}>{t('setup.goal')}</Text>
            <Option label={t('setup.lose')} selected={goal === 'lose'} onPress={() => setGoal('lose')} />
            <Option label={t('setup.maintain')} selected={goal === 'maintain'} onPress={() => setGoal('maintain')} />
            <Option label={t('setup.gain')} selected={goal === 'gain'} onPress={() => setGoal('gain')} />
          </View>
        );
      case 5:
        return (
          <View style={styles.formContainer}>
            <Text style={[styles.stepTitle, { color: theme.text }]}>{t('setup.yourGoals')}</Text>
            <Text style={[styles.stepSubtitle, { color: theme.textSecondary }]}>{t('setup.calculated')}</Text>
            <View style={[styles.summaryCard, { backgroundColor: theme.surfaceSecondary }]}>
              <SummaryRow label={t('dashboard.calories')} value={`${previewGoals.calories} kcal`} color={theme.primary} />
              <SummaryRow label={t('dashboard.protein')} value={`${previewGoals.protein}g`} color={theme.protein} />
              <SummaryRow label={t('dashboard.carbs')} value={`${previewGoals.carbs}g`} color={theme.carbs} />
              <SummaryRow label={t('dashboard.fat')} value={`${previewGoals.fat}g`} color={theme.fat} />
              <SummaryRow label={t('dashboard.water')} value={`${previewGoals.water}L`} color={theme.water} />
            </View>
          </View>
        );
      default:
        return null;
    }
  };

  return (
    <KeyboardAvoidingView
      style={[styles.container, { backgroundColor: theme.background }]}
      behavior={Platform.OS === 'ios' ? 'padding' : undefined}
    >
      <View style={styles.progressBar}>
        {steps.map((_, i) => (
          <View
            key={i}
            style={[
              styles.progressDot,
              {
                backgroundColor: i <= step ? theme.primary : theme.surfaceSecondary,
                flex: 1,
              },
            ]}
          />
        ))}
      </View>

      <ScrollView contentContainerStyle={styles.content} showsVerticalScrollIndicator={false}>
        {renderStep()}
      </ScrollView>

      <View style={styles.footer}>
        {step > 0 && (
          <TouchableOpacity
            style={[styles.backBtn, { backgroundColor: theme.surfaceSecondary }]}
            onPress={() => setStep(step - 1)}
          >
            <Text style={[styles.backBtnText, { color: theme.text }]}>←</Text>
          </TouchableOpacity>
        )}
        <TouchableOpacity
          style={[
            styles.nextBtn,
            { backgroundColor: canProceed() ? theme.primary : theme.surfaceSecondary },
            step === 0 && { flex: 1 },
          ]}
          onPress={handleNext}
          disabled={!canProceed()}
        >
          <Text style={[styles.nextBtnText, { color: canProceed() ? '#fff' : theme.textTertiary }]}>
            {step === 0 ? t('setup.getStarted') : step === steps.length - 1 ? t('setup.finish') : t('setup.next')}
          </Text>
        </TouchableOpacity>
      </View>
    </KeyboardAvoidingView>
  );
}

function SummaryRow({ label, value, color }: { label: string; value: string; color: string }) {
  return (
    <View style={summaryStyles.row}>
      <View style={[summaryStyles.dot, { backgroundColor: color }]} />
      <Text style={[summaryStyles.label, { color: '#9CA3AF' }]}>{label}</Text>
      <Text style={[summaryStyles.value, { color }]}>{value}</Text>
    </View>
  );
}

const summaryStyles = StyleSheet.create({
  row: { flexDirection: 'row', alignItems: 'center', paddingVertical: Spacing.md },
  dot: { width: 8, height: 8, borderRadius: 4, marginRight: Spacing.md },
  label: { flex: 1, fontSize: FontSize.md },
  value: { fontSize: FontSize.md, fontWeight: FontWeight.bold },
});

const styles = StyleSheet.create({
  container: { flex: 1 },
  progressBar: {
    flexDirection: 'row',
    gap: 4,
    paddingHorizontal: Spacing.xxl,
    paddingTop: Platform.OS === 'ios' ? 60 : Spacing.xxl,
  },
  progressDot: { height: 4, borderRadius: 2 },
  content: {
    flex: 1,
    padding: Spacing.xxl,
    justifyContent: 'center',
  },
  welcomeContainer: { alignItems: 'center' },
  welcomeEmoji: { fontSize: 64, marginBottom: Spacing.xxl },
  welcomeTitle: { fontSize: FontSize.xxl, fontWeight: FontWeight.bold, textAlign: 'center', marginBottom: Spacing.md },
  welcomeSubtitle: { fontSize: FontSize.md, textAlign: 'center', lineHeight: 24 },
  formContainer: {},
  stepTitle: { fontSize: FontSize.xl, fontWeight: FontWeight.bold, marginBottom: Spacing.lg },
  stepSubtitle: { fontSize: FontSize.sm, marginBottom: Spacing.xl, marginTop: -Spacing.sm },
  input: {
    height: 52,
    borderWidth: 1.5,
    borderRadius: BorderRadius.md,
    paddingHorizontal: Spacing.lg,
    fontSize: FontSize.md,
    fontWeight: FontWeight.medium,
  },
  optionsRow: { flexDirection: 'row', gap: Spacing.md },
  option: {
    paddingVertical: Spacing.lg,
    paddingHorizontal: Spacing.xl,
    borderRadius: BorderRadius.md,
    marginBottom: Spacing.sm,
    flex: 1,
    alignItems: 'center',
  },
  optionText: { fontSize: FontSize.md, fontWeight: FontWeight.semibold },
  summaryCard: { borderRadius: BorderRadius.lg, padding: Spacing.lg },
  footer: {
    flexDirection: 'row',
    gap: Spacing.md,
    paddingHorizontal: Spacing.xxl,
    paddingBottom: Platform.OS === 'ios' ? 40 : Spacing.xxl,
  },
  backBtn: {
    width: 52,
    height: 52,
    borderRadius: BorderRadius.md,
    justifyContent: 'center',
    alignItems: 'center',
  },
  backBtnText: { fontSize: FontSize.xl, fontWeight: FontWeight.bold },
  nextBtn: {
    flex: 2,
    height: 52,
    borderRadius: BorderRadius.md,
    justifyContent: 'center',
    alignItems: 'center',
  },
  nextBtnText: { fontSize: FontSize.md, fontWeight: FontWeight.semibold },
});
