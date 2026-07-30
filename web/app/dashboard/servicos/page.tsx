import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import ServicosTable from '@/components/servicos/ServicosTable'

export default async function ServicosPage() {
  const supabase = createClient()

  const {
    data: { user },
  } = await supabase.auth.getUser()

  if (!user) {
    redirect('/auth/login')
  }

  const { data: servicos, error } = await supabase
    .from('servicos')
    .select(`
      id,
      nome_tecnico,
      tipo_recurso_id,
      duracao_minutos,
      preco_base,
      percentual_sinal,
      anamnese_obrigatoria,
      ativo,
      foto_url,
      servico_cardapios (
        id,
        cardapio,
        nome_comercial,
        preco_final,
        ativo
      )
    `)
    .order('nome_tecnico')

  if (error) {
    console.error('Erro ao carregar serviços:', error)
    return <p className="text-red-600">Erro ao carregar serviços: {error.message}</p>
  }

  return (
    <div>
      <h2 className="text-2xl font-bold text-gray-900">Catálogo de serviços</h2>
      <p className="mt-2 text-gray-600">Edita preços, durações e visibilidade dos serviços.</p>
      <div className="mt-6">
        <ServicosTable servicos={servicos ?? []} />
      </div>
    </div>
  )
}
