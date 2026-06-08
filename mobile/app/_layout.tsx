import { useEffect, useState } from 'react';
import { Slot, useRouter, useSegments } from 'expo-router';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import * as SecureStore from 'expo-secure-store';
import { useAuthStore } from '../src/store/auth';
import { refreshTokens, getMe } from '../src/api/auth';

const queryClient = new QueryClient({
  defaultOptions: { queries: { staleTime: 30_000, retry: 1 } },
});

function AuthGuard() {
  const { isAuthenticated, setUser, logout } = useAuthStore();
  const router = useRouter();
  const segments = useSegments();
  const [mounted, setMounted] = useState(false);

  useEffect(() => {
    setMounted(true);
    (async () => {
      const refresh = await SecureStore.getItemAsync('refresh_token');
      if (refresh) {
        try {
          await refreshTokens();
          const me = await getMe();
          setUser(me);
        } catch {
          await logout();
        }
      }
    })();
  }, []);

  useEffect(() => {
    if (!mounted) return;
    const inAuthGroup = segments[0] === '(auth)';
    if (!isAuthenticated && !inAuthGroup) {
      router.replace('/(auth)/login');
    } else if (isAuthenticated && inAuthGroup) {
      router.replace('/(tabs)');
    }
  }, [mounted, isAuthenticated, segments]);

  return <Slot />;
}

export default function RootLayout() {
  return (
    <QueryClientProvider client={queryClient}>
      <AuthGuard />
    </QueryClientProvider>
  );
}
