'use client'

import Link from 'next/link'
import { usePathname, useRouter, useSearchParams } from 'next/navigation'
import { IconeSeta, IconeVoltar } from '@/components/Icones'
import { formatarDataLonga, somarDias } from '@/lib/marca'
import type { ProfissionalAgenda } from '@/lib/painel'

export default function BarraAgenda({
  data,
  hoje,
  vista,
  profissionais,
  filtro,
  mostrarTodas,
}: {
  data: string
  hoje: string
  vista: 'dia' | 'semana'
  profissionais: ProfissionalAgenda[]
  filtro: string | null
  mostrarTodas: boolean
}) {
  const router = useRouter()
  const pathname = usePathname()
  const params = useSearchParams()

  function url(mudancas: Record<string, string | null>) {
    const p = new URLSearchParams(params.toString())
    for (const [k, v] of Object.entries(mudancas)) {
      if (v === null) p.delete(k)
      else p.set(k, v)
    }
    return `${pathname}?${p.toString()}`
  }

  const passo = vista === 'semana' ? 7 : 1

  return (
    <div className="mt-6 space-y-3">
      <div className="flex flex-wrap items-center gap-2">
        <div className="flex items-center rounded-full border border-ella-line bg-white">
          <Link
            href={url({ data: somarDias(data, -passo) })}
            className="rounded-l-full p-2.5 hover:bg-ella-soft"
            aria-label="Anterior"
          >
            <IconeVoltar className="h-4 w-4" />
          </Link>
          <Link
            href={url({ data: hoje })}
            className={`border-x border-ella-line px-4 py-2 text-sm ${data === hoje ? 'font-medium text-ella-rose' : ''}`}
          >
            Hoje
          </Link>
          <Link
            href={url({ data: somarDias(data, passo) })}
            className="rounded-r-full p-2.5 hover:bg-ella-soft"
            aria-label="Próximo"
          >
            <IconeSeta className="h-4 w-4" />
          </Link>
        </div>

        <label className="relative">
          <span className="sr-only">Escolher data</span>
          <input
            type="date"
            value={data}
            onChange={(e) => e.target.value && router.push(url({ data: e.target.value }))}
            className="rounded-full border border-ella-line bg-white px-4 py-2 text-sm"
          />
        </label>

        <p className="hidden text-sm font-medium first-letter:uppercase md:block">
          {vista === 'dia' ? formatarDataLonga(data) : ''}
        </p>

        <div className="ml-auto flex rounded-full border border-ella-line bg-white p-1 text-sm">
          {(['dia', 'semana'] as const).map((v) => (
            <Link
              key={v}
              href={url({ vista: v === 'dia' ? null : v })}
              className={`rounded-full px-4 py-1.5 capitalize ${
                vista === v ? 'bg-ella-rose text-white' : 'text-ella-dark hover:bg-ella-soft'
              }`}
            >
              {v}
            </Link>
          ))}
        </div>
      </div>

      <div className="flex flex-wrap items-center gap-2 text-sm">
        {profissionais.length > 1 && (
          <>
            <Link
              href={url({ prof: null })}
              className={`rounded-full px-3.5 py-1.5 ring-1 ${
                !filtro ? 'bg-ella-dark text-white ring-ella-dark' : 'bg-white ring-ella-line hover:ring-ella-rose'
              }`}
            >
              Todas
            </Link>
            {profissionais.map((p) => (
              <Link
                key={p.id}
                href={url({ prof: p.id })}
                className={`rounded-full px-3.5 py-1.5 ring-1 ${
                  filtro === p.id ? 'bg-ella-dark text-white ring-ella-dark' : 'bg-white ring-ella-line hover:ring-ella-rose'
                }`}
              >
                {p.nome}
              </Link>
            ))}
          </>
        )}
        <Link
          href={url({ todas: mostrarTodas ? null : '1' })}
          className="ml-auto text-ella-muted underline-offset-4 hover:text-ella-rose hover:underline"
        >
          {mostrarTodas ? 'Esconder canceladas e expiradas' : 'Mostrar canceladas e expiradas'}
        </Link>
      </div>
    </div>
  )
}
