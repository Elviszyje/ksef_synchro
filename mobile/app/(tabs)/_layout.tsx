import { Tabs } from 'expo-router';
import { useColorScheme } from 'react-native';

function TabIcon({ focused, color }: { focused: boolean; color: string }) {
  return null;
}

export default function TabsLayout() {
  return (
    <Tabs
      screenOptions={{
        headerShown: true,
        tabBarActiveTintColor: '#2563eb',
        tabBarInactiveTintColor: '#6b7280',
        tabBarStyle: { backgroundColor: '#ffffff', borderTopColor: '#e5e7eb' },
        headerStyle: { backgroundColor: '#ffffff' },
        headerTintColor: '#111827',
        headerTitleStyle: { fontWeight: '600' },
      }}
    >
      <Tabs.Screen
        name="index"
        options={{ title: 'Dashboard', tabBarLabel: 'Dashboard' }}
      />
      <Tabs.Screen
        name="invoices"
        options={{ title: 'Faktury', tabBarLabel: 'Faktury', headerShown: false }}
      />
      <Tabs.Screen
        name="outgoing"
        options={{ title: 'Wychodzące', tabBarLabel: 'Wychodzące', headerShown: false }}
      />
      <Tabs.Screen
        name="payments"
        options={{ title: 'Przelewy', tabBarLabel: 'Przelewy', headerShown: false }}
      />
    </Tabs>
  );
}
