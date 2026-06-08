import { apiClient } from './client';

export interface InvoiceFilters {
  seller_name?: string;
  seller_nip?: string;
  invoice_number?: string;
  status?: string | string[];
  issue_date_from?: string;
  issue_date_to?: string;
  page?: number;
}

export const getInvoices = (filters: InvoiceFilters = {}) => {
  const { status, ...rest } = filters;
  const params = new URLSearchParams();
  Object.entries(rest).forEach(([k, v]) => { if (v !== undefined) params.append(k, String(v)); });
  if (status) {
    (Array.isArray(status) ? status : [status]).forEach((s) => params.append('status', s));
  }
  return apiClient.get('/invoices/', { params }).then((r) => r.data);
};

export const getInvoice = (id: number) =>
  apiClient.get(`/invoices/${id}/`).then((r) => r.data);

export const changeInvoiceStatus = (id: number, status: string, note = '') =>
  apiClient.post(`/invoices/${id}/status/`, { status, note }).then((r) => r.data);

export const bulkChangeStatus = (ids: number[], status: string) =>
  apiClient.post('/invoices/bulk-status/', { ids, status }).then((r) => r.data);

export const updateInvoiceNote = (id: number, notes: string) =>
  apiClient.patch(`/invoices/${id}/notes/`, { notes }).then((r) => r.data);

export const getDashboard = () =>
  apiClient.get('/invoices/dashboard/').then((r) => r.data);
