import { createClient } from '@supabase/supabase-js';

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL;
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY;

export const isSupabaseConfigured = Boolean(supabaseUrl && supabaseAnonKey);
const projectRef = isSupabaseConfigured ? new URL(supabaseUrl).hostname.split('.')[0] : '';
const customerAuthStorageKey = `sb-${projectRef}-customer-auth-token`;

if (isSupabaseConfigured && typeof window !== 'undefined') {
  try {
    const legacyStorageKey = `sb-${projectRef}-auth-token`;
    const legacySession = JSON.parse(window.localStorage.getItem(legacyStorageKey) || 'null');
    const legacyUser = (legacySession?.currentSession || legacySession)?.user;
    if (legacyUser?.is_anonymous) {
      if (!window.localStorage.getItem(customerAuthStorageKey)) {
        window.localStorage.setItem(customerAuthStorageKey, JSON.stringify(legacySession));
      }
      window.localStorage.removeItem(legacyStorageKey);
    }
  } catch {
    // Keep the app usable when browser storage is unavailable.
  }
}

export const supabase = isSupabaseConfigured
  ? createClient(supabaseUrl, supabaseAnonKey)
  : null;
export const customerSupabase = isSupabaseConfigured
  ? createClient(supabaseUrl, supabaseAnonKey, { auth: { storageKey: customerAuthStorageKey } })
  : null;
