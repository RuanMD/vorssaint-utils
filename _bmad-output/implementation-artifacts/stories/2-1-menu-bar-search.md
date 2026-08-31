# Story 2.1 — Menu Bar Search

Status: implemented
Epic: Epic 2 — Descoberta e densidade
Dependência: Story 1.2

## História

Como usuário, quero buscar um item da menu bar pelo nome e ativá-lo quando possível,
mesmo se estiver oculto.

## Critérios de aceitação

1. Buscar sem diferenciar maiúsculas ou acentos e mostrar seção/estado.
2. Selecionar Hidden/Always Hidden revela, aguarda refresh e revalida identidade.
3. Item provisório, removido ou alterado produz erro recuperável sem clique cego.
4. Busca pode ser aberta por atalho e pela Command Bar.

## Tarefas

- [x] Implementar índice puro/ranking do snapshot.
- [x] Criar painel de busca não ativador com estados vazio e resultado.
- [x] Integrar reveal + refresh + ativação verificada.
- [x] Adicionar Command Bar, localização e testes.

Observação: o painel usa mensagens de estado vazio/resultados; estados de erro
continuam no diagnóstico recuperável do serviço existente.
