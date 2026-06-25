import React, { useState } from 'react';
import {
  View,
  Text,
  TextInput,
  StyleSheet,
  TouchableOpacity,
  ActivityIndicator,
  KeyboardAvoidingView,
  Platform,
  ScrollView,
} from 'react-native';
import {
  signInWithEmailAndPassword,
  createUserWithEmailAndPassword,
  sendPasswordResetEmail,
} from 'firebase/auth';
import { auth } from '../config/firebase';
import { useTheme } from '../hooks/useTheme';
import { useStore } from '../store';
import { BorderRadius, FontSize, FontWeight, Spacing } from '../constants/theme';

export default function AuthScreen() {
  const theme = useTheme();
  const lang = useStore(s => s.settings.language);
  const [mode, setMode] = useState<'login' | 'register'>('login');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const [resetSent, setResetSent] = useState(false);

  const de = lang === 'de';

  const errorMessages: Record<string, string> = de ? {
    'auth/invalid-email': 'Ungültige E-Mail-Adresse',
    'auth/user-disabled': 'Konto deaktiviert',
    'auth/user-not-found': 'Kein Konto mit dieser E-Mail gefunden',
    'auth/wrong-password': 'Falsches Passwort',
    'auth/email-already-in-use': 'E-Mail wird bereits verwendet',
    'auth/weak-password': 'Passwort muss mindestens 6 Zeichen haben',
    'auth/invalid-credential': 'E-Mail oder Passwort falsch',
    'passwords-mismatch': 'Passwörter stimmen nicht überein',
  } : {
    'auth/invalid-email': 'Invalid email address',
    'auth/user-disabled': 'Account disabled',
    'auth/user-not-found': 'No account found with this email',
    'auth/wrong-password': 'Wrong password',
    'auth/email-already-in-use': 'Email already in use',
    'auth/weak-password': 'Password must be at least 6 characters',
    'auth/invalid-credential': 'Invalid email or password',
    'passwords-mismatch': 'Passwords do not match',
  };

  function getErrorMessage(code: string): string {
    return errorMessages[code] || (de ? 'Ein Fehler ist aufgetreten' : 'An error occurred');
  }

  async function handleSubmit() {
    setError('');
    if (!email || !password) {
      setError(de ? 'Bitte alle Felder ausfüllen' : 'Please fill in all fields');
      return;
    }
    if (mode === 'register' && password !== confirmPassword) {
      setError(getErrorMessage('passwords-mismatch'));
      return;
    }

    setLoading(true);
    try {
      if (mode === 'login') {
        await signInWithEmailAndPassword(auth, email.trim(), password);
      } else {
        await createUserWithEmailAndPassword(auth, email.trim(), password);
      }
    } catch (e: any) {
      setError(getErrorMessage(e.code));
    } finally {
      setLoading(false);
    }
  }

  async function handleResetPassword() {
    if (!email) {
      setError(de ? 'Bitte E-Mail eingeben' : 'Please enter your email');
      return;
    }
    setLoading(true);
    try {
      await sendPasswordResetEmail(auth, email.trim());
      setResetSent(true);
      setError('');
    } catch (e: any) {
      setError(getErrorMessage(e.code));
    } finally {
      setLoading(false);
    }
  }

  return (
    <KeyboardAvoidingView
      style={[styles.container, { backgroundColor: theme.background }]}
      behavior={Platform.OS === 'ios' ? 'padding' : undefined}
    >
      <ScrollView
        contentContainerStyle={styles.scroll}
        keyboardShouldPersistTaps="handled"
        showsVerticalScrollIndicator={false}
      >
        <View style={styles.logoSection}>
          <Text style={styles.logoEmoji}>🍎</Text>
          <Text style={[styles.appName, { color: theme.text }]}>NutriFlow</Text>
          <Text style={[styles.subtitle, { color: theme.textSecondary }]}>
            {de ? 'Kalorien zählen in unter 5 Sekunden' : 'Count calories in under 5 seconds'}
          </Text>
        </View>

        <View style={[styles.card, { backgroundColor: theme.surface }]}>
          <View style={[styles.tabRow, { backgroundColor: theme.surfaceSecondary }]}>
            <TouchableOpacity
              style={[styles.tab, mode === 'login' && { backgroundColor: theme.primary }]}
              onPress={() => { setMode('login'); setError(''); setResetSent(false); }}
            >
              <Text style={[styles.tabText, { color: mode === 'login' ? '#fff' : theme.textSecondary }]}>
                {de ? 'Anmelden' : 'Login'}
              </Text>
            </TouchableOpacity>
            <TouchableOpacity
              style={[styles.tab, mode === 'register' && { backgroundColor: theme.primary }]}
              onPress={() => { setMode('register'); setError(''); setResetSent(false); }}
            >
              <Text style={[styles.tabText, { color: mode === 'register' ? '#fff' : theme.textSecondary }]}>
                {de ? 'Registrieren' : 'Register'}
              </Text>
            </TouchableOpacity>
          </View>

          <View style={styles.form}>
            <Text style={[styles.label, { color: theme.textSecondary }]}>
              {de ? 'E-Mail' : 'Email'}
            </Text>
            <TextInput
              style={[styles.input, { backgroundColor: theme.surfaceSecondary, color: theme.text, borderColor: theme.border }]}
              value={email}
              onChangeText={setEmail}
              placeholder={de ? 'deine@email.de' : 'your@email.com'}
              placeholderTextColor={theme.textTertiary}
              keyboardType="email-address"
              autoCapitalize="none"
              autoCorrect={false}
            />

            <Text style={[styles.label, { color: theme.textSecondary }]}>
              {de ? 'Passwort' : 'Password'}
            </Text>
            <TextInput
              style={[styles.input, { backgroundColor: theme.surfaceSecondary, color: theme.text, borderColor: theme.border }]}
              value={password}
              onChangeText={setPassword}
              placeholder={de ? 'Mindestens 6 Zeichen' : 'At least 6 characters'}
              placeholderTextColor={theme.textTertiary}
              secureTextEntry
            />

            {mode === 'register' && (
              <>
                <Text style={[styles.label, { color: theme.textSecondary }]}>
                  {de ? 'Passwort bestätigen' : 'Confirm Password'}
                </Text>
                <TextInput
                  style={[styles.input, { backgroundColor: theme.surfaceSecondary, color: theme.text, borderColor: theme.border }]}
                  value={confirmPassword}
                  onChangeText={setConfirmPassword}
                  placeholder={de ? 'Passwort wiederholen' : 'Repeat password'}
                  placeholderTextColor={theme.textTertiary}
                  secureTextEntry
                />
              </>
            )}

            {error !== '' && (
              <View style={[styles.errorBox, { backgroundColor: theme.accent + '15' }]}>
                <Text style={[styles.errorText, { color: theme.accent }]}>{error}</Text>
              </View>
            )}

            {resetSent && (
              <View style={[styles.successBox, { backgroundColor: theme.primary + '15' }]}>
                <Text style={[styles.successText, { color: theme.primary }]}>
                  {de ? 'E-Mail zum Zurücksetzen gesendet!' : 'Password reset email sent!'}
                </Text>
              </View>
            )}

            <TouchableOpacity
              style={[styles.submitBtn, { backgroundColor: theme.primary }]}
              onPress={handleSubmit}
              disabled={loading}
              activeOpacity={0.8}
            >
              {loading ? (
                <ActivityIndicator color="#fff" />
              ) : (
                <Text style={styles.submitText}>
                  {mode === 'login'
                    ? (de ? 'Anmelden' : 'Login')
                    : (de ? 'Konto erstellen' : 'Create Account')}
                </Text>
              )}
            </TouchableOpacity>

            {mode === 'login' && (
              <TouchableOpacity onPress={handleResetPassword} style={styles.forgotBtn}>
                <Text style={[styles.forgotText, { color: theme.primary }]}>
                  {de ? 'Passwort vergessen?' : 'Forgot password?'}
                </Text>
              </TouchableOpacity>
            )}
          </View>
        </View>

        <View style={styles.privacyNote}>
          <Text style={[styles.privacyText, { color: theme.textTertiary }]}>
            🔒 {de
              ? 'Deine Daten werden verschlüsselt in der Cloud gespeichert und zwischen deinen Geräten synchronisiert.'
              : 'Your data is encrypted in the cloud and synced across your devices.'}
          </Text>
        </View>
      </ScrollView>
    </KeyboardAvoidingView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1 },
  scroll: {
    flexGrow: 1,
    justifyContent: 'center',
    padding: Spacing.lg,
  },
  logoSection: {
    alignItems: 'center',
    marginBottom: Spacing.xxl,
  },
  logoEmoji: { fontSize: 56 },
  appName: {
    fontSize: 32,
    fontWeight: FontWeight.bold,
    marginTop: Spacing.sm,
  },
  subtitle: {
    fontSize: FontSize.md,
    marginTop: Spacing.xs,
    textAlign: 'center',
  },
  card: {
    borderRadius: BorderRadius.xl,
    overflow: 'hidden',
  },
  tabRow: {
    flexDirection: 'row',
    borderRadius: BorderRadius.lg,
    margin: Spacing.lg,
    marginBottom: 0,
    overflow: 'hidden',
  },
  tab: {
    flex: 1,
    paddingVertical: Spacing.sm + 2,
    alignItems: 'center',
    borderRadius: BorderRadius.lg,
  },
  tabText: {
    fontSize: FontSize.md,
    fontWeight: FontWeight.semibold,
  },
  form: {
    padding: Spacing.lg,
  },
  label: {
    fontSize: FontSize.sm,
    fontWeight: FontWeight.medium,
    marginBottom: Spacing.xs,
    marginTop: Spacing.md,
  },
  input: {
    borderRadius: BorderRadius.md,
    paddingHorizontal: Spacing.md,
    paddingVertical: Spacing.sm + 2,
    fontSize: FontSize.md,
    borderWidth: 1,
  },
  errorBox: {
    borderRadius: BorderRadius.md,
    padding: Spacing.sm,
    marginTop: Spacing.md,
  },
  errorText: {
    fontSize: FontSize.sm,
    fontWeight: FontWeight.medium,
    textAlign: 'center',
  },
  successBox: {
    borderRadius: BorderRadius.md,
    padding: Spacing.sm,
    marginTop: Spacing.md,
  },
  successText: {
    fontSize: FontSize.sm,
    fontWeight: FontWeight.medium,
    textAlign: 'center',
  },
  submitBtn: {
    borderRadius: BorderRadius.lg,
    paddingVertical: Spacing.md + 2,
    alignItems: 'center',
    marginTop: Spacing.xl,
  },
  submitText: {
    color: '#fff',
    fontSize: FontSize.md,
    fontWeight: FontWeight.semibold,
  },
  forgotBtn: {
    alignItems: 'center',
    marginTop: Spacing.md,
    padding: Spacing.sm,
  },
  forgotText: {
    fontSize: FontSize.sm,
    fontWeight: FontWeight.medium,
  },
  privacyNote: {
    marginTop: Spacing.xl,
    paddingHorizontal: Spacing.md,
  },
  privacyText: {
    fontSize: FontSize.xs,
    textAlign: 'center',
    lineHeight: 18,
  },
});
