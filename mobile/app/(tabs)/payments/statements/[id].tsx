import { View, Text, FlatList, TouchableOpacity, Alert, StyleSheet, ScrollView } from 'react-native';
import { useLocalSearchParams } from 'expo-router';
import { useBankStatement, useRunMatcher, useToggleMatch, useConfirmStatement } from '../../../../src/hooks/useBankStatements';
import { LoadingSpinner } from '../../../../src/components/common/LoadingSpinner';
import { formatDate } from '../../../../src/utils/format';
import { colors, spacing, radius, shadow } from '../../../../src/theme';
import type { BankStatementDetail, BankTransaction, TransactionMatch } from '../../../../src/types/api';

const CONFIDENCE_COLORS: Record<string, string> = {
  high: '#065f46',
  medium: '#92400e',
  low: colors.gray500,
};

const MATCH_TYPE_LABELS: Record<string, string> = {
  invoice_nr_amount: 'nr faktury + kwota',
  nip_amount: 'NIP + kwota',
  amount: 'kwota',
  manual: 'ręczne',
};

function MatchRow({ match, stmtId, onToggle }: { match: TransactionMatch; stmtId: number; onToggle: (id: number) => void }) {
  return (
    <TouchableOpacity
      onPress={() => onToggle(match.id)}
      style={[styles.matchRow, match.is_confirmed && styles.matchRowConfirmed]}
    >
      <View style={[styles.matchCheck, match.is_confirmed && styles.matchCheckActive]}>
        {match.is_confirmed && <Text style={styles.checkmark}>✓</Text>}
      </View>
      <View style={styles.matchInfo}>
        <Text style={styles.matchInvoiceNr} numberOfLines={1}>{match.invoice.invoice_number}</Text>
        <Text style={styles.matchSeller} numberOfLines={1}>{match.invoice.seller_name}</Text>
        <Text style={[styles.matchConfidence, { color: CONFIDENCE_COLORS[match.confidence] ?? colors.gray500 }]}>
          {MATCH_TYPE_LABELS[match.match_type] ?? match.match_type} · {match.confidence}
        </Text>
      </View>
    </TouchableOpacity>
  );
}

function TransactionCard({ tx, stmtId, onToggle }: { tx: BankTransaction; stmtId: number; onToggle: (id: number) => void }) {
  const amountColor = tx.is_debit ? colors.danger : colors.success;
  const sign = tx.is_debit ? '-' : '+';

  return (
    <View style={[styles.txCard, shadow.sm]}>
      <View style={styles.txTop}>
        <View style={styles.txLeft}>
          <Text style={styles.txDate}>{formatDate(tx.transaction_date)}</Text>
          <Text style={styles.txDesc} numberOfLines={2}>{tx.description || '—'}</Text>
          {!!tx.counterparty && (
            <Text style={styles.txCounterparty} numberOfLines={1}>{tx.counterparty}</Text>
          )}
        </View>
        <Text style={[styles.txAmount, { color: amountColor }]}>
          {sign}{tx.amount} {tx.currency}
        </Text>
      </View>
      {tx.matches.length > 0 && (
        <View style={styles.matchesList}>
          {tx.matches.map((m) => (
            <MatchRow key={m.id} match={m} stmtId={stmtId} onToggle={onToggle} />
          ))}
        </View>
      )}
      {tx.matches.length === 0 && !tx.is_matched && (
        <Text style={styles.noMatch}>Brak dopasowania</Text>
      )}
    </View>
  );
}

export default function StatementReviewScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const stmtId = Number(id);
  const { data, isLoading, isRefetching } = useBankStatement(stmtId);
  const runMatcher = useRunMatcher(stmtId);
  const toggleMatch = useToggleMatch(stmtId);
  const confirmStmt = useConfirmStatement();

  const stmt = data as BankStatementDetail | undefined;

  const handleToggle = (matchId: number) => {
    toggleMatch.mutate(matchId);
  };

  const handleRunMatcher = () => {
    runMatcher.mutate(undefined, {
      onSuccess: (result) => {
        Alert.alert('Dopasowanie', `Znaleziono ${result.matched_count} nowych dopasowań.`);
      },
      onError: () => Alert.alert('Błąd', 'Nie udało się uruchomić dopasowania.'),
    });
  };

  const handleConfirm = () => {
    Alert.alert(
      'Zatwierdź wyciąg',
      'Zaznaczone transakcje zostaną dopasowane do faktur, a faktury oznaczone jako opłacone. Czy kontynuować?',
      [
        { text: 'Anuluj', style: 'cancel' },
        {
          text: 'Zatwierdź',
          style: 'destructive',
          onPress: () => {
            confirmStmt.mutate(stmtId, {
              onSuccess: (result) => {
                Alert.alert('Gotowe', `${result.confirmed_count} faktur oznaczono jako opłacone.`);
              },
              onError: () => Alert.alert('Błąd', 'Nie udało się zatwierdzić wyciągu.'),
            });
          },
        },
      ],
    );
  };

  if (isLoading || !stmt) return <LoadingSpinner />;

  const transactions: BankTransaction[] = stmt.transactions ?? [];
  const isConfirmed = stmt.status === 'confirmed';

  return (
    <View style={styles.container}>
      <View style={styles.header}>
        <Text style={styles.fileName} numberOfLines={1}>{stmt.file_name}</Text>
        <Text style={styles.accountNr}>{stmt.account_number}</Text>
        <View style={styles.actions}>
          {!isConfirmed && (
            <TouchableOpacity
              onPress={handleRunMatcher}
              disabled={runMatcher.isPending || isRefetching}
              style={styles.matcherBtn}
            >
              <Text style={styles.matcherBtnText}>
                {runMatcher.isPending ? 'Dopasowuję...' : 'Uruchom dopasowanie'}
              </Text>
            </TouchableOpacity>
          )}
          {!isConfirmed && (
            <TouchableOpacity
              onPress={handleConfirm}
              disabled={confirmStmt.isPending}
              style={[styles.confirmBtn, confirmStmt.isPending && styles.confirmBtnDisabled]}
            >
              <Text style={styles.confirmBtnText}>
                {confirmStmt.isPending ? 'Zatwierdzam...' : 'Zatwierdź wyciąg'}
              </Text>
            </TouchableOpacity>
          )}
          {isConfirmed && (
            <View style={styles.confirmedBadge}>
              <Text style={styles.confirmedBadgeText}>✓ Zatwierdzony</Text>
            </View>
          )}
        </View>
      </View>

      <FlatList
        data={transactions}
        keyExtractor={(item) => String(item.id)}
        contentContainerStyle={styles.list}
        ListEmptyComponent={
          <Text style={styles.emptyText}>Brak transakcji w wyciągu.</Text>
        }
        renderItem={({ item }) => (
          <TransactionCard tx={item} stmtId={stmtId} onToggle={handleToggle} />
        )}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.gray50 },
  header: { backgroundColor: colors.white, padding: spacing.lg, borderBottomWidth: 1, borderBottomColor: colors.gray200 },
  fileName: { fontSize: 15, fontWeight: '700', color: colors.gray900, marginBottom: 2 },
  accountNr: { fontSize: 12, color: colors.gray500, fontFamily: 'monospace', marginBottom: spacing.md },
  actions: { gap: spacing.sm },
  matcherBtn: { borderWidth: 1, borderColor: colors.primary, borderRadius: radius.md, paddingVertical: spacing.sm, alignItems: 'center' },
  matcherBtnText: { color: colors.primary, fontWeight: '600', fontSize: 14 },
  confirmBtn: { backgroundColor: colors.success, borderRadius: radius.md, paddingVertical: spacing.sm, alignItems: 'center' },
  confirmBtnDisabled: { backgroundColor: colors.gray300 },
  confirmBtnText: { color: colors.white, fontWeight: '700', fontSize: 14 },
  confirmedBadge: { backgroundColor: '#d1fae5', borderRadius: radius.md, paddingVertical: spacing.sm, alignItems: 'center' },
  confirmedBadgeText: { color: '#065f46', fontWeight: '700', fontSize: 14 },
  list: { padding: spacing.lg, gap: spacing.sm, paddingBottom: 40 },
  txCard: { backgroundColor: colors.white, borderRadius: radius.lg, padding: spacing.lg },
  txTop: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'flex-start', gap: spacing.md },
  txLeft: { flex: 1 },
  txDate: { fontSize: 12, color: colors.gray400, marginBottom: 2 },
  txDesc: { fontSize: 13, color: colors.gray700, lineHeight: 18 },
  txCounterparty: { fontSize: 12, color: colors.gray500, marginTop: 1 },
  txAmount: { fontWeight: '700', fontSize: 15 },
  matchesList: { marginTop: spacing.sm, gap: spacing.xs },
  matchRow: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm, padding: spacing.sm, borderRadius: radius.sm, borderWidth: 1, borderColor: colors.gray200, backgroundColor: colors.gray50 },
  matchRowConfirmed: { borderColor: colors.success, backgroundColor: '#f0fdf4' },
  matchCheck: { width: 20, height: 20, borderRadius: 4, borderWidth: 2, borderColor: colors.gray300, alignItems: 'center', justifyContent: 'center' },
  matchCheckActive: { backgroundColor: colors.success, borderColor: colors.success },
  checkmark: { color: colors.white, fontSize: 12, fontWeight: '700' },
  matchInfo: { flex: 1 },
  matchInvoiceNr: { fontSize: 13, fontWeight: '600', color: colors.gray800 },
  matchSeller: { fontSize: 12, color: colors.gray500 },
  matchConfidence: { fontSize: 11, marginTop: 1 },
  noMatch: { fontSize: 12, color: colors.gray400, marginTop: spacing.sm, fontStyle: 'italic' },
  emptyText: { textAlign: 'center', color: colors.gray400, padding: spacing.xl },
});
