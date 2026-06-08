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
    mutationFn: async ({ invoice_ids, format, debit_account }: { invoice_ids: number[]; format: 'erste' | 'elixir' | 'mbank'; debit_account?: string }) => {
      const pf = await generatePaymentFile(invoice_ids, format, debit_account);
      await downloadAndSharePaymentFile(pf.id, pf.file_name);
      return pf;
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['accepted-for-payment'] });
      qc.invalidateQueries({ queryKey: ['payment-files'] });
      qc.invalidateQueries({ queryKey: ['invoices'] });
    },
  });
};
