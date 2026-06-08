import axios from 'axios';
import * as SecureStore from 'expo-secure-store';
import { apiClient } from './client';
import { useAuthStore } from '../store/auth';

const API_BASE_URL = process.env.EXPO_PUBLIC_API_URL ?? 'http://10.0.2.2:8080/api/v1';

export async function login(username: string, password: string) {
  const { data } = await apiClient.post('/auth/login/', { username, password });
  await SecureStore.setItemAsync('refresh_token', data.refresh);
  useAuthStore.getState().setAccessToken(data.access);
  useAuthStore.getState().setUser(data.user);
  return data;
}

export async function logout() {
  const refreshToken = await SecureStore.getItemAsync('refresh_token');
  if (refreshToken) {
    try {
      await apiClient.post('/auth/logout/', { refresh: refreshToken });
    } catch {}
  }
  useAuthStore.getState().logout();
}

export async function refreshTokens(): Promise<string | null> {
  const refreshToken = await SecureStore.getItemAsync('refresh_token');
  if (!refreshToken) return null;
  const { data } = await axios.post(`${API_BASE_URL}/auth/refresh/`, { refresh: refreshToken });
  await SecureStore.setItemAsync('refresh_token', data.refresh ?? refreshToken);
  useAuthStore.getState().setAccessToken(data.access);
  return data.access;
}

export async function getMe() {
  const { data } = await apiClient.get('/auth/me/');
  return data;
}
