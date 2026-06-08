import { Stack } from 'expo-router';

export default function PaymentsLayout() {
  return (
    <Stack
      screenOptions={{
        headerStyle: { backgroundColor: '#ffffff' },
        headerTintColor: '#111827',
        headerTitleStyle: { fontWeight: '600' },
      }}
    >
      <Stack.Screen name="index" options={{ title: 'Przelewy' }} />
      <Stack.Screen name="history" options={{ title: 'Historia przelewów' }} />
      <Stack.Screen name="statements/index" options={{ title: 'Wyciągi bankowe' }} />
      <Stack.Screen name="statements/upload" options={{ title: 'Wgraj wyciąg MT940' }} />
      <Stack.Screen name="statements/[id]" options={{ title: 'Przegląd wyciągu' }} />
    </Stack>
  );
}
