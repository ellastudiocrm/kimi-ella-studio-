import 'server-only'
import { supabaseAdmin } from '@/lib/supabase/server'
import { supabasePublico as publico } from '@/lib/supabase/publico'
import type { Cardapio } from '@/lib/marca'

// Leituras públicas do catálogo, sempre feitas no servidor.
// servicos, servico_cardapios e profissionais têm leitura pública (RLS anon);
// profissional_servicos e horarios_empresa não, por isso usam o cliente admin.
// A role anon não tem acesso à coluna empresa_id, então as leituras públicas
// não filtram por empresa (hoje só existe a ELLA Studio com serviços ativos).

const EMPRESA_ID = process.env.NEXT_PUBLIC_EMPRESA_ID!

export interface ServicoCatalogo {
  id: string
  nomeTecnico: string
  nome: string
  descricao: string | null
  duracaoMinutos: number
  preco: number
  percentualSinal: number
  fotoUrl: string | null
}

export interface ProfissionalPublico {
  id: string
  nome: string
  fotoUrl: string | null
  bio: string | null
  especialidades: string[]
}

export async function listarServicos(cardapio: Cardapio): Promise<ServicoCatalogo[]> {
  const { data, error } = await publico
    .from('servico_cardapios')
    .select(
      'nome_comercial, descricao, preco_final, servicos!inner(id, nome_tecnico, duracao_minutos, percentual_sinal, foto_url, ativo)'
    )
    .eq('cardapio', cardapio)
    .eq('ativo', true)
    .eq('servicos.ativo', true)
    .order('nome_comercial')

  if (error) {
    console.error('Erro ao listar serviços:', error)
    return []
  }

  return (data ?? []).map((linha: any) => ({
    id: linha.servicos.id,
    nomeTecnico: linha.servicos.nome_tecnico,
    nome: linha.nome_comercial,
    descricao: linha.descricao,
    duracaoMinutos: linha.servicos.duracao_minutos,
    preco: Number(linha.preco_final),
    percentualSinal: Number(linha.servicos.percentual_sinal ?? 0),
    fotoUrl: linha.servicos.foto_url,
  }))
}

export async function obterServico(
  cardapio: Cardapio,
  filtro: { nomeTecnico?: string; id?: string }
): Promise<ServicoCatalogo | null> {
  const servicos = await listarServicos(cardapio)
  return (
    servicos.find((s) =>
      filtro.id ? s.id === filtro.id : s.nomeTecnico === filtro.nomeTecnico
    ) ?? null
  )
}

function mapearProfissional(p: any): ProfissionalPublico {
  return {
    id: p.id,
    nome: p.nome,
    fotoUrl: p.foto_url,
    bio: p.bio,
    especialidades: p.especialidades ?? [],
  }
}

export async function listarProfissionaisDoServico(servicoId: string): Promise<ProfissionalPublico[]> {
  const { data: habilitacoes, error } = await supabaseAdmin
    .from('profissional_servicos')
    .select('profissional_id')
    .eq('servico_id', servicoId)

  if (error) {
    console.error('Erro ao buscar profissionais do serviço:', error)
    return []
  }

  const ids = (habilitacoes ?? []).map((h: any) => h.profissional_id)
  if (ids.length === 0) return []

  const { data } = await publico
    .from('profissionais')
    .select('id, nome, foto_url, bio, especialidades')
    .eq('ativo', true)
    .in('id', ids)
    .order('nome')

  return (data ?? []).map(mapearProfissional)
}

export async function obterProfissional(id: string): Promise<ProfissionalPublico | null> {
  const { data } = await publico
    .from('profissionais')
    .select('id, nome, foto_url, bio, especialidades')
    .eq('id', id)
    .eq('ativo', true)
    .maybeSingle()

  return data ? mapearProfissional(data) : null
}

// Dias da semana em que o estúdio abre (0 = domingo … 6 = sábado).
export async function diasDeFuncionamento(): Promise<number[]> {
  const { data, error } = await supabaseAdmin
    .from('horarios_empresa')
    .select('dia_semana')
    .eq('empresa_id', EMPRESA_ID)
    .eq('ativo', true)

  if (error || !data || data.length === 0) {
    // Horário publicado no site oficial: terça a sábado
    return [2, 3, 4, 5, 6]
  }
  return data.map((d: any) => d.dia_semana)
}
