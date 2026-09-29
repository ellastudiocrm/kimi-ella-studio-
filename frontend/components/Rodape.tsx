import Image from 'next/image'
import { CONTATO, linkWhatsApp } from '@/lib/marca'
import { IconeInstagram, IconeLocal, IconeRelogio, IconeWhatsApp } from '@/components/Icones'

export default function Rodape() {
  return (
    <footer className="mt-20 border-t border-ella-line bg-ella-card">
      <div className="container-ella grid gap-10 py-12 sm:grid-cols-2 lg:grid-cols-4">
        <div className="flex items-start gap-4 sm:col-span-2 lg:col-span-1">
          <Image src="/marca/logo.png" alt="ELLA Studio" width={64} height={64} className="h-16 w-16" />
          <p className="text-sm leading-relaxed text-ella-muted">
            Beleza, estética e bem-estar para mulheres e homens em Valinhos.
          </p>
        </div>

        <div className="text-sm">
          <p className="eyebrow mb-3">Endereço</p>
          <a
            href={CONTATO.mapa}
            target="_blank"
            rel="noopener noreferrer"
            className="flex gap-2 text-ella-dark hover:text-ella-rose"
          >
            <IconeLocal className="mt-0.5 h-4 w-4 shrink-0 text-ella-rose" />
            <span>
              {CONTATO.endereco}
              <br />
              {CONTATO.bairro}
            </span>
          </a>
        </div>

        <div className="text-sm">
          <p className="eyebrow mb-3">Horário</p>
          <div className="flex gap-2">
            <IconeRelogio className="mt-0.5 h-4 w-4 shrink-0 text-ella-rose" />
            <span>
              {CONTATO.horarios.map((h) => (
                <span key={h} className="block">
                  {h}
                </span>
              ))}
            </span>
          </div>
        </div>

        <div className="text-sm">
          <p className="eyebrow mb-3">Contato</p>
          <a
            href={linkWhatsApp()}
            target="_blank"
            rel="noopener noreferrer"
            className="mb-2 flex items-center gap-2 hover:text-ella-rose"
          >
            <IconeWhatsApp className="h-4 w-4 text-ella-rose" />
            {CONTATO.telefoneExibicao}
          </a>
          <a
            href={CONTATO.instagram}
            target="_blank"
            rel="noopener noreferrer"
            className="flex items-center gap-2 hover:text-ella-rose"
          >
            <IconeInstagram className="h-4 w-4 text-ella-rose" />
            {CONTATO.instagramUser}
          </a>
        </div>
      </div>
      <div className="border-t border-ella-line py-5 text-center text-xs text-ella-muted">
        © {new Date().getFullYear()} ELLA Studio · Valinhos, SP
      </div>
    </footer>
  )
}
