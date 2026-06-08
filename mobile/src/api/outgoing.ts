import { apiClient } from './client';

export const getOutgoing = (status?: string) =>
  apiClient.get('/outgoing/', { params: status ? { status } : undefined }).then((r) => r.data);

export const getOutgoingInvoice = (id: number) =>
  apiClient.get(`/outgoing/${id}/`).then((r) => r.data);

export const createOutgoing = (data: object) =>
  apiClient.post('/outgoing/new/', data).then((r) => r.data);

export const updateOutgoing = (id: number, data: object) =>
  apiClient.patch(`/outgoing/${id}/edit/`, data).then((r) => r.data);

export const queueOutgoing = (id: number) =>
  apiClient.post(`/outgoing/${id}/queue/`).then((r) => r.data);

export const getBuyers = () =>
  apiClient.get('/outgoing/buyers/').then((r) => r.data);

export const searchBuyers = (q: string) =>
  apiClient.get('/outgoing/buyers/search/', { params: { q } }).then((r) => r.data);

export const nipLookup = (nip: string) =>
  apiClient.get('/outgoing/nip-lookup/', { params: { nip } }).then((r) => r.data);

export const bulkQueueOutgoing = (invoice_ids: number[]) =>
  apiClient.post('/outgoing/bulk-queue/', { invoice_ids }).then((r) => r.data);
