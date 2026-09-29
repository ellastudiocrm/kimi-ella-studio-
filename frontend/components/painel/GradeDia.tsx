import Link from 'next/link'
import { estado, TIPOS_BLOQUEIO } from '@/lib/estados'
import { formatarHora, hojeSaoPaulo, minutosDoDia } from '@/lib/marca'
import type { BloqueioAgenda, ItemAgenda, ProfissionalAgenda } from '@/lib/painel'
import LinhaAgora from '@/components/painel/LinhaAgora'

const PX_POR_HORA = 88

export default function GradeDia({
  data,
  profissionais,
  itens,
  bloqueios,
  abre,
  fecha,
  aberto,
}: {
  data: string
  profissionais: ProfissionalAgenda[]
  itens: ItemAgenda[]
  bloqueios: BloqueioAgenda[]
  abre: number
  fecha: number
  aberto: boolean
}) {
  // Amplia a faixa se houver atendimento fora do horário padrão
  const minutos = [...itens, ...bloqueios].flatMap((x) => [minutosDoDia(x.inicio), minutosDoDia(x.fim)])
  const inicioGrade = Math.min(abre, ...minutos.map((m) => Math.floor(m / 60)))
  const fimGrade = Math.max(fecha, ...minutos.map((m) => Math.ceil(m / 60)))
  const horas = Array.from({ length: fimGrade - inicioGrade }, (_, i) => inicioGrade + i)
  const altura = horas.length * PX_POR_HORA
  const topo = (iso: string) => ((minutosDoDia(iso) - inicioGrade * 60) / 60) * PX_POR_HORA
  const tamanho = (a: string, b: string) => Math.max(((minutosDoDia(b) - minutosDoDia(a)) / 60) * PX_POR_HORA, 28)

  return (
    <div className="mt-5 overflow-hidden rounded-3xl border border-ella-line bg-white">
      {!aberto && (
        <p className="border-b border-ella-line bg-ella-card px-5 py-2.5 text-sm text-ella-muted">
          O estúdio não abre neste dia.
        </p>
      )}
      <div className="overflow-x-auto">
        <div style={{ minWidth: 56 + profissionais.length * 200 }}>
          {/* Cabeçalho das colunas */}
          {profissionais.length > 1 && (
            <div className="sticky top-0 z-10 flex border-b border-ella-line bg-white">
              <div className="w-14 shrink-0" />
              {profissionais.map((p) => (
                <div key={p.id} className="flex-1 border-l border-ella-line px-3 py-3 text-sm font-medium">
                  {p.nome}
                </div>
              ))}
            </div>
          )}

          <div className="relative flex" style={{ height: altura }}>
            {/* Régua de horas */}
            <div className="w-14 shrink-0">
              {horas.map((h) => (
                <div key={h} className="relative text-right text-xs text-ella-muted" style={{ height: PX_POR_HORA }}>
                  <span className="absolute -top-2 right-2 bg-white px-1">{h}h</span>
                </div>
              ))}
            </div>

            {profissionais.map((p) => (
              <div key={p.id} className="relative flex-1 border-l border-ella-line">
                {horas.map((h) => (
                  <div key={h} className="border-t border-ella-line/60" style={{ height: PX_POR_HORA }}>
                    <div className="h-1/2 border-b border-dashed border-ella-line/40" />
                  </div>
                ))}

                {bloqueios
                  .filter((b) => b.profissionalId === p.id)
                  .map((b) => (
                    <div
                      key={b.id}
                      className="absolute inset-x-1 overflow-hidden rounded-lg border border-dashed border-stone-300 bg-[repeating-linear-gradient(135deg,#f5f0ee_0,#f5f0ee_6px,#fff_6px,#fff_12px)] px-2 py-1 text-xs text-stone-600"
                      style={{ top: topo(b.inicio), height: tamanho(b.inicio, b.fim) }}
                      title={b.motivo ?? undefined}
                    >
                      <span className="font-medium">{TIPOS_BLOQUEIO[b.tipo] ?? b.tipo}</span>
                      {b.motivo && <span className="text-stone-500"> · {b.motivo}</span>}
                    </div>
                  ))}

                {itens
                  .filter((i) => i.profissionalId === p.id)
                  .map((i) => {
                    const e = estado(i.estadoReserva)
                    const h = tamanho(i.inicio, i.fim)
                    return (
                      <Link
                        key={i.id}
                        href={`/dashboard/atendimento/${i.id}`}
                        className={`absolute inset-x-1 overflow-hidden rounded-lg border-l-4 px-2.5 py-1.5 text-xs shadow-sm transition hover:z-10 hover:shadow-suave ${e.bloco}`}
                        style={{ top: topo(i.inicio), height: h }}
                      >
                        <p className="truncate font-medium text-ella-dark">
                          {formatarHora(i.inicio)} · {i.cliente.nome}
                        </p>
                        {h > 40 && <p className="truncate text-ella-muted">{i.servico}</p>}
                        {h > 60 && <p className="truncate text-[11px] text-ella-muted">{e.rotulo}</p>}
                      </Link>
                    )
                  })}
              </div>
            ))}

            {data === hojeSaoPaulo() && <LinhaAgora inicioGrade={inicioGrade} pxPorHora={PX_POR_HORA} />}
          </div>
        </div>
      </div>
    </div>
  )
}
