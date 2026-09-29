import Cabecalho from '@/components/Cabecalho'
import Rodape from '@/components/Rodape'

export default function PaginaPublica({ children }: { children: React.ReactNode }) {
  return (
    <div className="flex min-h-screen flex-col">
      <Cabecalho />
      <main className="flex-1">{children}</main>
      <Rodape />
    </div>
  )
}
