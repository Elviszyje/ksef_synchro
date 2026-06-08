import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  getAcceptedInvoicesForPayment, getPaymentFiles,
  generatePaymentFile, downloadAndSharePaymentFile, getBankAccounts,
} from '../api/payments';

export const useAcceptedForPayment = () =>
  useQuery({ queryKey: ['accepted-for-payment'], queryFn: getAcceptedInvoicesForPayment });

export const usePaymentFiles = () =>
  useQuery({ queryKey: ['payment-files'], queryFn: getPaymentFiles });

export const useBankAccounts = () =>
  useQuery({ queryKey: ['bank-accounts'], queryFn: getBankAccounts });

export const useGeneratePaymentFile = () => {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: ({ invoice_ids, format, debit_account }: { invoice_ids: number[]; format: 'erste' | 'elixir' | 'mbank'; debit_account?: string }) =>
      generatePaymentFile(invoice_ids, format, debit_account),
    onSuccess: async (pf) => {
      qc.invalidateQueries({ queryKey: ['accepted-for-payment'] });
      qc.invalidateQueries({ queryKey: ['payment-files'] });
      qc.invalidateQueries({ queryKey: ['invoices'] });
      try {
        await downloadAndSharePaymentFile(pf.id, pf.file_name);
      } catch {
        // share nieudany — plik jest zapisany w historii, można pobrać później
      }
    },
  });
};
