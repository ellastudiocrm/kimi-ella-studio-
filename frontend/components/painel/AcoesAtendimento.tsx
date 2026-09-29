'use client'

import { useState, useTransition } from 'react'
import { useRouter } from 'next/navigation'
import {
  cancelarReserva,
  finalizarAtendimento,
  registrarSinal,
  type MeioPagamento,
  type Resultado,
} from '@/app/dashboard/acoes'
import { MEIOS } from '@/lib/estados'
import { formatarPreco } from '@/lib/marca'

export default function AcoesAtendimento({
  reservaId,
  estado,
  podeReceber,
  valorSinal,
}: {
  reservaId: string
  estado: string
  podeReceber: boolean
  valorSinal: number
}) {
  const router = useRouter()
  const [pendente, iniciar] = useTransition()
  const [painel, setPainel] = useState<'sinal' | 'cancelar' | null>(null)
  const [meio, setMeio] = useState<MeioPagamento>('pix')
  const [motivo, setMotivo] = useState('')
  const [msg, setMsg] = useState<{ tipo: 'ok' | 'erro'; texto: string } | null>(null)

  function executar(acao: () => Promise<Resultado>, sucesso: string) {
    setMsg(null)
    iniciar(async () => {
      const r = await acao()
      if (r.ok) {
        setPainel(null)
        setMsg({ tipo: 'ok', texto: r.aviso ?? sucesso })
        router.refresh()
      } else {
        setMsg({ tipo: 'erro', texto: r.erro })
      }
    })
  }

  const ativa = estado === 'pre_reserva' || estado === 'confirmada'
  if (!ativa && !msg) return null

  return (
    <section className="mt-6 rounded-3xl border border-ella-line bg-white p-5">
      <p className="text-sm font-medium">O que fazer agora?</p>

      <div className="mt-4 flex flex-wrap gap-2">
        {estado === 'pre_reserva' && podeReceber && (
          <button type="button" onClick={() => setPainel('sinal')} className="btn-primario !py-2.5 text-sm">
            Registrar sinal e confirmar
          </button>
        )}
        {estado === 'confirmada' && (
          <button
            type="button"
            disabled={pendente}
            onClick={() => executar(() => finalizarAtendimento(reservaId), 'Atendimento finalizado.')}
            className="btn-primario !py-2.5 text-sm"
          >
            Marcar como realizado
          </button>
        )}
        {ativa && (
          <button
            type="button"
            onClick={() => setPainel('cancelar')}
            className="inline-flex items-center rounded-full px-5 py-2.5 text-sm text-rose-700 ring-1 ring-rose-200 hover:bg-rose-50"
          >
            Cancelar agendamento
          </button>
        )}
      </div>

      {painel === 'sinal' && (
        <div className="mt-5 rounded-2xl bg-ella-card p-4">
          <p className="text-sm">
            Sinal de <strong>{formatarPreco(valorSinal)}</strong> recebido como:
          </p>
          <div className="mt-3 flex flex-wrap gap-2">
            {MEIOS.map((m) => (
              <button
                key={m.valor}
                type="button"
                onClick={() => setMeio(m.valor)}
                className={`rounded-full px-4 py-2 text-sm ring-1 ${
                  meio === m.valor ? 'bg-ella-rose text-white ring-ella-rose' : 'bg-white ring-ella-line'
                }`}
              >
                {m.rotulo}
              </button>
            ))}
          </div>
          <div className="mt-4 flex gap-2">
            <button
              type="button"
              disabled={pendente}
              onClick={() => executar(() => registrarSinal(reservaId, meio), 'Sinal registrado e agendamento confirmado.')}
              className="btn-primario !py-2.5 text-sm"
            >
              {pendente ? 'Salvando…' : 'Confirmar recebimento'}
            </button>
            <button type="button" onClick={() => setPainel(null)} className="btn-secundario !py-2.5 text-sm">
              Voltar
            </button>
          </div>
        </div>
      )}

      {painel === 'cancelar' && (
        <div className="mt-5 rounded-2xl bg-rose-50 p-4">
          <label htmlFor="motivo" className="text-sm text-rose-900">
            Motivo do cancelamento (opcional)
          </label>
          <input
            id="motivo"
            value={motivo}
            onChange={(e) => setMotivo(e.target.value)}
            placeholder="Ex.: cliente pediu para remarcar"
            className="campo mt-2"
          />
          <p className="mt-2 text-xs text-rose-900/80">
            Se houver sinal pago, o sistema aplica a regra de cancelamento (crédito ou estorno) automaticamente.
          </p>
          <div className="mt-4 flex gap-2">
            <button
              type="button"
              disabled={pendente}
              onClick={() => executar(() => cancelarReserva(reservaId, estado, motivo), 'Agendamento cancelado.')}
              className="inline-flex items-center rounded-full bg-rose-700 px-5 py-2.5 text-sm font-medium text-white hover:bg-rose-800 disabled:opacity-50"
            >
              {pendente ? 'Cancelando…' : 'Confirmar cancelamento'}
            </button>
            <button type="button" onClick={() => setPainel(null)} className="btn-secundario !py-2.5 text-sm">
              Voltar
            </button>
          </div>
        </div>
      )}

      {msg && (
        <p
          role="status"
          className={`mt-4 rounded-2xl p-3 text-sm ${
            msg.tipo === 'ok' ? 'bg-emerald-50 text-emerald-800' : 'bg-red-50 text-red-800'
          }`}
        >
          {msg.texto}
        </p>
      )}
    </section>
  )
}
