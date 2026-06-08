import { Stack } from 'expo-router';

export default function InvoicesLayout() {
  return (
    <Stack
      screenOptions={{
        headerStyle: { backgroundColor: '#ffffff' },
        headerTintColor: '#111827',
        headerTitleStyle: { fontWeight: '600' },
      }}
    >
      <Stack.Screen name="index" options={{ title: 'Faktury kosztowe' }} />
      <Stack.Screen name="[id]" options={{ title: 'Szczegóły faktury' }} />
    </Stack>
  );
}
