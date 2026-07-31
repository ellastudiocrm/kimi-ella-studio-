export interface Servico {
  id: string
  nome_tecnico: string
  duracao_minutos: number
  preco_base: number
  percentual_sinal: number
  anamnese_obrigatoria: boolean
  ativo: boolean
  foto_url: string | null
}

export interface ServicoCardapio {
  id: string
  servico_id: string
  cardapio: 'ella_studio' | 'ella_men'
  nome_comercial: string
  descricao: string | null
  preco_final: number
  ativo: boolean
}

export interface Profissional {
  id: string
  nome: string
  foto_url: string | null
  bio: string | null
  especialidades: string[]
  ativo: boolean
}

export interface SlotHorario {
  inicio: string
  fim: string
}

export interface PreReservaItem {
  servico_id: string
  profissional_id: string
  inicio: string
  cardapio: string
}

export interface PreReservaResponse {
  reserva_id: string
  idempotente: boolean
  estado: 'pre_reserva' | 'confirmada'
  valor_total: number
  valor_sinal: number
  anamneses: Array<{
    anamnese_id: string
    token?: string
    expira_em?: string
  }>
}
