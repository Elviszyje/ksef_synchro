import { useState, useEffect } from 'react';
import { View, Text, TextInput, Switch, TouchableOpacity, ScrollView, Alert, StyleSheet, ActivityIndicator } from 'react-native';
import { useRouter, useLocalSearchParams } from 'expo-router';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { getBankAccounts } from '../../../src/api/payments';
import { createBankAccount, updateBankAccount } from '../../../src/api/account';
import { colors, spacing, radius } from '../../../src/theme';
import type { CompanyBankAccount } from '../../../src/types/api';

function formatNrbInput(value: string): string {
  const digits = value.replace(/\D/g, '').slice(0, 26);
  return digits;
}

export default function BankAccountScreen() {
  const router = useRouter();
  const qc = useQueryClient();
  const params = useLocalSearchParams<{ id?: string }>();
  const editId = params.id ? Number(params.id) : null;

  const [accountNumber, setAccountNumber] = useState('');
  const [label, setLabel] = useState('');
  const [isDefault, setIsDefault] = useState(false);
  const [initialized, setInitialized] = useState(false);

  const { data: accounts = [] } = useQuery<CompanyBankAccount[]>({
    queryKey: ['bank-accounts'],
    queryFn: getBankAccounts,
    enabled: !!editId,
  });

  useEffect(() => {
    if (editId && accounts.length > 0 && !initialized) {
      const existing = accounts.find((a) => a.id === editId);
      if (existing) {
        setAccountNumber(existing.account_number);
        setLabel(existing.label ?? '');
        setIsDefault(existing.is_default);
        setInitialized(true);
      }
    }
  }, [editId, accounts, initialized]);

  const mutation = useMutation({
    mutationFn: (data: { account_number: string; label?: string; is_default: boolean }) =>
      editId ? updateBankAccount(editId, data) : createBankAccount(data),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['bank-accounts'] });
      Alert.alert('Zapisano', editId ? 'Rachunek został zaktualizowany.' : 'Rachunek został dodany.');
      router.back();
    },
    onError: (e: any) => {
      const msg = e?.response?.data?.account_number?.[0]
        ?? e?.response?.data?.detail
        ?? 'Nie udało się zapisać rachunku.';
      Alert.alert('Błąd', String(msg));
    },
  });

  const handleSave = () => {
    const digits = accountNumber.replace(/\D/g, '');
    if (digits.length !== 26) {
      Alert.alert('Błąd', 'Numer konta NRB musi mieć 26 cyfr.');
      return;
    }
    mutation.mutate({ account_number: digits, label: label.trim() || undefined, is_default: isDefault });
  };

  return (
    <ScrollView style={styles.container} contentContainerStyle={styles.content} keyboardShouldPersistTaps="handled">
      <View style={styles.field}>
        <Text style={styles.label}>Numer konta NRB <Text style={styles.required}>*</Text></Text>
        <TextInput
          style={styles.input}
          value={accountNumber}
          onChangeText={(v) => setAccountNumber(formatNrbInput(v))}
          placeholder="26 cyfr bez spacji"
          keyboardType="number-pad"
          maxLength={26}
          autoCorrect={false}
        />
        <Text style={styles.hint}>{accountNumber.length}/26 cyfr</Text>
      </View>
      <View style={styles.field}>
        <Text style={styles.label}>Etykieta <Text style={styles.optional}>(opcjonalna)</Text></Text>
        <TextInput
          style={styles.input}
          value={label}
          onChangeText={setLabel}
          placeholder="np. Rachunek PLN"
          autoCorrect={false}
        />
      </View>
      <View style={styles.switchRow}>
        <Text style={styles.label}>Ustaw jako domyślny</Text>
        <Switch
          value={isDefault}
          onValueChange={setIsDefault}
          trackColor={{ true: colors.primary, false: colors.gray200 }}
          thumbColor={colors.white}
        />
      </View>

      <TouchableOpacity
        style={[styles.saveBtn, mutation.isPending && styles.saveBtnDisabled]}
        onPress={handleSave}
        disabled={mutation.isPending}
      >
        {mutation.isPending
          ? <ActivityIndicator color={colors.white} />
          : <Text style={styles.saveBtnText}>{editId ? 'Zapisz zmiany' : 'Dodaj rachunek'}</Text>}
      </TouchableOpacity>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.gray50 },
  content: { padding: spacing.lg, gap: spacing.md },
  field: { gap: spacing.xs },
  label: { fontSize: 14, fontWeight: '600', color: colors.gray700 },
  required: { color: colors.danger },
  optional: { fontWeight: '400', color: colors.gray400 },
  hint: { fontSize: 12, color: colors.gray400 },
  input: { backgroundColor: colors.white, borderWidth: 1, borderColor: colors.gray200, borderRadius: radius.sm, paddingHorizontal: spacing.md, paddingVertical: spacing.sm, fontSize: 15, color: colors.gray900, fontFamily: 'monospace' },
  switchRow: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', backgroundColor: colors.white, borderRadius: radius.sm, paddingHorizontal: spacing.md, paddingVertical: spacing.sm, borderWidth: 1, borderColor: colors.gray200 },
  saveBtn: { backgroundColor: colors.primary, borderRadius: radius.lg, padding: spacing.lg, alignItems: 'center', marginTop: spacing.md },
  saveBtnDisabled: { backgroundColor: colors.gray300 },
  saveBtnText: { color: colors.white, fontWeight: '700', fontSize: 16 },
});
