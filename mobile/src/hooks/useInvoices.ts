import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  getInvoices, getInvoice, changeInvoiceStatus,
  bulkChangeStatus, getDashboard, updateInvoiceNote,
  InvoiceFilters,
} from '../api/invoices';

export const useInvoices = (filters: InvoiceFilters = {}) =>
  useQuery({ queryKey: ['invoices', filters], queryFn: () => getInvoices(filters) });

export const useInvoice = (id: number) =>
  useQuery({ queryKey: ['invoice', id], queryFn: () => getInvoice(id), enabled: id > 0 });

export const useDashboard = () =>
  useQuery({ queryKey: ['dashboard'], queryFn: getDashboard, staleTime: 60_000 });

export const useChangeStatus = () => {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: ({ id, status, note }: { id: number; status: string; note?: string }) =>
      changeInvoiceStatus(id, status, note),
    onSuccess: (_data, { id }) => {
      qc.invalidateQueries({ queryKey: ['invoice', id] });
      qc.invalidateQueries({ queryKey: ['invoices'] });
    },
  });
};

export const useBulkStatus = () => {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: ({ ids, status }: { ids: number[]; status: string }) => bulkChangeStatus(ids, status),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['invoices'] }),
  });
};

export const useUpdateNote = () => {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: ({ id, notes }: { id: number; notes: string }) => updateInvoiceNote(id, notes),
    onSuccess: (_data, { id }) => qc.invalidateQueries({ queryKey: ['invoice', id] }),
  });
};
