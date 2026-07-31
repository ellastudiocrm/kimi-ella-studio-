import Link from 'next/link'
import { redirect } from 'next/navigation'
import { createSessionClient } from '@/lib/supabase/session'

interface ReservaItem {
  id: string
  inicio: string
  fim: string
  estado: string
  reservas: {
    id: string
    estado: string
    clientes: {
      nome: string
      telefone_normalizado: string
    }
  }
  servicos: {
    nome_tecnico: string
    duracao_minutos: number
    servico_cardapios: {
      nome_comercial: string
      cardapio: string
    }[]
  }
}

export default async function DashboardPage() {
  const supabase = createSessionClient()

  const {
    data: { user },
  } = await supabase.auth.getUser()

  if (!user) {
    redirect('/login?redirect=/dashboard')
  }

  const { data: usuario } = await supabase
    .from('usuarios_internos')
    .select('perfil, profissional_id')
    .eq('auth_user_id', user.id)
    .single()

  if (!usuario?.profissional_id) {
    return (
      <div className="text-center py-12">
        <p className="text-gray-500">Esta conta não está vinculada a uma profissional.</p>
        {usuario?.perfil === 'admin' && (
          <Link href="/admin" className="text-ella-rose hover:underline">
            Ir para o painel admin
          </Link>
        )}
      </div>
    )
  }

  const hoje = new Date().toISOString().split('T')[0]
  const amanha = new Date(Date.now() + 86400000).toISOString().split('T')[0]

  const { data: itens, error } = await supabase
    .from('reserva_itens')
    .select(`
      id,
      inicio,
      fim,
      estado,
      reservas (
        id,
        estado,
        clientes (nome, telefone_normalizado)
      ),
      servicos (
        nome_tecnico,
        duracao_minutos,
        servico_cardapios (nome_comercial, cardapio)
      )
    `)
    .eq('profissional_id', usuario.profissional_id)
    .gte('inicio', `${hoje}T00:00:00`)
    .lt('inicio', `${amanha}T00:00:00`)
    .order('inicio', { ascending: true })

  if (error) {
    console.error('Erro ao carregar agenda:', error)
    return <p className="text-red-600">Erro ao carregar agenda: {error.message}</p>
  }

  const atendimentos = (itens || []) as unknown as ReservaItem[]

  const agora = new Date()
  const proximo = atendimentos.find((a) => new Date(a.inicio) >= agora)

  const estadoCor = (estado: string) => {
    switch (estado) {
      case 'pre_reserva':
        return 'bg-yellow-100 text-yellow-700'
      case 'confirmada':
        return 'bg-green-100 text-green-700'
      case 'em_atendimento':
        return 'bg-blue-100 text-blue-700'
      case 'concluida':
        return 'bg-gray-100 text-gray-600'
      default:
        return 'bg-gray-100 text-gray-600'
    }
  }

  const estadoLabel = (estado: string) => {
    switch (estado) {
      case 'pre_reserva':
        return 'Pré-reserva'
      case 'confirmada':
        return 'Confirmada'
      case 'em_atendimento':
        return 'Em atendimento'
      case 'concluida':
        return 'Concluída'
      default:
        return estado
    }
  }

  const nomeServico = (item: ReservaItem) => {
    const cardapio = item.servicos.servico_cardapios?.[0]
    return cardapio?.nome_comercial || item.servicos.nome_tecnico
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h2 className="text-xl font-bold text-ella-dark">Hoje</h2>
        <p className="text-sm text-gray-500">
          {new Date().toLocaleDateString('pt-BR', { weekday: 'long', day: 'numeric', month: 'long' })}
        </p>
      </div>

      {proximo && (
        <div className="bg-ella-rose text-white rounded-2xl p-5 shadow-lg">
          <p className="text-sm opacity-90 mb-1">Próximo atendimento</p>
          <p className="text-2xl font-bold">
            {new Date(proximo.inicio).toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' })}
          </p>
          <p className="font-medium mt-1">{proximo.reservas.clientes.nome}</p>
          <p className="text-sm opacity-90">{nomeServico(proximo)}</p>
          <Link
            href={`/dashboard/atendimento/${proximo.id}`}
            className="mt-4 block w-full py-3 bg-white text-ella-rose rounded-xl text-center font-semibold"
          >
            Ver atendimento
          </Link>
        </div>
      )}

      <div>
        <h3 className="text-sm font-semibold text-gray-500 uppercase tracking-wide mb-3">
          Agenda do dia
        </h3>

        {atendimentos.length === 0 ? (
          <p className="text-gray-500 text-center py-8">Nenhum atendimento agendado para hoje.</p>
        ) : (
          <div className="space-y-3">
            {atendimentos.map((item) => (
              <Link
                key={item.id}
                href={`/dashboard/atendimento/${item.id}`}
                className="block bg-white border border-gray-100 rounded-xl p-4 shadow-sm active:scale-[0.98] transition-transform"
              >
                <div className="flex items-start justify-between">
                  <div>
                    <p className="text-lg font-bold text-ella-dark">
                      {new Date(item.inicio).toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' })}
                    </p>
                    <p className="font-medium text-gray-900">{item.reservas.clientes.nome}</p>
                    <p className="text-sm text-gray-500">{nomeServico(item)} • {item.servicos.duracao_minutos} min</p>
                  </div>
                  <span className={`rounded-full px-2.5 py-1 text-xs font-medium ${estadoCor(item.reservas.estado)}`}>
                    {estadoLabel(item.reservas.estado)}
                  </span>
                </div>
              </Link>
            ))}
          </div>
        )}
      </div>
    </div>
  )
}
