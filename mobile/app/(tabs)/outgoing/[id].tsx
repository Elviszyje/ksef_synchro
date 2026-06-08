import { ScrollView, View, Text, TouchableOpacity, Alert, RefreshControl, StyleSheet } from 'react-native';
import { useLocalSearchParams } from 'expo-router';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { getOutgoingInvoice, queueOutgoing } from '../../../src/api/outgoing';
import { StatusBadge } from '../../../src/components/common/StatusBadge';
import { LoadingSpinner } from '../../../src/components/common/LoadingSpinner';
import { formatAmount, formatDate } from '../../../src/utils/format';
import { colors, spacing, radius, shadow } from '../../../src/theme';
import type { InvoiceItem } from '../../../src/types/api';

function Row({ label, value }: { label: string; value: string }) {
  return (
    <View style={styles.row}>
      <Text style={styles.rowLabel}>{label}</Text>
      <Text style={styles.rowValue}>{value}</Text>
    </View>
  );
}

export default function OutgoingDetailScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const qc = useQueryClient();

  const { data: invoice, isLoading, refetch, isRefetching } = useQuery({
    queryKey: ['outgoing', Number(id)],
    queryFn: () => getOutgoingInvoice(Number(id)),
    enabled: Number(id) > 0,
  });

  const queue = useMutation({
    mutationFn: () => queueOutgoing(Number(id)),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['outgoing'] }),
    onError: (e: any) => Alert.alert('Błąd', e?.response?.data?.detail ?? 'Nie udało się wysłać faktury.'),
  });

  if (isLoading || !invoice) return <LoadingSpinner />;

  return (
    <ScrollView style={styles.container} refreshControl={<RefreshControl refreshing={isRefetching} onRefresh={refetch} />}>
      <View style={[styles.card, { marginTop: spacing.lg }]}>
        <View style={styles.headerRow}>
          <Text style={styles.number}>{invoice.invoice_number}</Text>
          <StatusBadge status={invoice.status} />
        </View>
        <Text style={styles.buyer}>{invoice.buyer_name}</Text>
        {invoice.ksef_reference_number ? <Text style={styles.ksef}>KSeF: {invoice.ksef_reference_number}</Text> : null}
        {invoice.error_message ? <Text style={styles.error}>{invoice.error_message}</Text> : null}
      </View>

      <View style={styles.card}>
        <Text style={styles.amountMain}>{formatAmount(invoice.amount_gross)} {invoice.currency}</Text>
        <Row label="Netto" value={`${formatAmount(invoice.amount_net)} zł`} />
        <Row label="VAT" value={`${formatAmount(invoice.amount_vat)} zł`} />
      </View>

      <View style={styles.card}>
        <Row label="NIP nabywcy" value={invoice.buyer_nip} />
        <Row label="Data wystawienia" value={formatDate(invoice.issue_date)} />
        <Row label="Termin płatności" value={formatDate(invoice.payment_due_date)} />
        <Row label="Forma płatności" value={invoice.payment_form} />
      </View>

      {invoice.items && invoice.items.length > 0 && (
        <View style={styles.card}>
          <Text style={styles.sectionTitle}>Pozycje</Text>
          {invoice.items.map((item: InvoiceItem) => (
            <View key={item.id} style={styles.itemRow}>
              <Text style={styles.itemName}>{item.lp}. {item.name}</Text>
              <Text style={styles.itemDetails}>{item.quantity} {item.unit} × {formatAmount(item.unit_price_net)} zł — VAT {item.vat_rate}%</Text>
              <Text style={styles.itemAmount}>{formatAmount(item.amount_gross)} zł</Text>
            </View>
          ))}
        </View>
      )}

      {invoice.can_be_queued && (
        <View style={styles.actionPad}>
          <TouchableOpacity
            style={[styles.queueBtn, queue.isPending && styles.queueBtnDisabled]}
            onPress={() => queue.mutate()}
            disabled={queue.isPending}
          >
            <Text style={styles.queueBtnText}>{queue.isPending ? 'Wysyłanie...' : 'Wyślij do KSeF'}</Text>
          </TouchableOpacity>
        </View>
      )}
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.gray50 },
  card: { backgroundColor: colors.white, marginHorizontal: spacing.lg, marginBottom: spacing.md, borderRadius: radius.lg, padding: spacing.lg, ...shadow.sm },
  headerRow: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: spacing.sm },
  number: { fontSize: 18, fontWeight: '700', color: colors.gray900, flex: 1, marginRight: spacing.sm },
  buyer: { color: colors.gray500, fontSize: 15 },
  ksef: { fontSize: 12, color: colors.success, marginTop: 4 },
  error: { fontSize: 12, color: colors.danger, marginTop: 4 },
  amountMain: { fontSize: 24, fontWeight: '700', color: colors.gray900, paddingBottom: spacing.sm },
  row: { flexDirection: 'row', justifyContent: 'space-between', paddingVertical: spacing.sm, borderBottomWidth: 1, borderBottomColor: colors.gray100 },
  rowLabel: { fontSize: 14, color: colors.gray500 },
  rowValue: { fontSize: 14, color: colors.gray900, fontWeight: '500' },
  sectionTitle: { fontSize: 16, fontWeight: '600', color: colors.gray800, marginBottom: spacing.md },
  itemRow: { marginBottom: spacing.md, paddingBottom: spacing.md, borderBottomWidth: 1, borderBottomColor: colors.gray100 },
  itemName: { fontWeight: '500', color: colors.gray800 },
  itemDetails: { fontSize: 13, color: colors.gray500, marginTop: 2 },
  itemAmount: { fontSize: 14, fontWeight: '600', color: colors.gray700, textAlign: 'right', marginTop: 2 },
  actionPad: { padding: spacing.lg },
  queueBtn: { backgroundColor: colors.success, borderRadius: radius.lg, paddingVertical: spacing.lg, alignItems: 'center' },
  queueBtnDisabled: { backgroundColor: colors.gray300 },
  queueBtnText: { color: colors.white, fontWeight: '700', fontSize: 16 },
});
