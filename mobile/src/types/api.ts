export interface Invoice {
  id: number;
  invoice_number: string;
  ksef_reference_number: string;
  seller_name: string;
  seller_nip: string;
  seller_address?: string;
  buyer_nip?: string;
  amount_net: string;
  amount_vat: string;
  amount_gross: string;
  currency: string;
  is_split_payment: boolean;
  vat_amount_split?: string | null;
  issue_date: string;
  payment_due_date: string | null;
  bank_account_number: string;
  payment_title: string;
  payment_date?: string | null;
  payment_form?: string;
  status: string;
  status_display: string;
  is_overdue: boolean;
  notes: string;
  invoice_type: string;
  description?: string;
  synced_at: string;
  updated_at: string;
  allowed_transitions?: string[];
  status_logs?: StatusLog[];
}

export interface StatusLog {
  id: number;
  old_status: string;
  new_status: string;
  changed_by_username: string | null;
  changed_at: string;
  note: string;
}

export interface PaginatedResponse<T> {
  count: number;
  next: string | null;
  previous: string | null;
  results: T[];
}

export interface OutgoingInvoice {
  id: number;
  invoice_number: string;
  issue_date: string;
  delivery_date?: string | null;
  payment_due_date: string;
  payment_form: string;
  currency: string;
  buyer_nip: string;
  buyer_name: string;
  buyer_address?: string;
  notes?: string;
  status: string;
  status_display: string;
  ksef_reference_number?: string;
  error_message?: string;
  amount_gross: string;
  amount_net?: string;
  amount_vat?: string;
  can_be_edited?: boolean;
  can_be_queued?: boolean;
  created_at: string;
  updated_at?: string;
  items?: InvoiceItem[];
}

export interface InvoiceItem {
  id?: number;
  lp: number;
  name: string;
  unit: string;
  quantity: string;
  unit_price_net: string;
  vat_rate: string;
  amount_net: string;
  amount_vat: string;
  amount_gross: string;
}

export interface PaymentFile {
  id: number;
  format: 'erste' | 'elixir' | 'mbank';
  file_name: string;
  total_amount: string;
  invoice_count: number;
  debit_account?: string;
  created_at: string;
}

export interface CompanyBankAccount {
  id: number;
  account_number: string;
  label?: string;
  bank_name: string;
  bank_key: string;
  is_default: boolean;
}

export interface Company {
  nip: string;
  name: string;
  address: string;
  bank_account: string;
}

export interface Buyer {
  id: number;
  nip: string;
  name: string;
  address: string;
  email: string;
  phone: string;
  notes: string;
}

export interface NipLookupResult {
  name: string;
  address: string;
  regon: string;
  status_vat: string;
  account_numbers: string[];
}

export interface DashboardMonth {
  month: string;
  total_gross: string;
  total_net: string;
  count: number;
}

export interface TransactionMatch {
  id: number;
  invoice: Invoice;
  match_type: string;
  confidence: string;
  is_confirmed: boolean;
}

export interface BankTransaction {
  id: number;
  transaction_date: string;
  value_date: string;
  amount: string;
  currency: string;
  is_debit: boolean;
  description: string;
  reference: string;
  is_matched: boolean;
  matches: TransactionMatch[];
}

export interface BankStatement {
  id: number;
  file_name: string;
  account_number: string;
  statement_date: string | null;
  status: 'pending' | 'reviewed' | 'confirmed';
  uploaded_at: string;
  transaction_count: number;
}

export interface BankStatementDetail extends BankStatement {
  transactions: BankTransaction[];
}
