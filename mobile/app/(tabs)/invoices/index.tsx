import { useState } from 'react';
import { View, Text, FlatList, TouchableOpacity, TextInput, RefreshControl, StyleSheet } from 'react-native';
import { useRouter } from 'expo-router';
import { useInvoices, useBulkStatus } from '../../../src/hooks/useInvoices';
import { StatusBadge } from '../../../src/components/common/StatusBadge';
import { LoadingSpinner } from '../../../src/components/common/LoadingSpinner';
import { EmptyState } from '../../../src/components/common/EmptyState';
import { formatAmount, formatDate } from '../../../src/utils/format';
import { colors, spacing, radius, shadow } from '../../../src/theme';
import type { Invoice, PaginatedResponse } from '../../../src/types/api';

const STATUS_OPTIONS = [
  { label: 'Wszystkie', value: undefined },
  { label: 'Nowe', value: 'nowa' },
  { label: 'Sporne', value: 'sporna' },
  { label: 'Zaakceptowane', value: 'zaakceptowana' },
  { label: 'Do opłacenia', value: 'przekazano_do_oplacenia' },
  { label: 'Opłacone', value: 'oplacona' },
];

export default function InvoiceListScreen() {
  const router = useRouter();
  const [search, setSearch] = useState('');
  const [statusFilter, setStatusFilter] = useState<string | undefined>();
  const [page, setPage] = useState(1);
  const [selectedIds, setSelectedIds] = useState<number[]>([]);
  const bulkStatus = useBulkStatus();

  const { data, isLoading, refetch, isRefetching } = useInvoices({
    seller_name: search || undefined,
    status: statusFilter,
    page,
  });

  const invoices: Invoice[] = (data as PaginatedResponse<Invoice>)?.results ?? [];

  const toggleSelect = (id: number) =>
    setSelectedIds((prev) => prev.includes(id) ? prev.filter((i) => i !== id) : [...prev, id]);

  if (isLoading) return <LoadingSpinner />;

  return (
    <View style={styles.container}>
      <View style={styles.searchRow}>
        <TextInput
          style={styles.search}
          placeholder="Szukaj sprzedawcy..."
          placeholderTextColor={colors.gray400}
          value={search}
          onChangeText={(t) => { setSearch(t); setPage(1); }}
        />
      </View>

      <FlatList
        horizontal
        showsHorizontalScrollIndicator={false}
        data={STATUS_OPTIONS}
        keyExtractor={(item) => item.label}
        contentContainerStyle={styles.filterList}
        style={styles.filterContainer}
        renderItem={({ item }) => (
          <TouchableOpacity
            onPress={() => { setStatusFilter(item.value); setPage(1); }}
            style={[styles.filterChip, statusFilter === item.value && styles.filterChipActive]}
          >
            <Text style={[styles.filterChipText, statusFilter === item.value && styles.filterChipTextActive]}>
              {item.label}
            </Text>
          </TouchableOpacity>
        )}
      />

      {selectedIds.length > 0 && (
        <View style={styles.bulkBar}>
          <Text style={styles.bulkText}>Wybrano: {selectedIds.length}</Text>
          <TouchableOpacity
            onPress={() => { bulkStatus.mutate({ ids: selectedIds, status: 'zaakceptowana' }); setSelectedIds([]); }}
            style={styles.bulkBtn}
          >
            <Text style={styles.bulkBtnText}>Akceptuj wszystkie</Text>
          </TouchableOpacity>
        </View>
      )}

      <FlatList
        data={invoices}
        keyExtractor={(item) => String(item.id)}
        refreshControl={<RefreshControl refreshing={isRefetching} onRefresh={refetch} />}
        contentContainerStyle={styles.list}
        ListEmptyComponent={<EmptyState message="Brak faktur" />}
        renderItem={({ item }) => (
          <TouchableOpacity
            onPress={() => router.push(`/(tabs)/invoices/${item.id}`)}
            onLongPress={() => toggleSelect(item.id)}
            style={[styles.card, shadow.sm, selectedIds.includes(item.id) && styles.cardSelected, item.is_overdue && styles.cardOverdue]}
          >
            <View style={styles.cardTop}>
              <Text style={styles.invoiceNumber} numberOfLines={1}>{item.invoice_number}</Text>
              <StatusBadge status={item.status} />
            </View>
            <Text style={styles.sellerName} numberOfLines={1}>{item.seller_name}</Text>
            <View style={styles.cardBottom}>
              <Text style={styles.date}>{formatDate(item.issue_date)}</Text>
              <Text style={styles.amount}>{formatAmount(item.amount_gross)} {item.currency}</Text>
            </View>
            {item.is_split_payment && <Text style={styles.splitBadge}>⚡ Split payment</Text>}
          </TouchableOpacity>
        )}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.gray50 },
  searchRow: { paddingHorizontal: spacing.lg, paddingTop: spacing.lg, paddingBottom: spacing.sm },
  search: { backgroundColor: colors.white, borderWidth: 1, borderColor: colors.gray200, borderRadius: radius.md, paddingHorizontal: spacing.lg, paddingVertical: spacing.md, color: colors.gray800, fontSize: 16 },
  filterContainer: { maxHeight: 44, marginBottom: spacing.sm },
  filterList: { paddingHorizontal: spacing.lg, gap: spacing.sm },
  filterChip: { paddingHorizontal: spacing.lg, paddingVertical: 8, borderRadius: 999, borderWidth: 1, borderColor: colors.gray200, backgroundColor: colors.white },
  filterChipActive: { backgroundColor: colors.primary, borderColor: colors.primary },
  filterChipText: { color: colors.gray600, fontSize: 14, lineHeight: 20, includeFontPadding: false, fontWeight: '500' } as any,
  filterChipTextActive: { color: colors.white },
  bulkBar: { marginHorizontal: spacing.lg, marginBottom: spacing.sm, backgroundColor: colors.primaryLight, borderWidth: 1, borderColor: '#bfdbfe', borderRadius: radius.md, paddingHorizontal: spacing.lg, paddingVertical: spacing.md, flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' },
  bulkText: { color: colors.primary, fontWeight: '500' },
  bulkBtn: { backgroundColor: colors.primary, paddingHorizontal: spacing.lg, paddingVertical: 8, borderRadius: radius.sm },
  bulkBtnText: { color: colors.white, fontWeight: '600', fontSize: 13 },
  list: { padding: spacing.lg, gap: spacing.sm },
  card: { backgroundColor: colors.white, borderRadius: radius.lg, padding: spacing.lg, borderWidth: 2, borderColor: 'transparent' },
  cardSelected: { borderColor: colors.primary },
  cardOverdue: { borderLeftWidth: 4, borderLeftColor: colors.danger },
  cardTop: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: spacing.sm },
  invoiceNumber: { fontWeight: '600', color: colors.gray900, flex: 1, marginRight: spacing.sm, fontSize: 15 },
  sellerName: { fontSize: 14, color: colors.gray500, marginBottom: spacing.sm },
  cardBottom: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' },
  date: { fontSize: 12, color: colors.gray400 },
  amount: { fontWeight: '700', color: colors.primary, fontSize: 15 },
  splitBadge: { fontSize: 12, color: colors.orange, marginTop: 4 },
});
