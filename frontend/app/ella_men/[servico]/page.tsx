'use client'

import { useEffect, useState } from 'react'
import Link from 'next/link'
import { useParams } from 'next/navigation'
import { supabase } from '@/lib/supabase/client'
import type { Profissional } from '@/types'

export default function ProfissionaisMenPage() {
  const params = useParams()
  const servicoSlug = params.servico as string

  const [profissionais, setProfissionais] = useState<Profissional[]>([])
  const [servicoNome, setServicoNome] = useState('')
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    async function carregar() {
      const { data: servicoData } = await supabase
        .from('servicos')
        .select('*')
        .eq('nome_tecnico', servicoSlug)
        .eq('ativo', true)
        .single()

      if (servicoData) {
        setServicoNome(servicoData.nome_tecnico)

        const { data: habilitacoes } = await supabase
          .from('profissional_servicos')
          .select('profissional_id')
          .eq('servico_id', servicoData.id)

        if (habilitacoes && habilitacoes.length > 0) {
          const profIds = habilitacoes.map((h) => h.profissional_id)

          const { data: profsData } = await supabase
            .from('profissionais')
            .select('*')
            .eq('ativo', true)
            .in('id', profIds)

          if (profsData) {
            setProfissionais(profsData)
          }
        }
      }
      setLoading(false)
    }

    carregar()
  }, [servicoSlug])

  if (loading) {
    return (
      <div className="flex items-center justify-center min-h-screen">
        <p className="text-gray-500">Carregando profissionais...</p>
      </div>
    )
  }

  return (
    <div className="min-h-screen px-4 py-6">
      <div className="flex items-center mb-6">
        <Link href="/ella_men" className="text-gray-500 text-sm mr-4">
          ← Voltar
        </Link>
        <h1 className="text-xl font-bold">Escolha quem</h1>
      </div>

      <p className="text-gray-600 mb-6">
        Profissionais para <span className="font-medium">{servicoNome}</span>:
      </p>

      <div className="space-y-4">
        {profissionais.map((prof) => (
          <Link
            key={prof.id}
            href={`/agendar?profissional=${prof.id}&servico=${servicoSlug}&cardapio=ella_men`}
            className="block bg-white border border-gray-100 rounded-xl p-4 shadow-sm active:scale-[0.98] transition-transform"
          >
            <div className="flex items-center gap-4">
              <div className="w-16 h-16 rounded-full bg-gray-200 flex items-center justify-center text-2xl overflow-hidden">
                {prof.foto_url ? (
                  <img src={prof.foto_url} alt={prof.nome} className="w-full h-full object-cover" />
                ) : (
                  '👨‍⚕️'
                )}
              </div>
              <div className="flex-1">
                <h3 className="font-semibold text-gray-900">{prof.nome}</h3>
                {prof.especialidades && prof.especialidades.length > 0 && (
                  <p className="text-sm text-gray-500">{prof.especialidades.join(', ')}</p>
                )}
              </div>
              <span className="text-gray-400">→</span>
            </div>
          </Link>
        ))}
      </div>

    </div>
  )
}
