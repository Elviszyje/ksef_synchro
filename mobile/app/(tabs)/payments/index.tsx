import { useState, useEffect } from 'react';
import { View, Text, FlatList, TouchableOpacity, RefreshControl, Alert, ScrollView, StyleSheet } from 'react-native';
import { useAcceptedForPayment, useGeneratePaymentFile, useBankAccounts } from '../../../src/hooks/usePayments';
import { LoadingSpinner } from '../../../src/components/common/LoadingSpinner';
import { EmptyState } from '../../../src/components/common/EmptyState';
import { formatAmount, formatDate, formatNrb } from '../../../src/utils/format';
import { colors, spacing, radius, shadow } from '../../../src/theme';
import type { Invoice, PaginatedResponse, CompanyBankAccount } from '../../../src/types/api';

const BANK_KEY_TO_FORMAT: Record<string, 'erste' | 'mbank' | 'elixir'> = {
  erste: 'erste',
  mbank: 'mbank',
};

export default function PaymentsScreen() {
  const [selectedIds, setSelectedIds] = useState<number[]>([]);
  const [selectedAccountId, setSelectedAccountId] = useState<number | null>(null);

  const { data, isLoading, refetch, isRefetching } = useAcceptedForPayment();
  const { data: accountsData, isLoading: accountsLoading } = useBankAccounts();
  const generate = useGeneratePaymentFile();

  const invoices: Invoice[] = (data as PaginatedResponse<Invoice>)?.results ?? (Array.isArray(data) ? data : []);
  const accounts: CompanyBankAccount[] = Array.isArray(accountsData) ? accountsData : [];

  // Ustaw domyślne konto przy załadowaniu
  useEffect(() => {
    if (accounts.length > 0 && selectedAccountId === null) {
      const def = accounts.find((a) => a.is_default) ?? accounts[0];
      setSelectedAccountId(def.id);
    }
  }, [accounts, selectedAccountId]);

  const selectedAccount = accounts.find((a) => a.id === selectedAccountId) ?? null;
  const resolvedFormat = selectedAccount ? (BANK_KEY_TO_FORMAT[selectedAccount.bank_key] ?? 'elixir') : 'elixir';

  const toggle = (id: number) =>
    setSelectedIds((prev) => (prev.includes(id) ? prev.filter((i) => i !== id) : [...prev, id]));
  const selectAll = () => setSelectedIds(invoices.map((i) => i.id));

  const handleGenerate = () => {
    if (selectedIds.length === 0) {
      Alert.alert('Brak wyborów', 'Wybierz co najmniej jedną fakturę.');
      return;
    }
    if (!selectedAccount) {
      Alert.alert('Brak rachunku', 'Najpierw wybierz rachunek bankowy do obciążenia.');
      return;
    }
    generate.mutate(
      { invoice_ids: selectedIds, format: resolvedFormat, debit_account: selectedAccount.account_number },
      {
        onSuccess: () => {
          setSelectedIds([]);
          Alert.alert('Gotowe', 'Plik przelewu wygenerowany. Jeśli okno udostępniania nie otworzyło się, znajdziesz plik w historii przelewów.');
        },
        onError: (e: any) => {
          const data = e?.response?.data;
          const msg = data?.detail
            ?? (data && typeof data === 'object' ? Object.values(data).flat().join('\n') : null)
            ?? e?.message
            ?? 'Nie udało się wygenerować pliku.';
          Alert.alert('Błąd generowania', String(msg));
        },
      },
    );
  };

  if (isLoading || accountsLoading) return <LoadingSpinner />;

  return (
    <View style={styles.container}>
      {/* Selektor konta debetowego */}
      {accounts.length > 0 && (
        <View style={styles.accountSection}>
          <Text style={styles.sectionLabel}>Rachunek do obciążenia</Text>
          <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={styles.accountChips}>
            {accounts.map((acc) => (
              <TouchableOpacity
                key={acc.id}
                onPress={() => setSelectedAccountId(acc.id)}
                style={[styles.accountChip, selectedAccountId === acc.id && styles.accountChipActive]}
              >
                <Text style={[styles.accountChipBank, selectedAccountId === acc.id && styles.accountChipBankActive]}>
                  {acc.bank_name || acc.label || 'Rachunek'}
                </Text>
                <Text style={[styles.accountChipNrb, selectedAccountId === acc.id && styles.accountChipNrbActive]}>
                  {formatNrb(acc.account_number)}
                </Text>
                {acc.is_default && (
                  <Text style={[styles.accountChipDefault, selectedAccountId === acc.id && styles.accountChipDefaultActive]}>
                    domyślny
                  </Text>
                )}
              </TouchableOpacity>
            ))}
          </ScrollView>
          {selectedAccount && (
            <Text style={styles.formatInfo}>
              Format pliku: <Text style={{ fontWeight: '600' }}>{resolvedFormat.toUpperCase()}</Text>
            </Text>
          )}
        </View>
      )}

      {invoices.length > 0 && (
        <View style={styles.selectBar}>
          <Text style={styles.selectCount}>{invoices.length} faktur do opłacenia</Text>
          <TouchableOpacity onPress={selectAll}>
            <Text style={styles.selectAllText}>Zaznacz wszystkie</Text>
          </TouchableOpacity>
        </View>
      )}

      <FlatList
        data={invoices}
        keyExtractor={(item) => String(item.id)}
        refreshControl={<RefreshControl refreshing={isRefetching} onRefresh={refetch} />}
        contentContainerStyle={[styles.list, selectedIds.length > 0 && { paddingBottom: 100 }]}
        ListEmptyComponent={<EmptyState message="Brak faktur do przelewu. Faktury muszą mieć status 'Zaakceptowana' i zawierać numer konta bankowego dostawcy." />}
        renderItem={({ item }) => (
          <TouchableOpacity
            onPress={() => toggle(item.id)}
            style={[styles.card, shadow.sm, selectedIds.includes(item.id) && styles.cardSelected]}
          >
            <View style={styles.cardInner}>
              <View style={[styles.checkbox, selectedIds.includes(item.id) && styles.checkboxActive]}>
                {selectedIds.includes(item.id) && <Text style={styles.checkmark}>✓</Text>}
              </View>
              <View style={styles.cardInfo}>
                <Text style={styles.invoiceNumber} numberOfLines={1}>{item.invoice_number}</Text>
                <Text style={styles.sellerName} numberOfLines={1}>{item.seller_name}</Text>
                <Text style={styles.bankAccount}>{formatNrb(item.bank_account_number)} · do {formatDate(item.payment_due_date)}</Text>
              </View>
              <Text style={styles.amount}>{formatAmount(item.amount_gross)}</Text>
            </View>
          </TouchableOpacity>
        )}
      />

      {selectedIds.length > 0 && (
        <View style={styles.bottomBar}>
          <Text style={styles.bottomCount}>Wybrano: {selectedIds.length} faktur</Text>
          <TouchableOpacity
            onPress={handleGenerate}
            disabled={generate.isPending}
            style={[styles.generateBtn, generate.isPending && styles.generateBtnDisabled]}
          >
            <Text style={styles.generateBtnText}>
              {generate.isPending ? 'Generowanie...' : 'Generuj plik i pobierz'}
            </Text>
          </TouchableOpacity>
        </View>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.gray50 },
  accountSection: { backgroundColor: colors.white, borderBottomWidth: 1, borderBottomColor: colors.gray200, paddingTop: spacing.md, paddingBottom: spacing.sm },
  sectionLabel: { fontSize: 12, color: colors.gray500, fontWeight: '500', paddingHorizontal: spacing.lg, marginBottom: spacing.sm, textTransform: 'uppercase', letterSpacing: 0.5 },
  accountChips: { paddingHorizontal: spacing.lg, gap: spacing.sm },
  accountChip: { borderWidth: 2, borderColor: colors.gray200, borderRadius: radius.lg, paddingHorizontal: spacing.md, paddingVertical: spacing.sm, backgroundColor: colors.white, minWidth: 180 },
  accountChipActive: { borderColor: colors.primary, backgroundColor: colors.primaryLight },
  accountChipBank: { fontSize: 13, fontWeight: '600', color: colors.gray700 },
  accountChipBankActive: { color: colors.primary },
  accountChipNrb: { fontSize: 11, color: colors.gray500, fontFamily: 'monospace', marginTop: 2 },
  accountChipNrbActive: { color: colors.primary },
  accountChipDefault: { fontSize: 10, color: colors.gray400, marginTop: 2 },
  accountChipDefaultActive: { color: colors.primary },
  formatInfo: { fontSize: 12, color: colors.gray500, paddingHorizontal: spacing.lg, marginTop: spacing.sm },
  selectBar: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', paddingHorizontal: spacing.lg, paddingVertical: spacing.sm },
  selectCount: { fontSize: 13, color: colors.gray500 },
  selectAllText: { fontSize: 13, color: colors.primary, fontWeight: '500' },
  list: { paddingHorizontal: spacing.lg, paddingBottom: spacing.lg, gap: spacing.sm },
  card: { backgroundColor: colors.white, borderRadius: radius.lg, padding: spacing.lg, borderWidth: 2, borderColor: 'transparent' },
  cardSelected: { borderColor: colors.primary },
  cardInner: { flexDirection: 'row', alignItems: 'center', gap: spacing.md },
  checkbox: { width: 22, height: 22, borderRadius: 6, borderWidth: 2, borderColor: colors.gray300, alignItems: 'center', justifyContent: 'center' },
  checkboxActive: { backgroundColor: colors.primary, borderColor: colors.primary },
  checkmark: { color: colors.white, fontSize: 13, fontWeight: '700' },
  cardInfo: { flex: 1 },
  invoiceNumber: { fontWeight: '600', color: colors.gray800, fontSize: 15 },
  sellerName: { fontSize: 13, color: colors.gray500, marginTop: 2 },
  bankAccount: { fontSize: 12, color: colors.gray400, marginTop: 2 },
  amount: { fontWeight: '700', color: colors.primary, fontSize: 15 },
  bottomBar: { position: 'absolute', bottom: 0, left: 0, right: 0, backgroundColor: colors.white, borderTopWidth: 1, borderTopColor: colors.gray200, padding: spacing.lg },
  bottomCount: { textAlign: 'center', color: colors.gray600, fontSize: 13, marginBottom: spacing.sm },
  generateBtn: { backgroundColor: colors.success, borderRadius: radius.lg, paddingVertical: spacing.lg, alignItems: 'center' },
  generateBtnDisabled: { backgroundColor: colors.gray300 },
  generateBtnText: { color: colors.white, fontWeight: '700', fontSize: 16 },
});
