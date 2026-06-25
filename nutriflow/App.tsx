import React, { useEffect } from 'react';
import { StatusBar, View, ActivityIndicator, StyleSheet } from 'react-native';
import { NavigationContainer } from '@react-navigation/native';
import { SafeAreaProvider } from 'react-native-safe-area-context';
import { useStore } from './src/store';
import { useTheme, useIsDark } from './src/hooks/useTheme';
import AppNavigator from './src/navigation/AppNavigator';
import SetupScreen from './src/screens/SetupScreen';

function AppContent() {
  const theme = useTheme();
  const isDark = useIsDark();
  const isLoading = useStore(s => s.isLoading);
  const profile = useStore(s => s.profile);
  const initialize = useStore(s => s.initialize);

  useEffect(() => {
    initialize();
  }, []);

  if (isLoading) {
    return (
      <View style={[styles.loading, { backgroundColor: theme.background }]}>
        <ActivityIndicator size="large" color={theme.primary} />
      </View>
    );
  }

  if (!profile?.setupComplete) {
    return (
      <>
        <StatusBar barStyle={isDark ? 'light-content' : 'dark-content'} backgroundColor={theme.background} />
        <SetupScreen />
      </>
    );
  }

  return (
    <NavigationContainer>
      <StatusBar barStyle={isDark ? 'light-content' : 'dark-content'} backgroundColor={theme.background} />
      <AppNavigator />
    </NavigationContainer>
  );
}

export default function App() {
  return (
    <SafeAreaProvider>
      <AppContent />
    </SafeAreaProvider>
  );
}

const styles = StyleSheet.create({
  loading: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
});
