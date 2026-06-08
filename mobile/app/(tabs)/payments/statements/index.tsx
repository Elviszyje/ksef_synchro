import { View, Text, FlatList, TouchableOpacity, RefreshControl, StyleSheet } from 'react-native';
import { useRouter } from 'expo-router';
import { useBankStatements } from '../../../../src/hooks/useBankStatements';
import { LoadingSpinner } from '../../../../src/components/common/LoadingSpinner';
import { EmptyState } from '../../../../src/components/common/EmptyState';
import { formatDate } from '../../../../src/utils/format';
import { colors, spacing, radius, shadow } from '../../../../src/theme';
import type { BankStatement } from '../../../../src/types/api';

const STATUS_CONFIG = {
  pending: { label: 'Oczekuje', bg: colors.gray100, text: colors.gray600 },
  reviewed: { label: 'Przejrzany', bg: '#fef3c7', text: '#92400e' },
  confirmed: { label: 'Zatwierdzony', bg: '#d1fae5', text: '#065f46' },
} as const;

export default function StatementsListScreen() {
  const router = useRouter();
  const { data, isLoading, refetch, isRefetching } = useBankStatements();

  const statements: BankStatement[] = Array.isArray(data) ? data : [];

  if (isLoading) return <LoadingSpinner />;

  return (
    <View style={styles.container}>
      <TouchableOpacity
        onPress={() => router.push('/(tabs)/payments/statements/upload')}
        style={styles.uploadBtn}
      >
        <Text style={styles.uploadBtnText}>+ Wgraj wyciąg MT940</Text>
      </TouchableOpacity>

      <FlatList
        data={statements}
        keyExtractor={(item) => String(item.id)}
        refreshControl={<RefreshControl refreshing={isRefetching} onRefresh={refetch} />}
        contentContainerStyle={styles.list}
        ListEmptyComponent={<EmptyState message="Brak wyciągów bankowych. Wgraj plik MT940 aby dopasować transakcje do faktur." />}
        renderItem={({ item }) => {
          const cfg = STATUS_CONFIG[item.status] ?? STATUS_CONFIG.pending;
          return (
            <TouchableOpacity
              onPress={() => router.push(`/(tabs)/payments/statements/${item.id}`)}
              style={[styles.card, shadow.sm]}
            >
              <View style={styles.cardTop}>
                <Text style={styles.fileName} numberOfLines={1}>{item.file_name}</Text>
                <View style={[styles.statusBadge, { backgroundColor: cfg.bg }]}>
                  <Text style={[styles.statusText, { color: cfg.text }]}>{cfg.label}</Text>
                </View>
              </View>
              <Text style={styles.account} numberOfLines={1}>{item.account_number || '—'}</Text>
              <View style={styles.cardBottom}>
                <Text style={styles.meta}>
                  {item.transaction_count} transakcji
                  {item.statement_date ? ` · ${formatDate(item.statement_date)}` : ''}
                </Text>
                <Text style={styles.uploadedAt}>{formatDate(item.uploaded_at)}</Text>
              </View>
            </TouchableOpacity>
          );
        }}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.gray50 },
  uploadBtn: { margin: spacing.lg, backgroundColor: colors.primary, borderRadius: radius.lg, paddingVertical: spacing.lg, alignItems: 'center' },
  uploadBtnText: { color: colors.white, fontWeight: '700', fontSize: 15 },
  list: { paddingHorizontal: spacing.lg, paddingBottom: spacing.lg, gap: spacing.sm },
  card: { backgroundColor: colors.white, borderRadius: radius.lg, padding: spacing.lg },
  cardTop: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: spacing.xs },
  fileName: { flex: 1, fontWeight: '600', color: colors.gray800, fontSize: 14, marginRight: spacing.sm },
  statusBadge: { paddingHorizontal: spacing.sm, paddingVertical: 2, borderRadius: 999 },
  statusText: { fontSize: 11, fontWeight: '600' },
  account: { fontSize: 12, color: colors.gray500, fontFamily: 'monospace', marginBottom: spacing.sm },
  cardBottom: { flexDirection: 'row', justifyContent: 'space-between' },
  meta: { fontSize: 12, color: colors.gray500 },
  uploadedAt: { fontSize: 12, color: colors.gray400 },
});
