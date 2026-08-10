import React from 'react';
import {
  View,
  Text,
  ScrollView,
  StyleSheet,
  TouchableOpacity,
  Modal,
  Platform,
} from 'react-native';
import { useTheme } from '../hooks/useTheme';
import { useStore } from '../store';
import { BorderRadius, FontSize, FontWeight, Spacing } from '../constants/theme';

interface Challenge {
  id: string;
  title: string;
  description: string;
  icon: string;
  duration: string;
  progress: number;
  total: number;
  reward: string;
  active: boolean;
}

interface Props {
  visible: boolean;
  onClose: () => void;
}

export default function ChallengesScreen({ visible, onClose }: Props) {
  const theme = useTheme();
  const settings = useStore(s => s.settings);
  const streak = useStore(s => s.streak);
  const lang = settings.language;
  const isPremium = settings.subscription !== 'free';

  const challenges: Challenge[] = [
    {
      id: '1',
      title: lang === 'de' ? '7-Tage Protein Challenge' : '7-Day Protein Challenge',
      description: lang === 'de' ? 'Erreiche 7 Tage in Folge dein Proteinziel' : 'Hit your protein goal 7 days in a row',
      icon: '💪',
      duration: lang === 'de' ? '7 Tage' : '7 days',
      progress: Math.min(streak.currentStreak, 7),
      total: 7,
      reward: lang === 'de' ? 'Protein-Master Badge' : 'Protein Master Badge',
      active: true,
    },
    {
      id: '2',
      title: lang === 'de' ? 'Wasser Champion' : 'Water Champion',
      description: lang === 'de' ? 'Trinke 5 Tage lang mindestens 2.5L Wasser' : 'Drink at least 2.5L water for 5 days',
      icon: '💧',
      duration: lang === 'de' ? '5 Tage' : '5 days',
      progress: 0,
      total: 5,
      reward: lang === 'de' ? 'Hydration-Badge' : 'Hydration Badge',
      active: true,
    },
    {
      id: '3',
      title: lang === 'de' ? '30-Tage Streak' : '30-Day Streak',
      description: lang === 'de' ? 'Tracke 30 Tage ohne Unterbrechung' : 'Track 30 days without a break',
      icon: '🔥',
      duration: lang === 'de' ? '30 Tage' : '30 days',
      progress: Math.min(streak.currentStreak, 30),
      total: 30,
      reward: lang === 'de' ? 'Diamant-Badge' : 'Diamond Badge',
      active: true,
    },
    {
      id: '4',
      title: lang === 'de' ? 'Clean Eating Woche' : 'Clean Eating Week',
      description: lang === 'de' ? 'Bleibe 7 Tage unter deinem Kalorienziel' : 'Stay under your calorie goal for 7 days',
      icon: '🥗',
      duration: lang === 'de' ? '7 Tage' : '7 days',
      progress: 0,
      total: 7,
      reward: lang === 'de' ? 'Disziplin-Badge' : 'Discipline Badge',
      active: false,
    },
    {
      id: '5',
      title: lang === 'de' ? 'Gemüse Power' : 'Veggie Power',
      description: lang === 'de' ? 'Iss 5 Tage lang mindestens 30g Ballaststoffe' : 'Eat at least 30g fiber for 5 days',
      icon: '🥦',
      duration: lang === 'de' ? '5 Tage' : '5 days',
      progress: 0,
      total: 5,
      reward: lang === 'de' ? 'Veggie-Badge' : 'Veggie Badge',
      active: false,
    },
  ];

  if (!isPremium) {
    return (
      <Modal visible={visible} animationType="slide" presentationStyle="pageSheet">
        <View style={[styles.container, { backgroundColor: theme.background }]}>
          <View style={[styles.header, { borderBottomColor: theme.border }]}>
            <TouchableOpacity onPress={onClose}>
              <Text style={[styles.closeBtn, { color: theme.primary }]}>✕</Text>
            </TouchableOpacity>
            <Text style={[styles.headerTitle, { color: theme.text }]}>Challenges</Text>
            <View style={{ width: 40 }} />
          </View>
          <View style={styles.premiumGate}>
            <Text style={{ fontSize: 48 }}>🏆</Text>
            <Text style={[styles.premiumTitle, { color: theme.text }]}>Premium Feature</Text>
            <Text style={[styles.premiumDesc, { color: theme.textSecondary }]}>
              {lang === 'de'
                ? 'Nimm an Challenges teil und verdiene exklusive Badges für deine Erfolge.'
                : 'Join challenges and earn exclusive badges for your achievements.'}
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
          <Text style={[styles.headerTitle, { color: theme.text }]}>Challenges</Text>
          <View style={{ width: 40 }} />
        </View>

        <ScrollView contentContainerStyle={styles.content} showsVerticalScrollIndicator={false}>
          <Text style={[styles.sectionLabel, { color: theme.text }]}>
            {lang === 'de' ? 'Aktive Challenges' : 'Active Challenges'}
          </Text>

          {challenges.filter(c => c.active).map(challenge => {
            const progressPct = challenge.total > 0 ? challenge.progress / challenge.total : 0;
            const isComplete = challenge.progress >= challenge.total;

            return (
              <View
                key={challenge.id}
                style={[
                  styles.challengeCard,
                  {
                    backgroundColor: theme.surface,
                    shadowColor: theme.cardShadow,
                    borderColor: isComplete ? theme.success : theme.border,
                    borderWidth: isComplete ? 1.5 : 0,
                  },
                ]}
              >
                <View style={styles.challengeHeader}>
                  <Text style={styles.challengeIcon}>{challenge.icon}</Text>
                  <View style={styles.challengeInfo}>
                    <Text style={[styles.challengeTitle, { color: theme.text }]}>{challenge.title}</Text>
                    <Text style={[styles.challengeDesc, { color: theme.textTertiary }]}>{challenge.description}</Text>
                  </View>
                </View>

                <View style={styles.challengeProgress}>
                  <View style={[styles.progressTrack, { backgroundColor: theme.surfaceSecondary }]}>
                    <View
                      style={[
                        styles.progressFill,
                        {
                          backgroundColor: isComplete ? theme.success : theme.primary,
                          width: `${Math.min(progressPct * 100, 100)}%`,
                        },
                      ]}
                    />
                  </View>
                  <Text style={[styles.progressText, { color: theme.textSecondary }]}>
                    {challenge.progress}/{challenge.total} {challenge.duration}
                  </Text>
                </View>

                <View style={styles.challengeFooter}>
                  <View style={styles.rewardRow}>
                    <Text style={{ fontSize: 14 }}>🏅</Text>
                    <Text style={[styles.rewardText, { color: theme.textTertiary }]}>{challenge.reward}</Text>
                  </View>
                  {isComplete && (
                    <View style={[styles.completeBadge, { backgroundColor: theme.success + '20' }]}>
                      <Text style={[styles.completeText, { color: theme.success }]}>
                        {lang === 'de' ? 'Geschafft!' : 'Complete!'}
                      </Text>
                    </View>
                  )}
                </View>
              </View>
            );
          })}

          <Text style={[styles.sectionLabel, { color: theme.text, marginTop: Spacing.xl }]}>
            {lang === 'de' ? 'Kommende Challenges' : 'Upcoming Challenges'}
          </Text>

          {challenges.filter(c => !c.active).map(challenge => (
            <View
              key={challenge.id}
              style={[styles.challengeCard, { backgroundColor: theme.surface, shadowColor: theme.cardShadow, opacity: 0.7 }]}
            >
              <View style={styles.challengeHeader}>
                <Text style={styles.challengeIcon}>{challenge.icon}</Text>
                <View style={styles.challengeInfo}>
                  <Text style={[styles.challengeTitle, { color: theme.text }]}>{challenge.title}</Text>
                  <Text style={[styles.challengeDesc, { color: theme.textTertiary }]}>{challenge.description}</Text>
                </View>
              </View>
              <TouchableOpacity style={[styles.joinBtn, { backgroundColor: theme.primary + '15' }]}>
                <Text style={[styles.joinBtnText, { color: theme.primary }]}>
                  {lang === 'de' ? 'Beitreten' : 'Join'}
                </Text>
              </TouchableOpacity>
            </View>
          ))}

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
  content: { padding: Spacing.lg },
  sectionLabel: { fontSize: FontSize.lg, fontWeight: FontWeight.bold, marginBottom: Spacing.lg },
  challengeCard: {
    borderRadius: BorderRadius.lg,
    padding: Spacing.lg,
    marginBottom: Spacing.md,
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 1,
    shadowRadius: 6,
    elevation: 3,
  },
  challengeHeader: { flexDirection: 'row', gap: Spacing.md, marginBottom: Spacing.md },
  challengeIcon: { fontSize: 32 },
  challengeInfo: { flex: 1 },
  challengeTitle: { fontSize: FontSize.md, fontWeight: FontWeight.semibold },
  challengeDesc: { fontSize: FontSize.xs, marginTop: 2, lineHeight: 16 },
  challengeProgress: { marginBottom: Spacing.md },
  progressTrack: { height: 8, borderRadius: 4, overflow: 'hidden', marginBottom: 4 },
  progressFill: { height: '100%', borderRadius: 4 },
  progressText: { fontSize: FontSize.xs, fontWeight: FontWeight.medium },
  challengeFooter: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' },
  rewardRow: { flexDirection: 'row', alignItems: 'center', gap: 4 },
  rewardText: { fontSize: FontSize.xs },
  completeBadge: { paddingHorizontal: Spacing.md, paddingVertical: 3, borderRadius: BorderRadius.full },
  completeText: { fontSize: FontSize.xs, fontWeight: FontWeight.semibold },
  joinBtn: { paddingVertical: Spacing.sm, borderRadius: BorderRadius.md, alignItems: 'center', marginTop: Spacing.sm },
  joinBtnText: { fontSize: FontSize.sm, fontWeight: FontWeight.semibold },
  premiumGate: { flex: 1, justifyContent: 'center', alignItems: 'center', padding: Spacing.xxl },
  premiumTitle: { fontSize: FontSize.xl, fontWeight: FontWeight.bold, marginTop: Spacing.lg },
  premiumDesc: { fontSize: FontSize.sm, textAlign: 'center', marginTop: Spacing.sm, lineHeight: 22, maxWidth: 300 },
  upgradeBtn: { paddingHorizontal: Spacing.xxl, paddingVertical: Spacing.md, borderRadius: BorderRadius.md, marginTop: Spacing.xxl },
  upgradeBtnText: { color: '#fff', fontSize: FontSize.md, fontWeight: FontWeight.semibold },
});
