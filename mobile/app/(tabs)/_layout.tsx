import { Tabs } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';

type IoniconsName = React.ComponentProps<typeof Ionicons>['name'];

function tabIcon(name: IoniconsName, nameFocused: IoniconsName) {
  return ({ focused, color }: { focused: boolean; color: string }) => (
    <Ionicons name={focused ? nameFocused : name} size={24} color={color} />
  );
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
        options={{
          title: 'Dashboard',
          tabBarLabel: 'Dashboard',
          tabBarIcon: tabIcon('home-outline', 'home'),
        }}
      />
      <Tabs.Screen
        name="invoices"
        options={{
          title: 'Faktury',
          tabBarLabel: 'Faktury',
          headerShown: false,
          tabBarIcon: tabIcon('document-text-outline', 'document-text'),
        }}
      />
      <Tabs.Screen
        name="outgoing"
        options={{
          title: 'Wychodzące',
          tabBarLabel: 'Wychodzące',
          headerShown: false,
          tabBarIcon: tabIcon('paper-plane-outline', 'paper-plane'),
        }}
      />
      <Tabs.Screen
        name="payments"
        options={{
          title: 'Przelewy',
          tabBarLabel: 'Przelewy',
          headerShown: false,
          tabBarIcon: tabIcon('card-outline', 'card'),
        }}
      />
      <Tabs.Screen
        name="account"
        options={{
          title: 'Konto',
          tabBarLabel: 'Konto',
          headerShown: false,
          tabBarIcon: tabIcon('person-circle-outline', 'person-circle'),
        }}
      />
    </Tabs>
  );
}
