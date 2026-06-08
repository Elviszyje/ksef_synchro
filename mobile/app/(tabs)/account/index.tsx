import { useCallback } from 'react';
import { View, Text, ScrollView, TouchableOpacity, Alert, StyleSheet, ActivityIndicator } from 'react-native';
import { useRouter } from 'expo-router';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useAuthStore } from '../../../src/store/auth';
import { getCompany, deleteBankAccount } from '../../../src/api/account';
import { getBankAccounts } from '../../../src/api/payments';
import { formatNrb } from '../../../src/utils/format';
import { colors, spacing, radius, shadow } from '../../../src/theme';
import type { Company, CompanyBankAccount } from '../../../src/types/api';

const ROLE_LABELS: Record<string, string> = {
  viewer: 'Podgląd',
  accountant: 'Księgowy',
  approver: 'Zatwierdzający',
  admin: 'Admin',
  super_admin: 'Super Admin',
};

const PLAN_LABELS: Record<string, string> = {
  free: 'Free',
  standard: 'Standard',
  ultra: 'Ultra',
};

export default function AccountScreen() {
  const router = useRouter();
  const qc = useQueryClient();
  const { user, logout } = useAuthStore();

  const { data: company, isLoading: companyLoading } = useQuery<Company>({
    queryKey: ['company'],
    queryFn: getCompany,
    enabled: !!user?.company_id,
  });

  const { data: bankAccounts = [], isLoading: banksLoading } = useQuery<CompanyBankAccount[]>({
    queryKey: ['bank-accounts'],
    queryFn: getBankAccounts,
    enabled: !!user?.company_id,
  });

  const deleteBank = useMutation({
    mutationFn: deleteBankAccount,
    onSuccess: () => qc.invalidateQueries({ queryKey: ['bank-accounts'] }),
    onError: () => Alert.alert('Błąd', 'Nie udało się usunąć rachunku.'),
  });

  const handleDeleteBank = useCallback((id: number, label: string) => {
    Alert.alert(
      'Usuń rachunek',
      `Czy na pewno chcesz usunąć rachunek "${label || 'bez nazwy'}"?`,
      [
        { text: 'Anuluj', style: 'cancel' },
        { text: 'Usuń', style: 'destructive', onPress: () => deleteBank.mutate(id) },
      ],
    );
  }, [deleteBank]);

  const handleLogout = () => {
    Alert.alert('Wyloguj', 'Czy na pewno chcesz się wylogować?', [
      { text: 'Anuluj', style: 'cancel' },
      { text: 'Wyloguj', style: 'destructive', onPress: logout },
    ]);
  };

  if (!user) return null;

  const initials = [user.first_name?.[0], user.last_name?.[0]].filter(Boolean).join('').toUpperCase()
    || user.username[0].toUpperCase();

  return (
    <ScrollView style={styles.container} contentContainerStyle={styles.content}>

      {/* Profil */}
      <View style={[styles.card, shadow.sm]}>
        <View style={styles.avatarRow}>
          <View style={styles.avatar}>
            <Text style={styles.avatarText}>{initials}</Text>
          </View>
          <View style={styles.avatarInfo}>
            <Text style={styles.fullName}>
              {[user.first_name, user.last_name].filter(Boolean).join(' ') || user.username}
            </Text>
            <Text style={styles.username}>@{user.username}</Text>
            <Text style={styles.email}>{user.email}</Text>
          </View>
        </View>
        <View style={styles.badgeRow}>
          <View style={styles.roleBadge}>
            <Text style={styles.roleBadgeText}>{ROLE_LABELS[user.role] ?? user.role}</Text>
          </View>
          {user.license_plan && (
            <View style={[styles.roleBadge, styles.planBadge]}>
              <Text style={styles.roleBadgeText}>{PLAN_LABELS[user.license_plan] ?? user.license_plan}</Text>
            </View>
          )}
          {user.license_valid_until && (
            <Text style={styles.validUntil}>do {user.license_valid_until}</Text>
          )}
        </View>
        <TouchableOpacity
          style={styles.editBtn}
          onPress={() => router.push('/(tabs)/account/edit-profile')}
        >
          <Text style={styles.editBtnText}>Edytuj profil</Text>
        </TouchableOpacity>
      </View>

      {/* Firma */}
      {user.company_id && (
        <View style={[styles.card, shadow.sm]}>
          <View style={styles.sectionHeader}>
            <Text style={styles.sectionTitle}>Firma</Text>
            {user.role === 'admin' || user.role === 'super_admin' ? (
              <TouchableOpacity onPress={() => router.push('/(tabs)/account/company')}>
                <Text style={styles.sectionAction}>Edytuj</Text>
              </TouchableOpacity>
            ) : null}
          </View>
          {companyLoading ? (
            <ActivityIndicator size="small" color={colors.primary} />
          ) : company ? (
            <>
              <Text style={styles.companyName}>{company.name}</Text>
              <Text style={styles.companyDetail}>NIP: {company.nip}</Text>
              {company.address ? <Text style={styles.companyDetail}>{company.address}</Text> : null}
            </>
          ) : null}
        </View>
      )}

      {/* Rachunki bankowe */}
      {user.company_id && (
        <View style={[styles.card, shadow.sm]}>
          <View style={styles.sectionHeader}>
            <Text style={styles.sectionTitle}>Rachunki bankowe</Text>
            <TouchableOpacity onPress={() => router.push('/(tabs)/account/bank-account')}>
              <Text style={styles.sectionAction}>+ Dodaj</Text>
            </TouchableOpacity>
          </View>
          {banksLoading ? (
            <ActivityIndicator size="small" color={colors.primary} />
          ) : bankAccounts.length === 0 ? (
            <Text style={styles.emptyText}>Brak skonfigurowanych rachunków</Text>
          ) : (
            bankAccounts.map((ba) => (
              <View key={ba.id} style={styles.bankRow}>
                <View style={styles.bankInfo}>
                  <View style={styles.bankNameRow}>
                    <Text style={styles.bankName}>{ba.bank_name || 'Bank'}</Text>
                    {ba.is_default && (
                      <View style={styles.defaultBadge}>
                        <Text style={styles.defaultBadgeText}>domyślny</Text>
                      </View>
                    )}
                  </View>
                  {ba.label ? <Text style={styles.bankLabel}>{ba.label}</Text> : null}
                  <Text style={styles.bankNrb}>{formatNrb(ba.account_number)}</Text>
                </View>
                <View style={styles.bankActions}>
                  <TouchableOpacity
                    onPress={() => router.push({ pathname: '/(tabs)/account/bank-account', params: { id: ba.id } })}
                    style={styles.bankActionBtn}
                  >
                    <Text style={styles.bankActionEdit}>Edytuj</Text>
                  </TouchableOpacity>
                  <TouchableOpacity
                    onPress={() => handleDeleteBank(ba.id, ba.label ?? '')}
                    style={styles.bankActionBtn}
                  >
                    <Text style={styles.bankActionDelete}>Usuń</Text>
                  </TouchableOpacity>
                </View>
              </View>
            ))
          )}
        </View>
      )}

      {/* Wyloguj */}
      <TouchableOpacity style={styles.logoutBtn} onPress={handleLogout}>
        <Text style={styles.logoutText}>Wyloguj się</Text>
      </TouchableOpacity>

    </ScrollView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.gray50 },
  content: { padding: spacing.lg, gap: spacing.md, paddingBottom: spacing.xxl * 2 },
  card: { backgroundColor: colors.white, borderRadius: radius.lg, padding: spacing.lg },
  // Profil
  avatarRow: { flexDirection: 'row', alignItems: 'center', gap: spacing.lg, marginBottom: spacing.md },
  avatar: { width: 60, height: 60, borderRadius: 30, backgroundColor: colors.primary, alignItems: 'center', justifyContent: 'center' },
  avatarText: { color: colors.white, fontSize: 22, fontWeight: '700' },
  avatarInfo: { flex: 1 },
  fullName: { fontSize: 18, fontWeight: '700', color: colors.gray900 },
  username: { fontSize: 13, color: colors.gray400, marginTop: 2 },
  email: { fontSize: 14, color: colors.gray600, marginTop: 2 },
  badgeRow: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm, marginBottom: spacing.md, flexWrap: 'wrap' },
  roleBadge: { backgroundColor: colors.primaryLight, borderRadius: radius.sm, paddingHorizontal: spacing.sm, paddingVertical: 3 },
  planBadge: { backgroundColor: colors.successLight },
  roleBadgeText: { fontSize: 12, fontWeight: '600', color: colors.primary },
  validUntil: { fontSize: 12, color: colors.gray400 },
  editBtn: { borderWidth: 1, borderColor: colors.gray200, borderRadius: radius.sm, paddingVertical: spacing.sm, alignItems: 'center' },
  editBtnText: { fontSize: 14, fontWeight: '600', color: colors.gray700 },
  // Firma
  sectionHeader: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginBottom: spacing.md },
  sectionTitle: { fontSize: 16, fontWeight: '700', color: colors.gray900 },
  sectionAction: { fontSize: 14, fontWeight: '600', color: colors.primary },
  companyName: { fontSize: 15, fontWeight: '600', color: colors.gray900, marginBottom: 4 },
  companyDetail: { fontSize: 13, color: colors.gray500, marginBottom: 2 },
  // Rachunki
  emptyText: { fontSize: 14, color: colors.gray400, textAlign: 'center', paddingVertical: spacing.md },
  bankRow: { flexDirection: 'row', alignItems: 'flex-start', paddingVertical: spacing.sm, borderTopWidth: 1, borderTopColor: colors.gray100 },
  bankInfo: { flex: 1 },
  bankNameRow: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm, marginBottom: 2 },
  bankName: { fontSize: 14, fontWeight: '600', color: colors.gray900 },
  defaultBadge: { backgroundColor: colors.successLight, borderRadius: 99, paddingHorizontal: 6, paddingVertical: 1 },
  defaultBadgeText: { fontSize: 10, fontWeight: '700', color: colors.success },
  bankLabel: { fontSize: 12, color: colors.gray500, marginBottom: 2 },
  bankNrb: { fontSize: 12, color: colors.gray400, fontFamily: 'monospace' },
  bankActions: { gap: 4, alignItems: 'flex-end' },
  bankActionBtn: { paddingHorizontal: spacing.sm, paddingVertical: 4 },
  bankActionEdit: { fontSize: 13, color: colors.primary, fontWeight: '500' },
  bankActionDelete: { fontSize: 13, color: colors.danger, fontWeight: '500' },
  // Wyloguj
  logoutBtn: { backgroundColor: colors.dangerLight, borderRadius: radius.lg, padding: spacing.lg, alignItems: 'center' },
  logoutText: { color: colors.danger, fontWeight: '700', fontSize: 16 },
});
