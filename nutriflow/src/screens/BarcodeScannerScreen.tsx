import React from 'react';
import {
  View,
  Text,
  StyleSheet,
  TouchableOpacity,
  Modal,
  Platform,
} from 'react-native';
import { useTheme } from '../hooks/useTheme';
import { useStore } from '../store';
import { BorderRadius, FontSize, FontWeight, Spacing } from '../constants/theme';

interface Props {
  visible: boolean;
  onClose: () => void;
  onBarcodeScanned?: (barcode: string) => void;
}

export default function BarcodeScannerScreen({ visible, onClose, onBarcodeScanned }: Props) {
  const theme = useTheme();
  const settings = useStore(s => s.settings);

  return (
    <Modal visible={visible} animationType="slide" presentationStyle="fullScreen">
      <View style={[styles.container, { backgroundColor: '#000' }]}>
        <View style={styles.header}>
          <TouchableOpacity onPress={onClose} style={styles.closeBtn}>
            <Text style={styles.closeBtnText}>✕</Text>
          </TouchableOpacity>
        </View>

        <View style={styles.scanArea}>
          <View style={styles.scanFrame}>
            <View style={[styles.corner, styles.cornerTL]} />
            <View style={[styles.corner, styles.cornerTR]} />
            <View style={[styles.corner, styles.cornerBL]} />
            <View style={[styles.corner, styles.cornerBR]} />
          </View>

          <Text style={styles.scanText}>
            {settings.language === 'de'
              ? 'Barcode in den Rahmen halten'
              : 'Point camera at barcode'}
          </Text>
        </View>

        <View style={styles.footer}>
          <View style={[styles.infoCard, { backgroundColor: theme.surface }]}>
            <Text style={styles.infoIcon}>📸</Text>
            <Text style={[styles.infoTitle, { color: theme.text }]}>
              {settings.language === 'de' ? 'Barcode Scanner' : 'Barcode Scanner'}
            </Text>
            <Text style={[styles.infoDesc, { color: theme.textSecondary }]}>
              {settings.language === 'de'
                ? 'Scanne den Barcode auf der Produktverpackung, um die Nährwerte automatisch zu laden.'
                : 'Scan the barcode on the product packaging to automatically load nutrition data.'}
            </Text>
            <Text style={[styles.infoNote, { color: theme.textTertiary }]}>
              {settings.language === 'de'
                ? 'Kamerazugriff wird auf dem Gerät benötigt.'
                : 'Camera access required on device.'}
            </Text>

            <TouchableOpacity
              style={[styles.demoBtn, { backgroundColor: theme.primary }]}
              onPress={() => {
                onBarcodeScanned?.('4008400301020');
                onClose();
              }}
            >
              <Text style={styles.demoBtnText}>
                {settings.language === 'de' ? 'Demo: Milka Schokolade scannen' : 'Demo: Scan Milka Chocolate'}
              </Text>
            </TouchableOpacity>
          </View>
        </View>
      </View>
    </Modal>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  header: {
    paddingTop: Platform.OS === 'ios' ? 56 : Spacing.lg,
    paddingHorizontal: Spacing.lg,
    alignItems: 'flex-end',
  },
  closeBtn: {
    width: 36,
    height: 36,
    borderRadius: 18,
    backgroundColor: 'rgba(255,255,255,0.2)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  closeBtnText: {
    color: '#fff',
    fontSize: 18,
    fontWeight: FontWeight.bold,
  },
  scanArea: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
  scanFrame: {
    width: 260,
    height: 260,
    position: 'relative',
  },
  corner: {
    position: 'absolute',
    width: 40,
    height: 40,
    borderColor: '#4CAF50',
    borderWidth: 3,
  },
  cornerTL: { top: 0, left: 0, borderRightWidth: 0, borderBottomWidth: 0 },
  cornerTR: { top: 0, right: 0, borderLeftWidth: 0, borderBottomWidth: 0 },
  cornerBL: { bottom: 0, left: 0, borderRightWidth: 0, borderTopWidth: 0 },
  cornerBR: { bottom: 0, right: 0, borderLeftWidth: 0, borderTopWidth: 0 },
  scanText: {
    color: 'rgba(255,255,255,0.7)',
    fontSize: FontSize.sm,
    marginTop: Spacing.xl,
  },
  footer: {
    paddingHorizontal: Spacing.lg,
    paddingBottom: Platform.OS === 'ios' ? 40 : Spacing.xxl,
  },
  infoCard: {
    borderRadius: BorderRadius.xl,
    padding: Spacing.xl,
    alignItems: 'center',
  },
  infoIcon: {
    fontSize: 32,
    marginBottom: Spacing.md,
  },
  infoTitle: {
    fontSize: FontSize.lg,
    fontWeight: FontWeight.semibold,
    marginBottom: Spacing.sm,
  },
  infoDesc: {
    fontSize: FontSize.sm,
    textAlign: 'center',
    lineHeight: 20,
    marginBottom: Spacing.sm,
  },
  infoNote: {
    fontSize: FontSize.xs,
    fontStyle: 'italic',
    marginBottom: Spacing.lg,
  },
  demoBtn: {
    paddingHorizontal: Spacing.xxl,
    paddingVertical: Spacing.md,
    borderRadius: BorderRadius.md,
  },
  demoBtnText: {
    color: '#fff',
    fontSize: FontSize.sm,
    fontWeight: FontWeight.semibold,
  },
});
