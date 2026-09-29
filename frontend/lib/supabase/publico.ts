import { createClient } from '@supabase/supabase-js'

// Cliente com a chave pública (anon), para uso no servidor em leituras que a
// RLS já libera ao público (catálogo, profissionais, horários disponíveis).
export const supabasePublico = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
  { auth: { persistSession: false } }
)
