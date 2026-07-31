import { createSessionClient } from '@/lib/supabase/session'
import { redirect } from 'next/navigation'

export default async function ClientesPage() {
  const supabase = createSessionClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login?redirect=/dashboard/clientes')

  return (
    <div className="text-center py-12">
      <h2 className="text-xl font-bold text-ella-dark mb-2">Meus Clientes</h2>
      <p className="text-gray-500">Em construção — lista de clientes atendidos.</p>
    </div>
  )
}
