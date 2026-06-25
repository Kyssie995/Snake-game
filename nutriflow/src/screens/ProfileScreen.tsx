import React from 'react';
import { View, Text, ScrollView, StyleSheet, TouchableOpacity, Switch } from 'react-native';
import { useTheme, useIsDark } from '../hooks/useTheme';
import { useStore } from '../store';
import { t } from '../i18n';
import { BorderRadius, FontSize, FontWeight, Spacing } from '../constants/theme';

export default function ProfileScreen() {
  const theme = useTheme();
  const isDark = useIsDark();
  const profile = useStore(s => s.profile);
  const goals = useStore(s => s.goals);
  const settings = useStore(s => s.settings);
  const updateSettings = useStore(s => s.updateSettings);
  const streak = useStore(s => s.streak);

  const toggleTheme = () => {
    updateSettings({ theme: isDark ? 'light' : 'dark' });
  };

  const toggleLanguage = () => {
    updateSettings({ language: settings.language === 'de' ? 'en' : 'de' });
  };

  const tierLabels: Record<string, string> = {
    free: t('profile.free'),
    student: t('profile.student'),
    premium: t('profile.premium'),
    lifetime: t('profile.lifetime'),
  };

  return (
    <ScrollView
      style={[styles.container, { backgroundColor: theme.background }]}
      contentContainerStyle={styles.content}
      showsVerticalScrollIndicator={false}
    >
      <Text style={[styles.title, { color: theme.text }]}>{t('profile.title')}</Text>

      <View style={[styles.profileCard, { backgroundColor: theme.surface, shadowColor: theme.cardShadow }]}>
        <View style={[styles.avatar, { backgroundColor: theme.primary + '20' }]}>
          <Text style={[styles.avatarText, { color: theme.primary }]}>
            {(profile?.name || 'N')[0].toUpperCase()}
          </Text>
        </View>
        <Text style={[styles.profileName, { color: theme.text }]}>{profile?.name || 'NutriFlow'}</Text>
        <View style={[styles.tierBadge, { backgroundColor: theme.primary + '15' }]}>
          <Text style={[styles.tierText, { color: theme.primary }]}>
            {tierLabels[settings.subscription]}
          </Text>
        </View>

        <View style={styles.profileStats}>
          <View style={styles.profileStat}>
            <Text style={[styles.profileStatValue, { color: theme.text }]}>{streak.currentStreak}</Text>
            <Text style={[styles.profileStatLabel, { color: theme.textTertiary }]}>Streak</Text>
          </View>
          <View style={[styles.profileStatDivider, { backgroundColor: theme.border }]} />
          <View style={styles.profileStat}>
            <Text style={[styles.profileStatValue, { color: theme.text }]}>{profile?.currentWeight || '—'}</Text>
            <Text style={[styles.profileStatLabel, { color: theme.textTertiary }]}>kg</Text>
          </View>
          <View style={[styles.profileStatDivider, { backgroundColor: theme.border }]} />
          <View style={styles.profileStat}>
            <Text style={[styles.profileStatValue, { color: theme.text }]}>{goals.calories}</Text>
            <Text style={[styles.profileStatLabel, { color: theme.textTertiary }]}>kcal</Text>
          </View>
        </View>
      </View>

      <View style={[styles.section, { backgroundColor: theme.surface, shadowColor: theme.cardShadow }]}>
        <Text style={[styles.sectionTitle, { color: theme.text }]}>{t('profile.goals')}</Text>

        <View style={styles.goalRow}>
          <Text style={[styles.goalLabel, { color: theme.textSecondary }]}>{t('dashboard.calories')}</Text>
          <Text style={[styles.goalValue, { color: theme.text }]}>{goals.calories} kcal</Text>
        </View>
        <View style={styles.goalRow}>
          <Text style={[styles.goalLabel, { color: theme.textSecondary }]}>{t('dashboard.protein')}</Text>
          <Text style={[styles.goalValue, { color: theme.protein }]}>{goals.protein}g</Text>
        </View>
        <View style={styles.goalRow}>
          <Text style={[styles.goalLabel, { color: theme.textSecondary }]}>{t('dashboard.carbs')}</Text>
          <Text style={[styles.goalValue, { color: theme.carbs }]}>{goals.carbs}g</Text>
        </View>
        <View style={styles.goalRow}>
          <Text style={[styles.goalLabel, { color: theme.textSecondary }]}>{t('dashboard.fat')}</Text>
          <Text style={[styles.goalValue, { color: theme.fat }]}>{goals.fat}g</Text>
        </View>
        <View style={styles.goalRow}>
          <Text style={[styles.goalLabel, { color: theme.textSecondary }]}>{t('dashboard.water')}</Text>
          <Text style={[styles.goalValue, { color: theme.water }]}>{goals.water}L</Text>
        </View>
      </View>

      <View style={[styles.section, { backgroundColor: theme.surface, shadowColor: theme.cardShadow }]}>
        <Text style={[styles.sectionTitle, { color: theme.text }]}>{t('profile.settings')}</Text>

        <View style={styles.settingRow}>
          <View>
            <Text style={[styles.settingLabel, { color: theme.text }]}>{t('profile.theme')}</Text>
            <Text style={[styles.settingDesc, { color: theme.textTertiary }]}>
              {isDark ? t('profile.darkMode') : t('profile.lightMode')}
            </Text>
          </View>
          <Switch
            value={isDark}
            onValueChange={toggleTheme}
            trackColor={{ false: theme.surfaceSecondary, true: theme.primary + '50' }}
            thumbColor={isDark ? theme.primary : theme.textTertiary}
          />
        </View>

        <View style={[styles.settingDivider, { backgroundColor: theme.border }]} />

        <TouchableOpacity style={styles.settingRow} onPress={toggleLanguage}>
          <View>
            <Text style={[styles.settingLabel, { color: theme.text }]}>{t('profile.language')}</Text>
            <Text style={[styles.settingDesc, { color: theme.textTertiary }]}>
              {settings.language === 'de' ? 'Deutsch' : 'English'}
            </Text>
          </View>
          <Text style={[styles.settingChevron, { color: theme.textTertiary }]}>›</Text>
        </TouchableOpacity>

        <View style={[styles.settingDivider, { backgroundColor: theme.border }]} />

        <TouchableOpacity style={styles.settingRow}>
          <View>
            <Text style={[styles.settingLabel, { color: theme.text }]}>{t('profile.subscription')}</Text>
            <Text style={[styles.settingDesc, { color: theme.textTertiary }]}>
              {tierLabels[settings.subscription]}
            </Text>
          </View>
          <Text style={[styles.settingChevron, { color: theme.textTertiary }]}>›</Text>
        </TouchableOpacity>
      </View>

      <View style={[styles.section, { backgroundColor: theme.surface, shadowColor: theme.cardShadow }]}>
        <TouchableOpacity style={styles.settingRow}>
          <Text style={[styles.settingLabel, { color: theme.text }]}>{t('profile.mealCategories')}</Text>
          <Text style={[styles.settingChevron, { color: theme.textTertiary }]}>›</Text>
        </TouchableOpacity>
        <View style={[styles.settingDivider, { backgroundColor: theme.border }]} />
        <TouchableOpacity style={styles.settingRow}>
          <Text style={[styles.settingLabel, { color: theme.text }]}>{t('profile.export')}</Text>
          <Text style={[styles.settingChevron, { color: theme.textTertiary }]}>›</Text>
        </TouchableOpacity>
        <View style={[styles.settingDivider, { backgroundColor: theme.border }]} />
        <TouchableOpacity style={styles.settingRow}>
          <Text style={[styles.settingLabel, { color: theme.text }]}>{t('profile.privacy')}</Text>
          <Text style={[styles.settingChevron, { color: theme.textTertiary }]}>›</Text>
        </TouchableOpacity>
      </View>

      <View style={[styles.section, { backgroundColor: theme.surface, shadowColor: theme.cardShadow }]}>
        <TouchableOpacity style={styles.settingRow}>
          <View>
            <Text style={[styles.settingLabel, { color: theme.text }]}>{t('profile.about')}</Text>
            <Text style={[styles.settingDesc, { color: theme.textTertiary }]}>NutriFlow v1.0.0</Text>
          </View>
          <Text style={[styles.settingChevron, { color: theme.textTertiary }]}>›</Text>
        </TouchableOpacity>
      </View>

      <View style={{ height: 100 }} />
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1 },
  content: { padding: Spacing.lg, paddingTop: Spacing.xxl },
  title: { fontSize: FontSize.xxl, fontWeight: FontWeight.bold, marginBottom: Spacing.lg },
  profileCard: {
    borderRadius: BorderRadius.xl,
    padding: Spacing.xxl,
    alignItems: 'center',
    marginBottom: Spacing.lg,
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 1,
    shadowRadius: 12,
    elevation: 5,
  },
  avatar: {
    width: 72,
    height: 72,
    borderRadius: 36,
    justifyContent: 'center',
    alignItems: 'center',
    marginBottom: Spacing.md,
  },
  avatarText: { fontSize: FontSize.xxl, fontWeight: FontWeight.bold },
  profileName: { fontSize: FontSize.xl, fontWeight: FontWeight.bold, marginBottom: Spacing.sm },
  tierBadge: { paddingHorizontal: Spacing.md, paddingVertical: Spacing.xs, borderRadius: BorderRadius.full },
  tierText: { fontSize: FontSize.xs, fontWeight: FontWeight.semibold },
  profileStats: {
    flexDirection: 'row',
    alignItems: 'center',
    marginTop: Spacing.xl,
    gap: Spacing.xl,
  },
  profileStat: { alignItems: 'center' },
  profileStatValue: { fontSize: FontSize.xl, fontWeight: FontWeight.bold },
  profileStatLabel: { fontSize: FontSize.xs, fontWeight: FontWeight.medium, marginTop: 2 },
  profileStatDivider: { width: 1, height: 28 },
  section: {
    borderRadius: BorderRadius.lg,
    padding: Spacing.lg,
    marginBottom: Spacing.md,
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 1,
    shadowRadius: 6,
    elevation: 3,
  },
  sectionTitle: { fontSize: FontSize.lg, fontWeight: FontWeight.semibold, marginBottom: Spacing.lg },
  goalRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    paddingVertical: Spacing.sm,
  },
  goalLabel: { fontSize: FontSize.sm },
  goalValue: { fontSize: FontSize.sm, fontWeight: FontWeight.semibold },
  settingRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingVertical: Spacing.md,
  },
  settingLabel: { fontSize: FontSize.md, fontWeight: FontWeight.medium },
  settingDesc: { fontSize: FontSize.xs, marginTop: 2 },
  settingChevron: { fontSize: 22, fontWeight: FontWeight.medium },
  settingDivider: { height: StyleSheet.hairlineWidth },
});
