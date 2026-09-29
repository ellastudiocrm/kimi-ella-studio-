import { IconeCheck } from '@/components/Icones'

const PASSOS = ['Serviço', 'Profissional', 'Dia e horário', 'Seus dados']

// Indicador do progresso no agendamento. `atual` começa em 0.
export default function Passos({ atual }: { atual: number }) {
  return (
    <ol className="flex items-center gap-2 text-xs sm:gap-3 sm:text-sm" aria-label="Etapas do agendamento">
      {PASSOS.map((nome, i) => {
        const feito = i < atual
        const ativo = i === atual
        return (
          <li key={nome} className="flex items-center gap-2 sm:gap-3">
            <span
              className={`flex h-6 w-6 shrink-0 items-center justify-center rounded-full border text-[11px] font-medium ${
                feito
                  ? 'border-ella-rose bg-ella-rose text-white'
                  : ativo
                    ? 'border-ella-rose text-ella-rose'
                    : 'border-ella-line text-ella-muted'
              }`}
              aria-current={ativo ? 'step' : undefined}
            >
              {feito ? <IconeCheck className="h-3.5 w-3.5" /> : i + 1}
            </span>
            <span className={`${ativo ? 'font-medium text-ella-dark' : 'text-ella-muted'} ${ativo ? '' : 'hidden md:inline'}`}>
              {nome}
            </span>
            {i < PASSOS.length - 1 && <span className="h-px w-4 bg-ella-line sm:w-8" />}
          </li>
        )
      })}
    </ol>
  )
}
