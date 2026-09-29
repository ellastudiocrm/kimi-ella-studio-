import 'server-only'
import { redirect } from 'next/navigation'
import { createSessionClient } from '@/lib/supabase/session'

// Consultas do painel interno. Usam a sessão de quem está logado,
// então a RLS decide o que cada perfil pode ver.
// As tabelas têm duas FKs entre si (simples e composta com empresa_id), por
// isso os embeds indicam a FK pelo nome (tabela!nome_da_fk).

export const FUSO_OFFSET = '-03:00' // São Paulo (sem horário de verão desde 2019)
const PERFIS_EQUIPE = ['admin', 'gestor', 'recepcao']

export interface UsuarioPainel {
  nome: string
  perfil: string
  profissionalId: string | null
  equipe: boolean // vê e gere a agenda de todas
}

export async function usuarioAtual(): Promise<UsuarioPainel> {
  const supabase = createSessionClient()
  const {
    data: { user },
  } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const { data } = await supabase
    .from('usuarios_internos')
    .select('nome, perfil, usuario_profissional(profissional_id)')
    .eq('auth_user_id', user.id)
    .eq('ativo', true)
    .maybeSingle()

  const perfil = data?.perfil ?? 'desconhecido'
  return {
    nome: data?.nome ?? user.email?.split('@')[0] ?? 'Usuário',
    perfil,
    profissionalId: (data as any)?.usuario_profissional?.[0]?.profissional_id ?? null,
    equipe: PERFIS_EQUIPE.includes(perfil),
  }
}

export interface ProfissionalAgenda {
  id: string
  nome: string
  fotoUrl: string | null
}

// Profissionais que atendem (têm pelo menos um serviço habilitado)
export async function profissionaisDaAgenda(): Promise<ProfissionalAgenda[]> {
  const supabase = createSessionClient()
  const { data } = await supabase
    .from('profissionais')
    .select('id, nome, foto_url, profissional_servicos!profissional_servicos_profissional_id_fkey!inner(servico_id)')
    .eq('ativo', true)
    .order('nome')

  const vistos = new Set<string>()
  return (data ?? [])
    .filter((p: any) => !vistos.has(p.id) && vistos.add(p.id))
    .map((p: any) => ({ id: p.id, nome: p.nome, fotoUrl: p.foto_url }))
}

export type EstadoReserva =
  | 'pre_reserva'
  | 'expirada'
  | 'pagamento_em_revisao'
  | 'confirmada'
  | 'realizada'
  | 'cancelada'
  | 'no_show'

export interface ItemAgenda {
  id: string
  reservaId: string
  inicio: string
  fim: string
  servico: string
  preco: number
  profissionalId: string | null
  estadoReserva: EstadoReserva
  estadoItem: string
  cliente: { nome: string; telefone: string }
}

export interface BloqueioAgenda {
  id: string
  profissionalId: string | null
  inicio: string
  fim: string
  tipo: string
  motivo: string | null
}

export function limitesDoDia(dataISO: string) {
  const inicio = new Date(`${dataISO}T00:00:00${FUSO_OFFSET}`)
  return { inicio, fim: new Date(inicio.getTime() + 86400000) }
}

export async function carregarAgenda(
  inicio: Date,
  fim: Date,
  profissionalId?: string | null
): Promise<{ itens: ItemAgenda[]; bloqueios: BloqueioAgenda[]; erro: string | null }> {
  const supabase = createSessionClient()

  let q = supabase
    .from('reserva_itens')
    .select(
      `id, inicio, fim, estado, nome_servico, preco_final, profissional_id,
       reservas!reserva_itens_reserva_id_fkey!inner ( id, estado,
         clientes!reservas_cliente_id_fkey ( nome, telefone_normalizado ) ),
       servicos!reserva_itens_servico_id_fkey ( nome_tecnico, servico_cardapios ( nome_comercial ) )`
    )
    .gte('inicio', inicio.toISOString())
    .lt('inicio', fim.toISOString())
    .order('inicio')
  if (profissionalId) q = q.eq('profissional_id', profissionalId)

  let qb = supabase
    .from('bloqueios')
    .select('id, profissional_id, inicio, fim, tipo, motivo')
    .lt('inicio', fim.toISOString())
    .gt('fim', inicio.toISOString())
    .order('inicio')
  if (profissionalId) qb = qb.eq('profissional_id', profissionalId)

  const [{ data, error }, { data: bl }] = await Promise.all([q, qb])

  const itens: ItemAgenda[] = (data ?? []).map((i: any) => ({
    id: i.id,
    reservaId: i.reservas.id,
    inicio: i.inicio,
    fim: i.fim,
    servico:
      i.servicos?.servico_cardapios?.[0]?.nome_comercial ?? i.nome_servico ?? i.servicos?.nome_tecnico ?? 'Serviço',
    preco: Number(i.preco_final ?? 0),
    profissionalId: i.profissional_id,
    estadoReserva: i.reservas.estado,
    estadoItem: i.estado,
    cliente: {
      nome: i.reservas.clientes?.nome?.trim() || 'Cliente',
      telefone: i.reservas.clientes?.telefone_normalizado ?? '',
    },
  }))

  const bloqueios: BloqueioAgenda[] = (bl ?? []).map((b: any) => ({
    id: b.id,
    profissionalId: b.profissional_id,
    inicio: b.inicio,
    fim: b.fim,
    tipo: b.tipo,
    motivo: b.motivo,
  }))

  return { itens, bloqueios, erro: error ? error.message : null }
}

// Faixa de horário exibida na grade (a partir dos horários da empresa)
export async function faixaDeHorario(): Promise<{ abre: number; fecha: number; dias: number[] }> {
  const supabase = createSessionClient()
  const { data } = await supabase.from('horarios_empresa').select('dia_semana, abertura, fechamento').eq('ativo', true)
  if (!data || data.length === 0) return { abre: 8, fecha: 18, dias: [2, 3, 4, 5, 6] }
  const horas = (t: string) => Number(t.slice(0, 2)) + Number(t.slice(3, 5)) / 60
  return {
    abre: Math.floor(Math.min(...data.map((d: any) => horas(d.abertura)))),
    fecha: Math.ceil(Math.max(...data.map((d: any) => horas(d.fechamento)))),
    dias: data.map((d: any) => d.dia_semana),
  }
}
