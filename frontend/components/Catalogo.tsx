import Image from 'next/image'
import Link from 'next/link'
import PaginaPublica from '@/components/PaginaPublica'
import Passos from '@/components/Passos'
import { IconeRelogio, IconeSeta, IconeVoltar, IconeWhatsApp } from '@/components/Icones'
import { listarServicos } from '@/lib/catalogo'
import { CARDAPIOS, formatarDuracao, formatarPreco, fotoServico, linkWhatsApp, type Cardapio } from '@/lib/marca'

export default async function Catalogo({ cardapio }: { cardapio: Cardapio }) {
  const info = CARDAPIOS[cardapio]
  const servicos = await listarServicos(cardapio)
  const men = cardapio === 'ella_men'

  return (
    <PaginaPublica>
      {/* Topo com foto */}
      <section className={men ? 'bg-men-stone' : 'bg-ella-card'}>
        <div className="container-ella grid items-center gap-8 py-8 md:grid-cols-[1fr_auto] md:py-12">
          <div>
            <Link href="/" className="mb-5 inline-flex items-center gap-2 text-sm text-ella-muted hover:text-ella-rose">
              <IconeVoltar className="h-4 w-4" />
              Início
            </Link>
            <p className={`eyebrow ${men ? '!text-men-accent' : ''}`}>{info.nome}</p>
            <h1
              className={`mt-3 max-w-2xl text-3xl leading-tight sm:text-4xl lg:text-5xl ${
                men ? 'font-sans font-semibold text-men-ink' : 'font-serif font-medium'
              }`}
            >
              {info.titulo}
            </h1>
            <p className="mt-4 max-w-xl text-ella-muted">{info.descricao}</p>
            <div className="mt-6">
              <Passos atual={0} />
            </div>
          </div>
          <div className="relative hidden h-56 w-56 overflow-hidden rounded-full border-8 border-white shadow-suave md:block lg:h-64 lg:w-64">
            <Image src={info.hero} alt={info.nome} fill sizes="256px" className="object-cover" priority />
          </div>
        </div>
      </section>

      {/* Lista de serviços */}
      <section className="container-ella py-10 sm:py-12">
        {servicos.length === 0 ? (
          <div className="mx-auto max-w-md rounded-3xl bg-white p-8 text-center shadow-suave">
            <p className="font-serif text-2xl">Não conseguimos carregar os serviços agora</p>
            <p className="mt-3 text-sm text-ella-muted">
              Tente novamente em instantes ou fale com a gente pelo WhatsApp.
            </p>
            <a href={linkWhatsApp('Olá! Gostaria de agendar um horário.')} className="btn-primario mt-6">
              <IconeWhatsApp className="h-4 w-4" />
              Agendar pelo WhatsApp
            </a>
          </div>
        ) : (
          <>
            <p className="mb-6 text-sm text-ella-muted">
              {servicos.length} serviços · toque em um para escolher o horário
            </p>
            <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3 lg:gap-6">
              {servicos.map((s) => (
                <Link
                  key={s.id}
                  href={`/${cardapio}/${encodeURIComponent(s.nomeTecnico)}`}
                  className="group flex overflow-hidden rounded-2xl border border-ella-line/70 bg-white transition hover:-translate-y-0.5 hover:border-ella-blush hover:shadow-suave sm:flex-col"
                >
                  <div className="relative aspect-square w-28 shrink-0 overflow-hidden bg-ella-soft sm:aspect-[4/3] sm:w-full">
                    <Image
                      src={fotoServico(s.nomeTecnico, cardapio, s.fotoUrl)}
                      alt={s.nome}
                      fill
                      sizes="(min-width: 1024px) 33vw, (min-width: 640px) 50vw, 112px"
                      className="object-cover transition duration-500 group-hover:scale-105"
                    />
                  </div>
                  <div className="flex flex-1 flex-col justify-between gap-3 p-4 sm:p-5">
                    <div>
                      <h2 className="text-base font-medium leading-snug sm:text-lg">{s.nome}</h2>
                      {s.descricao && (
                        <p className="mt-1 line-clamp-2 text-sm text-ella-muted">{s.descricao}</p>
                      )}
                    </div>
                    <div className="flex items-end justify-between gap-2">
                      <div>
                        <p className="flex items-center gap-1.5 text-xs text-ella-muted">
                          <IconeRelogio className="h-3.5 w-3.5" />
                          {formatarDuracao(s.duracaoMinutos)}
                        </p>
                        <p className="mt-0.5 font-serif text-xl font-semibold text-ella-rose">
                          {formatarPreco(s.preco)}
                        </p>
                      </div>
                      <span className="hidden items-center gap-1 text-sm font-medium text-ella-rose sm:flex">
                        Agendar
                        <IconeSeta className="h-4 w-4 transition group-hover:translate-x-1" />
                      </span>
                      <IconeSeta className="h-5 w-5 text-ella-rose sm:hidden" />
                    </div>
                  </div>
                </Link>
              ))}
            </div>
          </>
        )}
      </section>
    </PaginaPublica>
  )
}
