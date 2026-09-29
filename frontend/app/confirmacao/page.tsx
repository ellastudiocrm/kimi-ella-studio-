import { notFound } from 'next/navigation'
import FormConfirmacao from '@/components/FormConfirmacao'
import PaginaPublica from '@/components/PaginaPublica'
import { obterProfissional, obterServico } from '@/lib/catalogo'
import { cardapioValido } from '@/lib/marca'

export const dynamic = 'force-dynamic'

export default async function ConfirmacaoPage({
  searchParams,
}: {
  searchParams: { profissional?: string; servico?: string; data?: string; hora?: string; cardapio?: string }
}) {
  const cardapio = cardapioValido(searchParams.cardapio)
  const { profissional: profissionalId, servico: servicoSlug, data, hora } = searchParams
  if (!profissionalId || !servicoSlug || !data || !hora) notFound()

  const [servico, profissional] = await Promise.all([
    obterServico(cardapio, { nomeTecnico: servicoSlug }),
    obterProfissional(profissionalId),
  ])
  if (!servico || !profissional) notFound()

  return (
    <PaginaPublica>
      <FormConfirmacao
        cardapio={cardapio}
        servico={servico}
        profissional={{ id: profissional.id, nome: profissional.nome }}
        data={data}
        hora={hora}
        empresaId={process.env.NEXT_PUBLIC_EMPRESA_ID!}
      />
    </PaginaPublica>
  )
}
