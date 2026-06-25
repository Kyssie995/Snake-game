import React from 'react';
import { View, Text, StyleSheet } from 'react-native';
import Svg, { Circle } from 'react-native-svg';
import { FontSize, FontWeight } from '../constants/theme';

interface Props {
  size: number;
  strokeWidth: number;
  progress: number;
  color: string;
  bgColor: string;
  textColor: string;
  value: string;
  label: string;
  labelColor: string;
}

export default function ProgressRing({
  size,
  strokeWidth,
  progress,
  color,
  bgColor,
  textColor,
  value,
  label,
  labelColor,
}: Props) {
  const radius = (size - strokeWidth) / 2;
  const circumference = 2 * Math.PI * radius;
  const clampedProgress = Math.min(Math.max(progress, 0), 1);
  const strokeDashoffset = circumference * (1 - clampedProgress);
  const center = size / 2;

  return (
    <View style={[styles.container, { width: size, height: size }]}>
      <Svg width={size} height={size}>
        <Circle
          cx={center}
          cy={center}
          r={radius}
          stroke={bgColor}
          strokeWidth={strokeWidth}
          fill="none"
        />
        <Circle
          cx={center}
          cy={center}
          r={radius}
          stroke={color}
          strokeWidth={strokeWidth}
          fill="none"
          strokeDasharray={circumference}
          strokeDashoffset={strokeDashoffset}
          strokeLinecap="round"
          rotation="-90"
          origin={`${center}, ${center}`}
        />
      </Svg>
      <View style={styles.textContainer}>
        <Text style={[styles.value, { color: textColor, fontSize: size > 120 ? FontSize.xxl : FontSize.md }]}>
          {value}
        </Text>
        <Text style={[styles.label, { color: labelColor, fontSize: size > 120 ? FontSize.xs : 9 }]}>
          {label}
        </Text>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    justifyContent: 'center',
    alignItems: 'center',
  },
  textContainer: {
    position: 'absolute',
    justifyContent: 'center',
    alignItems: 'center',
  },
  value: {
    fontWeight: FontWeight.bold,
  },
  label: {
    fontWeight: FontWeight.medium,
    marginTop: 2,
  },
});
