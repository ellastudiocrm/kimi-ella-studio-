import { IconeGrupo } from '@/components/Icones'

export default function ClientesPage() {
  return (
    <div>
      <p className="eyebrow">Clientes</p>
      <h1 className="mt-1 font-serif text-3xl font-medium sm:text-4xl">Clientes</h1>
      <div className="mt-8 flex flex-col items-center rounded-3xl border border-dashed border-ella-line bg-white px-6 py-16 text-center">
        <span className="flex h-14 w-14 items-center justify-center rounded-full bg-ella-soft text-ella-rose">
          <IconeGrupo className="h-7 w-7" />
        </span>
        <p className="mt-4 font-serif text-2xl">Em construção</p>
        <p className="mt-2 max-w-sm text-sm text-ella-muted">
          Aqui vai ficar a lista de clientes com histórico de atendimentos. Por enquanto, os clientes são cadastrados
          ao criar um novo agendamento.
        </p>
      </div>
    </div>
  )
}
