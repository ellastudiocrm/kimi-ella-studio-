'use client'

import { useEffect, useState } from 'react'
import Link from 'next/link'
import { supabase } from '@/lib/supabase/client'
import type { Servico, ServicoCardapio } from '@/types'

export default function EllaStudioPage() {
  const [servicos, setServicos] = useState<(Servico & { cardapio?: ServicoCardapio })[]>([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    async function carregar() {
      const { data: servicosData } = await supabase
        .from('servicos')
        .select('*')
        .eq('ativo', true)

      const { data: cardapiosData } = await supabase
        .from('servico_cardapios')
        .select('*')
        .eq('cardapio', 'ella_studio')
        .eq('ativo', true)

      if (servicosData && cardapiosData) {
        const combinado = servicosData.map((s: Servico) => ({
          ...s,
          cardapio: cardapiosData.find((c: ServicoCardapio) => c.servico_id === s.id),
        }))
        setServicos(combinado)
      }
      setLoading(false)
    }

    carregar()
  }, [])

  if (loading) {
    return (
      <div className="flex items-center justify-center min-h-screen">
        <p className="text-gray-500">Carregando serviços...</p>
      </div>
    )
  }

  return (
    <div className="min-h-screen px-4 py-6">
      {/* Header */}
      <div className="flex items-center mb-6">
        <Link href="/" className="text-gray-500 text-sm mr-4">
          ← Voltar
        </Link>
        <h1 className="text-xl font-bold">ELLA Studio</h1>
      </div>

      <p className="text-gray-600 mb-6">Escolha o serviço desejado:</p>

      {/* Lista de serviços */}
      <div className="space-y-3">
        {servicos.map((servico) => (
          <Link
            key={servico.id}
            href={`/ella_studio/${servico.nome_tecnico}`}
            className="block bg-white border border-gray-100 rounded-xl p-4 shadow-sm active:scale-[0.98] transition-transform"
          >
            <div className="flex items-center gap-4">
              {/* Placeholder foto */}
              <div className="w-16 h-16 rounded-lg bg-ella-rose/20 flex items-center justify-center text-2xl">
                💅
              </div>

              <div className="flex-1">
                <h3 className="font-semibold text-gray-900">
                  {servico.cardapio?.nome_comercial || servico.nome_tecnico}
                </h3>
                <p className="text-sm text-gray-500">
                  {servico.duracao_minutos} min
                </p>
                <p className="text-sm font-medium text-ella-dark">
                  R$ {servico.cardapio?.preco_final?.toFixed(2) || servico.preco_base.toFixed(2)}
                </p>
              </div>

              <span className="text-gray-400">→</span>
            </div>
          </Link>
        ))}
      </div>
    </div>
  )
}
