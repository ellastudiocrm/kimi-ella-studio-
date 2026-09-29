import Link from 'next/link'
import { IconeCalendario, IconeMais, IconeRelogio, IconeSeta } from '@/components/Icones'
import { estado, ocupaAgenda } from '@/lib/estados'
import { formatarDataLonga, formatarHora, formatarPreco, hojeSaoPaulo } from '@/lib/marca'
import { carregarAgenda, limitesDoDia, profissionaisDaAgenda, usuarioAtual } from '@/lib/painel'

export const dynamic = 'force-dynamic'

export default async function HojePage() {
  const usuario = await usuarioAtual()
  const hoje = hojeSaoPaulo()
  const { inicio, fim } = limitesDoDia(hoje)
  const filtro = usuario.equipe ? null : usuario.profissionalId

  const [{ itens, erro }, profissionais] = await Promise.all([
    carregarAgenda(inicio, fim, filtro),
    profissionaisDaAgenda(),
  ])
  const nomes = new Map(profissionais.map((p) => [p.id, p.nome]))
  const doDia = itens.filter((i) => ocupaAgenda(i.estadoReserva))
  const agora = Date.now()
  const proximo = doDia.find((i) => new Date(i.fim).getTime() > agora && i.estadoReserva !== 'realizada')

  const indicadores = [
    { rotulo: 'Atendimentos', valor: String(doDia.length) },
    { rotulo: 'Confirmados', valor: String(doDia.filter((i) => i.estadoReserva === 'confirmada').length) },
    { rotulo: 'Aguardando sinal', valor: String(doDia.filter((i) => i.estadoReserva === 'pre_reserva').length) },
    { rotulo: 'Previsto', valor: formatarPreco(doDia.reduce((s, i) => s + i.preco, 0)) },
  ]

  const hora = Number(formatarHora(new Date().toISOString()).slice(0, 2))
  const saudacao = hora < 12 ? 'Bom dia' : hora < 18 ? 'Boa tarde' : 'Boa noite'

  return (
    <div>
      <div className="flex flex-wrap items-end justify-between gap-4">
        <div>
          <p className="text-sm capitalize text-ella-muted">{formatarDataLonga(hoje)}</p>
          <h1 className="mt-1 font-serif text-3xl font-medium sm:text-4xl">
            {saudacao}, {usuario.nome.split(' ')[0]}
          </h1>
        </div>
        <div className="flex gap-2">
          <Link href="/dashboard/agenda" className="btn-secundario !px-4 !py-2.5 text-sm">
            <IconeCalendario className="h-4 w-4" />
            Ver agenda
          </Link>
          {usuario.equipe && (
            <Link href="/dashboard/agenda/novo" className="btn-primario !px-4 !py-2.5 text-sm">
              <IconeMais className="h-4 w-4" />
              Novo agendamento
            </Link>
          )}
        </div>
      </div>

      {erro && <p className="mt-4 rounded-2xl bg-red-50 p-4 text-sm text-red-800">Erro ao carregar: {erro}</p>}

      <div className="mt-6 grid grid-cols-2 gap-3 lg:grid-cols-4">
        {indicadores.map((k) => (
          <div key={k.rotulo} className="rounded-3xl border border-ella-line bg-white p-4 sm:p-5">
            <p className="text-xs text-ella-muted sm:text-sm">{k.rotulo}</p>
            <p className="mt-1 font-serif text-2xl font-semibold sm:text-3xl">{k.valor}</p>
          </div>
        ))}
      </div>

      <div className="mt-6 grid gap-6 lg:grid-cols-[380px_1fr]">
        {/* Próximo atendimento */}
        <section className="h-fit rounded-3xl bg-ella-rose p-6 text-white shadow-suave">
          <p className="text-sm text-white/80">Próximo atendimento</p>
          {proximo ? (
            <>
              <p className="mt-2 font-serif text-5xl font-medium">{formatarHora(proximo.inicio)}</p>
              <p className="mt-3 text-lg font-medium">{proximo.cliente.nome}</p>
              <p className="text-sm text-white/85">
                {proximo.servico}
                {usuario.equipe && proximo.profissionalId && ` · ${nomes.get(proximo.profissionalId) ?? ''}`}
              </p>
              <Link
                href={`/dashboard/atendimento/${proximo.id}`}
                className="mt-5 inline-flex items-center gap-2 rounded-full bg-white px-5 py-2.5 text-sm font-medium text-ella-rose-deep"
              >
                Abrir atendimento
                <IconeSeta className="h-4 w-4" />
              </Link>
            </>
          ) : (
            <p className="mt-3 font-serif text-2xl">Nenhum atendimento pela frente hoje.</p>
          )}
        </section>

        {/* Lista do dia */}
        <section className="rounded-3xl border border-ella-line bg-white">
          <h2 className="border-b border-ella-line px-5 py-4 font-medium">Agenda de hoje</h2>
          {doDia.length === 0 ? (
            <p className="px-5 py-10 text-center text-ella-muted">Nenhum atendimento marcado para hoje.</p>
          ) : (
            <ul className="divide-y divide-ella-line">
              {doDia.map((i) => {
                const e = estado(i.estadoReserva)
                const passou = new Date(i.fim).getTime() < agora
                return (
                  <li key={i.id}>
                    <Link
                      href={`/dashboard/atendimento/${i.id}`}
                      className={`flex items-center gap-4 px-5 py-4 transition hover:bg-ella-light ${passou ? 'opacity-60' : ''}`}
                    >
                      <div className="w-14 shrink-0 text-center">
                        <p className="font-serif text-xl font-semibold">{formatarHora(i.inicio)}</p>
                        <p className="flex items-center justify-center gap-1 text-[11px] text-ella-muted">
                          <IconeRelogio className="h-3 w-3" />
                          {formatarHora(i.fim)}
                        </p>
                      </div>
                      <div className="min-w-0 flex-1">
                        <p className="truncate font-medium">{i.cliente.nome}</p>
                        <p className="truncate text-sm text-ella-muted">
                          {i.servico}
                          {usuario.equipe && i.profissionalId && ` · ${nomes.get(i.profissionalId) ?? ''}`}
                        </p>
                      </div>
                      <span className={`hidden shrink-0 rounded-full px-2.5 py-1 text-xs ring-1 sm:inline ${e.cor}`}>
                        {e.rotulo}
                      </span>
                    </Link>
                  </li>
                )
              })}
            </ul>
          )}
        </section>
      </div>
    </div>
  )
}
