import { File, Paths, DownloadTask } from 'expo-file-system';
import * as Sharing from 'expo-sharing';
import { apiClient } from './client';
import { useAuthStore } from '../store/auth';

const API_BASE_URL = process.env.EXPO_PUBLIC_API_URL ?? 'http://10.0.2.2:8080/api/v1';

export const getAcceptedInvoicesForPayment = () =>
  apiClient.get('/payments/accepted-invoices/').then((r) => r.data);

export const getPaymentFiles = () =>
  apiClient.get('/payments/').then((r) => r.data);

export const getBankAccounts = () =>
  apiClient.get('/payments/bank-accounts/').then((r) => r.data);

export const generatePaymentFile = (invoice_ids: number[], format: 'erste' | 'elixir' | 'mbank', debit_account?: string) =>
  apiClient.post('/payments/generate/', { invoice_ids, format, ...(debit_account ? { debit_account } : {}) }).then((r) => r.data);

export async function downloadAndSharePaymentFile(id: number, fileName: string) {
  const token = useAuthStore.getState().accessToken;
  const destination = new File(Paths.cache, fileName);
  const task = new DownloadTask(
    `${API_BASE_URL}/payments/${id}/download/`,
    destination,
    { headers: { Authorization: `Bearer ${token}` } },
  );
  const downloadedFile = await task.downloadAsync();
  const canShare = await Sharing.isAvailableAsync();
  if (canShare && downloadedFile) {
    await Sharing.shareAsync(downloadedFile.uri);
  }
}
