'use client'

import Image from 'next/image'
import Link from 'next/link'
import { usePathname, useRouter } from 'next/navigation'
import { supabase } from '@/lib/supabase/client'
import { IconeCalendario, IconeCasa, IconeGrupo, IconeSair } from '@/components/Icones'

const ITENS = [
  { href: '/dashboard', rotulo: 'Hoje', Icone: IconeCasa },
  { href: '/dashboard/agenda', rotulo: 'Agenda', Icone: IconeCalendario },
  { href: '/dashboard/clientes', rotulo: 'Clientes', Icone: IconeGrupo },
]

const PERFIS: Record<string, string> = {
  admin: 'Administração',
  gestor: 'Gestão',
  recepcao: 'Recepção',
  profissional: 'Profissional',
}

function ativo(pathname: string, href: string) {
  return href === '/dashboard' ? pathname === href : pathname.startsWith(href)
}

export default function NavPainel({ nome, perfil }: { nome: string; perfil: string }) {
  const pathname = usePathname()
  const router = useRouter()

  async function sair() {
    await supabase.auth.signOut()
    router.push('/login')
    router.refresh()
  }

  return (
    <>
      {/* Computador: barra lateral */}
      <aside className="fixed inset-y-0 left-0 z-30 hidden w-60 flex-col border-r border-ella-line bg-white lg:flex">
        <Link href="/dashboard" className="flex items-center gap-3 px-5 py-5">
          <Image src="/marca/logo.png" alt="ELLA Studio" width={44} height={44} />
          <span className="font-serif text-lg leading-none">
            ELLA Studio
            <span className="mt-1 block font-sans text-[10px] uppercase tracking-[0.25em] text-ella-muted">Gestão</span>
          </span>
        </Link>
        <nav className="mt-2 flex-1 space-y-1 px-3">
          {ITENS.map(({ href, rotulo, Icone }) => (
            <Link
              key={href}
              href={href}
              className={`flex items-center gap-3 rounded-xl px-3 py-2.5 text-sm transition ${
                ativo(pathname, href)
                  ? 'bg-ella-soft font-medium text-ella-rose-deep'
                  : 'text-ella-dark hover:bg-ella-light'
              }`}
            >
              <Icone className="h-5 w-5" />
              {rotulo}
            </Link>
          ))}
        </nav>
        <div className="border-t border-ella-line p-4">
          <p className="truncate text-sm font-medium">{nome}</p>
          <p className="text-xs text-ella-muted">{PERFIS[perfil] ?? perfil}</p>
          <button
            type="button"
            onClick={sair}
            className="mt-3 flex items-center gap-2 text-sm text-ella-muted hover:text-ella-rose"
          >
            <IconeSair className="h-4 w-4" />
            Sair
          </button>
        </div>
      </aside>

      {/* Celular: topo + barra inferior */}
      <header className="sticky top-0 z-30 flex items-center justify-between border-b border-ella-line bg-white/95 px-4 py-3 backdrop-blur lg:hidden">
        <Link href="/dashboard" className="flex items-center gap-2">
          <Image src="/marca/logo.png" alt="ELLA Studio" width={36} height={36} />
          <span className="text-sm">
            <span className="block text-xs text-ella-muted">Olá,</span>
            <span className="font-medium">{nome}</span>
          </span>
        </Link>
        <button type="button" onClick={sair} className="rounded-full p-2 text-ella-muted" aria-label="Sair">
          <IconeSair className="h-5 w-5" />
        </button>
      </header>
      <nav className="fixed inset-x-0 bottom-0 z-30 border-t border-ella-line bg-white pb-[env(safe-area-inset-bottom)] lg:hidden">
        <div className="mx-auto flex max-w-md justify-around">
          {ITENS.map(({ href, rotulo, Icone }) => (
            <Link
              key={href}
              href={href}
              className={`flex flex-1 flex-col items-center gap-1 py-2.5 text-[11px] ${
                ativo(pathname, href) ? 'font-medium text-ella-rose' : 'text-ella-muted'
              }`}
            >
              <Icone className="h-6 w-6" />
              {rotulo}
            </Link>
          ))}
        </div>
      </nav>
    </>
  )
}
