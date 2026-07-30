import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'

export default async function BackofficeLayout({
  children,
}: {
  children: React.ReactNode
}) {
  const supabase = createClient()
  const {
    data: { user },
  } = await supabase.auth.getUser()

  if (!user) {
    redirect('/auth/login')
  }

  return (
    <div className="min-h-screen bg-gray-50">
      <header className="border-b bg-white px-6 py-4">
        <div className="mx-auto flex max-w-6xl items-center justify-between">
          <div className="flex items-center gap-6">
            <h1 className="text-lg font-bold text-pink-600">ELLA Studio — Backoffice</h1>
            <nav className="flex gap-4 text-sm">
              <a href="/dashboard" className="text-gray-600 hover:text-pink-600">
                Dashboard
              </a>
              <a href="/dashboard/servicos" className="text-gray-600 hover:text-pink-600">
                Serviços
              </a>
            </nav>
          </div>
          <p className="text-sm text-gray-600">{user.email}</p>
        </div>
      </header>
      <main className="mx-auto max-w-6xl p-6">{children}</main>
    </div>
  )
}
