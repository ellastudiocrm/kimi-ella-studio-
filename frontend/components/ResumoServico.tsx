import Image from 'next/image'
import { IconeCalendario, IconePessoa, IconeRelogio } from '@/components/Icones'
import { formatarDuracao, formatarPreco, fotoServico, type Cardapio } from '@/lib/marca'
import type { ServicoCatalogo } from '@/lib/catalogo'

// Cartão com o resumo da escolha, mostrado ao lado (computador) ou no topo (celular).
export default function ResumoServico({
  servico,
  cardapio,
  profissional,
  quando,
}: {
  servico: Pick<ServicoCatalogo, 'nome' | 'nomeTecnico' | 'duracaoMinutos' | 'preco' | 'fotoUrl'>
  cardapio: Cardapio
  profissional?: string | null
  quando?: string | null
}) {
  return (
    <aside className="h-fit overflow-hidden rounded-3xl border border-ella-line/70 bg-white lg:sticky lg:top-28">
      <div className="relative hidden aspect-[16/9] bg-ella-soft lg:block">
        <Image
          src={fotoServico(servico.nomeTecnico, cardapio, servico.fotoUrl)}
          alt={servico.nome}
          fill
          sizes="340px"
          className="object-cover"
        />
      </div>
      <div className="p-5">
        <p className="eyebrow">Seu agendamento</p>
        <p className="mt-2 font-serif text-2xl font-medium leading-tight">{servico.nome}</p>
        <dl className="mt-4 space-y-2.5 text-sm">
          <div className="flex items-center gap-2 text-ella-muted">
            <IconeRelogio className="h-4 w-4 text-ella-rose" />
            <dt className="sr-only">Duração</dt>
            <dd>{formatarDuracao(servico.duracaoMinutos)}</dd>
          </div>
          {profissional && (
            <div className="flex items-center gap-2 text-ella-muted">
              <IconePessoa className="h-4 w-4 text-ella-rose" />
              <dt className="sr-only">Profissional</dt>
              <dd>{profissional}</dd>
            </div>
          )}
          {quando && (
            <div className="flex items-center gap-2 text-ella-dark">
              <IconeCalendario className="h-4 w-4 text-ella-rose" />
              <dt className="sr-only">Quando</dt>
              <dd className="first-letter:uppercase">{quando}</dd>
            </div>
          )}
        </dl>
        <div className="mt-5 flex items-baseline justify-between border-t border-ella-line pt-4">
          <span className="text-sm text-ella-muted">Valor</span>
          <span className="font-serif text-2xl font-semibold text-ella-rose">{formatarPreco(servico.preco)}</span>
        </div>
      </div>
    </aside>
  )
}
