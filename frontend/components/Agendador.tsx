'use client'

import { useCallback, useEffect, useMemo, useState } from 'react'
import Link from 'next/link'
import Passos from '@/components/Passos'
import ResumoServico from '@/components/ResumoServico'
import { IconeSeta, IconeVoltar, IconeWhatsApp } from '@/components/Icones'
import {
  dataDoSlot,
  formatarDataLonga,
  formatarHora,
  hojeSaoPaulo,
  linkWhatsApp,
  type Cardapio,
} from '@/lib/marca'
import type { ServicoCatalogo } from '@/lib/catalogo'
import type { SlotHorario } from '@/types'

const MESES = [
  'Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho',
  'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro',
]
const SEMANA = ['D', 'S', 'T', 'Q', 'Q', 'S', 'S']
const SEMANA_LONGA = ['Domingo', 'Segunda', 'Terça', 'Quarta', 'Quinta', 'Sexta', 'Sábado']

// Até quantos meses à frente o calendário deixa navegar.
const MESES_A_FRENTE = 3

function iso(ano: number, mes: number, dia: number) {
  return `${ano}-${String(mes + 1).padStart(2, '0')}-${String(dia).padStart(2, '0')}`
}

function diaDaSemana(ano: number, mes: number, dia: number) {
  return new Date(Date.UTC(ano, mes, dia)).getUTCDay()
}

export default function Agendador({
  cardapio,
  servico,
  profissional,
  diasAbertos,
  empresaId,
}: {
  cardapio: Cardapio
  servico: ServicoCatalogo
  profissional: { id: string; nome: string }
  diasAbertos: number[]
  empresaId: string
}) {
  const hoje = hojeSaoPaulo()
  const [anoHoje, mesHoje] = hoje.split('-').map(Number)

  const [ano, setAno] = useState(anoHoje)
  const [mes, setMes] = useState(mesHoje - 1)
  const [data, setData] = useState<string>('')
  const [slots, setSlots] = useState<SlotHorario[]>([])
  const [carregando, setCarregando] = useState(false)
  const [erro, setErro] = useState<string | null>(null)
  const [horario, setHorario] = useState<string>('')

  const podeVoltarMes = ano > anoHoje || mes > mesHoje - 1
  const podeAvancarMes = (ano - anoHoje) * 12 + (mes - (mesHoje - 1)) < MESES_A_FRENTE

  const diaAberto = useCallback(
    (a: number, m: number, d: number) => diasAbertos.includes(diaDaSemana(a, m, d)),
    [diasAbertos]
  )

  const buscarHorarios = useCallback(
    async (dia: string) => {
      setData(dia)
      setHorario('')
      setErro(null)
      setCarregando(true)
      try {
        const resposta = await fetch('/api/horarios', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            empresa_id: empresaId,
            servico_id: servico.id,
            profissional_id: profissional.id,
            data: dia,
            cardapio,
          }),
        })
        const corpo = await resposta.json()
        if (!resposta.ok || !Array.isArray(corpo)) {
          setSlots([])
          setErro('Não foi possível consultar os horários agora.')
        } else {
          // Garante que só entram horários do dia escolhido e ainda não passados
          const agora = Date.now()
          setSlots(
            corpo.filter(
              (s: SlotHorario) => dataDoSlot(s.inicio) === dia && new Date(s.inicio).getTime() > agora
            )
          )
        }
      } catch {
        setSlots([])
        setErro('Não foi possível consultar os horários agora.')
      }
      setCarregando(false)
    },
    [cardapio, empresaId, profissional.id, servico.id]
  )

  // Já abre com o primeiro dia disponível selecionado
  useEffect(() => {
    const [a, m, d] = hoje.split('-').map(Number)
    for (let i = 0; i < 14; i++) {
      const dt = new Date(Date.UTC(a, m - 1, d + i))
      if (diasAbertos.includes(dt.getUTCDay())) {
        buscarHorarios(iso(dt.getUTCFullYear(), dt.getUTCMonth(), dt.getUTCDate()))
        return
      }
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  const dias = useMemo(() => {
    const vazios = diaDaSemana(ano, mes, 1)
    const total = new Date(Date.UTC(ano, mes + 1, 0)).getUTCDate()
    return [...Array(vazios).fill(null), ...Array.from({ length: total }, (_, i) => i + 1)] as (number | null)[]
  }, [ano, mes])

  const periodos = useMemo(() => {
    const grupos: { nome: string; itens: SlotHorario[] }[] = [
      { nome: 'Manhã', itens: [] },
      { nome: 'Tarde', itens: [] },
      { nome: 'Noite', itens: [] },
    ]
    for (const s of slots) {
      const hora = Number(formatarHora(s.inicio).slice(0, 2))
      grupos[hora < 12 ? 0 : hora < 18 ? 1 : 2].itens.push(s)
    }
    return grupos.filter((g) => g.itens.length > 0)
  }, [slots])

  function mudarMes(delta: number) {
    const novo = new Date(Date.UTC(ano, mes + delta, 1))
    setAno(novo.getUTCFullYear())
    setMes(novo.getUTCMonth())
  }

  const linkContinuar = horario
    ? `/confirmacao?profissional=${profissional.id}&servico=${encodeURIComponent(servico.nomeTecnico)}&data=${data}&hora=${encodeURIComponent(horario)}&cardapio=${cardapio}`
    : ''

  const quando = data ? `${formatarDataLonga(data)}${horario ? ` às ${formatarHora(horario)}` : ''}` : null

  return (
    <div className="container-ella pb-32 pt-8 sm:pt-12 lg:pb-12">
      <Link
        href={`/${cardapio}`}
        className="mb-6 inline-flex items-center gap-2 text-sm text-ella-muted hover:text-ella-rose"
      >
        <IconeVoltar className="h-4 w-4" />
        Trocar serviço
      </Link>
      <Passos atual={2} />
      <h1 className="mt-6 font-serif text-3xl font-medium sm:text-4xl">Escolha o dia e o horário</h1>

      <div className="mt-8 grid gap-6 lg:grid-cols-[1fr_340px] lg:gap-8">
        <div className="grid gap-6 md:grid-cols-2">
          {/* Calendário */}
          <section className="rounded-3xl border border-ella-line/70 bg-white p-5 sm:p-6" aria-label="Calendário">
            <div className="mb-4 flex items-center justify-between">
              <button
                type="button"
                onClick={() => mudarMes(-1)}
                disabled={!podeVoltarMes}
                className="flex h-10 w-10 items-center justify-center rounded-full text-ella-dark transition hover:bg-ella-soft disabled:opacity-25"
                aria-label="Mês anterior"
              >
                <IconeVoltar className="h-4 w-4" />
              </button>
              <p className="font-serif text-xl font-medium">
                {MESES[mes]} <span className="text-ella-muted">{ano}</span>
              </p>
              <button
                type="button"
                onClick={() => mudarMes(1)}
                disabled={!podeAvancarMes}
                className="flex h-10 w-10 items-center justify-center rounded-full text-ella-dark transition hover:bg-ella-soft disabled:opacity-25"
                aria-label="Próximo mês"
              >
                <IconeSeta className="h-4 w-4" />
              </button>
            </div>

            <div className="grid grid-cols-7 gap-1 text-center">
              {SEMANA.map((d, i) => (
                <span key={i} className="py-2 text-xs font-medium text-ella-muted" title={SEMANA_LONGA[i]}>
                  {d}
                </span>
              ))}
              {dias.map((dia, i) => {
                if (dia === null) return <span key={`v${i}`} />
                const valor = iso(ano, mes, dia)
                const passado = valor < hoje
                const fechado = !diaAberto(ano, mes, dia)
                const desabilitado = passado || fechado
                const selecionado = valor === data
                const ehHoje = valor === hoje
                return (
                  <button
                    key={valor}
                    type="button"
                    disabled={desabilitado}
                    onClick={() => buscarHorarios(valor)}
                    aria-pressed={selecionado}
                    aria-label={formatarDataLonga(valor)}
                    className={`relative mx-auto flex aspect-square w-full max-w-[44px] items-center justify-center rounded-full text-sm transition ${
                      selecionado
                        ? 'bg-ella-rose font-medium text-white shadow-suave'
                        : desabilitado
                          ? 'cursor-not-allowed text-ella-muted/35'
                          : 'font-medium text-ella-dark hover:bg-ella-soft'
                    }`}
                  >
                    {dia}
                    {ehHoje && !selecionado && (
                      <span className="absolute bottom-1 h-1 w-1 rounded-full bg-ella-rose" />
                    )}
                  </button>
                )
              })}
            </div>
            <p className="mt-4 text-xs text-ella-muted">
              Atendemos:{' '}
              {[...diasAbertos]
                .sort((a, b) => a - b)
                .map((d) => SEMANA_LONGA[d].toLowerCase())
                .join(', ')}
              .
            </p>
          </section>

          {/* Horários */}
          <section className="rounded-3xl border border-ella-line/70 bg-white p-5 sm:p-6" aria-live="polite">
            {!data ? (
              <p className="text-ella-muted">Escolha um dia no calendário.</p>
            ) : (
              <>
                <p className="font-serif text-xl font-medium first-letter:uppercase">{formatarDataLonga(data)}</p>
                {carregando ? (
                  <div className="mt-5 grid grid-cols-3 gap-2">
                    {Array.from({ length: 9 }).map((_, i) => (
                      <span key={i} className="h-11 animate-pulse rounded-xl bg-ella-soft" />
                    ))}
                  </div>
                ) : erro ? (
                  <div className="mt-4 text-sm text-ella-muted">
                    <p>{erro}</p>
                    <div className="mt-4 flex flex-wrap gap-2">
                      <button type="button" onClick={() => buscarHorarios(data)} className="btn-secundario !py-2.5 text-sm">
                        Tentar de novo
                      </button>
                      <a
                        href={linkWhatsApp(`Olá! Gostaria de agendar ${servico.nome} em ${formatarDataLonga(data)}.`)}
                        className="btn-primario !py-2.5 text-sm"
                      >
                        <IconeWhatsApp className="h-4 w-4" />
                        WhatsApp
                      </a>
                    </div>
                  </div>
                ) : periodos.length === 0 ? (
                  <p className="mt-4 text-sm text-ella-muted">
                    Não há horários livres neste dia. Que tal escolher outro dia?
                  </p>
                ) : (
                  <div className="mt-4 space-y-5">
                    {periodos.map((p) => (
                      <div key={p.nome}>
                        <p className="mb-2 text-xs font-medium uppercase tracking-[0.2em] text-ella-muted">{p.nome}</p>
                        <div className="grid grid-cols-3 gap-2 sm:grid-cols-4 md:grid-cols-3 xl:grid-cols-4">
                          {p.itens.map((s) => {
                            const ativo = horario === s.inicio
                            return (
                              <button
                                key={s.inicio}
                                type="button"
                                onClick={() => setHorario(s.inicio)}
                                aria-pressed={ativo}
                                className={`h-11 rounded-xl border text-sm font-medium transition ${
                                  ativo
                                    ? 'border-ella-rose bg-ella-rose text-white shadow-suave'
                                    : 'border-ella-line text-ella-dark hover:border-ella-rose hover:text-ella-rose'
                                }`}
                              >
                                {formatarHora(s.inicio)}
                              </button>
                            )
                          })}
                        </div>
                      </div>
                    ))}
                  </div>
                )}
              </>
            )}
          </section>
        </div>

        <div className="hidden lg:block">
          <ResumoServico servico={servico} cardapio={cardapio} profissional={profissional.nome} quando={quando} />
          <Link
            href={linkContinuar || '#'}
            aria-disabled={!horario}
            className={`btn-primario mt-4 w-full ${horario ? '' : 'pointer-events-none opacity-40'}`}
          >
            Continuar
            <IconeSeta className="h-4 w-4" />
          </Link>
        </div>
      </div>

      {/* Barra fixa no celular/tablet */}
      <div className="fixed inset-x-0 bottom-0 z-20 border-t border-ella-line bg-white/95 backdrop-blur lg:hidden">
        <div className="container-ella flex items-center gap-4 py-3">
          <div className="min-w-0 flex-1 text-sm">
            <p className="truncate font-medium">{servico.nome}</p>
            <p className="truncate text-ella-muted first-letter:uppercase">
              {quando ?? 'Escolha um dia'}
            </p>
          </div>
          <Link
            href={linkContinuar || '#'}
            aria-disabled={!horario}
            className={`btn-primario shrink-0 !px-5 ${horario ? '' : 'pointer-events-none opacity-40'}`}
          >
            Continuar
          </Link>
        </div>
      </div>
    </div>
  )
}
