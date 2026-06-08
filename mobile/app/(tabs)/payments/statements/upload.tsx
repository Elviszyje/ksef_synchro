import { useState } from 'react';
import { View, Text, TouchableOpacity, Alert, StyleSheet } from 'react-native';
import { useRouter } from 'expo-router';
import * as DocumentPicker from 'expo-document-picker';
import { useUploadStatement } from '../../../../src/hooks/useBankStatements';
import { colors, spacing, radius } from '../../../../src/theme';

export default function UploadStatementScreen() {
  const router = useRouter();
  const [selectedFile, setSelectedFile] = useState<{ uri: string; name: string; mimeType: string } | null>(null);
  const upload = useUploadStatement();

  const pickFile = async () => {
    const result = await DocumentPicker.getDocumentAsync({ type: '*/*', copyToCacheDirectory: true });
    if (result.canceled || !result.assets?.length) return;
    const asset = result.assets[0];
    setSelectedFile({ uri: asset.uri, name: asset.name, mimeType: asset.mimeType ?? 'application/octet-stream' });
  };

  const handleUpload = () => {
    if (!selectedFile) return;
    upload.mutate(selectedFile, {
      onSuccess: (stmt) => {
        router.replace(`/(tabs)/payments/statements/${stmt.id}`);
      },
      onError: (e: any) => {
        const msg = e?.response?.data?.detail ?? e?.message ?? 'Nie udało się wgrać pliku.';
        Alert.alert('Błąd', String(msg));
      },
    });
  };

  return (
    <View style={styles.container}>
      <Text style={styles.title}>Wgraj wyciąg bankowy</Text>
      <Text style={styles.subtitle}>
        Wybierz plik wyciągu bankowego (MT940 lub CSV). Obsługiwane banki: VeloBank, Erste Bank oraz inne formaty MT940.
        Format zostanie wykryty automatycznie.
      </Text>

      <TouchableOpacity onPress={pickFile} style={styles.pickBtn}>
        <Text style={styles.pickBtnText}>
          {selectedFile ? `📄 ${selectedFile.name}` : 'Wybierz wyciąg bankowy (MT940 lub CSV)'}
        </Text>
      </TouchableOpacity>

      {selectedFile && (
        <TouchableOpacity
          onPress={handleUpload}
          disabled={upload.isPending}
          style={[styles.uploadBtn, upload.isPending && styles.uploadBtnDisabled]}
        >
          <Text style={styles.uploadBtnText}>
            {upload.isPending ? 'Wgrywanie...' : 'Wgraj i parsuj'}
          </Text>
        </TouchableOpacity>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.gray50, padding: spacing.lg },
  title: { fontSize: 20, fontWeight: '700', color: colors.gray900, marginBottom: spacing.sm },
  subtitle: { fontSize: 14, color: colors.gray500, lineHeight: 20, marginBottom: spacing.xl },
  pickBtn: { backgroundColor: colors.white, borderWidth: 2, borderColor: colors.gray200, borderRadius: radius.lg, paddingVertical: spacing.xl, alignItems: 'center', marginBottom: spacing.md },
  pickBtnText: { color: colors.gray700, fontSize: 15, fontWeight: '500' },
  uploadBtn: { backgroundColor: colors.primary, borderRadius: radius.lg, paddingVertical: spacing.lg, alignItems: 'center' },
  uploadBtnDisabled: { backgroundColor: colors.gray300 },
  uploadBtnText: { color: colors.white, fontWeight: '700', fontSize: 16 },
});
