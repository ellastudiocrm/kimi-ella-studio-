import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import ProfissionalForm from '@/components/profissionais/ProfissionalForm'

interface Servico {
  id: string
  nome_tecnico: string
  servico_cardapios: { cardapio: string; nome_comercial: string }[]
}

export default async function ProfissionalPage({ params }: { params: { id: string } }) {
  const supabase = createClient()

  const {
    data: { user },
  } = await supabase.auth.getUser()

  if (!user) {
    redirect('/auth/login')
  }

  const [profissionalResult, servicosResult] = await Promise.all([
    supabase
      .from('profissionais')
      .select('id, nome, foto_url, bio, especialidades, ativo')
      .eq('id', params.id)
      .single(),
    supabase
      .from('servicos')
      .select('id, nome_tecnico, servico_cardapios(cardapio, nome_comercial)')
      .eq('ativo', true)
      .order('nome_tecnico'),
  ])

  if (profissionalResult.error) {
    console.error('Erro ao carregar profissional:', profissionalResult.error)
    return <p className="text-red-600">Erro ao carregar profissional.</p>
  }

  const profissionalServicosResult = await supabase
    .from('profissional_servicos')
    .select('servico_id')
    .eq('profissional_id', params.id)

  const profissional = {
    ...profissionalResult.data,
    servicos: (profissionalServicosResult.data ?? []).map((s) => s.servico_id),
  }

  const servicos = (servicosResult.data ?? []).map((s: Servico) => ({
    id: s.id,
    nome_tecnico: s.nome_tecnico,
    cardapios: s.servico_cardapios,
  }))

  return (
    <div>
      <h2 className="text-xl font-bold text-gray-900 md:text-2xl">Ficha do profissional</h2>
      <p className="mt-1 text-sm text-gray-600">Edita dados, foto, galeria e serviços habilitados.</p>
      <div className="mt-6">
        <ProfissionalForm profissional={profissional} servicos={servicos} />
      </div>
    </div>
  )
}
