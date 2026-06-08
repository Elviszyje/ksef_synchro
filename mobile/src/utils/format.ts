export function formatAmount(value: string | number | null | undefined): string {
  if (value == null) return '0,00';
  const num = typeof value === 'string' ? parseFloat(value) : value;
  return num.toLocaleString('pl-PL', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

export function formatDate(value: string | null | undefined): string {
  if (!value) return '—';
  const [year, month, day] = value.split('-');
  return `${day}.${month}.${year}`;
}

export function formatDateTime(value: string | null | undefined): string {
  if (!value) return '—';
  const d = new Date(value);
  return d.toLocaleString('pl-PL', { dateStyle: 'short', timeStyle: 'short' });
}

export function formatNrb(account: string | null | undefined): string {
  if (!account) return '';
  const digits = account.replace(/\D/g, '');
  if (digits.length !== 26) return account;
  return `${digits.slice(0, 2)} ${digits.slice(2, 6)} ${digits.slice(6, 10)} ${digits.slice(10, 14)} ${digits.slice(14, 18)} ${digits.slice(18, 22)} ${digits.slice(22, 26)}`;
}
