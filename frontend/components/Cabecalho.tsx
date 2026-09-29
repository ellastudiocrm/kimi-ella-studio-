import Image from 'next/image'
import Link from 'next/link'
import { linkWhatsApp } from '@/lib/marca'
import { IconeWhatsApp } from '@/components/Icones'

export default function Cabecalho() {
  return (
    <header className="sticky top-0 z-30 border-b border-ella-line/70 bg-ella-light/90 backdrop-blur">
      <div className="container-ella flex h-16 items-center justify-between gap-4 sm:h-20">
        <Link href="/" className="flex items-center gap-3" aria-label="ELLA Studio — início">
          <Image
            src="/marca/logo.png"
            alt="ELLA Studio"
            width={56}
            height={56}
            priority
            className="h-11 w-11 sm:h-14 sm:w-14"
          />
          <span className="hidden font-serif text-xl leading-none sm:block">
            ELLA Studio
            <span className="mt-1 block font-sans text-[10px] uppercase tracking-[0.3em] text-ella-muted">
              Beleza &amp; Estética
            </span>
          </span>
        </Link>

        <nav className="flex items-center gap-1 text-sm sm:gap-2">
          <Link
            href="/ella_studio"
            className="hidden rounded-full px-4 py-2 text-ella-dark transition hover:bg-ella-soft md:inline-block"
          >
            ELLA Studio
          </Link>
          <Link
            href="/ella_men"
            className="hidden rounded-full px-4 py-2 text-ella-dark transition hover:bg-ella-soft md:inline-block"
          >
            ELLA MEN
          </Link>
          <a
            href={linkWhatsApp('Olá! Gostaria de falar com o ELLA Studio.')}
            target="_blank"
            rel="noopener noreferrer"
            className="inline-flex items-center gap-2 rounded-full border border-ella-line bg-white px-4 py-2 font-medium text-ella-dark transition hover:border-ella-rose hover:text-ella-rose"
          >
            <IconeWhatsApp className="h-4 w-4" />
            <span className="hidden xs:inline">WhatsApp</span>
          </a>
        </nav>
      </div>
    </header>
  )
}
