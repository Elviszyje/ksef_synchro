import { apiClient } from './client';

export const getBankStatements = () =>
  apiClient.get('/bank-statements/').then((r) => r.data);

export const uploadBankStatement = (file: { uri: string; name: string; mimeType: string }) => {
  const formData = new FormData();
  formData.append('mt940_file', { uri: file.uri, name: file.name, type: file.mimeType } as any);
  return apiClient
    .post('/bank-statements/', formData, { headers: { 'Content-Type': 'multipart/form-data' } })
    .then((r) => r.data);
};

export const getBankStatement = (id: number) =>
  apiClient.get(`/bank-statements/${id}/`).then((r) => r.data);

export const runMatcher = (id: number) =>
  apiClient.post(`/bank-statements/${id}/run-matcher/`).then((r) => r.data);

export const toggleMatch = (stmtId: number, matchId: number) =>
  apiClient.post(`/bank-statements/${stmtId}/matches/${matchId}/toggle/`).then((r) => r.data);

export const confirmStatement = (id: number) =>
  apiClient.post(`/bank-statements/${id}/confirm/`).then((r) => r.data);
