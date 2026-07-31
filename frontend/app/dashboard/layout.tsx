import { redirect } from 'next/navigation'
import Link from 'next/link'
import { createSessionClient } from '@/lib/supabase/session'

interface LayoutProps {
  children: React.ReactNode
}

export default async function DashboardLayout({ children }: LayoutProps) {
  const supabase = createSessionClient()

  const {
    data: { user },
  } = await supabase.auth.getUser()

  if (!user) {
    redirect('/login?redirect=/dashboard')
  }

  const { data: usuario } = await supabase
    .from('usuarios_internos')
    .select('perfil, nome')
    .eq('auth_user_id', user.id)
    .single()

  const perfil = usuario?.perfil || 'desconhecido'
  const nome = usuario?.nome || user.email?.split('@')[0] || 'Usuário'

  const navItems = [
    { href: '/dashboard', label: 'Hoje', icon: '📅' },
    { href: '/dashboard/agenda', label: 'Agenda', icon: '🗓️' },
    { href: '/dashboard/clientes', label: 'Clientes', icon: '👥' },
    { href: '/dashboard/perfil', label: 'Perfil', icon: '👤' },
  ]

  return (
    <div className="min-h-screen pb-20">
      <header className="bg-white border-b border-gray-100 px-4 py-4">
        <div className="flex items-center justify-between">
          <div>
            <p className="text-xs text-gray-500">Bom dia,</p>
            <h1 className="text-lg font-bold text-ella-dark">{nome}</h1>
          </div>
          {(perfil === 'admin' || perfil === 'gestao') && (
            <Link
              href="/admin"
              className="text-xs font-medium text-ella-rose hover:underline"
            >
              Admin →
            </Link>
          )}
        </div>
      </header>

      <main className="px-4 py-4">{children}</main>

      <nav className="fixed bottom-0 left-0 right-0 bg-white border-t border-gray-100">
        <div className="max-w-md mx-auto flex justify-around py-2">
          {navItems.map((item) => (
            <Link
              key={item.href}
              href={item.href}
              className="flex flex-col items-center py-1 px-3 text-xs text-gray-500 hover:text-ella-rose"
            >
              <span className="text-xl mb-0.5">{item.icon}</span>
              <span>{item.label}</span>
            </Link>
          ))}
        </div>
      </nav>
    </div>
  )
}
