---
status: in-progress
baseline_commit: f7a5548
---

# Story 2.5 — Catálogo por Accessibility e correlação de posição

Epic: Epic 2 — Descoberta e densidade  
resource_slug: `menu-bar-manager-followup`  
Branch: `feat/menu-bar-manager-followup`  
Worktree: `/Users/ruansantana/Documents/DeepAgent/vorssaint-utils-menu-bar-manager`  
Base/dependência: `upstream/main` com PR #360 (`18383b9`) já mesclada localmente  
Objetivo único: tornar a descoberta do editor confiável sem alterar o contrato de
movimento seguro do Organizer.

## Correção de curso aprovada

A enumeração CGWindow não é uma lista canônica de status items no macOS 26: a barra
pode ser uma superfície composta. O catálogo de Accessibility deve descobrir os
itens; WindowServer serve somente para correlacionar posição e permitir movimento.

## Permissões

| Operação | Acesso | Recusa | Teste Developer |
|---|---|---|---|
| Enumerar `AXExtrasMenuBar` | Accessibility | serviço continua parado e a `PermissionRow` existente orienta o usuário | negar, abrir Organizer, conceder, atualizar |
| Correlacionar/mover | Accessibility + WindowServer existente | item fica visível, mas bloqueado | mover somente item confirmado |
| Renderizar ícone de app | nenhuma permissão nova | usar fallback existente | confirmar que Screen Recording não é solicitado |

## Critérios de aceitação

1. Com Accessibility concedida, o provider inclui cada item encontrado em
   `AXExtrasMenuBar` uma única vez, mesmo quando não existe uma janela CG individual.
2. Itens com correlação de janela são `confirmed` e podem manter o fluxo atual de
   movimentação; itens só-AX são `detected`, têm ícone/nome humano e são bloqueados.
3. O editor nunca apresenta identificadores internos/técnicos como rótulo e nunca
   inclui os divisores do Organizer.
4. A barra secundária usa somente itens confirmados; não se apresenta como inventário
   completo quando o macOS não fornece posição suficiente.
5. A coleta tem timeout/cache e não cria uma nova varredura completa a cada refresh.
6. Testes cobrem deduplicação, estados e contrato de itens não correlacionados.

## Limite explícito

Widgets que não expõem Accessibility nem janela correlacionável não podem ser
listados por nenhum gerenciador usando apenas essas APIs. O produto deve explicitar
essa indisponibilidade em vez de mover um item errado.
