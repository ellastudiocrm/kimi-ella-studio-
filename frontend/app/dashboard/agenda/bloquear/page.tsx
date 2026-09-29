import Link from 'next/link'
import FormBloqueio from '@/components/painel/FormBloqueio'
import { IconeVoltar } from '@/components/Icones'
import { hojeSaoPaulo } from '@/lib/marca'
import { profissionaisDaAgenda, usuarioAtual } from '@/lib/painel'

export const dynamic = 'force-dynamic'

export default async function BloquearPage({ searchParams }: { searchParams: { data?: string } }) {
  const usuario = await usuarioAtual()
  if (!usuario.equipe) {
    return <p className="rounded-2xl bg-white p-6 text-ella-muted">Só a equipe de gestão pode bloquear horários.</p>
  }
  const profissionais = await profissionaisDaAgenda()
  const hoje = hojeSaoPaulo()
  const data = searchParams.data && searchParams.data >= hoje ? searchParams.data : hoje

  return (
    <div className="mx-auto max-w-2xl">
      <Link href={`/dashboard/agenda?data=${data}`} className="inline-flex items-center gap-2 text-sm text-ella-muted hover:text-ella-rose">
        <IconeVoltar className="h-4 w-4" />
        Voltar à agenda
      </Link>
      <h1 className="mt-4 font-serif text-3xl font-medium sm:text-4xl">Bloquear horário</h1>
      <p className="mt-2 text-ella-muted">
        Use para almoço, folga ou imprevistos. Nesse período ninguém consegue agendar com a profissional.
      </p>
      <FormBloqueio profissionais={profissionais} dataInicial={data} hoje={hoje} />
    </div>
  )
}
