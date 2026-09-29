import NavPainel from '@/components/painel/NavPainel'
import { usuarioAtual } from '@/lib/painel'

export default async function DashboardLayout({ children }: { children: React.ReactNode }) {
  const usuario = await usuarioAtual()

  return (
    <div className="min-h-screen bg-ella-light">
      <NavPainel nome={usuario.nome} perfil={usuario.perfil} />
      <div className="pb-24 lg:pb-10 lg:pl-60">
        <main className="mx-auto w-full max-w-7xl px-4 py-5 sm:px-6 lg:px-8 lg:py-8">{children}</main>
      </div>
    </div>
  )
}
