'use client'

import { useState, useRef, ChangeEvent } from 'react'
import { useRouter } from 'next/navigation'

interface Cardapio {
  id: string
  cardapio: string
  nome_comercial: string
  preco_final: number
  ativo: boolean
}

interface Servico {
  id: string
  nome_tecnico: string
  duracao_minutos: number
  preco_base: number
  percentual_sinal: number
  anamnese_obrigatoria: boolean
  ativo: boolean
  foto_url: string | null
  servico_cardapios: Cardapio[]
}

interface Props {
  servicos: Servico[]
}

export default function ServicosTable({ servicos }: Props) {
  const router = useRouter()
  const [editando, setEditando] = useState<Servico | null>(null)
  const [salvando, setSalvando] = useState(false)
  const [form, setForm] = useState<Partial<Servico> & { cardapios?: Cardapio[] }>({})
  const [erro, setErro] = useState<string | null>(null)
  const [fotoFile, setFotoFile] = useState<File | null>(null)
  const [uploadingFoto, setUploadingFoto] = useState(false)
  const [tabAtiva, setTabAtiva] = useState<'ella_studio' | 'ella_men'>('ella_studio')
  const [criando, setCriando] = useState(false)
  const [novoForm, setNovoForm] = useState({
    nome_tecnico: '',
    nome_comercial: '',
    tipo_recurso_id: '11111111-1111-1111-1111-111111111111',
    duracao_minutos: 60,
    preco_base: 0,
    preco_final: 0,
    percentual_sinal: 30,
    anamnese_obrigatoria: false,
  })
  const fileInputRef = useRef<HTMLInputElement>(null)

  function abrirEdicao(servico: Servico) {
    setEditando(servico)
    setForm({
      preco_base: servico.preco_base,
      duracao_minutos: servico.duracao_minutos,
      foto_url: servico.foto_url ?? '',
      ativo: servico.ativo,
      cardapios: servico.servico_cardapios.map((c) => ({ ...c })),
    })
    setErro(null)
  }

  function fecharEdicao() {
    setEditando(null)
    setForm({})
    setFotoFile(null)
    setErro(null)
  }

  function abrirCriacao() {
    setCriando(true)
    setNovoForm({
      nome_tecnico: '',
      nome_comercial: '',
      tipo_recurso_id: '11111111-1111-1111-1111-111111111111',
      duracao_minutos: 60,
      preco_base: 0,
      preco_final: 0,
      percentual_sinal: 30,
      anamnese_obrigatoria: false,
    })
    setErro(null)
  }

  function fecharCriacao() {
    setCriando(false)
    setErro(null)
  }

  async function criarServico() {
    setSalvando(true)
    setErro(null)

    const res = await fetch('/api/servicos', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        ...novoForm,
        cardapio: tabAtiva,
      }),
    })

    setSalvando(false)

    if (!res.ok) {
      const data = await res.json()
      setErro(data.error || 'Erro ao criar serviço')
      return
    }

    fecharCriacao()
    router.refresh()
  }

  function handleFileChange(e: ChangeEvent<HTMLInputElement>) {
    if (e.target.files && e.target.files[0]) {
      setFotoFile(e.target.files[0])
    }
  }

  async function uploadFoto(): Promise<string | null> {
    if (!editando || !fotoFile) return form.foto_url ?? null

    setUploadingFoto(true)
    const data = new FormData()
    data.append('file', fotoFile)
    data.append('servicoId', editando.id)

    const res = await fetch('/api/upload/servico', {
      method: 'POST',
      body: data,
    })

    setUploadingFoto(false)

    if (!res.ok) {
      const json = await res.json()
      setErro(json.error || 'Erro ao fazer upload da foto')
      return null
    }

    const json = await res.json()
    return json.url as string
  }

  async function salvar() {
    if (!editando) return
    setSalvando(true)
    setErro(null)

    let fotoUrl = form.foto_url ?? null
    if (fotoFile) {
      const uploaded = await uploadFoto()
      if (!uploaded) {
        setSalvando(false)
        return
      }
      fotoUrl = uploaded
    }

    const res = await fetch(`/api/servicos/${editando.id}`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        preco_base: form.preco_base,
        duracao_minutos: form.duracao_minutos,
        foto_url: fotoUrl,
        ativo: form.ativo,
        cardapios: form.cardapios?.map((c) => ({
          id: c.id,
          preco_final: c.preco_final,
          ativo: c.ativo,
        })),
      }),
    })

    setSalvando(false)

    if (!res.ok) {
      const data = await res.json()
      setErro(data.error || 'Erro ao salvar')
      return
    }

    fecharEdicao()
    router.refresh()
  }

  const servicosFiltrados = servicos.filter((s) =>
    s.servico_cardapios.some((c) => c.cardapio === tabAtiva)
  )

  return (
    <div>
      <div className="mb-4 flex items-center justify-between border-b">
        <div className="flex gap-2">
          <button
            onClick={() => setTabAtiva('ella_studio')}
            className={`px-4 py-2 text-sm font-semibold ${
              tabAtiva === 'ella_studio'
                ? 'border-b-2 border-pink-600 text-pink-600'
                : 'text-gray-500 hover:text-gray-700'
            }`}
          >
            ELLA Studio (Feminino)
          </button>
          <button
            onClick={() => setTabAtiva('ella_men')}
            className={`px-4 py-2 text-sm font-semibold ${
              tabAtiva === 'ella_men'
                ? 'border-b-2 border-blue-600 text-blue-600'
                : 'text-gray-500 hover:text-gray-700'
            }`}
          >
            ELLA MEN (Masculino)
          </button>
        </div>
        <button
          onClick={abrirCriacao}
          className={`mb-2 rounded px-4 py-2 text-sm font-semibold text-white ${
            tabAtiva === 'ella_studio' ? 'bg-pink-600 hover:bg-pink-700' : 'bg-blue-600 hover:bg-blue-700'
          }`}
        >
          + Novo serviço
        </button>
      </div>

      <table className="w-full border-collapse rounded bg-white shadow">
        <thead>
          <tr className="border-b bg-gray-50 text-left text-sm font-semibold text-gray-700">
            <th className="px-4 py-3">Nome técnico</th>
            <th className="px-4 py-3">Nome comercial</th>
            <th className="px-4 py-3">Duração (min)</th>
            <th className="px-4 py-3">Preço base</th>
            <th className="px-4 py-3">Preço cardápio</th>
            <th className="px-4 py-3">Ativo</th>
            <th className="px-4 py-3"></th>
          </tr>
        </thead>
        <tbody>
          {servicosFiltrados.map((servico) => {
            const cardapio = servico.servico_cardapios.find((c) => c.cardapio === tabAtiva)
            return (
              <tr key={servico.id} className="border-b text-sm text-gray-800">
                <td className="px-4 py-3">{servico.nome_tecnico}</td>
                <td className="px-4 py-3">{cardapio?.nome_comercial ?? '-'}</td>
                <td className="px-4 py-3">{servico.duracao_minutos}</td>
                <td className="px-4 py-3">R$ {servico.preco_base.toFixed(2)}</td>
                <td className="px-4 py-3">R$ {(cardapio?.preco_final ?? 0).toFixed(2)}</td>
                <td className="px-4 py-3">{servico.ativo ? 'Sim' : 'Não'}</td>
                <td className="px-4 py-3">
                  <button
                    onClick={() => abrirEdicao(servico)}
                    className="rounded bg-pink-600 px-3 py-1 text-xs font-semibold text-white hover:bg-pink-700"
                  >
                    Editar
                  </button>
                </td>
              </tr>
            )
          })}
        </tbody>
      </table>

      {editando && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4">
          <div className="max-h-[90vh] w-full max-w-lg overflow-y-auto rounded bg-white p-6 shadow-lg">
            <h3 className="mb-4 text-lg font-bold text-gray-900">Editar serviço</h3>
            <p className="mb-4 text-sm text-gray-600">{editando.nome_tecnico}</p>

            {erro && <p className="mb-4 text-sm text-red-600">{erro}</p>}

            <div className="space-y-4">
              <div>
                <label className="block text-sm font-medium text-gray-700">Preço base</label>
                <input
                  type="number"
                  step="0.01"
                  value={form.preco_base ?? ''}
                  onChange={(e) => setForm({ ...form, preco_base: parseFloat(e.target.value) })}
                  className="mt-1 w-full rounded border border-gray-300 px-3 py-2 text-sm"
                />
              </div>

              <div>
                <label className="block text-sm font-medium text-gray-700">Duração (minutos)</label>
                <input
                  type="number"
                  value={form.duracao_minutos ?? ''}
                  onChange={(e) => setForm({ ...form, duracao_minutos: parseInt(e.target.value, 10) })}
                  className="mt-1 w-full rounded border border-gray-300 px-3 py-2 text-sm"
                />
              </div>

              <div>
                <label className="block text-sm font-medium text-gray-700">Foto do serviço</label>
                <input
                  ref={fileInputRef}
                  type="file"
                  accept="image/*"
                  onChange={handleFileChange}
                  className="mt-1 w-full text-sm"
                />
                {form.foto_url && !fotoFile && (
                  <p className="mt-1 text-xs text-gray-500">
                    Foto atual: <a href={form.foto_url} target="_blank" rel="noopener noreferrer" className="text-pink-600 underline">ver</a>
                  </p>
                )}
                {fotoFile && (
                  <p className="mt-1 text-xs text-gray-500">Nova foto: {fotoFile.name}</p>
                )}
              </div>

              <div className="flex items-center gap-2">
                <input
                  id="ativo"
                  type="checkbox"
                  checked={form.ativo ?? false}
                  onChange={(e) => setForm({ ...form, ativo: e.target.checked })}
                />
                <label htmlFor="ativo" className="text-sm font-medium text-gray-700">
                  Ativo
                </label>
              </div>

              <div>
                <label className="block text-sm font-medium text-gray-700">Preços por cardápio</label>
                {form.cardapios?.map((c, idx) => (
                  <div key={c.id} className="mt-2 flex items-center gap-3">
                    <span className="w-24 text-sm">{c.cardapio}</span>
                    <input
                      type="number"
                      step="0.01"
                      value={c.preco_final}
                      onChange={(e) => {
                        const novos = [...(form.cardapios ?? [])]
                        novos[idx].preco_final = parseFloat(e.target.value)
                        setForm({ ...form, cardapios: novos })
                      }}
                      className="w-32 rounded border border-gray-300 px-3 py-2 text-sm"
                    />
                  </div>
                ))}
              </div>
            </div>

            <div className="mt-6 flex justify-end gap-3">
              <button
                onClick={fecharEdicao}
                className="rounded border border-gray-300 px-4 py-2 text-sm font-semibold text-gray-700 hover:bg-gray-50"
              >
                Cancelar
              </button>
              <button
                onClick={salvar}
                disabled={salvando || uploadingFoto}
                className="rounded bg-pink-600 px-4 py-2 text-sm font-semibold text-white hover:bg-pink-700 disabled:opacity-50"
              >
                {uploadingFoto ? 'A carregar foto...' : salvando ? 'A guardar...' : 'Guardar'}
              </button>
            </div>
          </div>
        </div>
      )}

      {criando && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4">
          <div className="max-h-[90vh] w-full max-w-lg overflow-y-auto rounded bg-white p-6 shadow-lg">
            <h3 className="mb-4 text-lg font-bold text-gray-900">Novo serviço</h3>
            <p className="mb-4 text-sm text-gray-600">
              Cardápio: <strong>{tabAtiva === 'ella_studio' ? 'ELLA Studio' : 'ELLA MEN'}</strong>
            </p>

            {erro && <p className="mb-4 text-sm text-red-600">{erro}</p>}

            <div className="space-y-4">
              <div>
                <label className="block text-sm font-medium text-gray-700">Nome técnico</label>
                <input
                  type="text"
                  value={novoForm.nome_tecnico}
                  onChange={(e) => setNovoForm({ ...novoForm, nome_tecnico: e.target.value })}
                  className="mt-1 w-full rounded border border-gray-300 px-3 py-2 text-sm"
                />
              </div>

              <div>
                <label className="block text-sm font-medium text-gray-700">Nome comercial</label>
                <input
                  type="text"
                  value={novoForm.nome_comercial}
                  onChange={(e) => setNovoForm({ ...novoForm, nome_comercial: e.target.value })}
                  className="mt-1 w-full rounded border border-gray-300 px-3 py-2 text-sm"
                />
              </div>

              <div>
                <label className="block text-sm font-medium text-gray-700">Tipo de recurso</label>
                <select
                  value={novoForm.tipo_recurso_id}
                  onChange={(e) => setNovoForm({ ...novoForm, tipo_recurso_id: e.target.value })}
                  className="mt-1 w-full rounded border border-gray-300 px-3 py-2 text-sm"
                >
                  <option value="11111111-1111-1111-1111-111111111111">Mesa de manicure</option>
                  <option value="11111111-1111-1111-1111-111111111112">Cadeira de pedicure</option>
                  <option value="11111111-1111-1111-1111-111111111113">Cadeira de cílios/sobrancelhas</option>
                  <option value="11111111-1111-1111-1111-111111111114">Sala de estética</option>
                </select>
              </div>

              <div>
                <label className="block text-sm font-medium text-gray-700">Duração (minutos)</label>
                <input
                  type="number"
                  value={novoForm.duracao_minutos}
                  onChange={(e) => setNovoForm({ ...novoForm, duracao_minutos: parseInt(e.target.value, 10) })}
                  className="mt-1 w-full rounded border border-gray-300 px-3 py-2 text-sm"
                />
              </div>

              <div>
                <label className="block text-sm font-medium text-gray-700">Preço base</label>
                <input
                  type="number"
                  step="0.01"
                  value={novoForm.preco_base}
                  onChange={(e) => setNovoForm({ ...novoForm, preco_base: parseFloat(e.target.value) })}
                  className="mt-1 w-full rounded border border-gray-300 px-3 py-2 text-sm"
                />
              </div>

              <div>
                <label className="block text-sm font-medium text-gray-700">Preço final do cardápio</label>
                <input
                  type="number"
                  step="0.01"
                  value={novoForm.preco_final}
                  onChange={(e) => setNovoForm({ ...novoForm, preco_final: parseFloat(e.target.value) })}
                  className="mt-1 w-full rounded border border-gray-300 px-3 py-2 text-sm"
                />
              </div>

              <div>
                <label className="block text-sm font-medium text-gray-700">Percentual sinal (%)</label>
                <input
                  type="number"
                  value={novoForm.percentual_sinal}
                  onChange={(e) => setNovoForm({ ...novoForm, percentual_sinal: parseInt(e.target.value, 10) })}
                  className="mt-1 w-full rounded border border-gray-300 px-3 py-2 text-sm"
                />
              </div>

              <div className="flex items-center gap-2">
                <input
                  id="anamnese"
                  type="checkbox"
                  checked={novoForm.anamnese_obrigatoria}
                  onChange={(e) => setNovoForm({ ...novoForm, anamnese_obrigatoria: e.target.checked })}
                />
                <label htmlFor="anamnese" className="text-sm font-medium text-gray-700">
                  Anamnese obrigatória
                </label>
              </div>
            </div>

            <div className="mt-6 flex justify-end gap-3">
              <button
                onClick={fecharCriacao}
                className="rounded border border-gray-300 px-4 py-2 text-sm font-semibold text-gray-700 hover:bg-gray-50"
              >
                Cancelar
              </button>
              <button
                onClick={criarServico}
                disabled={salvando}
                className={`rounded px-4 py-2 text-sm font-semibold text-white disabled:opacity-50 ${
                  tabAtiva === 'ella_studio' ? 'bg-pink-600 hover:bg-pink-700' : 'bg-blue-600 hover:bg-blue-700'
                }`}
              >
                {salvando ? 'A criar...' : 'Criar serviço'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
