import { useState } from 'react';
import { View, Text, FlatList, TouchableOpacity, RefreshControl, Alert, StyleSheet } from 'react-native';
import { usePaymentFiles } from '../../../src/hooks/usePayments';
import { downloadAndSharePaymentFile } from '../../../src/api/payments';
import { LoadingSpinner } from '../../../src/components/common/LoadingSpinner';
import { EmptyState } from '../../../src/components/common/EmptyState';
import { formatAmount, formatDate } from '../../../src/utils/format';
import { colors, spacing, radius, shadow } from '../../../src/theme';
import type { PaymentFile, PaginatedResponse } from '../../../src/types/api';

const FORMAT_LABELS: Record<string, string> = {
  erste: 'Erste',
  elixir: 'Elixir-0',
  mbank: 'mBank',
};

export default function PaymentHistoryScreen() {
  const { data, isLoading, refetch, isRefetching } = usePaymentFiles();
  const [downloadingId, setDownloadingId] = useState<number | null>(null);

  const files: PaymentFile[] = (data as PaginatedResponse<PaymentFile>)?.results ?? (Array.isArray(data) ? data : []);

  const handleDownload = async (file: PaymentFile) => {
    setDownloadingId(file.id);
    try {
      await downloadAndSharePaymentFile(file.id, file.file_name);
    } catch {
      Alert.alert('Błąd', 'Nie udało się pobrać pliku.');
    } finally {
      setDownloadingId(null);
    }
  };

  if (isLoading) return <LoadingSpinner />;

  return (
    <FlatList
      data={files}
      keyExtractor={(item) => String(item.id)}
      refreshControl={<RefreshControl refreshing={isRefetching} onRefresh={refetch} />}
      contentContainerStyle={styles.list}
      ListEmptyComponent={<EmptyState message="Brak wygenerowanych plików przelewów." />}
      renderItem={({ item }) => (
        <TouchableOpacity
          onPress={() => handleDownload(item)}
          disabled={downloadingId === item.id}
          style={[styles.card, shadow.sm, downloadingId === item.id && styles.cardDisabled]}
        >
          <View style={styles.cardTop}>
            <View style={styles.formatBadge}>
              <Text style={styles.formatText}>{FORMAT_LABELS[item.format] ?? item.format}</Text>
            </View>
            <Text style={styles.date}>{formatDate(item.created_at)}</Text>
          </View>
          <Text style={styles.fileName} numberOfLines={1}>{item.file_name}</Text>
          <View style={styles.cardBottom}>
            <Text style={styles.meta}>{item.invoice_count} faktur</Text>
            <Text style={styles.amount}>{formatAmount(item.total_amount)} PLN</Text>
          </View>
          {downloadingId === item.id && (
            <Text style={styles.downloading}>Pobieranie...</Text>
          )}
        </TouchableOpacity>
      )}
    />
  );
}

const styles = StyleSheet.create({
  list: { padding: spacing.lg, gap: spacing.sm },
  card: { backgroundColor: colors.white, borderRadius: radius.lg, padding: spacing.lg },
  cardDisabled: { opacity: 0.6 },
  cardTop: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginBottom: spacing.sm },
  formatBadge: { backgroundColor: colors.primaryLight, paddingHorizontal: spacing.md, paddingVertical: 3, borderRadius: radius.sm },
  formatText: { color: colors.primary, fontSize: 12, fontWeight: '600' },
  date: { fontSize: 12, color: colors.gray400 },
  fileName: { fontSize: 14, color: colors.gray700, marginBottom: spacing.sm },
  cardBottom: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' },
  meta: { fontSize: 13, color: colors.gray500 },
  amount: { fontWeight: '700', color: colors.primary, fontSize: 15 },
  downloading: { fontSize: 12, color: colors.gray400, marginTop: spacing.xs, textAlign: 'center' },
});
