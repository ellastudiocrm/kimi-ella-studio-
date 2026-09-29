import { notFound } from 'next/navigation'
import Agendador from '@/components/Agendador'
import PaginaPublica from '@/components/PaginaPublica'
import { diasDeFuncionamento, obterProfissional, obterServico } from '@/lib/catalogo'
import { cardapioValido } from '@/lib/marca'

export const dynamic = 'force-dynamic'

export default async function AgendarPage({
  searchParams,
}: {
  searchParams: { profissional?: string; servico?: string; cardapio?: string }
}) {
  const cardapio = cardapioValido(searchParams.cardapio)
  if (!searchParams.servico || !searchParams.profissional) notFound()

  const [servico, profissional, diasAbertos] = await Promise.all([
    obterServico(cardapio, { nomeTecnico: searchParams.servico }),
    obterProfissional(searchParams.profissional),
    diasDeFuncionamento(),
  ])
  if (!servico || !profissional) notFound()

  return (
    <PaginaPublica>
      <Agendador
        cardapio={cardapio}
        servico={servico}
        profissional={{ id: profissional.id, nome: profissional.nome }}
        diasAbertos={diasAbertos}
        empresaId={process.env.NEXT_PUBLIC_EMPRESA_ID!}
      />
    </PaginaPublica>
  )
}
