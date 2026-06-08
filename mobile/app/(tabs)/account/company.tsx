import { useState } from 'react';
import { View, Text, TextInput, TouchableOpacity, ScrollView, Alert, StyleSheet, ActivityIndicator } from 'react-native';
import { useRouter } from 'expo-router';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useAuthStore } from '../../../src/store/auth';
import { getCompany, updateCompany } from '../../../src/api/account';
import { colors, spacing, radius } from '../../../src/theme';
import type { Company } from '../../../src/types/api';

export default function CompanyScreen() {
  const router = useRouter();
  const qc = useQueryClient();
  const { user } = useAuthStore();
  const [name, setName] = useState('');
  const [address, setAddress] = useState('');
  const [initialized, setInitialized] = useState(false);

  const { data: company, isLoading } = useQuery<Company>({
    queryKey: ['company'],
    queryFn: getCompany,
    enabled: !!user?.company_id,
    onSuccess: (data: Company) => {
      if (!initialized) {
        setName(data.name);
        setAddress(data.address ?? '');
        setInitialized(true);
      }
    },
  } as any);

  const mutation = useMutation({
    mutationFn: updateCompany,
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['company'] });
      Alert.alert('Zapisano', 'Dane firmy zostały zaktualizowane.');
      router.back();
    },
    onError: (e: any) => {
      Alert.alert('Błąd', e?.response?.data?.detail ?? 'Nie udało się zapisać danych firmy.');
    },
  });

  if (isLoading) {
    return (
      <View style={styles.center}>
        <ActivityIndicator size="large" color={colors.primary} />
      </View>
    );
  }

  return (
    <ScrollView style={styles.container} contentContainerStyle={styles.content} keyboardShouldPersistTaps="handled">
      <View style={styles.field}>
        <Text style={styles.label}>NIP</Text>
        <Text style={styles.readonly}>{company?.nip ?? '—'}</Text>
      </View>
      <View style={styles.field}>
        <Text style={styles.label}>Nazwa firmy</Text>
        <TextInput
          style={styles.input}
          value={name}
          onChangeText={setName}
          placeholder="Nazwa firmy"
          autoCorrect={false}
        />
      </View>
      <View style={styles.field}>
        <Text style={styles.label}>Adres</Text>
        <TextInput
          style={[styles.input, styles.multiline]}
          value={address}
          onChangeText={setAddress}
          placeholder="ul. Przykładowa 1, 00-001 Warszawa"
          multiline
          numberOfLines={3}
          autoCorrect={false}
        />
      </View>

      <TouchableOpacity
        style={[styles.saveBtn, mutation.isPending && styles.saveBtnDisabled]}
        onPress={() => mutation.mutate({ name, address })}
        disabled={mutation.isPending}
      >
        {mutation.isPending
          ? <ActivityIndicator color={colors.white} />
          : <Text style={styles.saveBtnText}>Zapisz zmiany</Text>}
      </TouchableOpacity>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.gray50 },
  content: { padding: spacing.lg, gap: spacing.md },
  center: { flex: 1, alignItems: 'center', justifyContent: 'center' },
  field: { gap: spacing.xs },
  label: { fontSize: 14, fontWeight: '600', color: colors.gray700 },
  readonly: { fontSize: 15, color: colors.gray500, paddingVertical: spacing.sm },
  input: { backgroundColor: colors.white, borderWidth: 1, borderColor: colors.gray200, borderRadius: radius.sm, paddingHorizontal: spacing.md, paddingVertical: spacing.sm, fontSize: 15, color: colors.gray900 },
  multiline: { minHeight: 80, textAlignVertical: 'top' },
  saveBtn: { backgroundColor: colors.primary, borderRadius: radius.lg, padding: spacing.lg, alignItems: 'center', marginTop: spacing.md },
  saveBtnDisabled: { backgroundColor: colors.gray300 },
  saveBtnText: { color: colors.white, fontWeight: '700', fontSize: 16 },
});
