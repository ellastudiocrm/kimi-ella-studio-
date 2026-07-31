'use client'

import { useEffect, useState, Suspense } from 'react'
import Link from 'next/link'
import { useSearchParams } from 'next/navigation'
import { supabase } from '@/lib/supabase/client'

function ConfirmacaoContent() {
  const searchParams = useSearchParams()
  const profissionalId = searchParams.get('profissional')
  const servicoId = searchParams.get('servico')
  const data = searchParams.get('data')
  const hora = searchParams.get('hora')
  const cardapio = searchParams.get('cardapio') || 'ella_studio'

  const [profissional, setProfissional] = useState<any>(null)
  const [servico, setServico] = useState<any>(null)
  const [cardapioData, setCardapioData] = useState<any>(null)
  const [clienteNome, setClienteNome] = useState('')
  const [clienteTelefone, setClienteTelefone] = useState('')
  const [loading, setLoading] = useState(true)
  const [enviando, setEnviando] = useState(false)
  const [resultado, setResultado] = useState<any>(null)

  useEffect(() => {
    async function carregar() {
      // Buscar serviço
      const { data: servicoData } = await supabase
        .from('servicos')
        .select('*')
        .eq('id', servicoId)
        .single()

      if (servicoData) setServico(servicoData)

      // Buscar cardápio
      const { data: cardData } = await supabase
        .from('servico_cardapios')
        .select('*')
        .eq('servico_id', servicoId)
        .eq('cardapio', cardapio)
        .single()

      if (cardData) setCardapioData(cardData)

      // Buscar profissional
      if (profissionalId) {
        const { data: profData } = await supabase
          .from('profissionais')
          .select('*')
          .eq('id', profissionalId)
          .single()

        if (profData) setProfissional(profData)
      }

      setLoading(false)
    }

    carregar()
  }, [servicoId, profissionalId, cardapio])

  async function confirmarReserva() {
    if (!clienteNome || !clienteTelefone) {
      alert('Preencha nome e telefone')
      return
    }

    if (!profissionalId) {
      alert('Selecione um profissional')
      return
    }

    setEnviando(true)

    try {
      const response = await fetch('/api/pre-reserva', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          empresa_id: process.env.NEXT_PUBLIC_EMPRESA_ID,
          cliente_nome: clienteNome,
          cliente_telefone: clienteTelefone.replace(/\D/g, ''),
          itens: [{
            servico_id: servicoId,
            profissional_id: profissionalId,
            inicio: hora,
            cardapio: cardapio,
          }],
          idempotencia_key: `web-${Date.now()}`,
        }),
      })

      const data = await response.json()
      if (!response.ok) {
        alert(data.error || 'Erro ao criar reserva')
      } else {
        setResultado(data)
      }
    } catch (err) {
      console.error('Erro:', err)
      alert('Erro ao criar reserva. Tente novamente.')
    }

    setEnviando(false)
  }

  if (loading) {
    return (
      <div className="flex items-center justify-center min-h-screen">
        <p className="text-gray-500">Carregando...</p>
      </div>
    )
  }

  if (resultado) {
    return (
      <div className="min-h-screen px-4 py-6 flex flex-col items-center justify-center text-center">
        <div className="text-6xl mb-4">✅</div>
        <h1 className="text-2xl font-bold mb-2">
          {resultado.estado === 'confirmada' ? 'Reserva confirmada!' : 'Pré-reserva criada!'}
        </h1>
        <p className="text-gray-600 mb-6">
          {resultado.estado === 'confirmada'
            ? 'Sua reserva está confirmada. Te esperamos!'
            : 'Você tem 30 minutos para realizar o pagamento do sinal.'}
        </p>

        <div className="bg-gray-50 rounded-xl p-4 w-full mb-6 text-left">
          <p><span className="font-medium">Serviço:</span> {cardapioData?.nome_comercial || servico?.nome_tecnico}</p>
          <p><span className="font-medium">Profissional:</span> {profissional?.nome || 'Qualquer disponível'}</p>
          <p><span className="font-medium">Data:</span> {data && new Date(data).toLocaleDateString('pt-BR')}</p>
          <p><span className="font-medium">Horário:</span> {hora && new Date(hora).toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' })}</p>
          <p><span className="font-medium">Valor:</span> R$ {cardapioData?.preco_final?.toFixed(2) || servico?.preco_base?.toFixed(2)}</p>
          {resultado.valor_sinal > 0 && (
            <p><span className="font-medium">Sinal (30%):</span> R$ {resultado.valor_sinal?.toFixed(2)}</p>
          )}
        </div>

        <Link
          href="/"
          className="block w-full py-4 bg-ella-rose text-white rounded-xl text-center font-semibold"
        >
          Voltar ao início
        </Link>
      </div>
    )
  }

  return (
    <div className="min-h-screen px-4 py-6">
      {/* Header */}
      <div className="flex items-center mb-4">
        <Link href="/agendar" className="text-gray-500 text-sm mr-4">
          ← Voltar
        </Link>
        <h1 className="text-lg font-bold">Confirme sua reserva</h1>
      </div>

      {/* Resumo */}
      <div className="bg-gray-50 rounded-xl p-4 mb-6">
        <h2 className="font-semibold mb-2">Resumo</h2>
        <p className="text-sm text-gray-600">
          <span className="font-medium">Serviço:</span> {cardapioData?.nome_comercial || servico?.nome_tecnico}
        </p>
        <p className="text-sm text-gray-600">
          <span className="font-medium">Profissional:</span> {profissional?.nome || 'Qualquer disponível'}
        </p>
        <p className="text-sm text-gray-600">
          <span className="font-medium">Data:</span> {data && new Date(data).toLocaleDateString('pt-BR', { weekday: 'long', day: 'numeric', month: 'long' })}
        </p>
        <p className="text-sm text-gray-600">
          <span className="font-medium">Horário:</span> {hora && new Date(hora).toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' })}
        </p>
        <p className="text-sm text-gray-600">
          <span className="font-medium">Valor:</span> R$ {cardapioData?.preco_final?.toFixed(2) || servico?.preco_base?.toFixed(2)}
        </p>
        <p className="text-sm text-gray-600">
          <span className="font-medium">Sinal (30%):</span> R$ {((cardapioData?.preco_final || servico?.preco_base) * 0.3).toFixed(2)}
        </p>
      </div>

      {/* Formulário */}
      <div className="space-y-4 mb-6">
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">
            Nome completo
          </label>
          <input
            type="text"
            value={clienteNome}
            onChange={(e) => setClienteNome(e.target.value)}
            placeholder="Seu nome"
            className="w-full px-4 py-3 rounded-xl border border-gray-200 focus:border-ella-rose focus:outline-none text-base"
          />
        </div>

        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">
            WhatsApp
          </label>
          <input
            type="tel"
            value={clienteTelefone}
            onChange={(e) => setClienteTelefone(e.target.value)}
            placeholder="(19) 99999-9999"
            className="w-full px-4 py-3 rounded-xl border border-gray-200 focus:border-ella-rose focus:outline-none text-base"
          />
        </div>
      </div>

      {/* Botão */}
      <button
        onClick={confirmarReserva}
        disabled={enviando}
        className="block w-full py-4 bg-ella-rose text-white rounded-xl text-center font-semibold text-lg shadow-lg active:scale-[0.98] transition-transform disabled:opacity-50"
      >
        {enviando ? 'Processando...' : 'Confirmar reserva'}
      </button>

      <p className="text-xs text-gray-400 text-center mt-4">
        Ao confirmar, você aceita nossa política de cancelamento.
      </p>
    </div>
  )
}

export default function ConfirmacaoPage() {
  return (
    <Suspense fallback={
      <div className="flex items-center justify-center min-h-screen">
        <p className="text-gray-500">Carregando...</p>
      </div>
    }>
      <ConfirmacaoContent />
    </Suspense>
  )
}
