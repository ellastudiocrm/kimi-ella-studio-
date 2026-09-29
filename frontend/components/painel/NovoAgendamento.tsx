'use client'

import { useEffect, useMemo, useRef, useState, useTransition } from 'react'
import { useRouter } from 'next/navigation'
import { buscarClientes, criarAgendamento, type MeioPagamento } from '@/app/dashboard/acoes'
import { IconeCheck, IconePessoa } from '@/components/Icones'
import { MEIOS, telefoneExibicao } from '@/lib/estados'
import {
  dataDoSlot,
  formatarDataLonga,
  formatarDuracao,
  formatarHora,
  formatarPreco,
  type Cardapio,
} from '@/lib/marca'
import type { ServicoCatalogo } from '@/lib/catalogo'
import type { ProfissionalAgenda } from '@/lib/painel'
import type { SlotHorario } from '@/types'

type ClienteEscolhido = { id: string; nome: string; telefone: string } | { novo: true; nome: string; telefone: string }

function mascara(valor: string) {
  const d = valor.replace(/\D/g, '').slice(0, 11)
  if (d.length <= 2) return d
  if (d.length <= 6) return `(${d.slice(0, 2)}) ${d.slice(2)}`
  if (d.length <= 10) return `(${d.slice(0, 2)}) ${d.slice(2, 6)}-${d.slice(6)}`
  return `(${d.slice(0, 2)}) ${d.slice(2, 7)}-${d.slice(7)}`
}

function Etapa({ n, titulo, feito, children }: { n: number; titulo: string; feito: boolean; children: React.ReactNode }) {
  return (
    <section className="rounded-3xl border border-ella-line bg-white p-5 sm:p-6">
      <h2 className="flex items-center gap-3 font-medium">
        <span
          className={`flex h-7 w-7 items-center justify-center rounded-full text-xs ${
            feito ? 'bg-ella-rose text-white' : 'bg-ella-soft text-ella-rose'
          }`}
        >
          {feito ? <IconeCheck className="h-4 w-4" /> : n}
        </span>
        {titulo}
      </h2>
      <div className="mt-4">{children}</div>
    </section>
  )
}

export default function NovoAgendamento({
  servicos,
  profissionais,
  porServico,
  dataInicial,
  hoje,
  empresaId,
}: {
  servicos: Record<Cardapio, ServicoCatalogo[]>
  profissionais: ProfissionalAgenda[]
  porServico: Record<string, string[]>
  dataInicial: string
  hoje: string
  empresaId: string
}) {
  const router = useRouter()
  const [salvando, iniciar] = useTransition()
  const chave = useRef(`painel-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`)

  // 1. Cliente
  const [cliente, setCliente] = useState<ClienteEscolhido | null>(null)
  const [busca, setBusca] = useState('')
  const [resultados, setResultados] = useState<{ id: string; nome: string; telefone: string }[]>([])
  const [modoNovo, setModoNovo] = useState(false)
  const [novoNome, setNovoNome] = useState('')
  const [novoTel, setNovoTel] = useState('')

  useEffect(() => {
    if (modoNovo || busca.trim().length < 2) {
      setResultados([])
      return
    }
    const t = setTimeout(async () => setResultados(await buscarClientes(busca)), 250)
    return () => clearTimeout(t)
  }, [busca, modoNovo])

  // 2. Serviço
  const [cardapio, setCardapio] = useState<Cardapio>('ella_studio')
  const [servicoId, setServicoId] = useState('')
  const servico = servicos[cardapio].find((s) => s.id === servicoId) ?? null

  // 3. Profissional
  const habilitadas = useMemo(
    () => profissionais.filter((p) => servicoId && (porServico[servicoId] ?? []).includes(p.id)),
    [profissionais, porServico, servicoId]
  )
  const [profissionalId, setProfissionalId] = useState('')
  useEffect(() => {
    setProfissionalId(habilitadas.length === 1 ? habilitadas[0].id : '')
  }, [habilitadas])

  // 4. Dia e horário
  const [data, setData] = useState(dataInicial)
  const [slots, setSlots] = useState<SlotHorario[] | null>(null)
  const [horario, setHorario] = useState('')
  const [carregandoSlots, setCarregandoSlots] = useState(false)

  useEffect(() => {
    setHorario('')
    if (!servicoId || !profissionalId || !data) {
      setSlots(null)
      return
    }
    let cancelado = false
    setCarregandoSlots(true)
    fetch('/api/horarios', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        empresa_id: empresaId,
        servico_id: servicoId,
        profissional_id: profissionalId,
        data,
        cardapio,
      }),
    })
      .then((r) => r.json())
      .then((corpo) => {
        if (cancelado) return
        const agora = Date.now()
        setSlots(
          Array.isArray(corpo)
            ? corpo.filter((s: SlotHorario) => dataDoSlot(s.inicio) === data && new Date(s.inicio).getTime() > agora)
            : []
        )
      })
      .catch(() => !cancelado && setSlots([]))
      .finally(() => !cancelado && setCarregandoSlots(false))
    return () => {
      cancelado = true
    }
  }, [servicoId, profissionalId, data, cardapio, empresaId])

  // 5. Sinal
  const [sinal, setSinal] = useState<MeioPagamento | null>(null)
  const [erro, setErro] = useState<string | null>(null)

  const clienteOk = !!cliente
  const pronto = clienteOk && !!servico && !!profissionalId && !!horario

  function salvar() {
    if (!pronto || !cliente || !servico) return
    setErro(null)
    iniciar(async () => {
      const r = await criarAgendamento({
        cliente: 'id' in cliente ? { id: cliente.id } : { nome: cliente.nome, telefone: cliente.telefone },
        servicoId: servico.id,
        profissionalId,
        inicio: horario,
        cardapio,
        chave: chave.current,
        sinal,
      })
      if (!r.ok) {
        setErro(r.erro)
        return
      }
      router.push(`/dashboard/agenda?data=${data}${r.aviso ? `&aviso=${encodeURIComponent(r.aviso)}` : ''}`)
    })
  }

  return (
    <div className="mt-6 grid gap-6 lg:grid-cols-[1fr_320px]">
      <div className="space-y-4">
        <Etapa n={1} titulo="Cliente" feito={clienteOk}>
          {cliente ? (
            <div className="flex items-center justify-between gap-3 rounded-2xl bg-ella-card px-4 py-3">
              <div>
                <p className="font-medium">{cliente.nome}</p>
                <p className="text-sm text-ella-muted">
                  {telefoneExibicao(cliente.telefone)}
                  {'novo' in cliente && ' · cliente novo'}
                </p>
              </div>
              <button type="button" onClick={() => setCliente(null)} className="text-sm text-ella-rose hover:underline">
                Trocar
              </button>
            </div>
          ) : modoNovo ? (
            <div className="grid gap-3 sm:grid-cols-2">
              <input
                value={novoNome}
                onChange={(e) => setNovoNome(e.target.value)}
                placeholder="Nome do cliente"
                className="campo"
                autoFocus
              />
              <input
                value={novoTel}
                onChange={(e) => setNovoTel(mascara(e.target.value))}
                placeholder="WhatsApp (19) 99999-9999"
                inputMode="numeric"
                className="campo"
              />
              <div className="flex gap-2 sm:col-span-2">
                <button
                  type="button"
                  disabled={novoNome.trim().length < 2 || novoTel.replace(/\D/g, '').length < 10}
                  onClick={() => setCliente({ novo: true, nome: novoNome.trim(), telefone: novoTel })}
                  className="btn-primario !py-2.5 text-sm"
                >
                  Usar este cliente
                </button>
                <button type="button" onClick={() => setModoNovo(false)} className="btn-secundario !py-2.5 text-sm">
                  Buscar cadastrado
                </button>
              </div>
            </div>
          ) : (
            <div>
              <input
                value={busca}
                onChange={(e) => setBusca(e.target.value)}
                placeholder="Buscar por nome ou telefone"
                className="campo"
              />
              {resultados.length > 0 && (
                <ul className="mt-2 divide-y divide-ella-line overflow-hidden rounded-2xl border border-ella-line">
                  {resultados.map((c) => (
                    <li key={c.id}>
                      <button
                        type="button"
                        onClick={() => setCliente(c)}
                        className="flex w-full items-center gap-3 px-4 py-3 text-left hover:bg-ella-light"
                      >
                        <IconePessoa className="h-5 w-5 text-ella-rose" />
                        <span className="flex-1">
                          <span className="block text-sm font-medium">{c.nome}</span>
                          <span className="block text-xs text-ella-muted">{telefoneExibicao(c.telefone)}</span>
                        </span>
                      </button>
                    </li>
                  ))}
                </ul>
              )}
              {busca.trim().length >= 2 && resultados.length === 0 && (
                <p className="mt-2 text-sm text-ella-muted">Nenhum cliente encontrado.</p>
              )}
              <button
                type="button"
                onClick={() => {
                  setModoNovo(true)
                  if (!/\d/.test(busca)) setNovoNome(busca)
                  else setNovoTel(mascara(busca))
                }}
                className="mt-3 text-sm font-medium text-ella-rose hover:underline"
              >
                + Cadastrar cliente novo
              </button>
            </div>
          )}
        </Etapa>

        <Etapa n={2} titulo="Serviço" feito={!!servico}>
          <div className="mb-3 inline-flex rounded-full border border-ella-line p-1 text-sm">
            {(['ella_studio', 'ella_men'] as const).map((c) => (
              <button
                key={c}
                type="button"
                onClick={() => {
                  setCardapio(c)
                  setServicoId('')
                }}
                className={`rounded-full px-4 py-1.5 ${cardapio === c ? 'bg-ella-rose text-white' : ''}`}
              >
                {c === 'ella_studio' ? 'ELLA Studio' : 'ELLA MEN'}
              </button>
            ))}
          </div>
          <div className="grid gap-2 sm:grid-cols-2">
            {servicos[cardapio].map((s) => (
              <button
                key={s.id}
                type="button"
                onClick={() => setServicoId(s.id)}
                className={`flex items-center justify-between gap-2 rounded-2xl px-4 py-3 text-left text-sm ring-1 transition ${
                  servicoId === s.id ? 'bg-ella-soft ring-ella-rose' : 'bg-white ring-ella-line hover:ring-ella-blush'
                }`}
              >
                <span>
                  <span className="block font-medium">{s.nome}</span>
                  <span className="text-xs text-ella-muted">{formatarDuracao(s.duracaoMinutos)}</span>
                </span>
                <span className="font-medium text-ella-rose">{formatarPreco(s.preco)}</span>
              </button>
            ))}
          </div>
        </Etapa>

        <Etapa n={3} titulo="Profissional" feito={!!profissionalId}>
          {!servico ? (
            <p className="text-sm text-ella-muted">Escolha o serviço primeiro.</p>
          ) : habilitadas.length === 0 ? (
            <p className="text-sm text-ella-muted">Nenhuma profissional faz este serviço.</p>
          ) : (
            <div className="flex flex-wrap gap-2">
              {habilitadas.map((p) => (
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
          )}
        </Etapa>

        <Etapa n={4} titulo="Dia e horário" feito={!!horario}>
          <input
            type="date"
            min={hoje}
            value={data}
            onChange={(e) => setData(e.target.value)}
            className="campo max-w-xs"
          />
          {data && <p className="mt-2 text-sm text-ella-muted first-letter:uppercase">{formatarDataLonga(data)}</p>}
          <div className="mt-4">
            {!servico || !profissionalId ? (
              <p className="text-sm text-ella-muted">Escolha serviço e profissional para ver os horários.</p>
            ) : carregandoSlots ? (
              <div className="grid grid-cols-4 gap-2 sm:grid-cols-6">
                {Array.from({ length: 12 }).map((_, i) => (
                  <span key={i} className="h-10 animate-pulse rounded-xl bg-ella-soft" />
                ))}
              </div>
            ) : slots && slots.length === 0 ? (
              <p className="text-sm text-ella-muted">Sem horários livres neste dia.</p>
            ) : (
              <div className="grid grid-cols-4 gap-2 sm:grid-cols-6">
                {(slots ?? []).map((s) => (
                  <button
                    key={s.inicio}
                    type="button"
                    onClick={() => setHorario(s.inicio)}
                    className={`h-10 rounded-xl text-sm font-medium ring-1 ${
                      horario === s.inicio ? 'bg-ella-rose text-white ring-ella-rose' : 'bg-white ring-ella-line hover:ring-ella-rose'
                    }`}
                  >
                    {formatarHora(s.inicio)}
                  </button>
                ))}
              </div>
            )}
          </div>
        </Etapa>

        <Etapa n={5} titulo="Sinal" feito={!!sinal}>
          <p className="text-sm text-ella-muted">
            O cliente já pagou o sinal
            {servico ? ` de ${formatarPreco((servico.preco * servico.percentualSinal) / 100)}` : ''}? Sem sinal, o
            horário fica reservado só por um tempo e depois é liberado.
          </p>
          <div className="mt-3 flex flex-wrap gap-2">
            <button
              type="button"
              onClick={() => setSinal(null)}
              className={`rounded-full px-4 py-2 text-sm ring-1 ${!sinal ? 'bg-ella-dark text-white ring-ella-dark' : 'bg-white ring-ella-line'}`}
            >
              Ainda não
            </button>
            {MEIOS.map((m) => (
              <button
                key={m.valor}
                type="button"
                onClick={() => setSinal(m.valor)}
                className={`rounded-full px-4 py-2 text-sm ring-1 ${
                  sinal === m.valor ? 'bg-ella-rose text-white ring-ella-rose' : 'bg-white ring-ella-line'
                }`}
              >
                Pago · {m.rotulo}
              </button>
            ))}
          </div>
        </Etapa>
      </div>

      {/* Resumo */}
      <aside className="h-fit rounded-3xl border border-ella-line bg-white p-5 lg:sticky lg:top-8">
        <p className="eyebrow">Resumo</p>
        <dl className="mt-4 space-y-3 text-sm">
          <div>
            <dt className="text-ella-muted">Cliente</dt>
            <dd className="font-medium">{cliente?.nome ?? '—'}</dd>
          </div>
          <div>
            <dt className="text-ella-muted">Serviço</dt>
            <dd className="font-medium">{servico?.nome ?? '—'}</dd>
          </div>
          <div>
            <dt className="text-ella-muted">Profissional</dt>
            <dd className="font-medium">{profissionais.find((p) => p.id === profissionalId)?.nome ?? '—'}</dd>
          </div>
          <div>
            <dt className="text-ella-muted">Quando</dt>
            <dd className="font-medium first-letter:uppercase">
              {horario ? `${formatarDataLonga(data)} às ${formatarHora(horario)}` : '—'}
            </dd>
          </div>
          {servico && (
            <div className="flex items-baseline justify-between border-t border-ella-line pt-3">
              <dt className="text-ella-muted">Valor</dt>
              <dd className="font-serif text-2xl font-semibold text-ella-rose">{formatarPreco(servico.preco)}</dd>
            </div>
          )}
        </dl>
        {erro && <p className="mt-4 rounded-2xl bg-red-50 p-3 text-sm text-red-800">{erro}</p>}
        <button type="button" disabled={!pronto || salvando} onClick={salvar} className="btn-primario mt-5 w-full">
          {salvando ? 'Agendando…' : 'Confirmar agendamento'}
        </button>
      </aside>
    </div>
  )
}
