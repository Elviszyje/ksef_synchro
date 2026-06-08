import { useState } from 'react';
import { View, Text, FlatList, TextInput, TouchableOpacity, RefreshControl, StyleSheet } from 'react-native';
import { useQuery } from '@tanstack/react-query';
import { getBuyers, searchBuyers } from '../../../src/api/outgoing';
import { LoadingSpinner } from '../../../src/components/common/LoadingSpinner';
import { EmptyState } from '../../../src/components/common/EmptyState';
import { colors, spacing, radius, shadow } from '../../../src/theme';
import type { Buyer } from '../../../src/types/api';

export default function BuyersScreen() {
  const [query, setQuery] = useState('');
  const [searched, setSearched] = useState(false);

  const allBuyers = useQuery({ queryKey: ['buyers'], queryFn: getBuyers });
  const searchResult = useQuery({
    queryKey: ['buyers-search', query],
    queryFn: () => searchBuyers(query),
    enabled: searched && query.length >= 2,
  });

  const isSearchActive = searched && query.length >= 2;
  const isLoading = isSearchActive ? searchResult.isLoading : allBuyers.isLoading;
  const isRefetching = isSearchActive ? searchResult.isRefetching : allBuyers.isRefetching;
  const rawData = isSearchActive ? searchResult.data : allBuyers.data;
  const buyers: Buyer[] = Array.isArray(rawData) ? rawData : rawData?.results ?? [];

  const handleSearch = () => setSearched(true);
  const handleClear = () => { setQuery(''); setSearched(false); };
  const handleRefresh = () => {
    allBuyers.refetch();
    if (isSearchActive) searchResult.refetch();
  };

  if (isLoading && !searched) return <LoadingSpinner />;

  return (
    <View style={styles.container}>
      <View style={styles.searchBar}>
        <TextInput
          style={styles.searchInput}
          value={query}
          onChangeText={(t) => { setQuery(t); if (!t) setSearched(false); }}
          placeholder="Szukaj po nazwie lub NIP…"
          placeholderTextColor={colors.gray400}
          onSubmitEditing={handleSearch}
          returnKeyType="search"
        />
        {query.length > 0 ? (
          <TouchableOpacity onPress={handleClear} style={styles.searchBtn}>
            <Text style={styles.searchBtnText}>✕</Text>
          </TouchableOpacity>
        ) : (
          <TouchableOpacity onPress={handleSearch} style={styles.searchBtn}>
            <Text style={styles.searchBtnText}>Szukaj</Text>
          </TouchableOpacity>
        )}
      </View>

      {isLoading && searched ? (
        <LoadingSpinner />
      ) : (
        <FlatList
          data={buyers}
          keyExtractor={(item) => String(item.id)}
          refreshControl={<RefreshControl refreshing={isRefetching} onRefresh={handleRefresh} />}
          contentContainerStyle={styles.list}
          ListEmptyComponent={
            <EmptyState message={searched ? `Brak wyników dla „${query}"` : 'Brak nabywców'} />
          }
          renderItem={({ item }) => (
            <View style={[styles.card, shadow.sm]}>
              <View style={styles.cardHeader}>
                <Text style={styles.name} numberOfLines={1}>{item.name}</Text>
                <Text style={styles.nip}>{item.nip}</Text>
              </View>
              {item.address ? <Text style={styles.address} numberOfLines={2}>{item.address}</Text> : null}
              <View style={styles.contacts}>
                {item.email ? <Text style={styles.contact}>✉ {item.email}</Text> : null}
                {item.phone ? <Text style={styles.contact}>✆ {item.phone}</Text> : null}
              </View>
            </View>
          )}
        />
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.gray50 },
  searchBar: { flexDirection: 'row', padding: spacing.lg, gap: spacing.sm, backgroundColor: colors.white, borderBottomWidth: 1, borderBottomColor: colors.gray200 },
  searchInput: { flex: 1, borderWidth: 1, borderColor: colors.gray200, borderRadius: radius.sm, paddingHorizontal: spacing.md, paddingVertical: spacing.sm, color: colors.gray900, fontSize: 15 },
  searchBtn: { backgroundColor: colors.primary, borderRadius: radius.sm, paddingHorizontal: spacing.md, justifyContent: 'center' },
  searchBtnText: { color: colors.white, fontSize: 14, fontWeight: '600' },
  list: { padding: spacing.lg, gap: spacing.sm },
  card: { backgroundColor: colors.white, borderRadius: radius.lg, padding: spacing.lg },
  cardHeader: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginBottom: 4 },
  name: { fontSize: 15, fontWeight: '600', color: colors.gray800, flex: 1 },
  nip: { fontSize: 13, color: colors.gray500, fontVariant: ['tabular-nums'] },
  address: { fontSize: 13, color: colors.gray500, marginBottom: 4 },
  contacts: { flexDirection: 'row', gap: spacing.lg, flexWrap: 'wrap' },
  contact: { fontSize: 12, color: colors.gray400 },
});
