import { useState } from 'react';
import { View, Text, FlatList, TouchableOpacity, RefreshControl, Alert, StyleSheet } from 'react-native';
import { useRouter } from 'expo-router';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { getOutgoing, bulkQueueOutgoing } from '../../../src/api/outgoing';
import { StatusBadge } from '../../../src/components/common/StatusBadge';
import { LoadingSpinner } from '../../../src/components/common/LoadingSpinner';
import { EmptyState } from '../../../src/components/common/EmptyState';
import { formatAmount, formatDate } from '../../../src/utils/format';
import { colors, spacing, radius, shadow } from '../../../src/theme';
import type { OutgoingInvoice, PaginatedResponse } from '../../../src/types/api';

const KSEF_STATUSES = ['queued', 'sending', 'accepted', 'rejected'];

type Tab = 'drafts' | 'ksef';

export default function OutgoingListScreen() {
  const router = useRouter();
  const qc = useQueryClient();
  const [tab, setTab] = useState<Tab>('drafts');
  const [selectedIds, setSelectedIds] = useState<number[]>([]);

  const { data, isLoading, refetch, isRefetching } = useQuery({
    queryKey: ['outgoing'],
    queryFn: () => getOutgoing(),
  });

  const allInvoices: OutgoingInvoice[] =
    (data as PaginatedResponse<OutgoingInvoice>)?.results ?? (Array.isArray(data) ? data : []);

  const drafts = allInvoices.filter((i) => i.status === 'draft');
  const ksefInvoices = allInvoices.filter((i) => KSEF_STATUSES.includes(i.status));
  const displayList = tab === 'drafts' ? drafts : ksefInvoices;

  const bulkQueue = useMutation({
    mutationFn: () => bulkQueueOutgoing(selectedIds),
    onSuccess: (result) => {
      setSelectedIds([]);
      qc.invalidateQueries({ queryKey: ['outgoing'] });
      const count = result?.queued?.length ?? 0;
      const errCount = result?.errors?.length ?? 0;
      let msg = `Dodano ${count} faktur do kolejki KSeF.`;
      if (errCount > 0) msg += ` Pominięto ${errCount} (brak pozycji).`;
      Alert.alert('Gotowe', msg);
      setTab('ksef');
    },
    onError: (e: any) =>
      Alert.alert('Błąd', e?.response?.data?.detail ?? 'Nie udało się wysłać faktur.'),
  });

  const toggleSelect = (id: number) =>
    setSelectedIds((prev) => prev.includes(id) ? prev.filter((i) => i !== id) : [...prev, id]);

  const selectAll = () => setSelectedIds(drafts.map((i) => i.id));
  const clearSelection = () => setSelectedIds([]);

  const handleBulkQueue = () => {
    if (selectedIds.length === 0) return;
    Alert.alert(
      'Wysłać do KSeF?',
      `Wyślij ${selectedIds.length} faktur do kolejki wysyłki?`,
      [
        { text: 'Anuluj', style: 'cancel' },
        { text: 'Wyślij', onPress: () => bulkQueue.mutate() },
      ],
    );
  };

  if (isLoading) return <LoadingSpinner />;

  return (
    <View style={styles.container}>
      {/* Przyciski akcji */}
      <View style={styles.topBar}>
        <TouchableOpacity
          onPress={() => router.push('/(tabs)/outgoing/new')}
          style={[styles.topBtn, styles.primaryBtn]}
        >
          <Text style={styles.primaryBtnText}>+ Nowa faktura</Text>
        </TouchableOpacity>
        <TouchableOpacity
          onPress={() => router.push('/(tabs)/outgoing/buyers')}
          style={[styles.topBtn, styles.secondaryBtn]}
        >
          <Text style={styles.secondaryBtnText}>Nabywcy</Text>
        </TouchableOpacity>
      </View>

      {/* Zakładki */}
      <View style={styles.tabs}>
        <TouchableOpacity
          onPress={() => { setTab('drafts'); clearSelection(); }}
          style={[styles.tab, tab === 'drafts' && styles.tabActive]}
        >
          <Text style={[styles.tabText, tab === 'drafts' && styles.tabTextActive]}>
            Szkice
          </Text>
          {drafts.length > 0 && (
            <View style={[styles.badge, tab === 'drafts' ? styles.badgeActive : styles.badgeInactive]}>
              <Text style={[styles.badgeText, tab === 'drafts' && styles.badgeTextActive]}>
                {drafts.length}
              </Text>
            </View>
          )}
        </TouchableOpacity>
        <TouchableOpacity
          onPress={() => { setTab('ksef'); clearSelection(); }}
          style={[styles.tab, tab === 'ksef' && styles.tabActive]}
        >
          <Text style={[styles.tabText, tab === 'ksef' && styles.tabTextActive]}>
            KSeF
          </Text>
          {ksefInvoices.length > 0 && (
            <View style={[styles.badge, tab === 'ksef' ? styles.badgeActive : styles.badgeInactive]}>
              <Text style={[styles.badgeText, tab === 'ksef' && styles.badgeTextActive]}>
                {ksefInvoices.length}
              </Text>
            </View>
          )}
        </TouchableOpacity>
      </View>

      {/* Pasek bulk-select dla szkiców */}
      {tab === 'drafts' && drafts.length > 0 && (
        <View style={styles.selectBar}>
          <TouchableOpacity onPress={selectedIds.length === drafts.length ? clearSelection : selectAll}>
            <Text style={styles.selectAllText}>
              {selectedIds.length === drafts.length ? 'Odznacz wszystkie' : 'Zaznacz wszystkie'}
            </Text>
          </TouchableOpacity>
          {selectedIds.length > 0 && (
            <TouchableOpacity
              onPress={handleBulkQueue}
              disabled={bulkQueue.isPending}
              style={[styles.queueBtn, bulkQueue.isPending && styles.queueBtnDisabled]}
            >
              <Text style={styles.queueBtnText}>
                {bulkQueue.isPending ? 'Wysyłanie...' : `Wyślij ${selectedIds.length} do KSeF`}
              </Text>
            </TouchableOpacity>
          )}
        </View>
      )}

      <FlatList
        data={displayList}
        keyExtractor={(item) => String(item.id)}
        refreshControl={<RefreshControl refreshing={isRefetching} onRefresh={refetch} />}
        contentContainerStyle={styles.list}
        ListEmptyComponent={
          <EmptyState
            message={tab === 'drafts' ? 'Brak szkiców faktur' : 'Brak faktur wysłanych do KSeF'}
          />
        }
        renderItem={({ item }) => {
          const isSelected = selectedIds.includes(item.id);
          return (
            <TouchableOpacity
              onPress={() =>
                tab === 'drafts'
                  ? toggleSelect(item.id)
                  : router.push(`/(tabs)/outgoing/${item.id}`)
              }
              onLongPress={() => router.push(`/(tabs)/outgoing/${item.id}`)}
              style={[styles.card, shadow.sm, isSelected && styles.cardSelected]}
            >
              <View style={styles.cardTop}>
                {tab === 'drafts' && (
                  <View style={[styles.checkbox, isSelected && styles.checkboxActive]}>
                    {isSelected && <Text style={styles.checkmark}>✓</Text>}
                  </View>
                )}
                <Text style={[styles.number, tab === 'drafts' && { flex: 1 }]} numberOfLines={1}>
                  {item.invoice_number}
                </Text>
                {tab === 'ksef' && <StatusBadge status={item.status} />}
              </View>
              <Text style={styles.buyer} numberOfLines={1}>{item.buyer_name}</Text>
              <View style={styles.cardBottom}>
                <Text style={styles.date}>
                  {tab === 'drafts'
                    ? `Wystawiona: ${formatDate(item.issue_date)}`
                    : `Termin: ${formatDate(item.payment_due_date)}`}
                </Text>
                <Text style={styles.amount}>{formatAmount(item.amount_gross)} {item.currency}</Text>
              </View>
              {tab === 'drafts' && (
                <Text style={styles.tapHint}>Dotknij aby zaznaczyć · przytrzymaj aby otworzyć</Text>
              )}
            </TouchableOpacity>
          );
        }}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.gray50 },
  topBar: { flexDirection: 'row', marginHorizontal: spacing.lg, marginTop: spacing.lg, marginBottom: spacing.sm, gap: spacing.sm },
  topBtn: { borderRadius: radius.lg, paddingVertical: spacing.md, alignItems: 'center', justifyContent: 'center' },
  primaryBtn: { flex: 1, backgroundColor: colors.primary },
  primaryBtnText: { color: colors.white, fontWeight: '700', fontSize: 15 },
  secondaryBtn: { paddingHorizontal: spacing.lg, borderWidth: 1, borderColor: colors.gray200, backgroundColor: colors.white },
  secondaryBtnText: { color: colors.gray700, fontWeight: '600', fontSize: 15 },
  // Zakładki
  tabs: { flexDirection: 'row', marginHorizontal: spacing.lg, marginBottom: spacing.sm, borderBottomWidth: 1, borderBottomColor: colors.gray200 },
  tab: { flexDirection: 'row', alignItems: 'center', paddingVertical: spacing.sm, paddingHorizontal: spacing.lg, gap: spacing.sm, marginBottom: -1 },
  tabActive: { borderBottomWidth: 2, borderBottomColor: colors.primary },
  tabText: { fontSize: 15, fontWeight: '500', color: colors.gray500 },
  tabTextActive: { color: colors.primary, fontWeight: '600' },
  badge: { borderRadius: 999, paddingHorizontal: 6, paddingVertical: 1, minWidth: 20, alignItems: 'center' },
  badgeActive: { backgroundColor: colors.primary },
  badgeInactive: { backgroundColor: colors.gray200 },
  badgeText: { fontSize: 11, fontWeight: '700', color: colors.gray600 },
  badgeTextActive: { color: colors.white },
  // Select bar
  selectBar: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingHorizontal: spacing.lg, paddingVertical: spacing.sm },
  selectAllText: { fontSize: 13, color: colors.primary, fontWeight: '500' },
  queueBtn: { backgroundColor: colors.success, borderRadius: radius.sm, paddingHorizontal: spacing.md, paddingVertical: spacing.sm },
  queueBtnDisabled: { backgroundColor: colors.gray300 },
  queueBtnText: { color: colors.white, fontSize: 13, fontWeight: '700' },
  // Lista
  list: { padding: spacing.lg, gap: spacing.sm },
  card: { backgroundColor: colors.white, borderRadius: radius.lg, padding: spacing.lg, borderWidth: 2, borderColor: 'transparent' },
  cardSelected: { borderColor: colors.primary },
  cardTop: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm, marginBottom: 4 },
  checkbox: { width: 20, height: 20, borderRadius: 5, borderWidth: 2, borderColor: colors.gray300, alignItems: 'center', justifyContent: 'center' },
  checkboxActive: { backgroundColor: colors.primary, borderColor: colors.primary },
  checkmark: { color: colors.white, fontSize: 12, fontWeight: '700' },
  number: { fontWeight: '600', color: colors.gray900, flex: 1, fontSize: 15 },
  buyer: { fontSize: 14, color: colors.gray500, marginBottom: spacing.sm },
  cardBottom: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' },
  date: { fontSize: 12, color: colors.gray400 },
  amount: { fontWeight: '700', color: colors.primary, fontSize: 15 },
  tapHint: { fontSize: 10, color: colors.gray300, marginTop: 4, textAlign: 'right' },
});
