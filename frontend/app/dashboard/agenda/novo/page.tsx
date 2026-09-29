import Link from 'next/link'
import NovoAgendamento from '@/components/painel/NovoAgendamento'
import { IconeVoltar } from '@/components/Icones'
import { listarServicos } from '@/lib/catalogo'
import { hojeSaoPaulo } from '@/lib/marca'
import { profissionaisDaAgenda, usuarioAtual } from '@/lib/painel'
import { createSessionClient } from '@/lib/supabase/session'

export const dynamic = 'force-dynamic'

export default async function NovoAgendamentoPage({ searchParams }: { searchParams: { data?: string } }) {
  const usuario = await usuarioAtual()
  if (!usuario.equipe) {
    return <p className="rounded-2xl bg-white p-6 text-ella-muted">Só a equipe de gestão pode criar agendamentos.</p>
  }

  const supabase = createSessionClient()
  const [studio, men, profissionais, { data: habilitacoes }] = await Promise.all([
    listarServicos('ella_studio'),
    listarServicos('ella_men'),
    profissionaisDaAgenda(),
    supabase.from('profissional_servicos').select('servico_id, profissional_id'),
  ])

  const porServico: Record<string, string[]> = {}
  for (const h of habilitacoes ?? []) {
    ;(porServico[h.servico_id] ??= []).push(h.profissional_id)
  }

  const hoje = hojeSaoPaulo()
  const data = searchParams.data && searchParams.data >= hoje ? searchParams.data : hoje

  return (
    <div>
      <Link href={`/dashboard/agenda?data=${data}`} className="inline-flex items-center gap-2 text-sm text-ella-muted hover:text-ella-rose">
        <IconeVoltar className="h-4 w-4" />
        Voltar à agenda
      </Link>
      <h1 className="mt-4 font-serif text-3xl font-medium sm:text-4xl">Novo agendamento</h1>

      <NovoAgendamento
        servicos={{ ella_studio: studio, ella_men: men }}
        profissionais={profissionais}
        porServico={porServico}
        dataInicial={data}
        hoje={hoje}
        empresaId={process.env.NEXT_PUBLIC_EMPRESA_ID!}
      />
    </div>
  )
}
