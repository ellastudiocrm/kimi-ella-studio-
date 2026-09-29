import Link from 'next/link'
import { notFound } from 'next/navigation'
import AcoesAtendimento from '@/components/painel/AcoesAtendimento'
import { IconeCalendario, IconePessoa, IconeRelogio, IconeVoltar, IconeWhatsApp } from '@/components/Icones'
import { estado, linkWhatsCliente, telefoneExibicao } from '@/lib/estados'
import { dataDoSlot, formatarDataLonga, formatarDuracao, formatarHora, formatarPreco } from '@/lib/marca'
import { usuarioAtual } from '@/lib/painel'
import { createSessionClient } from '@/lib/supabase/session'

export const dynamic = 'force-dynamic'

export default async function AtendimentoPage({ params }: { params: { id: string } }) {
  const usuario = await usuarioAtual()
  const supabase = createSessionClient()

  const { data: item } = await supabase
    .from('reserva_itens')
    .select(
      `id, inicio, fim, estado, nome_servico, preco_final, duracao_reservada, observacoes,
       reservas!inner ( id, estado, valor_total, valor_sinal_total, created_at,
         clientes ( id, nome, telefone_normalizado ),
         cobrancas ( valor_sinal, valor_total, estado, transacoes ( valor, estado, finalidade, meio ) ) ),
       servicos ( nome_tecnico, servico_cardapios ( nome_comercial ) ),
       profissionais ( id, nome )`
    )
    .eq('id', params.id)
    .maybeSingle()

  // A RLS já esconde atendimentos de outras profissionais
  if (!item) notFound()

  const a = item as any
  const reserva = a.reservas
  const cliente = reserva.clientes
  const cobranca = reserva.cobrancas?.[0]
  const pago = (cobranca?.transacoes ?? [])
    .filter((t: any) => t.estado === 'pago')
    .reduce((s: number, t: any) => s + Number(t.valor), 0)
  const servico = a.servicos?.servico_cardapios?.[0]?.nome_comercial ?? a.nome_servico ?? a.servicos?.nome_tecnico
  const e = estado(reserva.estado)
  const data = dataDoSlot(a.inicio)

  return (
    <div className="mx-auto max-w-3xl">
      <Link
        href={`/dashboard/agenda?data=${data}`}
        className="inline-flex items-center gap-2 text-sm text-ella-muted hover:text-ella-rose"
      >
        <IconeVoltar className="h-4 w-4" />
        Voltar à agenda
      </Link>

      <div className="mt-4 flex flex-wrap items-start justify-between gap-3">
        <div>
          <p className="eyebrow">Atendimento</p>
          <h1 className="mt-1 font-serif text-3xl font-medium sm:text-4xl">{cliente?.nome?.trim() || 'Cliente'}</h1>
        </div>
        <span className={`rounded-full px-3 py-1.5 text-sm font-medium ring-1 ${e.cor}`}>{e.rotulo}</span>
      </div>

      <div className="mt-6 grid gap-4 md:grid-cols-2">
        <section className="rounded-3xl border border-ella-line bg-white p-5">
          <p className="font-serif text-2xl font-medium">{servico}</p>
          <ul className="mt-4 space-y-2.5 text-sm">
            <li className="flex items-center gap-2">
              <IconeCalendario className="h-4 w-4 text-ella-rose" />
              <span className="first-letter:uppercase">{formatarDataLonga(data)}</span>
            </li>
            <li className="flex items-center gap-2">
              <IconeRelogio className="h-4 w-4 text-ella-rose" />
              {formatarHora(a.inicio)} – {formatarHora(a.fim)}
              {a.duracao_reservada ? ` (${formatarDuracao(a.duracao_reservada)})` : ''}
            </li>
            <li className="flex items-center gap-2">
              <IconePessoa className="h-4 w-4 text-ella-rose" />
              {a.profissionais?.nome ?? '—'}
            </li>
          </ul>
        </section>

        <section className="rounded-3xl border border-ella-line bg-white p-5">
          <p className="text-sm text-ella-muted">Cliente</p>
          <p className="mt-1 font-medium">{cliente?.nome}</p>
          {cliente?.telefone_normalizado && (
            <>
              <p className="text-sm text-ella-muted">{telefoneExibicao(cliente.telefone_normalizado)}</p>
              <a
                href={linkWhatsCliente(cliente.telefone_normalizado)}
                target="_blank"
                rel="noopener noreferrer"
                className="btn-secundario mt-4 !py-2.5 text-sm"
              >
                <IconeWhatsApp className="h-4 w-4 text-[#25D366]" />
                Chamar no WhatsApp
              </a>
            </>
          )}
        </section>

        <section className="rounded-3xl border border-ella-line bg-white p-5 md:col-span-2">
          <p className="text-sm text-ella-muted">Pagamento</p>
          <dl className="mt-3 grid grid-cols-3 gap-3 text-sm">
            <div>
              <dt className="text-ella-muted">Valor</dt>
              <dd className="font-serif text-xl font-semibold">{formatarPreco(a.preco_final ?? reserva.valor_total)}</dd>
            </div>
            <div>
              <dt className="text-ella-muted">Sinal</dt>
              <dd className="font-serif text-xl font-semibold">{formatarPreco(reserva.valor_sinal_total)}</dd>
            </div>
            <div>
              <dt className="text-ella-muted">Já pago</dt>
              <dd className="font-serif text-xl font-semibold text-emerald-700">{formatarPreco(pago)}</dd>
            </div>
          </dl>
          {a.observacoes && <p className="mt-4 text-sm text-ella-muted">Obs.: {a.observacoes}</p>}
        </section>
      </div>

      <AcoesAtendimento
        reservaId={reserva.id}
        estado={reserva.estado}
        podeReceber={usuario.equipe}
        valorSinal={Math.max(Number(reserva.valor_sinal_total ?? 0) - pago, 0)}
      />
    </div>
  )
}
