# Story 1.2 — Gatilhos de revelação e atalhos

Status: implemented
Epic: Epic 1 — Reveal seguro e auto-rehide
Dependência: Story 1.1

## História

Como usuário, quero revelar Hidden e Always Hidden por botão, atalho e gestos
configuráveis, para acessar itens sem reorganizar a barra.

## Critérios de aceitação

1. Botão local alterna Hidden; ação “mostrar todos” revela as duas seções.
2. Cada gatilho pode ser ligado/desligado sem iniciar monitores desnecessários.
3. Atalhos têm roles distintos, rejeitam conflito e não impedem o uso por botão.
4. Falta/revogação de Accessibility desmonta monitores e mostra orientação sem
   quebrar outras features.
5. Eventos fora da área/estado do Organizer retornam ao macOS.

## Tarefas

- [x] Integrar roles de atalho e Settings.
- [x] Implementar sessão de reveal e refresh pós-operação.
- [x] Adaptar hover/clique/scroll apenas aos monitores já suportados.
- [x] Adicionar testes de gating, conflito e teardown.
