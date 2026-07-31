'use client'

import { useEffect, useState, Suspense } from 'react'
import Link from 'next/link'
import { useSearchParams } from 'next/navigation'
import { supabase } from '@/lib/supabase/client'
import type { SlotHorario } from '@/types'

function AgendarContent() {
  const searchParams = useSearchParams()
  const profissionalId = searchParams.get('profissional')
  const servicoSlug = searchParams.get('servico')
  const cardapio = searchParams.get('cardapio') || 'ella_studio'

  const [servico, setServico] = useState<any>(null)
  const [profissional, setProfissional] = useState<any>(null)
  const [dataSelecionada, setDataSelecionada] = useState<string>('')
  const [slots, setSlots] = useState<SlotHorario[]>([])
  const [slotSelecionado, setSlotSelecionado] = useState<string>('')
  const [loading, setLoading] = useState(true)
  const [loadingSlots, setLoadingSlots] = useState(false)

  // Gerar dias do mês atual
  const hoje = new Date()
  const [mesAtual, setMesAtual] = useState(hoje.getMonth())
  const [anoAtual, setAnoAtual] = useState(hoje.getFullYear())

  useEffect(() => {
    async function carregar() {
      // Buscar serviço
      const { data: servicoData } = await supabase
        .from('servicos')
        .select('*')
        .eq('nome_tecnico', servicoSlug)
        .single()

      if (servicoData) setServico(servicoData)

      // Buscar profissional (se especificado)
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
  }, [servicoSlug, profissionalId])

  async function buscarSlots(data: string) {
    setLoadingSlots(true)
    setDataSelecionada(data)
    setSlotSelecionado('')

    try {
      const response = await fetch('/api/horarios', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          empresa_id: process.env.NEXT_PUBLIC_EMPRESA_ID,
          servico_id: servico?.id,
          profissional_id: profissionalId,
          data: data,
          cardapio: cardapio,
        }),
      })

      const data_ = await response.json()
      if (Array.isArray(data_)) {
        setSlots(data_)
      }
    } catch (err) {
      console.error('Erro ao buscar slots:', err)
    }

    setLoadingSlots(false)
  }

  function gerarDiasDoMes() {
    const primeiroDia = new Date(anoAtual, mesAtual, 1)
    const ultimoDia = new Date(anoAtual, mesAtual + 1, 0)
    const dias = []

    // Dias vazios antes do primeiro dia
    for (let i = 0; i < primeiroDia.getDay(); i++) {
      dias.push(null)
    }

    // Dias do mês
    for (let i = 1; i <= ultimoDia.getDate(); i++) {
      dias.push(i)
    }

    return dias
  }

  function formatarData(dia: number) {
    return `${anoAtual}-${String(mesAtual + 1).padStart(2, '0')}-${String(dia).padStart(2, '0')}`
  }

  const nomesMeses = [
    'Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho',
    'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro'
  ]

  const diasSemana = ['Dom', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb']

  if (loading) {
    return (
      <div className="flex items-center justify-center min-h-screen">
        <p className="text-gray-500">Carregando...</p>
      </div>
    )
  }

  return (
    <div className="min-h-screen px-4 py-6">
      {/* Header */}
      <div className="flex items-center mb-4">
        <Link href={`/${cardapio}/${servicoSlug}`} className="text-gray-500 text-sm mr-4">
          ← Voltar
        </Link>
        <h1 className="text-lg font-bold">Escolha o dia</h1>
      </div>

      {/* Resumo */}
      <div className="bg-gray-50 rounded-xl p-3 mb-4 text-sm">
        <p><span className="font-medium">Serviço:</span> {servico?.nome_tecnico}</p>
        {profissional && (
          <p><span className="font-medium">Profissional:</span> {profissional.nome}</p>
        )}
      </div>

      {/* Calendário */}
      <div className="bg-white rounded-xl border border-gray-100 p-4 mb-4">
        {/* Navegação do mês */}
        <div className="flex items-center justify-between mb-4">
          <button
            onClick={() => {
              if (mesAtual === 0) {
                setMesAtual(11)
                setAnoAtual(anoAtual - 1)
              } else {
                setMesAtual(mesAtual - 1)
              }
            }}
            className="p-2 text-gray-500"
          >
            ←
          </button>
          <span className="font-semibold">
            {nomesMeses[mesAtual]} {anoAtual}
          </span>
          <button
            onClick={() => {
              if (mesAtual === 11) {
                setMesAtual(0)
                setAnoAtual(anoAtual + 1)
              } else {
                setMesAtual(mesAtual + 1)
              }
            }}
            className="p-2 text-gray-500"
          >
            →
          </button>
        </div>

        {/* Dias da semana */}
        <div className="grid grid-cols-7 gap-1 mb-2">
          {diasSemana.map((dia) => (
            <div key={dia} className="text-center text-xs text-gray-400 py-1">
              {dia}
            </div>
          ))}
        </div>

        {/* Dias */}
        <div className="grid grid-cols-7 gap-1">
          {gerarDiasDoMes().map((dia, index) => {
            if (dia === null) {
              return <div key={`empty-${index}`} className="h-10" />
            }

            const dataStr = formatarData(dia)
            const isHoje = dataStr === `${hoje.getFullYear()}-${String(hoje.getMonth() + 1).padStart(2, '0')}-${String(hoje.getDate()).padStart(2, '0')}`
            const isSelecionado = dataStr === dataSelecionada
            const isPassado = new Date(dataStr) < new Date(hoje.toDateString())

            return (
              <button
                key={dia}
                onClick={() => !isPassado && buscarSlots(dataStr)}
                disabled={isPassado}
                className={`
                  h-10 rounded-lg text-sm font-medium transition-colors
                  ${isPassado ? 'text-gray-300 cursor-not-allowed' : ''}
                  ${isSelecionado ? 'bg-ella-rose text-white' : ''}
                  ${!isSelecionado && !isPassado ? 'hover:bg-gray-100 text-gray-700' : ''}
                  ${isHoje && !isSelecionado ? 'border border-ella-rose text-ella-rose' : ''}
                `}
              >
                {dia}
              </button>
            )
          })}
        </div>
      </div>

      {/* Slots de horário */}
      {dataSelecionada && (
        <div className="mb-4">
          <h2 className="text-sm font-medium text-gray-600 mb-3">
            Horários disponíveis em {new Date(dataSelecionada).toLocaleDateString('pt-BR', { weekday: 'long', day: 'numeric', month: 'long' })}
          </h2>

          {loadingSlots ? (
            <p className="text-gray-500 text-sm">Buscando horários...</p>
          ) : slots.length === 0 ? (
            <p className="text-gray-500 text-sm">Nenhum horário disponível neste dia.</p>
          ) : (
            <div className="grid grid-cols-3 gap-2">
              {slots.map((slot, index) => {
                const hora = new Date(slot.inicio).toLocaleTimeString('pt-BR', {
                  hour: '2-digit',
                  minute: '2-digit',
                })
                const isSelecionado = slotSelecionado === slot.inicio

                return (
                  <button
                    key={index}
                    onClick={() => setSlotSelecionado(slot.inicio)}
                    className={`
                      py-3 px-2 rounded-xl text-sm font-medium transition-colors
                      ${isSelecionado
                        ? 'bg-ella-rose text-white'
                        : 'bg-white border border-gray-200 text-gray-700 hover:border-ella-rose'
                      }
                    `}
                  >
                    {hora}
                  </button>
                )
              })}
            </div>
          )}
        </div>
      )}

      {/* Botão continuar */}
      {slotSelecionado && (
        <div className="fixed bottom-0 left-0 right-0 p-4 bg-white border-t border-gray-100">
          <Link
            href={`/confirmacao?profissional=${profissionalId}&servico=${servico?.id}&data=${dataSelecionada}&hora=${slotSelecionado}&cardapio=${cardapio}`}
            className="block w-full py-4 bg-ella-rose text-white rounded-xl text-center font-semibold text-lg shadow-lg active:scale-[0.98] transition-transform"
          >
            Continuar
          </Link>
        </div>
      )}
    </div>
  )
}

export default function AgendarPage() {
  return (
    <Suspense fallback={
      <div className="flex items-center justify-center min-h-screen">
        <p className="text-gray-500">Carregando...</p>
      </div>
    }>
      <AgendarContent />
    </Suspense>
  )
}
