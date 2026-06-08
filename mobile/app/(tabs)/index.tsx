import { ScrollView, View, Text, StyleSheet, RefreshControl } from 'react-native';
import { useDashboard } from '../../src/hooks/useInvoices';
import { useAuthStore } from '../../src/store/auth';
import { LoadingSpinner } from '../../src/components/common/LoadingSpinner';
import { formatAmount } from '../../src/utils/format';
import { colors, spacing, radius, shadow } from '../../src/theme';
import type { DashboardMonth } from '../../src/types/api';

export default function DashboardScreen() {
  const { data, isLoading, refetch, isRefetching } = useDashboard();
  const user = useAuthStore((s) => s.user);

  if (isLoading) return <LoadingSpinner />;

  const months: DashboardMonth[] = data ?? [];
  const totalGross = months.reduce((acc, m) => acc + parseFloat(m.total_gross || '0'), 0);
  const totalCount = months.reduce((acc, m) => acc + m.count, 0);
  const last = months[months.length - 1];

  return (
    <ScrollView style={styles.container} refreshControl={<RefreshControl refreshing={isRefetching} onRefresh={refetch} />}>
      <View style={styles.content}>
        <Text style={styles.greeting}>
          Dzień dobry{user?.first_name ? `, ${user.first_name}` : ''}!
        </Text>
        <Text style={styles.company}>{user?.company_name ?? 'Twoja firma'}</Text>

        <View style={styles.kpiRow}>
          <View style={[styles.kpiCard, shadow.sm]}>
            <Text style={styles.kpiLabel}>Suma brutto (12 mies.)</Text>
            <Text style={styles.kpiValue}>{formatAmount(totalGross)} zł</Text>
          </View>
          <View style={[styles.kpiCard, shadow.sm]}>
            <Text style={styles.kpiLabel}>Liczba faktur</Text>
            <Text style={[styles.kpiValue, { color: colors.gray800 }]}>{totalCount}</Text>
          </View>
        </View>

        {last && (
          <View style={[styles.monthCard, shadow.sm]}>
            <Text style={styles.kpiLabel}>Ostatni miesiąc ({last.month})</Text>
            <Text style={[styles.kpiValue, { color: colors.gray900 }]}>{formatAmount(last.total_gross)} zł</Text>
            <Text style={styles.kpiSub}>{last.count} faktur</Text>
          </View>
        )}

        <Text style={styles.sectionTitle}>Miesięczne zestawienie</Text>
        {[...months].reverse().map((m) => (
          <View key={m.month} style={[styles.monthRow, shadow.sm]}>
            <View>
              <Text style={styles.monthLabel}>{m.month}</Text>
              <Text style={styles.monthSub}>{m.count} faktur</Text>
            </View>
            <Text style={styles.monthAmount}>{formatAmount(m.total_gross)} zł</Text>
          </View>
        ))}
      </View>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.gray50 },
  content: { padding: spacing.lg },
  greeting: { fontSize: 20, fontWeight: '700', color: colors.gray900, marginBottom: 4 },
  company: { fontSize: 14, color: colors.gray500, marginBottom: spacing.lg },
  kpiRow: { flexDirection: 'row', gap: spacing.md, marginBottom: spacing.md },
  kpiCard: { flex: 1, backgroundColor: colors.white, borderRadius: radius.lg, padding: spacing.lg },
  kpiLabel: { fontSize: 12, color: colors.gray500, marginBottom: 4 },
  kpiValue: { fontSize: 20, fontWeight: '700', color: colors.primary },
  kpiSub: { fontSize: 14, color: colors.gray500, marginTop: 2 },
  monthCard: { backgroundColor: colors.white, borderRadius: radius.lg, padding: spacing.lg, marginBottom: spacing.lg },
  sectionTitle: { fontSize: 16, fontWeight: '600', color: colors.gray800, marginBottom: spacing.sm },
  monthRow: { backgroundColor: colors.white, borderRadius: radius.lg, padding: spacing.lg, marginBottom: spacing.sm, flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' },
  monthLabel: { fontWeight: '500', color: colors.gray800, fontSize: 15 },
  monthSub: { fontSize: 12, color: colors.gray500, marginTop: 2 },
  monthAmount: { fontWeight: '700', color: colors.primary, fontSize: 15 },
});
