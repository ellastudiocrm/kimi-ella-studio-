import Link from 'next/link'
import { estado, TIPOS_BLOQUEIO } from '@/lib/estados'
import { dataDoSlot, formatarDataCurta, formatarHora, somarDias } from '@/lib/marca'
import type { BloqueioAgenda, ItemAgenda, ProfissionalAgenda } from '@/lib/painel'

export default function GradeSemana({
  segunda,
  hoje,
  profissionais,
  itens,
  bloqueios,
  diasAbertos,
  mostrarProfissional,
}: {
  segunda: string
  hoje: string
  profissionais: ProfissionalAgenda[]
  itens: ItemAgenda[]
  bloqueios: BloqueioAgenda[]
  diasAbertos: number[]
  mostrarProfissional: boolean
}) {
  const nomes = new Map(profissionais.map((p) => [p.id, p.nome]))
  const ids = new Set(profissionais.map((p) => p.id))
  const dias = Array.from({ length: 7 }, (_, i) => somarDias(segunda, i))
    // Esconde domingo/segunda se o estúdio fecha e não há nada marcado
    .filter((d, i) => {
      const dow = (i + 1) % 7
      return diasAbertos.includes(dow) || itens.some((x) => dataDoSlot(x.inicio) === d)
    })

  return (
    <div
      className="mt-5 grid gap-3 md:grid-cols-3 xl:[grid-template-columns:repeat(var(--dias),minmax(0,1fr))]"
      style={{ '--dias': dias.length } as React.CSSProperties}
    >
      {dias.map((d) => {
        const doDia = itens.filter((i) => dataDoSlot(i.inicio) === d && (!i.profissionalId || ids.has(i.profissionalId)))
        const blq = bloqueios.filter((b) => dataDoSlot(b.inicio) === d && b.profissionalId && ids.has(b.profissionalId))
        const ehHoje = d === hoje
        return (
          <section
            key={d}
            className={`flex min-h-[160px] flex-col rounded-3xl border bg-white ${
              ehHoje ? 'border-ella-rose ring-2 ring-ella-rose/15' : 'border-ella-line'
            }`}
          >
            <Link
              href={`/dashboard/agenda?data=${d}`}
              className="flex items-baseline justify-between border-b border-ella-line px-4 py-3 hover:bg-ella-light"
            >
              <span className={`font-medium capitalize ${ehHoje ? 'text-ella-rose' : ''}`}>{formatarDataCurta(d)}</span>
              <span className="text-xs text-ella-muted">
                {doDia.length || '—'} {doDia.length === 1 ? 'horário' : doDia.length ? 'horários' : ''}
              </span>
            </Link>
            <div className="flex-1 space-y-2 p-3">
              {blq.map((b) => (
                <div key={b.id} className="rounded-xl border border-dashed border-stone-300 px-3 py-2 text-xs text-stone-600">
                  {formatarHora(b.inicio)}–{formatarHora(b.fim)} · {TIPOS_BLOQUEIO[b.tipo] ?? b.tipo}
                  {mostrarProfissional && b.profissionalId && ` · ${nomes.get(b.profissionalId)}`}
                </div>
              ))}
              {doDia.map((i) => {
                const e = estado(i.estadoReserva)
                return (
                  <Link
                    key={i.id}
                    href={`/dashboard/atendimento/${i.id}`}
                    className={`block rounded-xl border-l-4 px-3 py-2 text-sm transition hover:shadow-suave ${e.bloco}`}
                  >
                    <p className="font-medium">
                      {formatarHora(i.inicio)} · <span className="text-ella-dark">{i.cliente.nome}</span>
                    </p>
                    <p className="truncate text-xs text-ella-muted">
                      {i.servico}
                      {mostrarProfissional && i.profissionalId && ` · ${nomes.get(i.profissionalId)}`}
                    </p>
                  </Link>
                )
              })}
              {doDia.length === 0 && blq.length === 0 && <p className="px-1 py-2 text-xs text-ella-muted">Livre</p>}
            </div>
          </section>
        )
      })}
    </div>
  )
}
