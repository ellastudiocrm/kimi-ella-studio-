'use client'

import { useState, useTransition } from 'react'
import { useRouter } from 'next/navigation'
import { criarBloqueio } from '@/app/dashboard/acoes'
import { TIPOS_BLOQUEIO } from '@/lib/estados'
import type { ProfissionalAgenda } from '@/lib/painel'

type Tipo = 'almoco' | 'folga' | 'imprevisto'

export default function FormBloqueio({
  profissionais,
  dataInicial,
  hoje,
}: {
  profissionais: ProfissionalAgenda[]
  dataInicial: string
  hoje: string
}) {
  const router = useRouter()
  const [salvando, iniciar] = useTransition()
  const [profissionalId, setProfissionalId] = useState(profissionais.length === 1 ? profissionais[0].id : '')
  const [tipo, setTipo] = useState<Tipo>('almoco')
  const [data, setData] = useState(dataInicial)
  const [diaTodo, setDiaTodo] = useState(false)
  const [horaInicio, setHoraInicio] = useState('12:00')
  const [horaFim, setHoraFim] = useState('13:00')
  const [motivo, setMotivo] = useState('')
  const [confirmando, setConfirmando] = useState(false)
  const [erro, setErro] = useState<string | null>(null)

  function salvar() {
    setErro(null)
    iniciar(async () => {
      const r = await criarBloqueio({
        profissionalId,
        data,
        horaInicio: diaTodo ? '00:00' : horaInicio,
        horaFim: diaTodo ? '23:59' : horaFim,
        tipo,
        motivo,
      })
      if (!r.ok) {
        setErro(r.erro)
        setConfirmando(false)
        return
      }
      router.push(`/dashboard/agenda?data=${data}${r.aviso ? `&aviso=${encodeURIComponent(r.aviso)}` : ''}`)
    })
  }

  return (
    <div className="mt-6 space-y-5 rounded-3xl border border-ella-line bg-white p-5 sm:p-6">
      <div>
        <p className="mb-2 text-sm font-medium">Profissional</p>
        <div className="flex flex-wrap gap-2">
          {profissionais.map((p) => (
            <button
              key={p.id}
              type="button"
              onClick={() => setProfissionalId(p.id)}
              className={`rounded-full px-4 py-2 text-sm ring-1 ${
                profissionalId === p.id ? 'bg-ella-rose text-white ring-ella-rose' : 'bg-white ring-ella-line'
              }`}
            >
              {p.nome}
            </button>
          ))}
        </div>
      </div>

      <div>
        <p className="mb-2 text-sm font-medium">Tipo</p>
        <div className="flex flex-wrap gap-2">
          {(Object.keys(TIPOS_BLOQUEIO) as Tipo[]).map((t) => (
            <button
              key={t}
              type="button"
              onClick={() => {
                setTipo(t)
                setDiaTodo(t === 'folga')
              }}
              className={`rounded-full px-4 py-2 text-sm ring-1 ${
                tipo === t ? 'bg-ella-dark text-white ring-ella-dark' : 'bg-white ring-ella-line'
              }`}
            >
              {TIPOS_BLOQUEIO[t]}
            </button>
          ))}
        </div>
      </div>

      <div className="grid gap-4 sm:grid-cols-3">
        <label className="block text-sm font-medium">
          Dia
          <input type="date" min={hoje} value={data} onChange={(e) => setData(e.target.value)} className="campo mt-1.5" />
        </label>
        {!diaTodo && (
          <>
            <label className="block text-sm font-medium">
              Das
              <input type="time" value={horaInicio} onChange={(e) => setHoraInicio(e.target.value)} className="campo mt-1.5" />
            </label>
            <label className="block text-sm font-medium">
              Até
              <input type="time" value={horaFim} onChange={(e) => setHoraFim(e.target.value)} className="campo mt-1.5" />
            </label>
          </>
        )}
      </div>
      <label className="flex items-center gap-2 text-sm">
        <input type="checkbox" checked={diaTodo} onChange={(e) => setDiaTodo(e.target.checked)} className="h-4 w-4 accent-ella-rose" />
        Dia inteiro
      </label>

      <label className="block text-sm font-medium">
        Observação (opcional)
        <input
          value={motivo}
          onChange={(e) => setMotivo(e.target.value)}
          placeholder="Ex.: consulta médica"
          className="campo mt-1.5"
        />
      </label>

      {erro && <p className="rounded-2xl bg-red-50 p-3 text-sm text-red-800">{erro}</p>}

      {confirmando ? (
        <div className="rounded-2xl bg-amber-50 p-4 text-sm text-amber-900">
          <p>
            <strong>Atenção:</strong> se já houver clientes marcados nesse horário, os agendamentos serão cancelados
            automaticamente. Confirmar o bloqueio?
          </p>
          <div className="mt-3 flex gap-2">
            <button type="button" disabled={salvando} onClick={salvar} className="btn-primario !py-2.5 text-sm">
              {salvando ? 'Bloqueando…' : 'Sim, bloquear'}
            </button>
            <button type="button" onClick={() => setConfirmando(false)} className="btn-secundario !py-2.5 text-sm">
              Voltar
            </button>
          </div>
        </div>
      ) : (
        <button
          type="button"
          disabled={!profissionalId || !data}
          onClick={() => setConfirmando(true)}
          className="btn-primario"
        >
          Bloquear horário
        </button>
      )}
    </div>
  )
}
