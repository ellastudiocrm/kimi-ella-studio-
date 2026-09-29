import { createBrowserClient } from '@supabase/ssr'

// Cliente do navegador. Guarda a sessão em cookies para o servidor
// (middleware e páginas) reconhecer quem fez login.
export const supabase = createBrowserClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
)
