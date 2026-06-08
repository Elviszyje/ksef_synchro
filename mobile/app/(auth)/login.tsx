import { useState } from 'react';
import { View, Text, TextInput, TouchableOpacity, ActivityIndicator, KeyboardAvoidingView, Platform, StyleSheet } from 'react-native';
import { login } from '../../src/api/auth';
import { colors, spacing, radius } from '../../src/theme';

export default function LoginScreen() {
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);

  const handleLogin = async () => {
    if (!username || !password) { setError('Podaj login i hasło.'); return; }
    setError('');
    setLoading(true);
    try {
      await login(username, password);
    } catch (e: any) {
      setError(e?.response?.data?.non_field_errors?.[0] ?? 'Błąd logowania. Spróbuj ponownie.');
    } finally {
      setLoading(false);
    }
  };

  return (
    <KeyboardAvoidingView behavior={Platform.OS === 'ios' ? 'padding' : 'height'} style={styles.container}>
      <View style={styles.inner}>
        <View style={styles.maxWidth}>
          <Text style={styles.logo}>KSeF</Text>
          <Text style={styles.subtitle}>Faktury kosztowe</Text>

          <View style={styles.card}>
            <Text style={styles.label}>Login</Text>
            <TextInput
              style={styles.input}
              value={username}
              onChangeText={setUsername}
              autoCapitalize="none"
              autoCorrect={false}
              returnKeyType="next"
              placeholder="Nazwa użytkownika"
              placeholderTextColor={colors.gray400}
            />
            <Text style={styles.label}>Hasło</Text>
            <TextInput
              style={styles.input}
              value={password}
              onChangeText={setPassword}
              secureTextEntry
              returnKeyType="done"
              onSubmitEditing={handleLogin}
              placeholder="Hasło"
              placeholderTextColor={colors.gray400}
            />
            {error ? <Text style={styles.error}>{error}</Text> : null}
            <TouchableOpacity
              onPress={handleLogin}
              disabled={loading}
              style={[styles.button, loading && styles.buttonDisabled]}
            >
              {loading
                ? <ActivityIndicator color={colors.white} />
                : <Text style={styles.buttonText}>Zaloguj się</Text>
              }
            </TouchableOpacity>
          </View>
        </View>
      </View>
    </KeyboardAvoidingView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.gray50 },
  inner: { flex: 1, alignItems: 'center', justifyContent: 'center', paddingHorizontal: spacing.xl },
  maxWidth: { width: '100%', maxWidth: 400 },
  logo: { fontSize: 32, fontWeight: '700', color: colors.primary, textAlign: 'center', marginBottom: 4 },
  subtitle: { color: colors.gray500, textAlign: 'center', marginBottom: 32, fontSize: 16 },
  card: { backgroundColor: colors.white, borderRadius: radius.lg, padding: spacing.xl, shadowColor: '#000', shadowOffset: { width: 0, height: 1 }, shadowOpacity: 0.08, shadowRadius: 4, elevation: 2 },
  label: { fontSize: 14, fontWeight: '500', color: colors.gray700, marginBottom: 4 },
  input: { borderWidth: 1, borderColor: colors.gray300, borderRadius: radius.md, paddingHorizontal: spacing.lg, paddingVertical: spacing.md, color: colors.gray900, marginBottom: spacing.lg, fontSize: 16 },
  error: { color: colors.danger, fontSize: 14, textAlign: 'center', marginBottom: spacing.md },
  button: { backgroundColor: colors.primary, borderRadius: radius.md, paddingVertical: spacing.lg, alignItems: 'center' },
  buttonDisabled: { backgroundColor: '#93c5fd' },
  buttonText: { color: colors.white, fontWeight: '700', fontSize: 16 },
});
