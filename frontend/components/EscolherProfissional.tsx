import Image from 'next/image'
import Link from 'next/link'
import { notFound, redirect } from 'next/navigation'
import PaginaPublica from '@/components/PaginaPublica'
import Passos from '@/components/Passos'
import ResumoServico from '@/components/ResumoServico'
import { IconePessoa, IconeSeta, IconeVoltar, IconeWhatsApp } from '@/components/Icones'
import { listarProfissionaisDoServico, obterServico } from '@/lib/catalogo'
import { linkWhatsApp, type Cardapio } from '@/lib/marca'

export default async function EscolherProfissional({
  cardapio,
  slug,
}: {
  cardapio: Cardapio
  slug: string
}) {
  const servico = await obterServico(cardapio, { nomeTecnico: decodeURIComponent(slug) })
  if (!servico) notFound()

  const profissionais = await listarProfissionaisDoServico(servico.id)
  const linkAgendar = (profissionalId: string) =>
    `/agendar?profissional=${profissionalId}&servico=${encodeURIComponent(servico.nomeTecnico)}&cardapio=${cardapio}`

  // Com uma só profissional não há o que escolher: vai direto para o calendário.
  if (profissionais.length === 1) {
    redirect(linkAgendar(profissionais[0].id))
  }

  return (
    <PaginaPublica>
      <div className="container-ella py-8 sm:py-12">
        <Link
          href={`/${cardapio}`}
          className="mb-6 inline-flex items-center gap-2 text-sm text-ella-muted hover:text-ella-rose"
        >
          <IconeVoltar className="h-4 w-4" />
          Voltar aos serviços
        </Link>
        <Passos atual={1} />

        <div className="mt-8 grid gap-8 lg:grid-cols-[1fr_340px]">
          <div>
            <h1 className="font-serif text-3xl font-medium sm:text-4xl">Com quem você quer agendar?</h1>

            {profissionais.length === 0 ? (
              <div className="mt-6 rounded-2xl bg-white p-6 text-ella-muted shadow-suave">
                <p>Este serviço ainda não tem horários online. Fale com a gente para agendar:</p>
                <a href={linkWhatsApp(`Olá! Gostaria de agendar: ${servico.nome}`)} className="btn-primario mt-4">
                  <IconeWhatsApp className="h-4 w-4" />
                  Agendar pelo WhatsApp
                </a>
              </div>
            ) : (
              <div className="mt-6 grid gap-4 sm:grid-cols-2">
                {profissionais.map((p) => (
                  <Link
                    key={p.id}
                    href={linkAgendar(p.id)}
                    className="group flex items-center gap-4 rounded-2xl border border-ella-line/70 bg-white p-4 transition hover:border-ella-blush hover:shadow-suave"
                  >
                    <div className="relative flex h-16 w-16 shrink-0 items-center justify-center overflow-hidden rounded-full bg-ella-soft text-ella-rose">
                      {p.fotoUrl ? (
                        <Image src={p.fotoUrl} alt={p.nome} fill sizes="64px" className="object-cover" />
                      ) : (
                        <IconePessoa className="h-7 w-7" />
                      )}
                    </div>
                    <div className="min-w-0 flex-1">
                      <p className="font-medium">{p.nome}</p>
                      {p.bio && <p className="mt-0.5 line-clamp-2 text-sm text-ella-muted">{p.bio}</p>}
                    </div>
                    <IconeSeta className="h-5 w-5 text-ella-rose transition group-hover:translate-x-1" />
                  </Link>
                ))}
              </div>
            )}
          </div>

          <ResumoServico servico={servico} cardapio={cardapio} />
        </div>
      </div>
    </PaginaPublica>
  )
}
