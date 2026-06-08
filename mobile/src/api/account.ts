import { apiClient } from './client';

export const getCompany = () =>
  apiClient.get('/auth/company/').then((r) => r.data);

export const updateCompany = (data: { name?: string; address?: string }) =>
  apiClient.patch('/auth/company/', data).then((r) => r.data);

export const updateProfile = (data: {
  first_name?: string;
  last_name?: string;
  email?: string;
  password?: string;
}) => apiClient.patch('/auth/me/', data).then((r) => r.data);

export const createBankAccount = (data: {
  account_number: string;
  label?: string;
  is_default?: boolean;
}) => apiClient.post('/payments/bank-accounts/', data).then((r) => r.data);

export const updateBankAccount = (
  id: number,
  data: { account_number?: string; label?: string; is_default?: boolean },
) => apiClient.patch(`/payments/bank-accounts/${id}/`, data).then((r) => r.data);

export const deleteBankAccount = (id: number) =>
  apiClient.delete(`/payments/bank-accounts/${id}/`).then((r) => r.data);
