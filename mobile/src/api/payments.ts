import * as FileSystem from 'expo-file-system';
import * as Sharing from 'expo-sharing';
import { apiClient } from './client';

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
  const response = await apiClient.get(`/payments/${id}/download/`, { responseType: 'arraybuffer' });
  const base64 = btoa(
    new Uint8Array(response.data).reduce((acc, byte) => acc + String.fromCharCode(byte), ''),
  );
  const fileUri = (FileSystem.cacheDirectory ?? '') + fileName;
  await FileSystem.writeAsStringAsync(fileUri, base64, { encoding: 'base64' as any });
  const canShare = await Sharing.isAvailableAsync();
  if (canShare) {
    await Sharing.shareAsync(fileUri, {
      mimeType: 'application/octet-stream',
      UTI: 'public.data',
      dialogTitle: fileName,
    });
  }
}
