import { useState } from 'react';
import { ScrollView, View, Text, TouchableOpacity, RefreshControl, StyleSheet } from 'react-native';
import { useLocalSearchParams } from 'expo-router';
import { useInvoice, useChangeStatus } from '../../../src/hooks/useInvoices';
import { StatusBadge } from '../../../src/components/common/StatusBadge';
import { StatusChangeSheet } from '../../../src/components/invoices/StatusChangeSheet';
import { LoadingSpinner } from '../../../src/components/common/LoadingSpinner';
import { formatAmount, formatDate, formatDateTime } from '../../../src/utils/format';
import { STATUS_LABELS } from '../../../src/utils/statusColors';
import { colors, spacing, radius, shadow } from '../../../src/theme';
import type { StatusLog } from '../../../src/types/api';

function Row({ label, value }: { label: string; value: string }) {
  return (
    <View style={styles.row}>
      <Text style={styles.rowLabel}>{label}</Text>
      <Text style={styles.rowValue} numberOfLines={2}>{value}</Text>
    </View>
  );
}

export default function InvoiceDetailScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const { data: invoice, isLoading, refetch, isRefetching } = useInvoice(Number(id));
  const changeStatus = useChangeStatus();
  const [sheetVisible, setSheetVisible] = useState(false);

  if (isLoading || !invoice) return <LoadingSpinner />;

  return (
    <ScrollView style={styles.container} refreshControl={<RefreshControl refreshing={isRefetching} onRefresh={refetch} />}>
      <View style={[styles.card, styles.headerCard]}>
        <View style={styles.headerTop}>
          <Text style={styles.invoiceNumber}>{invoice.invoice_number}</Text>
          <StatusBadge status={invoice.status} />
        </View>
        <Text style={styles.sellerName}>{invoice.seller_name}</Text>
        {invoice.is_overdue && <Text style={styles.overdueText}>⚠ Termin płatności minął</Text>}
      </View>

      <View style={[styles.card, styles.amountCard]}>
        <Text style={styles.amountMain}>{formatAmount(invoice.amount_gross)} {invoice.currency}</Text>
        <Text style={styles.amountSub}>Netto: {formatAmount(invoice.amount_net)} | VAT: {formatAmount(invoice.amount_vat)}</Text>
        {invoice.is_split_payment && <Text style={styles.splitText}>⚡ Split payment</Text>}
      </View>

      <View style={[styles.card, styles.detailsCard]}>
        <Row label="NIP sprzedawcy" value={invoice.seller_nip} />
        <Row label="Data wystawienia" value={formatDate(invoice.issue_date)} />
        <Row label="Termin płatności" value={formatDate(invoice.payment_due_date)} />
        <Row label="Forma płatności" value={invoice.payment_form || '—'} />
        {invoice.bank_account_number ? <Row label="Nr konta" value={invoice.bank_account_number} /> : null}
        {invoice.payment_title ? <Row label="Tytuł płatności" value={invoice.payment_title} /> : null}
      </View>

      {invoice.status_logs && invoice.status_logs.length > 0 && (
        <View style={[styles.card, styles.logsCard]}>
          <Text style={styles.sectionTitle}>Historia zmian</Text>
          {invoice.status_logs.map((log: StatusLog) => (
            <View key={log.id} style={styles.logItem}>
              <Text style={styles.logStatus}>
                {STATUS_LABELS[log.old_status] ?? log.old_status} → {STATUS_LABELS[log.new_status] ?? log.new_status}
              </Text>
              <Text style={styles.logMeta}>{log.changed_by_username} · {formatDateTime(log.changed_at)}</Text>
              {log.note ? <Text style={styles.logNote}>{log.note}</Text> : null}
            </View>
          ))}
        </View>
      )}

      {invoice.allowed_transitions && invoice.allowed_transitions.length > 0 && (
        <View style={styles.actionPad}>
          <TouchableOpacity style={styles.actionBtn} onPress={() => setSheetVisible(true)}>
            <Text style={styles.actionBtnText}>Zmień status</Text>
          </TouchableOpacity>
        </View>
      )}

      <StatusChangeSheet
        visible={sheetVisible}
        onClose={() => setSheetVisible(false)}
        allowedTransitions={invoice.allowed_transitions ?? []}
        onConfirm={(status, note) => {
          changeStatus.mutate({ id: invoice.id, status, note });
          setSheetVisible(false);
        }}
      />
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.gray50 },
  card: { backgroundColor: colors.white, marginTop: spacing.md, marginHorizontal: spacing.lg, borderRadius: radius.lg, ...shadow.sm },
  headerCard: { padding: spacing.lg, marginTop: spacing.lg },
  headerTop: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: spacing.sm },
  invoiceNumber: { fontSize: 18, fontWeight: '700', color: colors.gray900, flex: 1, marginRight: spacing.sm },
  sellerName: { color: colors.gray500, fontSize: 15 },
  overdueText: { color: colors.danger, fontSize: 14, fontWeight: '500', marginTop: 4 },
  amountCard: { padding: spacing.lg },
  amountMain: { fontSize: 26, fontWeight: '700', color: colors.gray900 },
  amountSub: { color: colors.gray500, fontSize: 13, marginTop: 4 },
  splitText: { color: colors.orange, fontSize: 13, fontWeight: '500', marginTop: 4 },
  detailsCard: { paddingHorizontal: spacing.lg, paddingVertical: spacing.sm },
  row: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'flex-start', paddingVertical: spacing.sm, borderBottomWidth: 1, borderBottomColor: colors.gray100 },
  rowLabel: { fontSize: 14, color: colors.gray500, flex: 1 },
  rowValue: { fontSize: 14, color: colors.gray900, fontWeight: '500', flex: 2, textAlign: 'right' },
  logsCard: { padding: spacing.lg },
  sectionTitle: { fontSize: 16, fontWeight: '600', color: colors.gray800, marginBottom: spacing.md },
  logItem: { marginBottom: spacing.md, paddingLeft: spacing.md, borderLeftWidth: 2, borderLeftColor: colors.gray200 },
  logStatus: { fontSize: 14, color: colors.gray600 },
  logMeta: { fontSize: 12, color: colors.gray400, marginTop: 2 },
  logNote: { fontSize: 12, color: colors.gray500, marginTop: 2, fontStyle: 'italic' },
  actionPad: { padding: spacing.lg },
  actionBtn: { backgroundColor: colors.primary, borderRadius: radius.lg, paddingVertical: spacing.lg, alignItems: 'center' },
  actionBtnText: { color: colors.white, fontWeight: '700', fontSize: 16 },
});
