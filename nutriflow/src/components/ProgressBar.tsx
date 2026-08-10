import React from 'react';
import { View, Text, StyleSheet } from 'react-native';
import { BorderRadius, FontSize, FontWeight, Spacing } from '../constants/theme';
import { useTheme } from '../hooks/useTheme';

interface Props {
  label: string;
  current: number;
  goal: number;
  color: string;
  unit?: string;
}

export default function ProgressBar({ label, current, goal, color, unit = 'g' }: Props) {
  const theme = useTheme();
  const progress = goal > 0 ? Math.min(current / goal, 1) : 0;
  const isOver = current > goal;

  return (
    <View style={styles.container}>
      <View style={styles.header}>
        <Text style={[styles.label, { color: theme.textSecondary }]}>{label}</Text>
        <Text style={[styles.values, { color: isOver ? theme.warning : theme.text }]}>
          {Math.round(current)}{' '}
          <Text style={{ color: theme.textTertiary }}>/ {goal}{unit}</Text>
        </Text>
      </View>
      <View style={[styles.track, { backgroundColor: theme.surfaceSecondary }]}>
        <View
          style={[
            styles.fill,
            {
              backgroundColor: isOver ? theme.warning : color,
              width: `${progress * 100}%`,
            },
          ]}
        />
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    marginBottom: Spacing.md,
  },
  header: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: Spacing.xs,
  },
  label: {
    fontSize: FontSize.sm,
    fontWeight: FontWeight.medium,
  },
  values: {
    fontSize: FontSize.sm,
    fontWeight: FontWeight.semibold,
  },
  track: {
    height: 8,
    borderRadius: BorderRadius.full,
    overflow: 'hidden',
  },
  fill: {
    height: '100%',
    borderRadius: BorderRadius.full,
  },
});
