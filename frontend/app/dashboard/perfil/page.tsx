import { createSessionClient } from '@/lib/supabase/session'
import { redirect } from 'next/navigation'

export default async function PerfilPage() {
  const supabase = createSessionClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login?redirect=/dashboard/perfil')

  return (
    <div className="text-center py-12">
      <h2 className="text-xl font-bold text-ella-dark mb-2">Meu Perfil</h2>
      <p className="text-gray-500">Em construção — foto, especialidades e horários.</p>
    </div>
  )
}
