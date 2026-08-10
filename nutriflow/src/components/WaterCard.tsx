import React from 'react';
import { View, Text, StyleSheet, TouchableOpacity } from 'react-native';
import { useTheme } from '../hooks/useTheme';
import { useStore } from '../store';
import { t } from '../i18n';
import { BorderRadius, FontSize, FontWeight, Spacing } from '../constants/theme';

export default function WaterCard() {
  const theme = useTheme();
  const selectedDate = useStore(s => s.selectedDate);
  const waterLog = useStore(s => s.waterLog);
  const water = waterLog[selectedDate] || 0;
  const waterGoal = useStore(s => s.goals.water);
  const addWater = useStore(s => s.addWater);

  const waterMl = Math.round(water);
  const goalMl = Math.round(waterGoal * 1000);
  const progress = goalMl > 0 ? Math.min(waterMl / goalMl, 1) : 0;

  return (
    <View style={[styles.card, { backgroundColor: theme.surface, shadowColor: theme.cardShadow }]}>
      <View style={styles.header}>
        <View style={styles.headerLeft}>
          <Text style={styles.icon}>💧</Text>
          <Text style={[styles.title, { color: theme.text }]}>{t('water.title')}</Text>
        </View>
        <Text style={[styles.amount, { color: theme.water }]}>
          {waterMl} <Text style={{ color: theme.textTertiary, fontSize: FontSize.xs }}>/ {goalMl} ml</Text>
        </Text>
      </View>

      <View style={[styles.track, { backgroundColor: theme.surfaceSecondary }]}>
        <View style={[styles.fill, { backgroundColor: theme.water, width: `${progress * 100}%` }]} />
      </View>

      <View style={styles.buttons}>
        <TouchableOpacity
          style={[styles.btn, { backgroundColor: theme.surfaceSecondary }]}
          onPress={() => addWater(250)}
          activeOpacity={0.7}
        >
          <Text style={[styles.btnText, { color: theme.water }]}>+250ml</Text>
        </TouchableOpacity>
        <TouchableOpacity
          style={[styles.btn, { backgroundColor: theme.surfaceSecondary }]}
          onPress={() => addWater(500)}
          activeOpacity={0.7}
        >
          <Text style={[styles.btnText, { color: theme.water }]}>+500ml</Text>
        </TouchableOpacity>
        <TouchableOpacity
          style={[styles.btn, { backgroundColor: theme.water }]}
          onPress={() => addWater(1000)}
          activeOpacity={0.7}
        >
          <Text style={[styles.btnText, { color: '#fff' }]}>+1L</Text>
        </TouchableOpacity>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  card: {
    borderRadius: BorderRadius.lg,
    padding: Spacing.lg,
    marginBottom: Spacing.md,
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 1,
    shadowRadius: 8,
    elevation: 3,
  },
  header: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: Spacing.md,
  },
  headerLeft: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.sm,
  },
  icon: {
    fontSize: 20,
  },
  title: {
    fontSize: FontSize.md,
    fontWeight: FontWeight.semibold,
  },
  amount: {
    fontSize: FontSize.md,
    fontWeight: FontWeight.bold,
  },
  track: {
    height: 10,
    borderRadius: BorderRadius.full,
    overflow: 'hidden',
    marginBottom: Spacing.md,
  },
  fill: {
    height: '100%',
    borderRadius: BorderRadius.full,
  },
  buttons: {
    flexDirection: 'row',
    gap: Spacing.sm,
  },
  btn: {
    flex: 1,
    paddingVertical: Spacing.sm,
    borderRadius: BorderRadius.md,
    alignItems: 'center',
  },
  btnText: {
    fontSize: FontSize.sm,
    fontWeight: FontWeight.semibold,
  },
});
