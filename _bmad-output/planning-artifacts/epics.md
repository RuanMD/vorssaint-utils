# Épicos e stories — Menu Bar Manager avançado

project: Vorssaint
resource_slug: menu-bar-manager-followup
branch: feat/menu-bar-manager-followup
worktree: /Users/ruansantana/Documents/DeepAgent/vorssaint-utils-menu-bar-manager
base: upstream/pr-360 (18383b9) sobre upstream/main
dependency: PR #360 — Menu Bar Organizer MVP
status: implemented-pending-manual-validation

## Decisão de decomposição

Este é um follow-up dependente do Organizer MVP. O núcleo da PR #360 não será
reimplementado. A entrega será feita em duas unidades de valor:

- Epic 1: Reveal seguro — transformar as três seções existentes em uma superfície
  de acesso sob demanda, com atalhos e auto-rehide seguro.
- Epic 2: Descoberta e densidade — encontrar itens ocultos e apresentar a barra
  secundária com espaçamento configurável.

## Requisitos funcionais

- FR1: manter itens nas seções Visible, Hidden e Always Hidden sem alterar a ordem.
- FR2: revelar Hidden e Always Hidden por ações configuráveis.
- FR3: reocultar automaticamente sem fechar menus ou interromper interação.
- FR4: permitir atalhos separados, com conflitos e falhas de registro recuperáveis.
- FR5: localizar itens por nome, revelar a seção correta e ativar somente identidade
  revalidada e estável.
- FR6: aplicar espaçamento sanitizado à barra secundária/divisores existentes.
- FR7: persistir e fazer backup das preferências portáveis.
- FR8: preservar o restante do app sem Accessibility, em macOS 27+ e diante de
  outro organizer.

## Requisitos não funcionais

- NFR1: nenhum conteúdo, screenshot, token ou segredo deixa o Mac.
- NFR2: usar APIs nativas e nenhuma dependência externa.
- NFR3: serviços devem ter sync/teardown idempotente e callbacks canceláveis.
- NFR4: regras puras devem ter cobertura em MetricsTests.
- NFR5: testar TCC com o bundle Developer separado.
- NFR6: macOS 27+ permanece inerte até existir provider compatível.

## Epic 1 — Reveal seguro e auto-rehide

| Story | Valor | Dependências | Status |
|---|---|---|---|
| 1.1 | Modelo de sessão, preferências e sanitização previsíveis | PR #360 | implemented |
| 1.2 | Revelar/ocultar por gatilhos e atalhos | 1.1 | implemented |
| 1.3 | Auto-rehide que respeita interação e teardown | 1.1, 1.2 | implemented |

## Epic 2 — Descoberta e densidade

| Story | Valor | Dependências | Status |
|---|---|---|---|
| 2.1 | Busca e ativação segura de itens ocultos | 1.2 | implemented |
| 2.2 | Barra secundária multi-monitor e espaçamento | 1.1 | implemented |

## Critérios de saída do recurso

Os testes determinísticos e o build do código estão concluídos; permanece a
validação manual Developer para Accessibility, notch, monitores, Spaces, auto-hide
e organizer concorrente. Não incluir aparência, perfis, grupos, automações, menus
da esquerda ou backend macOS 27 neste recurso.
