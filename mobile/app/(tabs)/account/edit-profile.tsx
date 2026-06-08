import { useState } from 'react';
import { View, Text, TextInput, TouchableOpacity, ScrollView, Alert, StyleSheet, ActivityIndicator } from 'react-native';
import { useRouter } from 'expo-router';
import { useMutation } from '@tanstack/react-query';
import { useAuthStore } from '../../../src/store/auth';
import { updateProfile } from '../../../src/api/account';
import { getMe } from '../../../src/api/auth';
import { colors, spacing, radius } from '../../../src/theme';

export default function EditProfileScreen() {
  const router = useRouter();
  const { user, setUser } = useAuthStore();

  const [firstName, setFirstName] = useState(user?.first_name ?? '');
  const [lastName, setLastName] = useState(user?.last_name ?? '');
  const [email, setEmail] = useState(user?.email ?? '');
  const [password, setPassword] = useState('');

  const mutation = useMutation({
    mutationFn: updateProfile,
    onSuccess: async () => {
      const me = await getMe();
      setUser(me);
      Alert.alert('Zapisano', 'Profil został zaktualizowany.');
      router.back();
    },
    onError: (e: any) => {
      const detail = e?.response?.data?.detail
        ?? Object.values(e?.response?.data ?? {})[0]
        ?? 'Nie udało się zaktualizować profilu.';
      Alert.alert('Błąd', String(detail));
    },
  });

  const handleSave = () => {
    const data: Record<string, string> = {};
    if (firstName !== user?.first_name) data.first_name = firstName;
    if (lastName !== user?.last_name) data.last_name = lastName;
    if (email !== user?.email) data.email = email;
    if (password) data.password = password;
    if (Object.keys(data).length === 0) { router.back(); return; }
    mutation.mutate(data);
  };

  return (
    <ScrollView style={styles.container} contentContainerStyle={styles.content} keyboardShouldPersistTaps="handled">
      <View style={styles.field}>
        <Text style={styles.label}>Imię</Text>
        <TextInput style={styles.input} value={firstName} onChangeText={setFirstName} placeholder="Imię" autoCorrect={false} />
      </View>
      <View style={styles.field}>
        <Text style={styles.label}>Nazwisko</Text>
        <TextInput style={styles.input} value={lastName} onChangeText={setLastName} placeholder="Nazwisko" autoCorrect={false} />
      </View>
      <View style={styles.field}>
        <Text style={styles.label}>Email</Text>
        <TextInput style={styles.input} value={email} onChangeText={setEmail} placeholder="email@firma.pl" keyboardType="email-address" autoCapitalize="none" autoCorrect={false} />
      </View>
      <View style={styles.field}>
        <Text style={styles.label}>Nowe hasło <Text style={styles.optional}>(opcjonalne)</Text></Text>
        <TextInput style={styles.input} value={password} onChangeText={setPassword} placeholder="Min. 8 znaków" secureTextEntry autoCorrect={false} />
      </View>

      <TouchableOpacity
        style={[styles.saveBtn, mutation.isPending && styles.saveBtnDisabled]}
        onPress={handleSave}
        disabled={mutation.isPending}
      >
        {mutation.isPending
          ? <ActivityIndicator color={colors.white} />
          : <Text style={styles.saveBtnText}>Zapisz zmiany</Text>}
      </TouchableOpacity>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.gray50 },
  content: { padding: spacing.lg, gap: spacing.md },
  field: { gap: spacing.xs },
  label: { fontSize: 14, fontWeight: '600', color: colors.gray700 },
  optional: { fontWeight: '400', color: colors.gray400 },
  input: { backgroundColor: colors.white, borderWidth: 1, borderColor: colors.gray200, borderRadius: radius.sm, paddingHorizontal: spacing.md, paddingVertical: spacing.sm, fontSize: 15, color: colors.gray900 },
  saveBtn: { backgroundColor: colors.primary, borderRadius: radius.lg, padding: spacing.lg, alignItems: 'center', marginTop: spacing.md },
  saveBtnDisabled: { backgroundColor: colors.gray300 },
  saveBtnText: { color: colors.white, fontWeight: '700', fontSize: 16 },
});
