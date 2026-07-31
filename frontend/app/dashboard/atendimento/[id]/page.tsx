import Link from 'next/link'
import { redirect } from 'next/navigation'
import { createSessionClient } from '@/lib/supabase/session'

interface AtendimentoPageProps {
  params: { id: string }
}

export default async function AtendimentoPage({ params }: AtendimentoPageProps) {
  const supabase = createSessionClient()

  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect(`/login?redirect=/dashboard/atendimento/${params.id}`)

  const { data: usuario } = await supabase
    .from('usuarios_internos')
    .select('profissional_id')
    .eq('auth_user_id', user.id)
    .single()

  const { data: item, error } = await supabase
    .from('reserva_itens')
    .select(`
      id,
      inicio,
      fim,
      estado,
      reservas (id, estado),
      servicos (nome_tecnico, duracao_minutos, servico_cardapios (nome_comercial, cardapio)),
      profissionais (id, nome),
      clientes (nome, telefone_normalizado)
    `)
    .eq('id', params.id)
    .single()

  if (error || !item) {
    return <p className="text-red-600">Atendimento não encontrado.</p>
  }

  const atendimento = item as any

  if (atendimento.profissionais.id !== usuario?.profissional_id) {
    return <p className="text-red-600">Sem permissão para ver este atendimento.</p>
  }

  const nomeServico = atendimento.servicos.servico_cardapios?.[0]?.nome_comercial || atendimento.servicos.nome_tecnico

  return (
    <div className="space-y-4">
      <Link href="/dashboard" className="text-sm text-gray-500">← Voltar</Link>

      <h2 className="text-xl font-bold text-ella-dark">Atendimento</h2>

      <div className="bg-white border border-gray-100 rounded-xl p-4 shadow-sm">
        <p className="text-sm text-gray-500">Cliente</p>
        <p className="font-semibold text-lg">{atendimento.clientes.nome}</p>
        <p className="text-sm text-gray-600">{atendimento.clientes.telefone_normalizado}</p>
      </div>

      <div className="bg-white border border-gray-100 rounded-xl p-4 shadow-sm">
        <p className="text-sm text-gray-500">Serviço</p>
        <p className="font-semibold">{nomeServico}</p>
        <p className="text-sm text-gray-600">
          {new Date(atendimento.inicio).toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' })} — {' '}
          {atendimento.servicos.duracao_minutos} min
        </p>
      </div>

      <div className="bg-white border border-gray-100 rounded-xl p-4 shadow-sm">
        <p className="text-sm text-gray-500">Estado</p>
        <p className="font-semibold capitalize">{atendimento.reservas.estado}</p>
      </div>

      <div className="space-y-2">
        {atendimento.reservas.estado === 'confirmada' && (
          <button className="w-full py-4 bg-ella-rose text-white rounded-xl font-semibold min-h-[44px]">
            Cliente chegou
          </button>
        )}
        {atendimento.reservas.estado === 'em_atendimento' && (
          <>
            <button className="w-full py-4 bg-blue-600 text-white rounded-xl font-semibold min-h-[44px]">
              Iniciar procedimento
            </button>
            <button className="w-full py-4 bg-green-600 text-white rounded-xl font-semibold min-h-[44px]">
              Concluir atendimento
            </button>
          </>
        )}
      </div>
    </div>
  )
}
