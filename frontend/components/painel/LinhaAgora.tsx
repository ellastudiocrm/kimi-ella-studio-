'use client'

import { useEffect, useState } from 'react'
import { minutosDoDia } from '@/lib/marca'

// Linha vermelha que marca a hora atual na agenda do dia
export default function LinhaAgora({ inicioGrade, pxPorHora }: { inicioGrade: number; pxPorHora: number }) {
  const [agora, setAgora] = useState<number | null>(null)

  useEffect(() => {
    const atualizar = () => setAgora(minutosDoDia(new Date().toISOString()))
    atualizar()
    const t = setInterval(atualizar, 60_000)
    return () => clearInterval(t)
  }, [])

  if (agora === null) return null
  const topo = ((agora - inicioGrade * 60) / 60) * pxPorHora
  if (topo < 0) return null

  return (
    <div className="pointer-events-none absolute left-12 right-0 z-20 flex items-center" style={{ top: topo }}>
      <span className="h-2.5 w-2.5 rounded-full bg-ella-rose" />
      <span className="h-px flex-1 bg-ella-rose" />
    </div>
  )
}
