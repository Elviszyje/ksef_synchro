import { Stack } from 'expo-router';

export default function AccountLayout() {
  return (
    <Stack
      screenOptions={{
        headerStyle: { backgroundColor: '#ffffff' },
        headerTintColor: '#111827',
        headerTitleStyle: { fontWeight: '600' },
      }}
    >
      <Stack.Screen name="index" options={{ title: 'Konto' }} />
      <Stack.Screen name="edit-profile" options={{ title: 'Edytuj profil' }} />
      <Stack.Screen name="company" options={{ title: 'Dane firmy' }} />
      <Stack.Screen name="bank-account" options={{ title: 'Rachunek bankowy' }} />
    </Stack>
  );
}
