# Story 1.3 — Auto-rehide seguro

Status: implemented
Epic: Epic 1 — Reveal seguro e auto-rehide
Dependência: Stories 1.1 e 1.2

## História

Como usuário, quero que itens revelados desapareçam depois de um período sem uso,
sem fechar menus ou interromper uma ação em andamento.

## Critérios de aceitação

1. Suportar clique fora, 3 s, 5 s, 10 s, 30 s e valor customizado limitado.
2. Menu/submenu aberto, ponteiro dentro da área ou item em interação pausa/adia o
   rehide.
3. Perda de foco sem estado verificável nunca causa rehide forçado.
4. Desligar, revogar permissão ou trocar monitor cancela timers de forma idempotente.

## Tarefas

- [x] Criar scheduler de deadline cancelável.
- [x] Detectar interação/menu aberto sem assumir sucesso de AX.
- [x] Integrar teardown e reavaliação em foreground.
- [x] Testar deadlines, pausa e recuperação.
