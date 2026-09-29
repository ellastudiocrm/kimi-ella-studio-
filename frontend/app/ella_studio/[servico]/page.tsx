import EscolherProfissional from '@/components/EscolherProfissional'

export const dynamic = 'force-dynamic'

export default function ProfissionaisPage({ params }: { params: { servico: string } }) {
  return <EscolherProfissional cardapio="ella_studio" slug={params.servico} />
}
