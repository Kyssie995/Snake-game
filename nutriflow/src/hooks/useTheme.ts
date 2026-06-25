import { useColorScheme } from 'react-native';
import { Colors } from '../constants/theme';
import { useStore } from '../store';

export function useTheme() {
  const systemScheme = useColorScheme();
  const themeSetting = useStore(s => s.settings.theme);

  const isDark =
    themeSetting === 'dark' ||
    (themeSetting === 'system' && systemScheme === 'dark');

  return isDark ? Colors.dark : Colors.light;
}

export function useIsDark() {
  const systemScheme = useColorScheme();
  const themeSetting = useStore(s => s.settings.theme);
  return themeSetting === 'dark' || (themeSetting === 'system' && systemScheme === 'dark');
}
