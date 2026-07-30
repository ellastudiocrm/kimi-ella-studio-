'use client'

import { useState, useRef, ChangeEvent } from 'react'
import { useRouter } from 'next/navigation'
import Image from 'next/image'

interface Servico {
  id: string
  nome_tecnico: string
  cardapios: { cardapio: string; nome_comercial: string }[]
}

interface Foto {
  id: string
  url: string
  ordem: number
}

interface Profissional {
  id: string
  nome: string
  foto_url: string | null
  bio: string | null
  especialidades: string[]
  ativo: boolean
  servicos: string[]
}

interface Props {
  profissional: Profissional
  servicos: Servico[]
}

export default function ProfissionalForm({ profissional, servicos }: Props) {
  const router = useRouter()
  const [form, setForm] = useState({
    nome: profissional.nome,
    bio: profissional.bio ?? '',
    especialidades: profissional.especialidades?.join(', ') ?? '',
    ativo: profissional.ativo,
    servicos: new Set(profissional.servicos),
  })
  const [fotoFile, setFotoFile] = useState<File | null>(null)
  const [fotoPreview, setFotoPreview] = useState<string | null>(null)
  const [fotos, setFotos] = useState<Foto[]>([])
  const [uploading, setUploading] = useState(false)
  const [salvando, setSalvando] = useState(false)
  const [erro, setErro] = useState<string | null>(null)
  const [mensagem, setMensagem] = useState<string | null>(null)
  const perfilInputRef = useRef<HTMLInputElement>(null)
  const galeriaInputRef = useRef<HTMLInputElement>(null)

  function handlePerfilChange(e: ChangeEvent<HTMLInputElement>) {
    if (e.target.files && e.target.files[0]) {
      const file = e.target.files[0]
      setFotoFile(file)
      setFotoPreview(URL.createObjectURL(file))
    }
  }

  async function uploadPerfil(): Promise<string | null> {
    if (!fotoFile) return profissional.foto_url

    setUploading(true)
    const data = new FormData()
    data.append('file', fotoFile)
    data.append('profissionalId', profissional.id)

    const res = await fetch('/api/upload/profissional', {
      method: 'POST',
      body: data,
    })

    setUploading(false)

    if (!res.ok) {
      const json = await res.json()
      setErro(json.error || 'Erro ao fazer upload da foto')
      return null
    }

    const json = await res.json()
    return json.url as string
  }

  async function handleSalvar() {
    setSalvando(true)
    setErro(null)
    setMensagem(null)

    const fotoUrl = await uploadPerfil()
    if (fotoFile && !fotoUrl) {
      setSalvando(false)
      return
    }

    const res = await fetch(`/api/profissionais/${profissional.id}`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        nome: form.nome,
        bio: form.bio,
        especialidades: form.especialidades
          .split(',')
          .map((s) => s.trim())
          .filter(Boolean),
        ativo: form.ativo,
        foto_url: fotoUrl,
        servicos: Array.from(form.servicos),
      }),
    })

    setSalvando(false)

    if (!res.ok) {
      const data = await res.json()
      setErro(data.error || 'Erro ao guardar')
      return
    }

    setMensagem('Guardado com sucesso')
    setFotoFile(null)
    setFotoPreview(null)
    router.refresh()
  }

  function toggleServico(id: string) {
    const novos = new Set(form.servicos)
    if (novos.has(id)) novos.delete(id)
    else novos.add(id)
    setForm({ ...form, servicos: novos })
  }

  async function adicionarFotoGaleria(e: ChangeEvent<HTMLInputElement>) {
    if (!e.target.files || !e.target.files[0]) return

    const file = e.target.files[0]
    setUploading(true)
    setErro(null)

    const data = new FormData()
    data.append('file', file)

    const res = await fetch(`/api/profissionais/${profissional.id}/fotos`, {
      method: 'POST',
      body: data,
    })

    setUploading(false)

    if (!res.ok) {
      const json = await res.json()
      setErro(json.error || 'Erro ao adicionar foto')
      return
    }

    const foto: Foto = await res.json()
    setFotos([...fotos, foto])
    if (galeriaInputRef.current) galeriaInputRef.current.value = ''
  }

  async function removerFoto(id: string) {
    setErro(null)
    const res = await fetch(`/api/profissionais/${profissional.id}/fotos/${id}`, {
      method: 'DELETE',
    })

    if (!res.ok) {
      const json = await res.json()
      setErro(json.error || 'Erro ao remover foto')
      return
    }

    setFotos(fotos.filter((f) => f.id !== id))
  }

  const servicosAgrupados = {
    ella_studio: servicos.filter((s) => s.cardapios.some((c) => c.cardapio === 'ella_studio')),
    ella_men: servicos.filter((s) => s.cardapios.some((c) => c.cardapio === 'ella_men')),
  }

  return (
    <div className="space-y-6">
      {erro && <p className="rounded bg-red-50 p-3 text-sm text-red-600">{erro}</p>}
      {mensagem && <p className="rounded bg-green-50 p-3 text-sm text-green-700">{mensagem}</p>}

      {/* Dados principais */}
      <section className="rounded-lg bg-white p-4 shadow-sm ring-1 ring-gray-100">
        <h3 className="mb-4 text-lg font-semibold text-gray-900">Dados principais</h3>
        <div className="space-y-4">
          <div>
            <label className="block text-sm font-medium text-gray-700">Nome</label>
            <input
              type="text"
              value={form.nome}
              onChange={(e) => setForm({ ...form, nome: e.target.value })}
              className="mt-1 w-full rounded border border-gray-300 px-3 py-2 text-sm min-h-[44px]"
            />
          </div>

          <div>
            <label className="block text-sm font-medium text-gray-700">Bio</label>
            <textarea
              value={form.bio}
              onChange={(e) => setForm({ ...form, bio: e.target.value })}
              rows={4}
              className="mt-1 w-full rounded border border-gray-300 px-3 py-2 text-sm"
            />
          </div>

          <div>
            <label className="block text-sm font-medium text-gray-700">Especialidades (separadas por vírgula)</label>
            <input
              type="text"
              value={form.especialidades}
              onChange={(e) => setForm({ ...form, especialidades: e.target.value })}
              placeholder="Ex: manicure, pedicure, cílios"
              className="mt-1 w-full rounded border border-gray-300 px-3 py-2 text-sm min-h-[44px]"
            />
          </div>

          <div className="flex items-center gap-2">
            <input
              id="ativo"
              type="checkbox"
              checked={form.ativo}
              onChange={(e) => setForm({ ...form, ativo: e.target.checked })}
            />
            <label htmlFor="ativo" className="text-sm font-medium text-gray-700">
              Ativo
            </label>
          </div>
        </div>
      </section>

      {/* Foto de perfil */}
      <section className="rounded-lg bg-white p-4 shadow-sm ring-1 ring-gray-100">
        <h3 className="mb-4 text-lg font-semibold text-gray-900">Foto de perfil</h3>
        <div className="flex items-center gap-4">
          <div className="relative h-24 w-24 flex-shrink-0 overflow-hidden rounded-full bg-gray-100">
            {fotoPreview ? (
              <Image src={fotoPreview} alt="Pré-visualização" fill className="object-cover" sizes="96px" />
            ) : profissional.foto_url ? (
              <Image src={profissional.foto_url} alt={profissional.nome} fill className="object-cover" sizes="96px" />
            ) : (
              <div className="flex h-full w-full items-center justify-center text-2xl font-bold text-gray-400">
                {profissional.nome.charAt(0).toUpperCase()}
              </div>
            )}
          </div>
          <div className="flex-1">
            <input
              ref={perfilInputRef}
              type="file"
              accept="image/*"
              onChange={handlePerfilChange}
              className="w-full text-sm"
            />
            <p className="mt-1 text-xs text-gray-500">Máximo 5MB. Imagem quadrada recomendada.</p>
          </div>
        </div>
      </section>

      {/* Galeria */}
      <section className="rounded-lg bg-white p-4 shadow-sm ring-1 ring-gray-100">
        <h3 className="mb-4 text-lg font-semibold text-gray-900">Galeria de fotos</h3>
        <div className="mb-4">
          <input
            ref={galeriaInputRef}
            type="file"
            accept="image/*"
            onChange={adicionarFotoGaleria}
            disabled={uploading}
            className="w-full text-sm"
          />
        </div>
        <div className="grid grid-cols-2 gap-3 sm:grid-cols-3">
          {fotos.map((foto) => (
            <div key={foto.id} className="relative aspect-square overflow-hidden rounded-lg bg-gray-100">
              <Image src={foto.url} alt="Foto do trabalho" fill className="object-cover" sizes="(max-width: 640px) 50vw, 33vw" />
              <button
                onClick={() => removerFoto(foto.id)}
                className="absolute right-2 top-2 rounded-full bg-red-600 p-1 text-white shadow hover:bg-red-700"
                aria-label="Remover foto"
              >
                ×
              </button>
            </div>
          ))}
        </div>
        {fotos.length === 0 && <p className="text-sm text-gray-500">Nenhuma foto na galeria.</p>}
      </section>

      {/* Serviços habilitados */}
      <section className="rounded-lg bg-white p-4 shadow-sm ring-1 ring-gray-100">
        <h3 className="mb-4 text-lg font-semibold text-gray-900">Serviços habilitados</h3>

        <div className="mb-4">
          <h4 className="mb-2 text-sm font-semibold text-pink-600">ELLA Studio</h4>
          <div className="grid gap-2">
            {servicosAgrupados.ella_studio.map((s) => {
              const nome = s.cardapios.find((c) => c.cardapio === 'ella_studio')?.nome_comercial ?? s.nome_tecnico
              return (
                <label key={s.id} className="flex items-center gap-2 rounded border border-gray-100 p-2">
                  <input
                    type="checkbox"
                    checked={form.servicos.has(s.id)}
                    onChange={() => toggleServico(s.id)}
                  />
                  <span className="text-sm text-gray-800">{nome}</span>
                </label>
              )
            })}
          </div>
        </div>

        <div>
          <h4 className="mb-2 text-sm font-semibold text-blue-600">ELLA MEN</h4>
          <div className="grid gap-2">
            {servicosAgrupados.ella_men.map((s) => {
              const nome = s.cardapios.find((c) => c.cardapio === 'ella_men')?.nome_comercial ?? s.nome_tecnico
              return (
                <label key={s.id} className="flex items-center gap-2 rounded border border-gray-100 p-2">
                  <input
                    type="checkbox"
                    checked={form.servicos.has(s.id)}
                    onChange={() => toggleServico(s.id)}
                  />
                  <span className="text-sm text-gray-800">{nome}</span>
                </label>
              )
            })}
          </div>
        </div>
      </section>

      <button
        onClick={handleSalvar}
        disabled={salvando || uploading}
        className="w-full rounded bg-pink-600 px-4 py-3 text-sm font-semibold text-white hover:bg-pink-700 disabled:opacity-50 min-h-[44px]"
      >
        {salvando || uploading ? 'A guardar...' : 'Guardar alterações'}
      </button>
    </div>
  )
}
