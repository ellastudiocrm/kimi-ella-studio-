import Link from 'next/link'
import BarraAgenda from '@/components/painel/BarraAgenda'
import GradeDia from '@/components/painel/GradeDia'
import GradeSemana from '@/components/painel/GradeSemana'
import { IconeCadeado, IconeMais } from '@/components/Icones'
import { ocupaAgenda } from '@/lib/estados'
import { diaDaSemanaISO, hojeSaoPaulo, somarDias } from '@/lib/marca'
import { carregarAgenda, faixaDeHorario, limitesDoDia, profissionaisDaAgenda, usuarioAtual } from '@/lib/painel'

export const dynamic = 'force-dynamic'

export default async function AgendaPage({
  searchParams,
}: {
  searchParams: { data?: string; vista?: string; prof?: string; todas?: string; aviso?: string }
}) {
  const usuario = await usuarioAtual()
  const hoje = hojeSaoPaulo()
  const data = /^\d{4}-\d{2}-\d{2}$/.test(searchParams.data ?? '') ? searchParams.data! : hoje
  const vista = searchParams.vista === 'semana' ? 'semana' : 'dia'
  const mostrarTodas = searchParams.todas === '1'

  // Profissional vê só a própria agenda; a equipe pode filtrar
  const todasProfissionais = await profissionaisDaAgenda()
  const profissionais = usuario.equipe
    ? todasProfissionais
    : todasProfissionais.filter((p) => p.id === usuario.profissionalId)
  const filtro = usuario.equipe ? searchParams.prof ?? null : usuario.profissionalId
  const colunas = filtro ? profissionais.filter((p) => p.id === filtro) : profissionais

  // Semana de segunda a domingo
  const segunda = somarDias(data, -((diaDaSemanaISO(data) + 6) % 7))
  const inicio = vista === 'semana' ? limitesDoDia(segunda).inicio : limitesDoDia(data).inicio
  const fim = vista === 'semana' ? limitesDoDia(somarDias(segunda, 6)).fim : limitesDoDia(data).fim

  const [{ itens, bloqueios, erro }, faixa] = await Promise.all([
    carregarAgenda(inicio, fim, filtro),
    faixaDeHorario(),
  ])
  const visiveis = mostrarTodas ? itens : itens.filter((i) => ocupaAgenda(i.estadoReserva))

  const ativos = visiveis.filter((i) => i.estadoReserva !== 'realizada')
  const faturamento = visiveis.reduce((s, i) => s + (i.estadoReserva === 'cancelada' ? 0 : i.preco), 0)

  return (
    <div>
      <div className="flex flex-wrap items-end justify-between gap-4">
        <div>
          <p className="eyebrow">Agenda</p>
          <h1 className="mt-1 font-serif text-3xl font-medium sm:text-4xl">
            {vista === 'dia' ? 'Agenda do dia' : 'Agenda da semana'}
          </h1>
          <p className="mt-1 text-sm text-ella-muted">
            {ativos.length} {ativos.length === 1 ? 'atendimento' : 'atendimentos'}
            {faturamento > 0 &&
              ` · ${faturamento.toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' })} previstos`}
          </p>
        </div>
        {usuario.equipe && (
          <div className="flex gap-2">
            <Link href={`/dashboard/agenda/bloquear?data=${data}`} className="btn-secundario !px-4 !py-2.5 text-sm">
              <IconeCadeado className="h-4 w-4" />
              <span className="hidden sm:inline">Bloquear horário</span>
            </Link>
            <Link href={`/dashboard/agenda/novo?data=${data}`} className="btn-primario !px-4 !py-2.5 text-sm">
              <IconeMais className="h-4 w-4" />
              Novo agendamento
            </Link>
          </div>
        )}
      </div>

      <BarraAgenda
        data={data}
        hoje={hoje}
        vista={vista}
        profissionais={usuario.equipe ? profissionais : []}
        filtro={usuario.equipe ? filtro : null}
        mostrarTodas={mostrarTodas}
      />

      {searchParams.aviso && (
        <p className="mt-4 rounded-2xl border border-amber-200 bg-amber-50 p-4 text-sm text-amber-900">
          {searchParams.aviso}
        </p>
      )}

      {erro && (
        <p className="mt-4 rounded-2xl border border-red-200 bg-red-50 p-4 text-sm text-red-800">
          Não foi possível carregar a agenda: {erro}
        </p>
      )}

      {colunas.length === 0 ? (
        <p className="mt-8 rounded-2xl bg-white p-6 text-ella-muted">
          Nenhuma profissional com serviços cadastrados para mostrar na agenda.
        </p>
      ) : vista === 'dia' ? (
        <GradeDia
          data={data}
          profissionais={colunas}
          itens={visiveis}
          bloqueios={bloqueios}
          abre={faixa.abre}
          fecha={faixa.fecha}
          aberto={faixa.dias.includes(diaDaSemanaISO(data))}
        />
      ) : (
        <GradeSemana
          segunda={segunda}
          hoje={hoje}
          profissionais={colunas}
          itens={visiveis}
          bloqueios={bloqueios}
          diasAbertos={faixa.dias}
          mostrarProfissional={colunas.length > 1}
        />
      )}
    </div>
  )
}
