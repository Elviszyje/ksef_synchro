import { Stack } from 'expo-router';

export default function OutgoingLayout() {
  return (
    <Stack
      screenOptions={{
        headerStyle: { backgroundColor: '#ffffff' },
        headerTintColor: '#111827',
        headerTitleStyle: { fontWeight: '600' },
      }}
    >
      <Stack.Screen name="index" options={{ title: 'Faktury wychodzące' }} />
      <Stack.Screen name="[id]" options={{ title: 'Szczegóły' }} />
      <Stack.Screen name="new" options={{ title: 'Nowa faktura' }} />
      <Stack.Screen name="buyers" options={{ title: 'Nabywcy' }} />
    </Stack>
  );
}
