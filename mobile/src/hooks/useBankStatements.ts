import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  getBankStatements, uploadBankStatement, getBankStatement,
  runMatcher, toggleMatch, confirmStatement,
} from '../api/bankStatements';

export const useBankStatements = () =>
  useQuery({ queryKey: ['bank-statements'], queryFn: getBankStatements });

export const useBankStatement = (id: number) =>
  useQuery({ queryKey: ['bank-statement', id], queryFn: () => getBankStatement(id), enabled: !!id });

export const useUploadStatement = () => {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (file: { uri: string; name: string; mimeType: string }) => uploadBankStatement(file),
    onSuccess: () => { qc.invalidateQueries({ queryKey: ['bank-statements'] }); },
  });
};

export const useRunMatcher = (stmtId: number) => {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: () => runMatcher(stmtId),
    onSuccess: () => { qc.invalidateQueries({ queryKey: ['bank-statement', stmtId] }); },
  });
};

export const useToggleMatch = (stmtId: number) => {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (matchId: number) => toggleMatch(stmtId, matchId),
    onSuccess: () => { qc.invalidateQueries({ queryKey: ['bank-statement', stmtId] }); },
  });
};

export const useConfirmStatement = () => {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (stmtId: number) => confirmStatement(stmtId),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['bank-statements'] });
      qc.invalidateQueries({ queryKey: ['invoices'] });
    },
  });
};
