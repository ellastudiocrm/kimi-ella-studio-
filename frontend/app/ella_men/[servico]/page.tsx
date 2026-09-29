import EscolherProfissional from '@/components/EscolherProfissional'

export const dynamic = 'force-dynamic'

export default function ProfissionaisMenPage({ params }: { params: { servico: string } }) {
  return <EscolherProfissional cardapio="ella_men" slug={params.servico} />
}
