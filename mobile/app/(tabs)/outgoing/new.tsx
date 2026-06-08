import { useState } from 'react';
import {
  ScrollView, View, Text, TextInput, TouchableOpacity,
  Alert, Modal, FlatList, ActivityIndicator, Switch, StyleSheet,
} from 'react-native';
import { useRouter } from 'expo-router';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { createOutgoing, searchBuyers, nipLookup } from '../../../src/api/outgoing';
import { colors, spacing, radius, shadow } from '../../../src/theme';
import type { Buyer, NipLookupResult } from '../../../src/types/api';

interface ItemForm { name: string; quantity: string; unit: string; unit_price_net: string; vat_rate: string; }
const VAT_RATES = ['23', '8', '5', '0', 'zw', 'np'];

export default function NewOutgoingScreen() {
  const router = useRouter();
  const qc = useQueryClient();

  // Dane faktury
  const [invoiceNumber, setInvoiceNumber] = useState('');
  const [issueDate, setIssueDate] = useState('');
  const [dueDate, setDueDate] = useState('');

  // Nabywca
  const [buyerId, setBuyerId] = useState<number | null>(null);
  const [buyerNip, setBuyerNip] = useState('');
  const [buyerName, setBuyerName] = useState('');
  const [buyerAddress, setBuyerAddress] = useState('');
  const [saveBuyer, setSaveBuyer] = useState(false);
  const [vatStatus, setVatStatus] = useState('');

  // Wyszukiwarka nabywców
  const [searchQuery, setSearchQuery] = useState('');
  const [searchResults, setSearchResults] = useState<Buyer[]>([]);
  const [searchLoading, setSearchLoading] = useState(false);
  const [searchModalVisible, setSearchModalVisible] = useState(false);

  // NIP lookup
  const [nipLookupLoading, setNipLookupLoading] = useState(false);

  // Pozycje
  const [items, setItems] = useState<ItemForm[]>([
    { name: '', quantity: '1', unit: 'szt.', unit_price_net: '', vat_rate: '23' },
  ]);

  const addItem = () =>
    setItems((prev) => [...prev, { name: '', quantity: '1', unit: 'szt.', unit_price_net: '', vat_rate: '23' }]);
  const updateItem = (index: number, field: keyof ItemForm, value: string) =>
    setItems((prev) => prev.map((it, i) => (i === index ? { ...it, [field]: value } : it)));

  const handleSearch = async () => {
    const q = searchQuery.trim();
    if (q.length < 2) { Alert.alert('', 'Wpisz co najmniej 2 znaki.'); return; }
    setSearchLoading(true);
    try {
      const results = await searchBuyers(q);
      setSearchResults(Array.isArray(results) ? results : results?.results ?? []);
      setSearchModalVisible(true);
    } catch {
      Alert.alert('Błąd', 'Nie udało się wyszukać nabywców.');
    } finally {
      setSearchLoading(false);
    }
  };

  const selectBuyer = (buyer: Buyer) => {
    setBuyerId(buyer.id);
    setBuyerNip(buyer.nip);
    setBuyerName(buyer.name);
    setBuyerAddress(buyer.address);
    setSearchModalVisible(false);
    setSearchQuery('');
  };

  const clearBuyer = () => {
    setBuyerId(null);
    setBuyerNip('');
    setBuyerName('');
    setBuyerAddress('');
    setVatStatus('');
    setSaveBuyer(false);
  };

  const handleNipLookup = async () => {
    const nip = buyerNip.replace(/[\s\-]/g, '');
    if (nip.length !== 10) { Alert.alert('', 'Wpisz poprawny 10-cyfrowy NIP.'); return; }
    setNipLookupLoading(true);
    try {
      const data: NipLookupResult = await nipLookup(nip);
      if (data.name) setBuyerName(data.name);
      if (data.address) setBuyerAddress(data.address);
      if (data.status_vat) setVatStatus(data.status_vat);
    } catch (e: any) {
      Alert.alert('Błąd', e?.response?.data?.error ?? 'Nie znaleziono firmy o podanym NIP.');
    } finally {
      setNipLookupLoading(false);
    }
  };

  const create = useMutation({
    mutationFn: () =>
      createOutgoing({
        invoice_number: invoiceNumber,
        issue_date: issueDate,
        payment_due_date: dueDate,
        buyer_nip: buyerNip,
        buyer_name: buyerName,
        buyer_address: buyerAddress,
        payment_form: 'przelew',
        currency: 'PLN',
        items: items.map((it, i) => ({ lp: i + 1, ...it })),
        ...(buyerId ? { buyer_id: buyerId } : {}),
        ...(saveBuyer && !buyerId ? { save_buyer: true } : {}),
      }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['outgoing'] });
      router.back();
    },
    onError: (e: any) =>
      Alert.alert(
        'Błąd',
        e?.response?.data?.invoice_number?.[0] ?? e?.response?.data?.detail ?? 'Błąd tworzenia faktury.',
      ),
  });

  return (
    <ScrollView style={styles.container}>
      <View style={styles.content}>

        {/* Dane faktury */}
        <View style={[styles.section, shadow.sm]}>
          <Text style={styles.sectionTitle}>Dane faktury</Text>
          {([
            ['Numer faktury', invoiceNumber, setInvoiceNumber, false],
            ['Data wystawienia (RRRR-MM-DD)', issueDate, setIssueDate, false],
            ['Termin płatności (RRRR-MM-DD)', dueDate, setDueDate, false],
          ] as [string, string, (v: string) => void, boolean][]).map(([label, value, setter]) => (
            <View key={label} style={styles.fieldGroup}>
              <Text style={styles.fieldLabel}>{label}</Text>
              <TextInput
                style={styles.input}
                value={value}
                onChangeText={setter}
                placeholderTextColor={colors.gray400}
                placeholder={label}
              />
            </View>
          ))}
        </View>

        {/* Nabywca */}
        <View style={[styles.section, shadow.sm]}>
          <Text style={styles.sectionTitle}>Nabywca</Text>

          {/* Wyszukiwarka */}
          <View style={styles.fieldGroup}>
            <Text style={styles.fieldLabel}>Wyszukaj z listy nabywców</Text>
            <View style={styles.row}>
              <TextInput
                style={[styles.input, { flex: 1, marginBottom: 0 }]}
                value={searchQuery}
                onChangeText={setSearchQuery}
                placeholder="Wpisz nazwę lub NIP…"
                placeholderTextColor={colors.gray400}
                onSubmitEditing={handleSearch}
              />
              <TouchableOpacity onPress={handleSearch} disabled={searchLoading} style={styles.actionBtn}>
                {searchLoading
                  ? <ActivityIndicator size="small" color={colors.white} />
                  : <Text style={styles.actionBtnText}>Szukaj</Text>}
              </TouchableOpacity>
            </View>
          </View>

          {buyerId !== null && (
            <View style={styles.selectedBuyerBanner}>
              <Text style={styles.selectedBuyerText}>✓ Wybrany nabywca: {buyerName}</Text>
              <TouchableOpacity onPress={clearBuyer}>
                <Text style={styles.clearBuyerText}>Wyczyść</Text>
              </TouchableOpacity>
            </View>
          )}

          {/* NIP z lookupem */}
          <View style={styles.fieldGroup}>
            <Text style={styles.fieldLabel}>NIP nabywcy *</Text>
            <View style={styles.row}>
              <TextInput
                style={[styles.input, { flex: 1, marginBottom: 0 }]}
                value={buyerNip}
                onChangeText={(t) => { setBuyerNip(t); setBuyerId(null); }}
                placeholder="0000000000"
                placeholderTextColor={colors.gray400}
                keyboardType="numeric"
                maxLength={10}
              />
              <TouchableOpacity onPress={handleNipLookup} disabled={nipLookupLoading} style={styles.actionBtn}>
                {nipLookupLoading
                  ? <ActivityIndicator size="small" color={colors.white} />
                  : <Text style={styles.actionBtnText}>Pobierz z GUS</Text>}
              </TouchableOpacity>
            </View>
            {vatStatus !== '' && (
              <Text style={styles.vatStatusText}>Status VAT: {vatStatus}</Text>
            )}
          </View>

          {/* Nazwa i adres */}
          <View style={styles.fieldGroup}>
            <Text style={styles.fieldLabel}>Nazwa nabywcy *</Text>
            <TextInput style={styles.input} value={buyerName} onChangeText={setBuyerName} placeholder="Nazwa firmy" placeholderTextColor={colors.gray400} />
          </View>
          <View style={styles.fieldGroup}>
            <Text style={styles.fieldLabel}>Adres nabywcy *</Text>
            <TextInput
              style={[styles.input, styles.textArea]}
              value={buyerAddress}
              onChangeText={setBuyerAddress}
              placeholder="ul. Przykładowa 1, 00-000 Miasto"
              placeholderTextColor={colors.gray400}
              multiline
              numberOfLines={2}
            />
          </View>

          {/* Zapisz nabywcę */}
          {buyerId === null && (
            <View style={styles.switchRow}>
              <Switch value={saveBuyer} onValueChange={setSaveBuyer} trackColor={{ true: colors.primary }} />
              <Text style={styles.switchLabel}>Zapisz do listy nabywców</Text>
            </View>
          )}
        </View>

        {/* Pozycje */}
        <View style={[styles.section, shadow.sm]}>
          <Text style={styles.sectionTitle}>Pozycje</Text>
          {items.map((item, index) => (
            <View key={index} style={styles.itemSection}>
              <Text style={styles.itemLabel}>Poz. {index + 1}</Text>
              <TextInput style={styles.input} placeholder="Nazwa towaru/usługi" placeholderTextColor={colors.gray400} value={item.name} onChangeText={(t) => updateItem(index, 'name', t)} />
              <View style={styles.row}>
                <TextInput style={[styles.input, styles.halfInput]} placeholder="Ilość" placeholderTextColor={colors.gray400} value={item.quantity} onChangeText={(t) => updateItem(index, 'quantity', t)} keyboardType="numeric" />
                <TextInput style={[styles.input, styles.halfInput]} placeholder="Jednostka" placeholderTextColor={colors.gray400} value={item.unit} onChangeText={(t) => updateItem(index, 'unit', t)} />
              </View>
              <TextInput style={styles.input} placeholder="Cena jedn. netto" placeholderTextColor={colors.gray400} value={item.unit_price_net} onChangeText={(t) => updateItem(index, 'unit_price_net', t)} keyboardType="numeric" />
              <View style={styles.vatRow}>
                {VAT_RATES.map((r) => (
                  <TouchableOpacity key={r} onPress={() => updateItem(index, 'vat_rate', r)} style={[styles.vatChip, item.vat_rate === r && styles.vatChipActive]}>
                    <Text style={[styles.vatChipText, item.vat_rate === r && styles.vatChipTextActive]}>{r === 'zw' ? 'ZW' : r === 'np' ? 'NP' : `${r}%`}</Text>
                  </TouchableOpacity>
                ))}
              </View>
            </View>
          ))}
          <TouchableOpacity onPress={addItem} style={styles.addItemBtn}>
            <Text style={styles.addItemText}>+ Dodaj pozycję</Text>
          </TouchableOpacity>
        </View>

        <TouchableOpacity onPress={() => create.mutate()} disabled={create.isPending} style={[styles.submitBtn, create.isPending && styles.submitBtnDisabled]}>
          <Text style={styles.submitBtnText}>{create.isPending ? 'Tworzenie...' : 'Utwórz fakturę'}</Text>
        </TouchableOpacity>
      </View>

      {/* Modal wyszukiwania nabywców */}
      <Modal visible={searchModalVisible} animationType="slide" onRequestClose={() => setSearchModalVisible(false)}>
        <View style={styles.modalContainer}>
          <View style={styles.modalHeader}>
            <Text style={styles.modalTitle}>Wybierz nabywcę</Text>
            <TouchableOpacity onPress={() => setSearchModalVisible(false)}>
              <Text style={styles.modalClose}>Zamknij</Text>
            </TouchableOpacity>
          </View>
          <FlatList
            data={searchResults}
            keyExtractor={(item) => String(item.id)}
            contentContainerStyle={{ padding: spacing.lg, gap: spacing.sm }}
            ListEmptyComponent={<Text style={styles.noResults}>Brak wyników.</Text>}
            renderItem={({ item }) => (
              <TouchableOpacity onPress={() => selectBuyer(item)} style={[styles.resultItem, shadow.sm]}>
                <Text style={styles.resultName}>{item.name}</Text>
                <Text style={styles.resultNip}>NIP: {item.nip}</Text>
                {item.address ? <Text style={styles.resultAddress} numberOfLines={1}>{item.address}</Text> : null}
              </TouchableOpacity>
            )}
          />
        </View>
      </Modal>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.gray50 },
  content: { padding: spacing.lg, gap: spacing.lg },
  section: { backgroundColor: colors.white, borderRadius: radius.lg, padding: spacing.lg },
  sectionTitle: { fontSize: 16, fontWeight: '600', color: colors.gray800, marginBottom: spacing.md },
  fieldGroup: { marginBottom: spacing.md },
  fieldLabel: { fontSize: 14, color: colors.gray600, marginBottom: 4 },
  input: { borderWidth: 1, borderColor: colors.gray200, borderRadius: radius.sm, paddingHorizontal: spacing.md, paddingVertical: spacing.sm, color: colors.gray900, fontSize: 16, marginBottom: spacing.sm },
  textArea: { minHeight: 60, textAlignVertical: 'top' },
  row: { flexDirection: 'row', gap: spacing.sm, alignItems: 'center' },
  halfInput: { flex: 1 },
  actionBtn: { backgroundColor: colors.primary, borderRadius: radius.sm, paddingHorizontal: spacing.md, paddingVertical: 10, justifyContent: 'center' },
  actionBtnText: { color: colors.white, fontSize: 13, fontWeight: '600' },
  selectedBuyerBanner: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', backgroundColor: colors.successLight, borderRadius: radius.sm, padding: spacing.sm, marginBottom: spacing.md },
  selectedBuyerText: { fontSize: 13, color: colors.success, flex: 1 },
  clearBuyerText: { fontSize: 13, color: colors.danger ?? '#dc2626', fontWeight: '500' },
  vatStatusText: { fontSize: 12, color: colors.success, marginTop: 2 },
  switchRow: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm, marginTop: spacing.sm },
  switchLabel: { fontSize: 14, color: colors.gray700 },
  itemSection: { marginBottom: spacing.lg, paddingBottom: spacing.lg, borderBottomWidth: 1, borderBottomColor: colors.gray100 },
  itemLabel: { fontSize: 14, fontWeight: '600', color: colors.gray600, marginBottom: spacing.sm },
  vatRow: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.sm, marginTop: 4 },
  vatChip: { paddingHorizontal: spacing.md, paddingVertical: 4, borderRadius: 999, borderWidth: 1, borderColor: colors.gray200 },
  vatChipActive: { backgroundColor: colors.primary, borderColor: colors.primary },
  vatChipText: { fontSize: 13, color: colors.gray600 },
  vatChipTextActive: { color: colors.white, fontWeight: '500' },
  addItemBtn: { borderWidth: 2, borderStyle: 'dashed', borderColor: colors.gray300, borderRadius: radius.md, paddingVertical: spacing.md, alignItems: 'center' },
  addItemText: { color: colors.gray400, fontSize: 15 },
  submitBtn: { backgroundColor: colors.primary, borderRadius: radius.lg, paddingVertical: spacing.lg, alignItems: 'center' },
  submitBtnDisabled: { backgroundColor: colors.gray300 },
  submitBtnText: { color: colors.white, fontWeight: '700', fontSize: 16 },
  // Modal
  modalContainer: { flex: 1, backgroundColor: colors.gray50 },
  modalHeader: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', padding: spacing.lg, borderBottomWidth: 1, borderBottomColor: colors.gray200, backgroundColor: colors.white },
  modalTitle: { fontSize: 17, fontWeight: '600', color: colors.gray800 },
  modalClose: { fontSize: 15, color: colors.primary },
  noResults: { textAlign: 'center', color: colors.gray500, marginTop: spacing.xl ?? 32 },
  resultItem: { backgroundColor: colors.white, borderRadius: radius.lg, padding: spacing.lg },
  resultName: { fontSize: 15, fontWeight: '600', color: colors.gray800 },
  resultNip: { fontSize: 13, color: colors.gray500, marginTop: 2 },
  resultAddress: { fontSize: 12, color: colors.gray400, marginTop: 2 },
});
